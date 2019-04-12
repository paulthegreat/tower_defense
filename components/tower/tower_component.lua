local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3

local TowerComponent = class()

local FILTER_HP_LOW = 'lowest_health'
local FILTER_HP_HIGH = 'highest_health'
local FILTER_CLOSEST_TO_TOWER = 'closest_to_tower'
local FILTER_CLOSEST_TO_END = 'closest_to_end'
local FILTER_SHORTEST_DEBUFF_TIME = 'shortest_debuff_time'
local FILTER_HIGHEST_DEBUFF_STACK = 'highest_debuff_stack'
local FILTER_MOST_TARGETS = 'most_targets'
local FILTER_TARGET_TYPE = 'target_type'

function TowerComponent:create()
   local wave = tower_defense.game:get_current_wave()
   if tower_defense.game:has_active_wave() then
      wave = wave - 1
   end
   self._sv._wave_created = wave
end

function TowerComponent:activate()
   self._json = radiant.entities.get_json(self) or {}
   if not self._json.targeting then
      self._json.targeting = {}
   end

   if self._sv.reveals_invis == nil then
      self._sv.reveals_invis = self._json.reveals_invis or false
      self.__saved_variables:mark_changed()
   end

   if not self._sv.target_filters then
      self:set_target_filters(self._json.targeting.target_filters)
   end

   if not self._sv.preferred_target_types then
      self:set_preferred_target_types(self._json.targeting.preferred_target_types)
   end

   -- update commands
   -- add a listener for wave change if necessary
   local cur_wave = tower_defense.game:get_current_wave()
   self:_update_sell_command(cur_wave)

   -- make sure we have any other commands, like auto-targeting and upgrade options


   -- set up a listener for added to / removed from world for registering/unregistering with tower service
   self._parent_trace = self._entity:add_component('mob'):trace_parent('tower added or removed')
      :on_changed(function(parent_entity)
            if not parent_entity then
               --we were just removed from the world
               self:_unregister()
            else
               --we were just added to the world
               self:_register()
            end
         end)
      :push_object_state()
end

function TowerComponent:destroy()
   self:_destroy_wave_listener()
end

function TowerComponent:reveals_invis()
   return self._sv.reveals_invis
end

function TowerComponent:get_targetable_region()
   return self._sv.targetable_region
end

function TowerComponent:get_targetable_path_region()
   return self._sv.targetable_path_region
end

function TowerComponent:attacks_ground()
   return self._sv.attacks_ground
end

function TowerComponent:attacks_air()
   return self._sv.attacks_air
end

function TowerComponent:set_target_filters(target_filters)
   self._sv.target_filters = target_filters or {}
   self.__saved_variables:mark_changed()
end

function TowerComponent:set_preferred_target_types(preferred_target_types)
   self._sv.preferred_target_types = preferred_target_types or {}
   self.__saved_variables:mark_changed()
end

function TowerComponent:get_best_target()
   -- first check what total targets are available
   -- then apply filters in order until we have a single tower remaining or we run out of filters
   -- return the first (if any) remaining tower
   if not self._sv.targetable_path_region or self._sv.targetable_path_region:empty() then
      return
   end

   local targets = radiant.values(radiant.terrain.get_entities_in_region(self._sv.targetable_path_region,
      function(entity)
         return entity:get_component('tower_defense:monster') ~= nil
      end))
   
   for _, filter in ipairs(self._sv.target_filters) do
      if #targets < 2 then
         break
      end

      local best_targets = {}
      local best_value

      for _, target in ipairs(targets) do
         local value = self:_get_filter_value(filter, target)
         if not best_value or value == best_value then
            best_value = value
            table.insert(best_targets, target)
         elseif value > best_value then
            best_targets = {target}
         end
      end

      targets = best_targets
   end

   return targets[1]
end

function TowerComponent:_get_filter_value(filter, target)
   if filter == FILTER_HP_LOW then
      return -(radiant.entities.get_health(target) or 0)
   elseif filter == FILTER_HP_HIGH then
      return radiant.entities.get_health(target) or 0
   elseif filter == FILTER_CLOSEST_TO_TOWER then
      return -radiant.entities.distance_between_entities(self._entity, target)
   elseif filter == FILTER_CLOSEST_TO_END then
      return -target:get_component('tower_defense:monster'):get_path_length()
   elseif filter == FILTER_SHORTEST_DEBUFF_TIME then
      
   elseif filter == FILTER_HIGHEST_DEBUFF_STACK then
      
   elseif filter == FILTER_MOST_TARGETS then

   elseif filter == FILTER_TARGET_TYPE then

   end

   return 0
end

function TowerComponent:_destroy_wave_listener()
   if self._wave_listener then
      self._wave_listener:destroy()
      self._wave_listener = nil
   end
   if self._parent_trace then
      self._parent_trace:destroy()
      self._parent_trace = nil
   end
end

function TowerComponent:_register()
   -- calculate targetable range and translate it to our location
   -- pass that in to the tower service registration function
   -- store the resulting targetable path intersection ranges
   self._location = radiant.entities.get_world_grid_location(self._entity)
   if self._location then
      local targetable_region = self:_create_targetable_region()
      self._sv.targetable_region = targetable_region
      if targetable_region then
         self._sv.attacks_ground = self._json.targeting.attacks_ground
         self._sv.attacks_air = self._json.targeting.attacks_air

         self._sv.targetable_path_region = tower_defense.tower:register_tower(self._entity, self._location)
      end
      self.__saved_variables:mark_changed()
   end
end

function TowerComponent:_unregister()
   tower_defense.tower:unregister_tower(self._entity)
end

function TowerComponent:_create_targetable_region()
   local targeting = self._json.targeting or {}
   local region
   if targeting.type == 'rectangle' then
      region = Region3(radiant.util.to_cube3(targeting.region))
   elseif targeting.type == 'circle' then
      -- create a blocky circle region
      region = Region3()
      local r2 = (targeting.radius + 0.5) * (targeting.radius + 0.5)
      for x = -targeting.radius, targeting.radius do
         local z_size = math.floor(math.sqrt(r2 - x * x))
         region:add_cube(Cube3(Point3(x, 0, -z_size), Point3(x + 1, 1, z_size + 1)))
      end
   end

   if region then
      region:optimize('targetable region')
   end

   return region
end

function TowerComponent:_on_wave_started(wave)
   if wave > self._sv._wave_created then
      self:_update_sell_command(wave)
   end
end

function TowerComponent:_update_sell_command(wave)
   local commands = self._entity:add_component('stonehearth:commands')
   if wave > self._sv._wave_created then
      commands:remove_command('tower_defense:commands:sell_full')
      commands:add_command('tower_defense:commands:sell_less')
   else
      commands:remove_command('tower_defense:commands:sell_less')
      commands:add_command('tower_defense:commands:sell_full')
      if not self._wave_listener then
         self._wave_listener = radiant.events.listen(radiant, 'tower_defense:wave_started', self, self._on_wave_started)
      end
   end
end

return TowerComponent
