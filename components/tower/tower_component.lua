local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3

local AssaultContext = require 'stonehearth.services.server.combat.assault_context'
local BatteryContext = require 'stonehearth.services.server.combat.battery_context'

local log = radiant.log.create_logger('tower_component')

local TowerComponent = class()

local STATES = {
   IDLE = 'idle', -- not doing anything, i.e. between waves
   WAITING_FOR_TARGETABLE = 'waiting_for_targetable', -- waiting until there are any targets within range
   WAITING_FOR_COOLDOWN = 'waiting_for_cooldown',  -- waiting until shortest ability cooldown is done
   FINDING_TARGET = 'finding_target',   -- finding a target to use ability on
}

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

      self._sv.sm = radiant.create_controller('radiant:state_machine')
      self._sv.sm:set_log_entity(self._entity)
   end
   self._sv.original_facing = 0
end

function TowerComponent:restore()
   self._is_restore = true
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

   if not radiant.is_server then
      self:_client_activate()
   else
      self._shoot_timers = {}

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
   end
end

-- as a client component, we just care about rendering regions
function TowerComponent:_client_activate()
   self:_load_targetable_region()
end

function TowerComponent:post_activate()
   if radiant.is_server then
      self:_initialize()
      
      local sm = self._sv.sm
      self:_declare_states(sm)
      self:_declare_triggers(sm)
      self:_declare_state_event_handlers(sm)
      self:_declare_state_transitions(sm)
      sm:start(self._is_restore)
   end
end

function TowerComponent:destroy()
   self:_destroy_listeners()
   if self._sv.sm then
      self._sv.sm:destroy()
      self._sv.sm = nil
   end
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

   local weapon = self._weapon
   if not weapon or not weapon:is_valid() then
      return
   end

   local attack_types = self._attack_types
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

   return targets[1], attack_info
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
   for timer, _ in pairs(self._shoot_timers) do
      timer:destroy()
   end
   self._shoot_timers = {}
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

--[[
   state machine stuff for targeting/acting
]]

function TowerComponent:_initialize()
   self:_unregister()
   self._weapon = stonehearth.combat:get_main_weapon(self._entity)
   self._combat_state = self._entity:add_component('stonehearth:combat_state')
   self._weapon_data = self._weapon and self._weapon:is_valid() and radiant.entities.get_entity_data(self._weapon, 'stonehearth:combat:weapon_data')
   self._attack_types = self._weapon_data and stonehearth.combat:get_combat_actions(self._entity, 'stonehearth:combat:ranged_attacks') or {}
   self:_register()
end

function TowerComponent:_reinitialize(sm)
   self:_initialize()

   if next(self._attack_types) and self._sv.targetable_path_region and not self._sv.targetable_path_region:empty() and tower_defense.game:has_active_wave() then
      sm:go_into(STATES.WAITING_FOR_COOLDOWN)
   else
      sm:go_into(STATES.IDLE)
   end
end

function TowerComponent:_destroy_cooldown_listener()
   if self._cooldown_listener then
      self._cooldown_listener:destroy()
      self._cooldown_listener = nil
   end
end

function TowerComponent:_set_idle()
   self:_set_status_text_key('stonehearth:ai.actions.status_text.idle')
   radiant.entities.turn_to(self._entity, self._sv.original_facing)
end

function TowerComponent:_get_shortest_cooldown(attack_types)
   local shortest_cd
   local now = radiant.gamestate.now()
   for _, action_info in ipairs(attack_types) do
      local cd = self._combat_state:get_cooldown_end_time(action_info.name)
      cd = cd and (cd - now) or 0
      if not shortest_cd or cd < shortest_cd then
         shortest_cd = cd
         if cd <= 0 then
            break
         end
      end
   end

   return shortest_cd
end

function TowerComponent:_stop_current_effect()
   if self._current_effect then
      self._current_effect:stop()
      self._current_effect = nil
   end
end

function TowerComponent:_find_target_and_engage(sm)
   local target, attack_info = self:get_best_target()
   if not target then
      log:debug('%s couldn\'t find target, going to waiting_for_targetable', self._entity)
      sm:go_into(STATES.WAITING_FOR_TARGETABLE)
   else
      log:debug('%s found target, going to engage %s', self._entity, target)
      self._current_target = target
      self._current_attack_info = attack_info
      sm:go_into(STATES.FINDING_TARGET)
   end
end

