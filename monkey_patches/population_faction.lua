local PopulationFaction = class()

function PopulationFaction:get_kingdom_id()
   return self._data and self._data.kingdom_id
end

return PopulationFaction
