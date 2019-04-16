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

local _target_filter_fn = function(entity)
   local monster_comp = entity:get_component('tower_defense:monster')
   return monster_comp and monster_comp:is_visible()
end

function TowerComponent:create()
   if radiant.is_server then
      local wave = tower_defense.game:get_current_wave()
      if tower_defense.game:has_active_wave() then
         wave = wave - 1
      end
      self._sv._wave_created = wave
   end
   self._sv.original_facing = 0
end

function TowerComponent:activate()
   self._json = radiant.entities.get_json(self) or {}
   if not self._json.targeting then
      self._json.targeting = {}
   end

   if not self._sv.original_facing then
      self._sv.original_facing = 0
   end

   if self._sv.reveals_invis == nil then
      self._sv.reveals_invis = self._json.reveals_invis or false
      self.__saved_variables:mark_changed()
   end

   if not radiant.is_server then
      self:_client_activate()
   else
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
end

-- as a client component, we just care about rendering regions
function TowerComponent:_client_activate()
   self:_load_targetable_region()
end

function TowerComponent:destroy()
   self:_destroy_listeners()
   if radiant.is_server then
      self:_unregister()
   end
end

function TowerComponent:_destroy_listeners()
   if self._wave_listener then
      self._wave_listener:destroy()
      self._wave_listener = nil
   end
   if self._parent_trace then
      self._parent_trace:destroy()
      self._parent_trace = nil
   end
end

function TowerComponent:reveals_invis()
   return self._sv.reveals_invis
end

function TowerComponent:get_targetable_region()
   return self._sv.targetable_region
end

function TowerComponent:_load_targetable_region()
   self._sv.targetable_region = self:_create_targetable_region()
   self.__saved_variables:mark_changed()
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

function TowerComponent:placed(rotation)
   self._sv.original_facing = rotation
   self.__saved_variables:mark_changed()
end

function TowerComponent:get_original_facing()
   return self._sv.original_facing
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

   local weapon = stonehearth.combat:get_main_weapon(self._entity)
   if not weapon or not weapon:is_valid() then
      return
   end

   local attack_types = stonehearth.combat:get_combat_actions(self._entity, 'stonehearth:combat:ranged_attacks')
   if not next(attack_types) then
      return
   end

   local attack_info = stonehearth.combat:choose_attack_action(self._entity, attack_types)
   if not attack_info then
      return
   end

   local targets = radiant.values(radiant.terrain.get_entities_in_region(self._sv.targetable_path_region, _target_filter_fn))
   
   local debuff_cache = {}

   for _, filter in ipairs(self._sv.target_filters) do
      if #targets < 2 then
         break
      end

      local best_targets = {}
      local best_value

      for _, target in ipairs(targets) do
         local value = self:_get_filter_value(filter, target, weapon, attack_info, debuff_cache)
         if not best_value or value == best_value then
            best_value = value
            table.insert(best_targets, target)
         elseif value > best_value then
            best_targets = {target}
         end
      end

      targets = best_targets
   end

   return targets[1], weapon, attack_info
end

function TowerComponent:_get_filter_value(filter, target, weapon, attack_info, debuff_cache)
   if filter == FILTER_HP_LOW then
      return -(radiant.entities.get_health(target) or 0)

   elseif filter == FILTER_HP_HIGH then
      return radiant.entities.get_health(target) or 0

   elseif filter == FILTER_CLOSEST_TO_TOWER then
      return -radiant.entities.distance_between_entities(self._entity, target)

   elseif filter == FILTER_CLOSEST_TO_END then
      return -target:get_component('tower_defense:monster'):get_path_length()
      
   elseif filter == FILTER_SHORTEST_DEBUFF_TIME then
      self:_verify_debuff_cache(debuff_cache, attack_info)
      if debuff_cache.total_duration > 0 then
         local buffs_comp = target:get_component('stonehearth:buffs')
         if not buffs_comp then
            return debuff_cache.total_duration
         end

         local diff = 0
         for uri, data in pairs(debuff_cache.debuffs) do
            local buff = buffs_comp:get_buff(uri)
            local duration = buff and buff:get_duration() or 0
            
            if duration >= 0 then
               -- the target doesn't have this debuff or it has a duration/expiration
               diff = diff + data.duration - duration * data.priority
            end
         end
         return diff
      end

   elseif filter == FILTER_HIGHEST_DEBUFF_STACK then
      self:_verify_debuff_cache(debuff_cache, attack_info)
      local buffs_comp = target:get_component('stonehearth:buffs')
      if not buffs_comp then
         return 0
      end

      local stacks = 0
      for uri, data in pairs(debuff_cache.debuffs) do
         stacks = stacks + (buffs_comp:get_buff_stacks(uri) or 0) * data.priority
      end
      return stacks
      
   elseif filter == FILTER_MOST_TARGETS then
      local reach = attack_info.aoe_effect and weapon.reach
      if reach then
         local cube = Cube3(radiant.entities.get_world_grid_location(target)):extruded('x', reach, reach):extruded('z', reach, reach)
         return radiant.size(radiant.terrain.get_entities_in_cube(cube, _target_filter_fn))
      end
      
   elseif filter == FILTER_TARGET_TYPE then

   end

   return 0
end

function TowerComponent:_verify_debuff_cache(debuff_cache, attack_info)
   if not debuff_cache.total_duration then
      local debuffs = stonehearth.combat:get_inflictable_debuffs(self._entity, attack_info)
      local exp_debuffs = {}

      -- store total debuff duration (no duration = 999) times priority (no priority = 1) for each debuff
      -- so we can subtract actual value from potential
      local total_duration = 0
      for _, debuff in ipairs(debuffs) do
         local exp_debuff = radiant.resources.load_json(debuff)
         local priority = exp_debuff.priority or 1
         local duration = (exp_debuff.duration and stonehearth.calendar:parse_duration(exp_debuff.duration) or 999) * priority
         
         exp_debuffs[debuff] = {
            data = exp_debuff,
            priority = priority,
            duration = duration
         }
         total_duration = total_duration + duration
      end

      debuff_cache.debuffs = exp_debuffs
      debuff_cache.total_duration = total_duration
   end
end

function TowerComponent:_register()
   -- calculate targetable range and translate it to our location
   -- pass that in to the tower service registration function
   -- store the resulting targetable path intersection ranges
   self._location = radiant.entities.get_world_grid_location(self._entity)
   if self._location then
      self:_load_targetable_region()
      if self._sv.targetable_region then
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
      region = Region3(radiant.util.to_cube3(targeting.region)):translated(Point3(-.5, 0, -.5)):rotated(radiant.entities.get_facing(self._entity)):translated(Point3(.5, 0, .5))
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
