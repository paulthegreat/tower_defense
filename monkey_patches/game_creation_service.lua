local Point2 = _radiant.csg.Point2
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region2 = _radiant.csg.Region2
local Region3 = _radiant.csg.Region3
local rng = _radiant.math.get_default_rng()
local csg_lib = require 'stonehearth.lib.csg.csg_lib'
local landmark_lib = require 'stonehearth.lib.landmark.landmark_lib'
local render_lib = require 'tower_defense.lib.render.render_lib'

local validator = radiant.validator
local log = radiant.log.create_logger('world_generation')

GameCreationService = class()

function GameCreationService:new_game_command(session, response, num_tiles_x, num_tiles_y, seed, options, starting_data)
	--if no kingdom has been set for the player yet, set it to ascendancy
	if not stonehearth.player:get_kingdom(session.player_id) then
		stonehearth.player:add_kingdom(session.player_id, "stonehearth:kingdoms:ascendancy")
	end

	local pop = stonehearth.population:get_population(session.player_id)
   pop:set_game_options(options)

   tower_defense.game:set_game_options(options)
   
   stonehearth.world_generation:create_empty_world(options.biome_src)

   local result = {
      map_info = {
         biome_src = options.biome_src
      }
   }

	return result
end

function GameCreationService:generate_start_location_command(session, response, feature_cell_x, feature_cell_y, map_info)
	self:_generate_world(session, response, map_info)
   self:start_game(session)
   response:resolve({})
end

function GameCreationService:_generate_world(session, response, map_info)
   if validator.is_host_player(session) then
      stonehearth.terrain._enable_full_vision = true
      
      -- generate the world!
      local biome = radiant.resources.load_json(map_info.biome_src)
      -- default if not specified is the burbenog map
      local map = radiant.resources.load_json(biome.tower_defense_generation_file or 'tower_defense:data:map_generation:desert')

      -- first generate the world terrain
      local block_types = radiant.terrain.get_block_types()
      local terrain = Region3()
      local world = map.world
      local size = world.size or 32
      assert(size % 2 == 0)
      local half_size = size / 2
      local height = 0
      
      for _, layer in ipairs(world.layers) do
         terrain:add_cube(Cube3(Point3(0, height, 0), Point3(size, layer.height + height, size), block_types[layer.terrain]))
         height = height + layer.height
      end

      -- hacky edge shading fix (add a null terrain block super far below us)
      terrain:add_cube(Cube3(Point3(-1, -999999, -1), Point3(0, -999998, 0), block_types.null))

      --move the region to be centered
      local center_point = Point3(-half_size, 0, -half_size)
      terrain = terrain:translated(center_point)
      radiant.terrain.get_terrain_component():add_tile(terrain)

      -- create primary terrain landmark if there is one
      if map.terrain_landmark then
         self:_create_landmark(map.terrain_landmark, center_point)
      end

      -- add landmarks to edges of map
      self:_create_landmarks(map.landmarks, size, Point3(0, height, 0))
      
      -- if we're having the path cut into the terrain, subtract 1 from the height
      local top = center_point + Point3(0, height - (map.path.width and 1 or 0), 0)
      local air_top = Point3(0, map.air_path.height, 0)

      local sub_terrain = Region3()
      local first_point, last_point, path_region, path_entity, add_terrain = 
            self:_create_path(map.path.points, top, false, map.path.width or 3, sub_terrain, map.path.block_type and block_types[map.path.block_type])
      local air_first_point, air_last_point, air_path_region, air_path_entity =
            self:_create_path(map.air_path.points, top + air_top, true, map.path.width or 3, sub_terrain)
      
      -- apply path block type terrain
      radiant.terrain.add_region(add_terrain)
      -- subtract the path from the world terrain
      radiant.terrain.subtract_region(sub_terrain)
      
      -- place path entities with movement modifiers
      --path_entity:add_component('tower_defense:region_renderer'):set_options('path', {face_color = {128, 51, 0, 96}})
      radiant.terrain.place_entity_at_exact_location(path_entity, first_point + top)
      --radiant.terrain.place_entity_at_exact_location(path_neighbor_entity, first_point + top)
      --air_path_entity:add_component('tower_defense:region_renderer'):set_options('path', {face_color = {224, 64, 224, 96}})
      radiant.terrain.place_entity_at_exact_location(air_path_entity, air_first_point + top + air_top)

      -- finally, add any entities that should start out in the world
      local entities = map.entities
      local offset = center_point + Point3(0, height, 0)
      for uri, entity_list in pairs(entities) do
         for _, entity_data in ipairs(entity_list) do
            local entity = radiant.entities.create_entity(uri, { owner = '' })
            radiant.terrain.place_entity_at_exact_location(entity, Point3(unpack(entity_data.location)) + offset, { force_iconic = false })
            local facing = entity_data.facing or 0
            if facing == 'random' then
               facing = rng:get_int(0, 3) * 90
            end
            radiant.entities.turn_to(entity, facing)
         end
      end

      self:on_world_generation_complete()

      if map.tower_placeable_region then
         local reg = Region3()
         for _, cube in ipairs(map.tower_placeable_region) do
            reg:add_cube(Cube3(Point3(unpack(cube[1])), Point3(unpack(cube[2]))))
         end
         reg:translate(offset)
         reg:optimize('tower placeable region')
         map.tower_placeable_region = reg
      else
         map.tower_placeable_region = Region3(Cube3(Point3(-half_size, height, -half_size), Point3(half_size - 1, height + 1, half_size - 1)))
      end
      map.spawn_location = first_point + top
      map.air_spawn_location = air_first_point + top + air_top
      map.end_point = last_point + offset - Point3(0, 1, 0)
      map.air_end_point = air_last_point + air_top + offset - Point3(0, 1, 0)
      map.ground_path_region = path_region:translated(map.spawn_location)
      map.air_path_region = air_path_region:translated(map.air_spawn_location)

      tower_defense.game:set_map_data(map)
	end
