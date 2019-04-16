local PopulationFaction = class()

function PopulationFaction:get_kingdom_id()
   return self._data and self._data.kingdom_id
end

function PopulationFaction:get_kingdom_level_costs()
   local cache = self._cached_kingdom_level_costs
   if not cache then
      cache = radiant.resources.load_json(self._data.kingdom_level_costs or 'tower_defense:data:kingdom_level_costs:default')
      self._cached_kingdom_level_costs = cache
   end
   return cache
end

return PopulationFaction
