local validator = radiant.validator

GameCreationService = class()

function GameCreationService:new_game_command(session, response, num_tiles_x, num_tiles_y, seed, options, starting_data)
	--if no kingdom has been set for the player yet, set it to ascendancy
	if not stonehearth.player:get_kingdom(session.player_id) then
		stonehearth.player:add_kingdom(session.player_id, "stonehearth:kingdoms:ascendancy")
	end

	local pop = stonehearth.population:get_population(session.player_id)
	pop:set_game_options(options)

	return {}
end

function GameCreationService:generate_start_location_command(session, response, feature_cell_x, feature_cell_y, map_info)
	self:_generate_world(session, response, map_info)
	self:start_game(session)
end

function GameCreationService:_generate_world(session, response, map_info)
	if validator.is_host_player(session) then
		-- generate the world!

		local biome = nil
		stonehearth.world_generation:create_empty_world(biome)

		local height = 5
		if self._height then 
		  height = self._height
		end

		local size = 32
		assert(size % 2 == 0)
		local half_size = size / 2

		local block_types = radiant.terrain.get_block_types()

		local region3 = Region3()
		region3:add_cube(Cube3(Point3(0, -2, 0), Point3(size, 0, size), block_types.bedrock))
		region3:add_cube(Cube3(Point3(0, 0, 0), Point3(size, height-1, size), block_types.soil_dark))
		region3:add_cube(Cube3(Point3(0, height-1, 0), Point3(size, height, size), block_types.grass))
		region3 = region3:translated(Point3(-half_size, 0, -half_size))

		radiant.terrain.get_terrain_component():add_tile(region3)
	end
end

function GameCreationService:start_game(session)
	local player_id = session.player_id
	local pop = stonehearth.population:get_population(player_id)
	local game_options = pop:get_game_options()
	
	tower_defense.game:add_player(player_id, game_options)
	
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
	end
end

function GameCreationService:get_game_world_options_commands(session, response)
	response:resolve({
		game_mode = self._sv.game_mode,
		biome = stonehearth.world_generation:get_biome_alias(),
		-- any other options, like more generous starting gold, etc.
	})
end

return GameCreationService
