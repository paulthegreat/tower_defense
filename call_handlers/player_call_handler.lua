local PlayerCallHandler = class()

function PlayerCallHandler:give_gold_cheat_command(session, response, amount)
   local player = tower_defense.game:get_player(session.player_id)
   if player then
      player:add_gold(amount)
   end
end

return PlayerCallHandler
