local rng = _radiant.math.get_default_rng()
local constants = require 'stonehearth.constants'
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

function PopulationFaction:get_role_entity_uris(role, gender)
   return self:_get_citizen_uris_from_role(role, self:get_role_data(role), gender)
end

function PopulationFaction:_get_citizen_uris_from_role(role, role_data, gender)
   --If there is no gender, default to male
   if not role_data[gender] then
      gender = constants.population.DEFAULT_GENDER
   end
   local entities = role_data[gender].uri
   if not self._sv.is_npc and role_data[gender].uri_pc then
      entities = role_data[gender].uri_pc
   end
   if not entities then
      error(string.format('role %s in population has no gender table for %s', role, gender))
   end

   return entities
end

function PopulationFaction:_generate_citizen_from_role(role, role_data, gender)
   local uris = self:_get_citizen_uris_from_role(role, role_data, gender)
   local uri = uris[rng:get_int(1, #uris)]
   return self:create_entity(uri)
end

return PopulationFaction
