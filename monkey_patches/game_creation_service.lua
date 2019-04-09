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
   
   stonehearth.world_generation:create_empty_world(options.biome_src)

   local result = {
      map_info = {}
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
		local map=radiant.resources.load_json("tower_defense:data:map_generation")

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
      local path = map.path
      local width = path.width or 3
      local last_point
      local top = Point3(0, height - 1, 0)
      for _, point in ipairs(path.points) do
			local this_point = Point3(unpack(point))
			if last_point then
				terrain:subtract_cube(csg_lib.create_cube(last_point + top, this_point + top):extruded('x', width, width):extruded('z', width, width))
			end
			last_point = this_point
      end
      
      -- hacky edge shading fix (add a null terrain block super far below us)
      terrain:add_cube(Cube3(Point3(-1, -999999, -1), Point3(0, -999998, 0), block_types.null))

		--move the region to be centered
		terrain = terrain:translated(Point3(-half_size, 0, -half_size))
      radiant.terrain.get_terrain_component():add_tile(terrain)
      
      -- finally, add any entities that should start out in the world
      local entities = map.entities
      local offset = Point3(-half_size, height, -half_size)
      for uri, entity_list in pairs(entities) do
         for _, entity_data in ipairs(entity_list) do
            local entity = radiant.entities.create_entity(uri, { owner = '' })
            radiant.terrain.place_entity(entity, Point3(unpack(entity_data.location)) + offset, { force_iconic = false })
            radiant.entities.turn_to(entity, entity_data.facing or 0)
         end
      end

      self:on_world_generation_complete()

      if map.spawn_location then
         map.spawn_location = Point3(unpack(map.spawn_location))
      end
      map.spawn_location = (map.spawn_location or top) + offset

      tower_defense.game:set_map_data(map)

		-- local height = 5
		-- local width=map.path.width or 3
		-- local size = map.world_size or 32
		-- assert(size % 2 == 0)
		-- local half_size = size / 2

		-- local block_types = radiant.terrain.get_block_types()
		-- local region3 = Region3()
		-- --basic slab of stone and grass
		-- region3:add_cube(Cube3(Point3(0, -2, 0), Point3(size, 0, size), block_types.bedrock))
		-- region3:add_cube(Cube3(Point3(0, 0, 0), Point3(size, height-1, size), block_types.soil_dark))
		-- region3:add_cube(Cube3(Point3(0, height-1, 0), Point3(size, height, size), block_types.grass))
		-- --remove the path from the grass layer
		-- local lastpoint=nil
		-- local top=Point3(0,height-1,0)
		-- for _,v in ipairs(map.path.points) do
		-- 	local thispoint=Point3(unpack(v))
		-- 	if lastpoint then
		-- 		region3:subtract_cube(csg_lib.create_cube(lastpoint+top,thispoint+top):extruded('x',width,width):extruded('z',width,width))
		-- 	end
		-- 	lastpoint=thispoint
		-- end
		-- --move the region to be centered
		-- region3 = region3:translated(Point3(-half_size, 0, -half_size))

		-- radiant.terrain.get_terrain_component():add_tile(region3)
		
		-- local hacky_edge_shading_fix = Region3()
		-- hacky_edge_shading_fix:add_cube(Cube3(Point3(-half_size-1, -999999, -half_size-1), Point3(-half_size, -999998, -half_size), block_types.null))
		-- radiant.terrain.get_terrain_component():add_tile(hacky_edge_shading_fix)

      -- local end_gate = map.path.end_gate
      -- if end_gate then
      --    local exit_gate = radiant.entities.create_entity(end_gate.uri, { owner = session.player_id })
      --    radiant.terrain.place_entity(exit_gate, Point3(unpack(end_gate.location)), { force_iconic = false })
      --    radiant.entities.turn_to(exit_gate, end_gate.facing)
      -- end
      
      -- self:on_world_generation_complete()
	end
end

function GameCreationService:start_game(session)
	local player_id = session.player_id
	local pop = stonehearth.population:get_population(player_id)
	local game_options = pop:get_game_options()
	
   tower_defense.game:add_player(player_id, game_options)
   
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
