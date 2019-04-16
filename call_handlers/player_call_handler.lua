local PlayerCallHandler = class()

function PlayerCallHandler:give_gold_cheat_command(session, response, amount)
   tower_defense.game:add_player_gold(session.player_id, amount)
end

function PlayerCallHandler:give_wood_cheat_command(session, response, amount)
   tower_defense.game:add_player_wood(session.player_id, amount)
end

function PlayerCallHandler:donate_gold_command(session, response, amount)
   if tower_defense.game:donate_gold(session.player_id, amount) then
      response:resolve({})
   else
      response:reject({})
   end
end

function PlayerCallHandler:unlock_kingdom_command(session, response, kingdom)
   local player_id = session.player_id
   local player = tower_defense.game:get_player(player_id)
   if player then
      local result = player:try_add_kingdom_level(kingdom)
      if result.resolve then
         response:resolve(result)
      else
         response:reject(result)
      end
   else
      response:reject('invalid player')
   end
end

return PlayerCallHandler
