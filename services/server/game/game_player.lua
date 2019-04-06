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

function GamePlayer:get_gold()
   return self._sv.gold
end

function GamePlayer:add_gold(amount)
   if amount and amount > 0 then
      self._sv.gold = self._sv.gold + amount
      self.__saved_variables:mark_changed()
   end
end

-- takes as much as possible up to amount and returns the amount taken
function GamePlayer:take_gold(amount)
   local gold = self._sv.gold
   amount = math.max(0, math.min(amount, gold))
   
   if amount > 0 then
      self._sv.gold = gold - amount
      self.__saved_variables:mark_changed()
   end

   return amount
end

-- only_self if cannot spend from common player
function GamePlayer:spend_gold(amount, only_self)
   local gold = self._sv.gold
   local success

   if amount <= gold then
      success = true
   elseif not only_self then
      -- check the common player to see if we can take enough from them
      local common_player = tower_defense.game:get_common_player()
      success = common_player:spend_gold(amount - gold, true)
      amount = gold
   end

   if success then
      self._sv.gold = gold - amount
      self.__saved_variables:mark_changed()
   end

   return success
end

return GamePlayer