end

function GameCreationService:_create_path(path_array, top, is_air, width, sub_terrain, path_block_type)
   local path_region = Region3()
   local trans_path_region
   local path_neighbor = Region3()
   local first_point
   local last_point

   local path_cubes = {}

   for i, point in ipairs(path_array) do
      local this_point = Point3(unpack(point))
      if not first_point then
         first_point = this_point
      end
      if last_point then
         local cube
         -- if it's the final point, make sure it extends all the way (important for air path, otherwise they can't run the final segment)
         if i == #path_array then
            cube = csg_lib.create_cube(last_point + top, this_point + top)
         else
            cube = render_lib.shy_cube(last_point + top, this_point + top)
         end
         table.insert(path_cubes, cube)
         path_region:add_cube(cube)

         if width and width >= 0 and sub_terrain then
            local extruded_cube = cube:extruded('x', width, width):extruded('z', width, width)
            path_neighbor:add_cube(extruded_cube)
            extruded_cube = extruded_cube:extruded('y', 0, 4) -- TODO: maybe have this height be customizable
            sub_terrain:add_cube(extruded_cube)
            -- also remove any non-terrain entities in this area (plus 1 higher y)
            for _, entity in pairs(radiant.terrain.get_entities_in_cube(extruded_cube:extruded('y', 0, 1))) do
               if not entity:get_component('terrain') then
                  local water_comp = entity:get_component('stonehearth:water')
                  if water_comp then
                     -- if it's water, just subtract the part that intersects the path
                     water_comp:remove_from_region(sub_terrain)
                  else
                     radiant.entities.destroy_entity(entity)
                  end
               end
            end
         end
      end
      last_point = this_point
   end
   path_neighbor:subtract_region(path_region)
   trans_path_region = path_region:translated(-(first_point + top))

   -- create path entity with movement modifier
   local path_entity = radiant.entities.create_entity('tower_defense:path', { owner = '' })
   local path_entity_region = path_entity:add_component('movement_modifier_shape')
   path_entity_region:set_region(_radiant.sim.alloc_region3())
   path_entity_region:get_region():modify(function(mod_region)
         mod_region:copy_region(trans_path_region)
         mod_region:set_tag(0)
         mod_region:optimize_by_defragmentation('path movement modifier shape')
      end)

   -- local hues
   -- local hue_range
   -- if is_air then
   --    hues = {0, 60}
   -- else
   --    hues = {120, 300}
   -- end
   -- hue_range = hues[2] - hues[1]
   -- local cur_hue = hues[1]
   -- if #path_cubes == 1 then
   --    cur_hue = hue_range / 2 + cur_hue
   -- end
   -- local render_comp = path_entity:add_component('tower_defense:region_renderer')
   -- for i, cube in ipairs(path_cubes) do
   --    local color = render_lib.hsv_to_rgb(cur_hue, 0.75, 1)
   --    render_comp:add_render_region('path'..i, {
   --       ui_modes = {
   --          hud = true
   --       },
   --       -- transformations = {
   --       --    {
   --       --       name = 'inflated',
   --       --       params = {
   --       --          x = 0,
   --       --          y = -0.49,
   --       --          z = 0
   --       --       }
   --       --    }
   --       -- },
   --       material = '/stonehearth/data/horde/materials/transparent_box.material.json',
   --       face_color = {color.x, color.y, color.z, 51},
   --       region = Region3(cube:translated(-(first_point + top)))
   --    })
   --    cur_hue = (hue_range / (#path_cubes - 1)) * i + hues[1]
   -- end

   -- local path_neighbor_entity = radiant.entities.create_entity('tower_defense:path_neighbor', { owner = '' })
   -- local path_neighbor_entity_region = path_neighbor_entity:add_component('movement_modifier_shape')
   -- path_neighbor_entity_region:set_region(_radiant.sim.alloc_region3())
   -- path_neighbor_entity_region:get_region():modify(function(mod_region)
   --       mod_region:copy_region(path_neighbor:translated(-(first_point + top)))
   --       mod_region:set_tag(0)
   --       mod_region:optimize_by_defragmentation('path movement modifier shape')
   --    end)

   local add_terrain = Region3()
   if is_air then
      -- if it's air, we need to specify a collision region directly under the path
      path_entity_region = path_entity:add_component('region_collision_shape')
      path_entity_region:set_region_collision_type(_radiant.om.RegionCollisionShape.PLATFORM)
      path_entity_region:set_region(_radiant.sim.alloc_region3())
      path_entity_region:get_region():modify(function(mod_region)
            mod_region:copy_region(trans_path_region:inflated(Point3(0, -0.45, 0)):translated(Point3(0, -0.55, 0)))
            --mod_region:optimize_by_defragmentation('path region collision shape')
         end)
   elseif path_block_type then
      -- if it's ground, modify the terrain directly under the path so it's a different shade
      path_region = path_region:duplicate()
      path_region:set_tag(path_block_type)
      path_region:translate(Point3(0, -1, 0))
      add_terrain:add_region(path_region)
   end

   return first_point, last_point, trans_path_region, path_entity, add_terrain
end

function GameCreationService:_create_landmarks(landmarks, world_size, center_point)
   if not landmarks or #landmarks < 1 then
      return
   end

   -- prefer to use landmarks that haven't already been used
   landmarks = radiant.shallow_copy(landmarks)
   local directions = {
      Point3( 1, 0, -1),
      Point3(-1, 0, -1),
      Point3( -1, 0, 1),
      Point3( 1, 0, 1)
   }
   local used = {}

   for i = 0, 3 do
      local landmark = table.remove(landmarks, rng:get_int(1, #landmarks))
      table.insert(used, landmark)

      if #landmarks < 1 then
         landmarks = used
         used = {}
      end

      -- try to load the landmark at the appropriate location/rotation
      local json = radiant.resources.load_json(landmark)
      if json then
         local size = json.size or Point3(32, 0, 32)
         local direction = directions[i + 1]
         local translation = Point3(direction.x * math.floor((world_size - size.x) / 2), 0, direction.z * math.floor((world_size - size.z) / 2))
         self:_create_landmark(json, center_point, translation, i * 90)
      end
   end
end

function GameCreationService:_create_landmark(landmark, location, translation, rotation)
   -- try to load the landmark at the appropriate location/rotation
   if type(landmark) == 'string' then
      landmark = radiant.resources.load_json(landmark)
   end
   if landmark then
      landmark_lib.create_landmark(location, {
         translation = (translation or Point3.zero) + (radiant.util.to_point3(landmark.offset) or Point3.zero),
         rotation = (rotation or 0) + (landmark.rotation or 0),
         landmark_block_types = landmark.landmark_block_types or 'stonehearth:landmark_blocks',
         brush = landmark.brush
      })
   end
end

function GameCreationService:start_game(session)
	local player_id = session.player_id
	local pop = stonehearth.population:get_population(player_id)
	local game_options = pop:get_game_options()
	
   tower_defense.game:add_player(player_id)
   
   --stonehearth.world_generation:set_starting_location(Point2(0, 0))
	
	-- as soon as the host clicks to start the game, start it up
	if validator.is_host_player(session) then
		stonehearth.calendar:start()
		stonehearth.hydrology:start()
		stonehearth.mining:start()

		if game_options.remote_connections_enabled then
			stonehearth.session_server:set_remote_connections_enabled(true)
		end

		-- Set max number of remote players if specified
		if game_options.max_players then
			stonehearth.session_server:set_max_players(game_options.max_players)
		end

		-- Set whether clients can control game speed
		if game_options.game_speed_anarchy_enabled then
			stonehearth.game_speed:set_anarchy_enabled(game_options.game_speed_anarchy_enabled)
      end
      
      -- switch to having the host manually tell the game to start
      --stonehearth.game_speed:set_game_speed(0, true)
      --tower_defense.game:start()
   end
   
   stonehearth.terrain:set_fow_enabled(player_id, false)

   pop:place_camp()
end

function GameCreationService:get_game_world_options_commands(session, response)
	response:resolve({
		game_mode = self._sv.game_mode,
		biome = stonehearth.world_generation:get_biome_alias(),
		-- any other options, like more generous starting gold, etc.
	})
end

return GameCreationService