function TowerComponent:_engage_current_target(sm)
   local target = self._current_target
   local weapon_data = self._weapon_data
   local attack_info = self._current_attack_info

   if not target or not target:is_valid() or not weapon_data or not attack_info then
      log:error('target/weapon/attack_info was null when trying to _engage_current_target')
      return
   end

   self:_set_status_text_key('stonehearth:ai.actions.status_text.attack_melee_adjacent', { target = target })

   self:_stop_current_effect()
   radiant.entities.turn_to_face(self._entity, target)
   stonehearth.combat:start_cooldown(self._entity, attack_info)

   -- if we have a tower effect, start it up
   if attack_info.effect then
      self._current_effect = radiant.effects.run_effect(self._entity, attack_info.effect)
   end

   for i, time in ipairs(attack_info.attack_times) do
      local shoot_timer
      shoot_timer = stonehearth.combat:set_timer('tower attack shoot', time, function()
         self._shoot_timers[shoot_timer] = nil
         self:_shoot(target, attack_info)
         if i == #attack_info.attack_times then
            sm:go_into(STATES.WAITING_FOR_COOLDOWN)
         end
      end)
      self._shoot_timers[shoot_timer] = true
   end
   
   return true
end

function TowerComponent:_shoot(target, attack_info)
   if not target:is_valid() then
      return
   end

   local attacker = self._entity
   local assault_context
   local impact_time = radiant.gamestate.now()

   -- if we have projectile data, create and launch the projectile, running combat effects upon completion
   -- otherwise, run them immediately
   local finish_fn = function(projectile, impact_trace)
      if target:is_valid() and not projectile or projectile:is_valid() then
         if not assault_context.target_defending then
            if attack_info.hit_effect then
               radiant.effects.run_effect(target, attack_info.hit_effect)
            end
            local total_damage = stonehearth.combat:calculate_ranged_damage(attacker, target, attack_info)
            local battery_context = BatteryContext(attacker, target, total_damage)
            stonehearth.combat:inflict_debuffs(attacker, target, attack_info)
            stonehearth.combat:battery(battery_context)
         end
      end

      if assault_context then
         stonehearth.combat:end_assault(assault_context)
         assault_context = nil
      end

      if impact_trace then
         impact_trace:destroy()
         impact_trace = nil
      end
   end

   if attack_info.projectile then
      local attacker_offset, target_offset = self:_get_projectile_offsets(attack_info.projectile)
      local projectile = self:_create_projectile(attacker, target, attack_info.projectile.speed, attack_info.projectile.uri, attacker_offset, target_offset)
      local projectile_component = projectile:add_component('stonehearth:projectile')
      local flight_time = projectile_component:get_estimated_flight_time()
      impact_time = impact_time + flight_time

      local impact_trace
      impact_trace = radiant.events.listen(projectile, 'stonehearth:combat:projectile_impact', function()
            finish_fn(projectile, impact_trace)
         end)

      local destroy_trace
      destroy_trace = radiant.events.listen(projectile, 'radiant:entity:pre_destroy', function()
            if assault_context then
               stonehearth.combat:end_assault(assault_context)
               assault_context = nil
            end

            if destroy_trace then
               destroy_trace:destroy()
               destroy_trace = nil
            end
         end)
   end

   assault_context = AssaultContext('melee', attacker, target, impact_time)
   stonehearth.combat:begin_assault(assault_context)

   if not attack_info.projectile then
      finish_fn()
   end
end

function TowerComponent:_create_projectile(attacker, target, projectile_speed, projectile_uri, attacker_offset, target_offset)
   projectile_uri = projectile_uri or 'stonehearth:weapons:arrow' -- default projectile is an arrow
   local projectile = radiant.entities.create_entity(projectile_uri, { owner = attacker })
   local projectile_component = projectile:add_component('stonehearth:projectile')
   projectile_component:set_speed(projectile_speed or 1)
   projectile_component:set_target_offset(target_offset)
   projectile_component:set_target(target)

   local projectile_origin = self:_get_world_location(attacker_offset, attacker)
   radiant.terrain.place_entity_at_exact_location(projectile, projectile_origin)

   projectile_component:start()
   return projectile
end

-- local_to_world not doing the right thing
function TowerComponent:_get_world_location(point, entity)
   local mob = entity:add_component('mob')
   local facing = mob:get_facing()
   local entity_location = mob:get_world_location()

   local offset = radiant.math.rotate_about_y_axis(point, facing)
   local world_location = entity_location + offset
   return world_location
end

function TowerComponent:_get_projectile_offsets(projectile_data)
   local attacker_offset = Point3(-0.5, 0.8, -0.5)
   local target_offset = Point3(0, 1, 0)

   if projectile_data then
      local projectile_start_offset = projectile_data.start_offset
      local projectile_end_offset = projectile_data.end_offset
      -- Get start and end offsets from weapon data if provided
      if projectile_start_offset then
         attacker_offset = Point3(projectile_start_offset.x,
                                       projectile_start_offset.y,
                                       projectile_start_offset.z)
      end
      if projectile_end_offset then
         target_offset = Point3(projectile_end_offset.x,
                                       projectile_end_offset.y,
                                       projectile_end_offset.z)
      end
   end

   return attacker_offset, target_offset
