local Point2 = _radiant.csg.Point2
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local csg_lib = require 'stonehearth.lib.csg.csg_lib'

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
      local map = radiant.resources.load_json(biome.tower_defense_generation_file or 'tower_defense:data:map_generation')

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

      -- subtract the path from the world terrain
      local top = Point3(0, height - 1, 0)
      local air_top = Point3(0, map.air_path.height, 0)
      
      local first_point, last_point, path_region, path_entity, path_neighbor_entity = 
            self:_create_path(map.path.points, top, false, map.path.width or 3, terrain, map.path.block_type and block_types[map.path.block_type])
      local air_first_point, air_last_point, air_path_region, air_path_entity = self:_create_path(map.air_path.points, top, true)
      
      -- hacky edge shading fix (add a null terrain block super far below us)
      terrain:add_cube(Cube3(Point3(-1, -999999, -1), Point3(0, -999998, 0), block_types.null))

      --move the region to be centered
      local center_point = Point3(-half_size, 0, -half_size)
      terrain = terrain:translated(center_point)
      radiant.terrain.get_terrain_component():add_tile(terrain)

      -- place path entities with movement modifiers
      radiant.terrain.place_entity_at_exact_location(path_entity, first_point + top + center_point)
      radiant.terrain.place_entity_at_exact_location(path_neighbor_entity, first_point + top + center_point)
      radiant.terrain.place_entity_at_exact_location(air_path_entity, air_first_point + top + air_top + center_point)

      -- finally, add any entities that should start out in the world
      local entities = map.entities
      local offset = center_point + Point3(0, height, 0)
      for uri, entity_list in pairs(entities) do
         for _, entity_data in ipairs(entity_list) do
            local entity = radiant.entities.create_entity(uri, { owner = '' })
            radiant.terrain.place_entity_at_exact_location(entity, Point3(unpack(entity_data.location)) + offset, { force_iconic = false })
            radiant.entities.turn_to(entity, entity_data.facing or 0)
         end
      end

      self:on_world_generation_complete()

      map.spawn_location = first_point + top + center_point
      map.air_spawn_location = air_first_point + top + air_top + center_point
      map.end_point = last_point + offset - Point3(0, 1, 0)
      map.air_end_point = air_last_point + air_top + offset - Point3(0, 1, 0)

      tower_defense.game:set_map_data(map)

      tower_defense.tower:set_ground_path(path_region:translated(Point3(first_point.x, 0, first_point.z) + center_point))
      tower_defense.tower:set_air_path(air_path_region:translated(Point3(air_first_point.x, 0, air_first_point.z) + center_point), map.air_path.height)
	end
end

function GameCreationService:_create_path(path_array, top, is_air, width, terrain, path_block_type)
   local path_region = Region3()
   local trans_path_region
   local path_neighbor = Region3()
   local first_point
   local last_point

   for _, point in ipairs(path_array) do
      local this_point = Point3(unpack(point))
      if not first_point then
         first_point = this_point
      end
      if last_point then
         local cube = csg_lib.create_cube(last_point + top, this_point + top)
         path_region:add_cube(cube)
         if width and width > 0 and terrain then
            local extruded_cube = cube:extruded('x', width, width):extruded('z', width, width)
            path_neighbor:add_cube(extruded_cube)
            terrain:subtract_cube(extruded_cube)
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

   local path_neighbor_entity = radiant.entities.create_entity('tower_defense:path_neighbor', { owner = '' })
   local path_neighbor_entity_region = path_neighbor_entity:add_component('movement_modifier_shape')
   path_neighbor_entity_region:set_region(_radiant.sim.alloc_region3())
   path_neighbor_entity_region:get_region():modify(function(mod_region)
         mod_region:copy_region(path_neighbor:translated(-(first_point + top)))
         mod_region:set_tag(0)
         mod_region:optimize_by_defragmentation('path movement modifier shape')
      end)

   if is_air then
      -- if it's air, we need to specify a collision region directly under the path
      path_entity_region = path_entity:add_component('region_collision_shape')
      path_entity_region:set_region_collision_type(_radiant.om.RegionCollisionShape.PLATFORM)
      path_entity_region:set_region(_radiant.sim.alloc_region3())
      path_entity_region:get_region():modify(function(mod_region)
            mod_region:copy_region(trans_path_region:inflated(Point3(0, -0.45, 0)):translated(Point3(0, -0.55, 0)))
            --mod_region:optimize_by_defragmentation('path region collision shape')
         end)
   elseif terrain and path_block_type then
      -- if it's ground, modify the terrain directly under the path so it's a different shade
      path_region = path_region:duplicate()
      path_region:set_tag(path_block_type)
      path_region:translate(Point3(0, -1, 0))
      terrain:add_region(path_region)
   end

   return first_point, last_point, trans_path_region, path_entity, path_neighbor_entity
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
      
      stonehearth.game_speed:set_game_speed(0, true)
      tower_defense.game:start()
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
