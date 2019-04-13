local GamePlayer = class()

function GamePlayer:create(player_id, game_options)
   self._sv.player_id = player_id

   for _, resource in pairs(stonehearth.constants.tower_defense.player_resources) do
      self._sv[resource] = game_options['starting_' .. resource] or 0
   end
end

-- for the common player, when a new player is added (for added initial gold)
function GamePlayer:add_player(game_options)
   for _, resource in pairs(stonehearth.constants.tower_defense.player_resources) do
      self._sv[resource] = self._sv[resource] + game_options['common_starting_' .. resource] or 0
   end

   self.__saved_variables:mark_changed()
end

function GamePlayer:get_resource(resource)
   return self._sv[resource]
end

function GamePlayer:add_resource(resource, amount)
   if amount and amount > 0 then
      self._sv[resource] = self._sv[resource] + amount
      self.__saved_variables:mark_changed()
   end
end

-- takes as much as possible up to amount and returns the amount taken
function GamePlayer:take_resource(resource, amount)
   local has_amount = self._sv[resource]
   amount = math.max(0, math.min(amount, has_amount))
   
   if amount > 0 then
      self._sv[resource] = has_amount - amount
      self.__saved_variables:mark_changed()
   end

   return amount
end

-- only_self if cannot spend from common player
function GamePlayer:spend_resource(resource, amount, only_self)
   local has_amount = self._sv[resource]
   local success

   if amount <= has_amount then
      success = true
   elseif not only_self then
      -- check the common player to see if we can take enough from them
      local common_player = tower_defense.game:get_common_player()
      success = common_player:spend_resource(resource, amount - has_amount, true)
      amount = has_amount
   end

   if success then
      self._sv[resource] = has_amount - amount
      self.__saved_variables:mark_changed()
   end

   return success
end

return GamePlayer
