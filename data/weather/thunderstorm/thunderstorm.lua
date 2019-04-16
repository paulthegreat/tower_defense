local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local WeightedSet = require 'lib.algorithms.weighted_set'
local rng = _radiant.math.get_default_rng()

local ThunderstormWeather = class()

local LIGHTNING_INTERVAL = '15m+30m'
local LIGHTNING_EFFECTS = {
   'stonehearth:effects:lightning_effect',
   'stonehearth:effects:lightning_effect2'
}
local LIGHTNING_GROUND_EFFECT = 'stonehearth:effects:lightning_impact_ground'
local LIGHTNING_TREE_EFFECT = 'stonehearth:effects:lightning_impact_tree'
local LIGHTNING_DAMAGE = 30
local LIGHTNING_TARGETS_SET = WeightedSet(rng)
LIGHTNING_TARGETS_SET:add('SPOT', 25)
LIGHTNING_TARGETS_SET:add('CITIZEN', 1)
local TREE_SEARCH_RADIUS = 3

function ThunderstormWeather:initialize()
   self._sv._lightning_timer = nil
end

function ThunderstormWeather:destroy()
   self:stop()
end

function ThunderstormWeather:start()
   self._sv._lightning_timer = stonehearth.calendar:set_persistent_timer('thunderstorm ligtning', LIGHTNING_INTERVAL, radiant.bind(self, '_spawn_lightning'))
end

function ThunderstormWeather:restore()
   if self._sv._lightning_interval then  -- Old savegames
      self._sv._lightning_interval:destroy()
      self._sv._lightning_interval = nil
   end
end

function ThunderstormWeather:stop()
   if self._sv._lightning_timer then
      self._sv._lightning_timer:destroy()
      self._sv._lightning_timer = nil
   end
end

function ThunderstormWeather:_spawn_lightning()
   local effect = LIGHTNING_EFFECTS[rng:get_int(1, #LIGHTNING_EFFECTS)]
   local target = LIGHTNING_TARGETS_SET:choose_random()
   if target == 'CITIZEN' and stonehearth.game_creation:get_game_mode() ~= 'stonehearth:game_mode:peaceful' then
      local citizen = self:_select_random_player_character(effect)
      if citizen then
         local location = radiant.entities.get_world_grid_location(citizen)
         if location and not stonehearth.terrain:is_sheltered(location) then
            radiant.effects.run_effect(citizen, effect)
            radiant.entities.modify_health(citizen, -LIGHTNING_DAMAGE)
            radiant.entities.add_buff(citizen, 'stonehearth:buffs:weather:hit_by_lightning')
         end
      end
   elseif target == 'SPOT' then
      -- Choose a point to hit.
      local terrain_bounds = stonehearth.terrain:get_bounds()
      local x = rng:get_int(terrain_bounds.min.x, terrain_bounds.max.x)
      local z = rng:get_int(terrain_bounds.min.z, terrain_bounds.max.z)

      -- Find a tree to hit near our chosen point.
      local tree
      local search_cube = Cube3(Point3(x - TREE_SEARCH_RADIUS, terrain_bounds.min.y, z - TREE_SEARCH_RADIUS),
                                Point3(x + TREE_SEARCH_RADIUS, terrain_bounds.max.y, z + TREE_SEARCH_RADIUS))
      for _, item in pairs(radiant.terrain.get_entities_in_cube(search_cube)) do
         local catalog_data = stonehearth.catalog:get_catalog_data(item:get_uri()) or {}
         if item:get_component('stonehearth:resource_node') and catalog_data.category == 'plants' then
            tree = item
            break
         end
      end

      if tree then
         local location = radiant.entities.get_world_grid_location(tree)
         self:_spawn_effect_at(location, effect)
         self:_spawn_effect_at(location, LIGHTNING_TREE_EFFECT)
         while tree:is_valid() do
            tree:get_component('stonehearth:resource_node'):spawn_resource(nil, location)
         end
      else
         local center = Point3(x, terrain_bounds.max.y, z)
         local target = Point3(x, terrain_bounds.min.y, z)
         local ground_point = _physics:shoot_ray(center, target, true, 0)

         -- Don't hit water.
         local search_cube = Cube3(ground_point - Point3(1, 2, 1),
                                   ground_point + Point3(1, 2, 1))
         local is_in_water = next(radiant.terrain.get_entities_in_cube(search_cube, function(e)
               return e:get_component('stonehearth:water') ~= nil
            end)) ~= nil
         if not is_in_water then
            ground_point.y = ground_point.y + 1  -- On top of the terain voxel.
            self:_spawn_effect_at(ground_point, effect)
            self:_spawn_effect_at(ground_point, LIGHTNING_GROUND_EFFECT)
         end
      end
   end
   self._sv._lightning_timer = stonehearth.calendar:set_persistent_timer('thunderstorm ligtning', LIGHTNING_INTERVAL, radiant.bind(self, '_spawn_lightning'))
end

function ThunderstormWeather:_spawn_effect_at(location, effect)
   local proxy = radiant.entities.create_entity('stonehearth:object:transient', { debug_text = 'thunderstorm ligtning effect anchor' })
   radiant.terrain.place_entity_at_exact_location(proxy, location)
   radiant.effects.run_effect(proxy, effect):set_finished_cb(function()
      radiant.entities.destroy_entity(proxy)
   end)
end

function ThunderstormWeather:_select_random_player_character()
   local pops = stonehearth.population:get_all_populations()

   local total_citizens = 0
   for _, pop in pairs(pops) do
      if not pop:is_npc() then
         total_citizens = total_citizens + pop:get_citizen_count()
      end
   end

   local selected_citizen_number = rng:get_int(1, total_citizens)
   for _, pop in pairs(pops) do
      if not pop:is_npc() then
         if selected_citizen_number > pop:get_citizen_count() then
            selected_citizen_number = selected_citizen_number - pop:get_citizen_count()
         end
         for _, citizen in pop:get_citizens():each() do
            selected_citizen_number = selected_citizen_number - 1
            if selected_citizen_number == 0 then
               return citizen
            end
         end
      end
   end

   return nil
end

return ThunderstormWeather
