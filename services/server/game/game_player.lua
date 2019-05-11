local GamePlayer = class()

function GamePlayer:create(player_id, starting_resources)
   self._sv.player_id = player_id

   for _, resource in pairs(stonehearth.constants.tower_defense.player_resources) do
      self._sv[resource] = starting_resources[resource] or 0
   end

   self._sv.kingdoms = {}
   self.__saved_variables:mark_changed()

   self._is_create = true
end

function GamePlayer:post_activate()
   local pop = stonehearth.population:get_population(self._sv.player_id)
   
   -- common player doesn't have a population
   if pop then
      if self._is_create then
         local kingdom_id = pop:get_kingdom_id()
         if kingdom_id then
            self._sv.kingdoms[kingdom_id] = 1
         end
      end

      self._sv.kingdom_level_costs = pop:get_kingdom_level_costs() or {}
   else
      self._sv.kingdom_level_costs = {}
   end
   self.__saved_variables:mark_changed()
   -- ^^ this is in saved variables so it's simpler to remote to client
end

-- for the common player, when a new player is added (for added initial gold)
function GamePlayer:add_player(common_starting_resources)
   for _, resource in pairs(stonehearth.constants.tower_defense.player_resources) do
      self._sv[resource] = self._sv[resource] + (common_starting_resources[resource] or 0)
   end

   self.__saved_variables:mark_changed()
end

function GamePlayer:try_add_kingdom_level(kingdom)
   -- check if the player can afford it
   -- if so, proceed and return 'resolve' as a table key
   -- otherwise, return 'reject' as a table key along with missing resources
   local cost = self:_get_kingdom_level_cost(kingdom)
   local result = {}
   if not cost then
      -- everything has a cost... if we can get it
      result.reject = true
      result.message = 'i18n(tower_defense:alerts.add_kingdom_level.unavailable)'
   else
      for resource, amount in pairs(cost) do
         local missing = self:can_spend_resource(resource, amount)
         if missing > 0 then
            result[resource] = missing
         end
      end
   end

   if not result.reject and next(result) then
      result.reject = true
      result.message = 'i18n(tower_defense:alerts.add_kingdom_level.missing_resources)'
   end
   
   if not result.reject then
      for resource, amount in pairs(cost) do
         self:spend_resource(resource, amount)
      end
      self:_add_kingdom_level(kingdom)
      
      result.resolve = true
      result.message = 'i18n(tower_defense:alerts.add_kingdom_level.success)'
   end

   return result
end

function GamePlayer:_get_kingdom_level_cost(kingdom)
   local kingdom_costs = self._sv.kingdom_level_costs[kingdom]
   local next_level = (self._sv.kingdoms[kingdom] or 0) + 1
   return kingdom_costs and kingdom_costs[next_level]
end

function GamePlayer:_add_kingdom_level(kingdom)
   self._sv.kingdoms[kingdom] = (self._sv.kingdoms[kingdom] or 0) + 1
   self.__saved_variables:mark_changed()
end

function GamePlayer:get_resource(resource)
   return self._sv[resource]
end

function GamePlayer:add_resource(resource, amount)
   if amount and amount >= 1 then
      self._sv[resource] = self._sv[resource] + math.floor(amount)
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

function GamePlayer:can_spend_resource(resource, amount)
   -- don't actually spend it, just see if you can
   local has_amount = self._sv[resource]
   
   local common_player = tower_defense.game:get_common_player()
   if self ~= common_player then
      has_amount = has_amount + common_player:get_resource(resource)
   end

   return amount - has_amount
end

return GamePlayer
