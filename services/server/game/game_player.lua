local GamePlayer = class()

function GamePlayer:create(player_id, game_options)
   self._sv.player_id = player_id

   self._sv.gold = game_options.starting_gold or 0
end

-- for the common player, when a new player is added (for added initial gold)
function GamePlayer:add_player(game_options)
   self._sv.gold = self._sv.gold + (game_options.common_starting_gold or 0)

   self.__saved_variables:mark_changed()
end

return GamePlayer