end

function TowerComponent:_set_status_text_key(key, data)
   self._sv.status_text_key = key
   if data and data['target'] then
      local entity = data['target']
      if type(entity) == 'string' then
         local catalog_data = stonehearth.catalog:get_catalog_data(entity)
         if catalog_data then
            data['target_display_name'] = catalog_data.display_name
            data['target_custom_name'] = ''
         end
      elseif entity and entity:is_valid() then
         data['target_display_name'] = radiant.entities.get_display_name(entity)
         data['target_custom_name']  = radiant.entities.get_custom_name(entity)
      end
      data['target'] = nil
   end
   self._sv.status_text_data = data
   self.__saved_variables:mark_changed()
end

function TowerComponent:_declare_states(sm)
   sm:add_states(STATES)
   sm:set_start_state(STATES.IDLE)
end

function TowerComponent:_declare_triggers(sm)
   sm:trigger_on_event('tower_defense:wave_started', radiant, {
      states = {
         STATES.IDLE,
      },
   })

   sm:trigger_on_event('tower_defense:tower:monster_entered_range', self._entity, {
      states = {
         STATES.WAITING_FOR_TARGETABLE,
      },
   })

   sm:trigger_on_event('tower_defense:wave:ended', radiant, {
      states = {
         STATES.WAITING_FOR_TARGETABLE,
         STATES.WAITING_FOR_COOLDOWN,
         STATES.FINDING_TARGET
      },
   })

   sm:trigger_on_event('stonehearth:equipment_changed', self._entity, {
      states = {
         STATES.IDLE,
         STATES.WAITING_FOR_TARGETABLE,
         STATES.WAITING_FOR_COOLDOWN,
         STATES.FINDING_TARGET
      },
   })
end

function TowerComponent:_declare_state_event_handlers(sm)
   sm:on_state_event_triggered(STATES.IDLE, {
      ['tower_defense:wave_started'] = function(event_args, event_source)
         if self._attack_types and next(self._attack_types) and self._sv.targetable_path_region and not self._sv.targetable_path_region:empty() then
            sm:go_into(STATES.WAITING_FOR_TARGETABLE)
         end
      end,
      ['stonehearth:equipment_changed'] = function(event_args, event_source)
         self:_reinitialize(sm)
      end,
   })

   sm:on_state_event_triggered(STATES.WAITING_FOR_TARGETABLE, {
      ['tower_defense:tower:monster_entered_range'] = function(event_args, event_source)
         sm:go_into(STATES.WAITING_FOR_COOLDOWN)
      end,
      ['tower_defense:wave:ended'] = function(event_args, event_source)
         sm:go_into(STATES.IDLE)
      end,
      ['stonehearth:equipment_changed'] = function(event_args, event_source)
         self:_reinitialize(sm)
      end,
   })
   
   sm:on_state_event_triggered(STATES.WAITING_FOR_COOLDOWN, {
      ['tower_defense:wave:ended'] = function(event_args, event_source)
         sm:go_into(STATES.IDLE)
      end,
      ['stonehearth:equipment_changed'] = function(event_args, event_source)
         self:_reinitialize(sm)
      end,
   })
   
   sm:on_state_event_triggered(STATES.FINDING_TARGET, {
      ['tower_defense:wave:ended'] = function(event_args, event_source)
         sm:go_into(STATES.IDLE)
      end,
      ['stonehearth:equipment_changed'] = function(event_args, event_source)
         self:_reinitialize(sm)
      end,
   })
end

function TowerComponent:_declare_state_transitions(sm)
   sm:on_state_enter(STATES.IDLE, function(restoring)
         self:_set_idle()
      end, true)

   sm:on_state_enter(STATES.WAITING_FOR_TARGETABLE, function(restoring)
         self:_set_idle()   
         tower_defense.game:register_waiting_for_target(self._sv.targetable_path_region, function()
            sm:go_into(STATES.WAITING_FOR_COOLDOWN)
         end)
      end, true)

   sm:on_state_enter(STATES.WAITING_FOR_COOLDOWN, function(restoring)
         local cd = math.max(0, self:_get_shortest_cooldown(self._attack_types))
         self._cooldown_listener = stonehearth.combat:set_timer('wait for attack cooldown', cd, function()
            self:_find_target_and_engage(sm)
         end)
      end, true)

   sm:on_state_enter(STATES.FINDING_TARGET, function(restoring)
         self:_engage_current_target(sm)
      end, true)

   sm:on_state_exit(STATES.WAITING_FOR_TARGETABLE, function(restoring)
         tower_defense.game:register_waiting_for_target(self._sv.targetable_path_region, nil)
      end, true)

   sm:on_state_exit(STATES.WAITING_FOR_COOLDOWN, function(restoring)
         self:_destroy_cooldown_listener()
      end, true)

end

return TowerComponent
