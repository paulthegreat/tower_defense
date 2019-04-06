GameCreationService = class()

function GameCreationService:start_game_command(session, response)
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

return GameCreationService
