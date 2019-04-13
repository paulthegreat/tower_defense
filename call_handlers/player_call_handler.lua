local PlayerCallHandler = class()

function PlayerCallHandler:give_gold_cheat_command(session, response, amount)
   tower_defense.game:add_player_gold(session.player_id, amount)
end

return PlayerCallHandler
