local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3

local AssaultContext = require 'stonehearth.services.server.combat.assault_context'
local BatteryContext = require 'stonehearth.services.server.combat.battery_context'

local log = radiant.log.create_logger('tower_component')
local rng = _radiant.math.get_default_rng()

local TowerComponent = class()

local STATES = {
   IDLE = 'idle', -- not doing anything, i.e. between waves
   WAITING_FOR_TARGETABLE = 'waiting_for_targetable', -- waiting until there are any targets within range
   WAITING_FOR_COOLDOWN = 'waiting_for_cooldown',  -- waiting until shortest ability cooldown is done
   FINDING_TARGET = 'finding_target',   -- finding a target to use ability on
}

local MAX_PATH_HEIGHT_DIFFERENTIAL = 10 -- used for creating target regions for aoe attacks that can hit both ground and air
local TARGET_DEFAULTS
local TARGET_DEFAULTS_BY_KEY
local FILTER_TYPES

local _target_filter_fn = function(entity)
   local monster_comp = entity:get_component('tower_defense:monster')
   return monster_comp and monster_comp:is_visible()
end

local _ignore_target_invis_filter_fn = function(entity)
   return entity:get_component('tower_defense:monster') ~= nil
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
      self._sv.stats = radiant.create_controller('tower_defense:tower_stats', wave)
   else
      self._sv.is_client_entity = true
   end
   self._sv.original_facing = 0
end

function TowerComponent:restore()
   self._is_restore = true
end

function TowerComponent:activate()
   self._json = radiant.entities.get_json(self) or {}
   
   self._target_hit_trace = radiant.events.listen(self._entity, 'stonehearth:combat:target_hit', self, self._on_target_hit)

   if radiant.is_server then
      if not TARGET_DEFAULTS then
         TARGET_DEFAULTS = stonehearth.constants.tower_defense.tower.target_defaults
         TARGET_DEFAULTS_BY_KEY = {}
         for _, defaults in pairs(TARGET_DEFAULTS) do
            TARGET_DEFAULTS_BY_KEY[defaults.key] = defaults
         end
      end
      if not FILTER_TYPES then
         FILTER_TYPES = stonehearth.constants.tower_defense.tower.target_filters
      end
      self._shoot_timers = {}
      self._facing_targets = {}

      -- update commands
      -- add a listener for wave change if necessary
      local cur_wave = tower_defense.game:get_current_wave()
      self:_update_sell_command(cur_wave)

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

function TowerComponent:post_activate()
   -- only initialize here for the client (or if restoring)
   -- otherwise we wait until after the tower is "placed" to make sure its rotation is properly set
   if self._is_restore or not radiant.is_server then
      self:_initialize()
   end
   
   if radiant.is_server then
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
   self:_stop_current_effect()
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
   if self._gameloop_listener then
      self._gameloop_listener:destroy()
      self._gameloop_listener = nil
   end
   if self._target_hit_trace then
      self._target_hit_trace:destroy()
      self._target_hit_trace = nil
   end
   self:_destroy_cooldown_listener()
end

function TowerComponent:get_stats()
   return self._sv.stats
end

function TowerComponent:_initialize(equipment_changed)
   if radiant.is_server then
      self:_unregister()
      self._weapon = stonehearth.combat:get_main_weapon(self._entity)
      if (not self._weapon or not self._weapon:is_valid()) and self._json.default_weapon then
         local prev_weapon
         prev_weapon, self._weapon = radiant.entities.equip_item(self._entity, self._json.default_weapon)
         if prev_weapon then
            log:error('there wasn\'t a primary weapon for %s, but %s got replaced by the default equipment %s!', self._entity, prev_weapon, self._weapon)
            return
         end
         if self._weapon and not self._weapon:is_valid() then
            self._weapon = nil
         end

         -- if there was no weapon and we equipped the default weapon, add upgrade commands
         local commands = self._entity:add_component('stonehearth:commands')
         local upgrades = self._json.upgrades or {}
         if upgrades.damage then
            commands:add_command('tower_defense:commands:upgrade_tower_damage')
         end
         if upgrades.utility then
            commands:add_command('tower_defense:commands:upgrade_tower_utility')
         end
      end
   else
      self._weapon = self._json.default_weapon
   end

   if self._weapon then
      local weapon_uri = type(self._weapon) == 'string' and self._weapon or self._weapon:get_uri()
      self._sv.can_upgrade = (weapon_uri == self._json.default_weapon) and (self._json.upgrades ~= nil and radiant.size(self._json.upgrades) > 0)
   end

   self._combat_state = self._entity:add_component('stonehearth:combat_state')
   self._weapon_data = self._weapon and radiant.entities.get_entity_data(self._weapon, 'stonehearth:combat:weapon_data')
   self:_load_targetable_region()
   self:_load_all_buffs_filters()

   if radiant.is_server then
      -- these settings should be loaded the first time any weapon is equipped
      -- because upgrade weapons may have different behavior with different default targeting
      local target_defaults = self._weapon_data and self._weapon_data.targeting and self._weapon_data.targeting.defaults
      local targeting = target_defaults and TARGET_DEFAULTS_BY_KEY[target_defaults]

      if targeting then
         if targeting.sticky_targeting ~= nil then
            self:set_sticky_targeting(targeting.sticky_targeting)
         end
         if targeting.filters then
            self:set_target_filters(targeting.filters)
         end
         if targeting.preferred_types then
            self:set_preferred_target_types(targeting.preferred_types)
         end
      end

      if not self._sv.target_filters then
         self:set_target_filters({})
      end
      if not self._sv.preferred_target_types then
         self:set_preferred_target_types({})
      end

      self._combat_state:recompile_combat_actions('stonehearth:combat:ranged_attacks')
      self._attack_types = self._weapon_data and self._combat_state:get_combat_actions('stonehearth:combat:ranged_attacks') or {}
      self:_register()
   end
end

function TowerComponent:_on_target_hit(context)
   -- if it's periodic damage, the proper amount has already been added
   if context.is_periodic_damage then
      return
   end

   -- just abusing the BatteryContext's last argument and using it as damage_type, rather than overriding/patching that file
   self._sv.stats:increment_damage(context.damage - (context.overkill or 0), context.aggro_override)
end

function TowerComponent:try_upgrade_tower(upgrade)
   -- find the upgrade in the component data and try to load it
   -- try to spend the resources to upgrade it
   -- if successful, apply the equipment, which should automatically reinitialize via the state machine, and return true
   local player = tower_defense.game:get_player(self._entity:get_player_id())
   local upgrade_data = (self._json.upgrades or {})[upgrade]
   local cost = upgrade_data and upgrade_data.cost
   local uri = upgrade_data and upgrade_data.uri
   local result = {}
   if not cost or not uri or not player then
      -- everything has a cost... if we can get it
      result.reject = true
      result.message = 'i18n(tower_defense:alerts.towers.upgrade.unavailable)'
   else
      for resource, amount in pairs(cost) do
         local missing = player:can_spend_resource(resource, amount)
         if missing > 0 then
            result[resource] = missing
         end
      end
   end

   if not result.reject and next(result) then
      result.reject = true
      result.message = 'i18n(tower_defense:alerts.towers.upgrade.missing_resources)'
   end
   
   if not result.reject then
      for resource, amount in pairs(cost) do
         player:spend_resource(resource, amount)
      end
      radiant.entities.equip_item(self._entity, upgrade_data.uri)
      local commands = self._entity:add_component('stonehearth:commands')
      commands:remove_command('tower_defense:commands:upgrade_tower_damage')
      commands:remove_command('tower_defense:commands:upgrade_tower_utility')
      self:_reinitialize(self._sv.sm, true)
      
      result.resolve = true
      result.message = 'i18n(tower_defense:alerts.towers.upgrade.success)'
   end

   return result
end

function TowerComponent:reveals_invis()
   return self._sv.reveals_invis
end

function TowerComponent:can_upgrade()
   return self._sv.can_upgrade
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

function TowerComponent:get_filter_buffs()
   return self._sv.buffs
end

function TowerComponent:placed(rotation)
   self._sv.original_facing = rotation
   self.__saved_variables:mark_changed()
   self:_reinitialize(self._sv.sm, false)
end

function TowerComponent:get_original_facing()
   return self._sv.original_facing
end

function TowerComponent:set_sticky_targeting(sticky)
   self._sv.sticky_targeting = sticky or false
   self.__saved_variables:mark_changed()
end

function TowerComponent:set_target_filters(target_filters)
   self._sv.target_filters = target_filters or {}
   self.__saved_variables:mark_changed()
end

function TowerComponent:set_preferred_target_types(preferred_target_types)
   self._sv.preferred_target_types = preferred_target_types or {}
   self.__saved_variables:mark_changed()
end

function TowerComponent:_load_all_buffs_filters()
   local buffs = {}

   if self._weapon then
      local weapon = type(self._weapon) == 'string' and self._weapon or self._weapon:get_uri()
      local catalog_data = stonehearth[radiant.is_server and 'catalog' or 'catalog_client']:get_catalog_data(weapon)
      if catalog_data.injected_buffs then
         for _, buff in ipairs(catalog_data.injected_buffs) do
            buffs[buff.uri] = true
         end
      end
      if catalog_data.inflictable_debuffs then
         for _, buff in ipairs(catalog_data.inflictable_debuffs) do
            buffs[buff.uri] = true
         end
      end
      local gp = catalog_data.tower_weapon_attack_info and catalog_data.tower_weapon_attack_info.ground_presence
      if gp then
         for _, instance in ipairs({'first_time', 'other_times', 'every_time'}) do
            if gp[instance] and gp[instance].expanded_buffs then
               for _, buff in ipairs(gp[instance].expanded_buffs) do
                  buffs[buff.uri] = true
               end
            end
         end
      end
   end

   self._sv.buffs = buffs
   self.__saved_variables:mark_changed()
end

function TowerComponent:get_best_targets(from_target_id, attacked_targets, region_override, attack_info_override)
   -- first check what total targets are available
   -- then apply filters in order until we have a single tower remaining or we run out of filters
   -- return the first (if any) remaining tower
   if (not region_override or region_override:empty()) and (not self._sv.targetable_path_region or self._sv.targetable_path_region:empty()) then
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

   local attack_info = attack_info_override or stonehearth.combat:choose_attack_action(self._entity, attack_types)
   if not attack_info or not attack_info.attack_times or #attack_info.attack_times < 1 then
      return
   end

   local num_targets = attack_info.num_targets or 1
   local max_secondary_attacks_per_target = attack_info.secondary_attack and attack_info.secondary_attack.max_attacks_per_target or 1
   local best_targets = {}
   local region_targets = radiant.terrain.get_entities_in_region(region_override or self._sv.targetable_path_region,
         self._sv.sees_invis and _ignore_target_invis_filter_fn or _target_filter_fn)
   region_targets = self:_filter_air_ground_attackable(region_targets, attack_info.hits_ground_and_air)

   if from_target_id then
      region_targets[from_target_id] = nil
      num_targets = attack_info.secondary_attack and attack_info.secondary_attack.num_targets or 1
   end
   if attacked_targets and next(attacked_targets) then
      for id, num in pairs(attacked_targets) do
         if num >= max_secondary_attacks_per_target then
            region_targets[id] = nil
         end
      end
   end

   if self._sv.sticky_targeting and self._current_targets and #self._current_targets > 0 then
      -- if sticky targeting is on, try to attack as many of the previous (current) targets as possible
      -- (as long as they're still valid entities and in the targetable region)
      -- if the full num_targets quota has been reached, simply return
      -- otherwise, we'll go through the same filtering process as we would without sticky targeting
      for _, current_target in ipairs(self._current_targets) do
         local id = current_target:is_valid() and current_target:get_id()
         if id and region_targets[id] then
            table.insert(best_targets, current_target)
            region_targets[id] = nil
            num_targets = num_targets - 1
         end
      end
      if num_targets <= 0 then
         return best_targets, attack_info
      end
   end

   local targets = radiant.values(region_targets)
   --log:debug('%s found %s potential targets: %s', self._entity, #targets, radiant.util.table_tostring(targets))

   if #targets <= num_targets then
      for _, target in ipairs(targets) do
         table.insert(best_targets, target)
      end
      return best_targets, attack_info
   end
   
   local debuff_cache = {}

   for _, filter in ipairs(self._sv.target_filters) do
      local ranked_targets = {}
      local best_value

      --log:debug('%s evaluating targets with filter %s: %s', self._entity, filter, radiant.util.table_tostring(targets))
      for _, target in ipairs(targets) do
         table.insert(ranked_targets, {
            target = target,
            value = self:_get_filter_value(filter, target, attack_info, debuff_cache)
         })
      end

      table.sort(ranked_targets, function(a, b) return a.value > b.value end)

      local lowest = ranked_targets[num_targets]
      local lowest_ranked = {}
      for _, ranked_target in ipairs(ranked_targets) do
         if ranked_target.value > lowest.value then
            table.insert(best_targets, ranked_target.target)
            num_targets = num_targets - 1
         elseif ranked_target.value == lowest.value then
            table.insert(lowest_ranked, ranked_target.target)
         end
      end

      if #lowest_ranked <= num_targets then
         for _, lowest in ipairs(lowest_ranked) do
            table.insert(best_targets, lowest)
            num_targets = num_targets - 1
         end
         break
      else
         targets = lowest_ranked
      end
   end

   -- for any remaining targets we need to get (final filters resulted in ties), just grab them from the list arbitrarily
   for i = 1, num_targets do
      if #targets < 1 then
         break
      end
      table.insert(best_targets, table.remove(targets))
   end

   return best_targets, attack_info
end

function TowerComponent:_get_filter_value(filter, target, attack_info, debuff_cache)
   if filter == FILTER_TYPES.FILTER_HP_LOW.key then
      return -(radiant.entities.get_health(target) or 0)

   elseif filter == FILTER_TYPES.FILTER_HP_HIGH.key then
      return radiant.entities.get_health(target) or 0

   elseif filter == FILTER_TYPES.FILTER_CLOSEST_TO_TOWER.key then
      return -radiant.entities.distance_between_entities(self._entity, target)

   elseif filter == FILTER_TYPES.FILTER_FARTHEST_FROM_TOWER.key then
      return radiant.entities.distance_between_entities(self._entity, target)

   elseif filter == FILTER_TYPES.FILTER_CLOSEST_TO_START.key then
      return -target:get_component('tower_defense:monster'):get_path_traveled()

   elseif filter == FILTER_TYPES.FILTER_CLOSEST_TO_END.key then
      return -target:get_component('tower_defense:monster'):get_path_length()
      
   elseif filter == FILTER_TYPES.FILTER_SHORTEST_DEBUFF_TIME.key then
      self:_verify_debuff_cache(debuff_cache, attack_info)
      if debuff_cache.total_duration > 0 then
         local buffs_comp = target:get_component('stonehearth:buffs')
         if not buffs_comp then
            return debuff_cache.total_duration
         end

         local diff = 0
         for uri, data in pairs(debuff_cache.debuffs) do
            local buff = buffs_comp:get_buff(uri)
            -- returns -1 if the buff has no duration (lasts forever)
            local duration = buff and buff:get_duration() or 0
            
            -- only consider the value of the buff being applied if it can actually be applied
            if duration >= 0 and not buffs_comp:is_buff_diminishing_disabled(uri) then
               -- the target doesn't have this debuff or it has a duration/expiration
               diff = diff + (data.duration - duration) * data.priority
            end
         end
         return diff
      end

   elseif filter == FILTER_TYPES.FILTER_SHORTEST_STACKABLE_DEBUFF_TIME.key then
      self:_verify_debuff_cache(debuff_cache, attack_info)
      if debuff_cache.total_duration > 0 then
         local buffs_comp = target:get_component('stonehearth:buffs')
         if not buffs_comp then
            return 0
         end

         local attack_time = 200 + (attack_info.attack_times and attack_info.attack_times[1] or 0)
         attack_time = stonehearth.calendar:realtime_to_game_seconds(attack_time, true)

         local diff = 0
         for uri, data in pairs(debuff_cache.debuffs) do
            local buff = buffs_comp:get_buff(uri)
            -- returns -1 if the buff has no duration (lasts forever)
            local duration = buff and buff:get_duration() or 0
            
            -- only consider the value of the buff being applied if it can actually be applied
            -- and if the duration is greater than the attack time plus some wiggle room (200ms)
            if duration >= attack_time and not buffs_comp:is_buff_diminishing_disabled(uri) then
               -- the target doesn't have this debuff or it has a duration/expiration
               diff = diff + (data.duration - duration) * data.priority
            end
         end
         return diff
      end

   elseif filter == FILTER_TYPES.FILTER_HIGHEST_DEBUFF_STACK.key then
      self:_verify_debuff_cache(debuff_cache, attack_info)
      local buffs_comp = target:get_component('stonehearth:buffs')
      if not buffs_comp then
         return 0
      end

      local stacks = 0
      for uri, data in pairs(debuff_cache.debuffs) do
         -- only consider the value of the buff being applied if it can actually be applied
         if not buffs_comp:is_buff_diminishing_disabled(uri) then
            stacks = stacks + (buffs_comp:get_buff_stacks(uri) or 0) * data.priority
         end
      end
      return stacks
      
   elseif filter == FILTER_TYPES.FILTER_MOST_TARGETS.key then
      local targets = self:_get_aoe_targets(attack_info.aoe or attack_info.secondary_attack or attack_info.ground_presence, radiant.entities.get_world_location(target))
      return targets and radiant.size(targets) or 0
      
   elseif filter == FILTER_TYPES.FILTER_TARGET_TYPE.key then
      local match_count = 0
      for _, target_type in ipairs(self._sv.preferred_target_types) do
         if radiant.entities.is_material(target, target_type) then
            match_count = match_count + 1
         end
      end
      return match_count
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
      for _, debuff_data in ipairs(debuffs) do
         for name, debuff in pairs(debuff_data) do
            local exp_debuff = radiant.resources.load_json(debuff.uri)
            local priority = exp_debuff.priority or 1
            local duration = self:_parse_duration(exp_debuff.duration) * priority
            
            exp_debuffs[debuff.uri] = {
               data = exp_debuff,
               priority = priority,
               duration = duration
            }
            total_duration = total_duration + duration
         end
      end

      debuff_cache.debuffs = exp_debuffs
      debuff_cache.total_duration = total_duration
   end
end

function TowerComponent:_parse_duration(duration)
   if type(duration) == 'number' then
      return stonehearth.calendar:realtime_to_game_seconds(duration, true)
   elseif type(duration) == 'string' then
      return stonehearth.calendar:parse_duration(duration)
   else
      return 99999
   end
end

function TowerComponent:_register()
   -- calculate targetable range and translate it to our location
   -- pass that in to the tower service registration function
   -- store the resulting targetable path intersection ranges
   self._location = radiant.entities.get_world_grid_location(self._entity)
   if self._location and self._sv.targetable_region then
      self._sv.targetable_path_region_ground, self._sv.targetable_path_region_air = tower_defense.tower:register_tower(self._entity, self._location)
      self:_update_targetable_path_region()
   end
end

function TowerComponent:_unregister()
   tower_defense.tower:unregister_tower(self._entity)
   for timer, _ in pairs(self._shoot_timers) do
      timer:destroy()
   end
   self._shoot_timers = {}
end

function TowerComponent:_load_targetable_region()
   local targeting = self._weapon_data and self._weapon_data.targeting or {}
   local region
   if targeting.type == 'rectangle' then
      region = Region3(radiant.util.to_cube3(targeting.region))
               :translated(Point3(-0.5, 0, -0.5))
               :rotated(radiant.entities.get_facing(self._entity))
               :translated(Point3(0.5, 0, 0.5))
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

   self._sv.targetable_region = region
   self._sv.reveals_invis = targeting.reveals_invis or false
   self._sv.sees_invis = targeting.sees_invis or false
   self._sv.attacks_ground = targeting.attacks_ground or false
   self._sv.attacks_air = targeting.attacks_air or false
   self.__saved_variables:mark_changed()
end

function TowerComponent:set_attacks_ground(attacks)
   self._sv.attacks_ground = attacks
   self:_update_targetable_path_region()
end

function TowerComponent:set_attacks_air(attacks)
   self._sv.attacks_air = attacks
   self:_update_targetable_path_region()
end

function TowerComponent:_update_targetable_path_region()
   local region = Region3()
   if self._sv.attacks_ground then
      region = region + self._sv.targetable_path_region_ground
   end
   if self._sv.attacks_air then
      region = region + self._sv.targetable_path_region_air
   end
   self._sv.targetable_path_region = region
   self.__saved_variables:mark_changed()
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
         self._wave_listener = radiant.events.listen(radiant, 'tower_defense:wave:started', self, self._on_wave_started)
      end
   end
end

--[[
   state machine stuff for targeting/acting
]]

function TowerComponent:_reinitialize(sm, equipment_changed)
   self:_initialize(equipment_changed)

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
   if self._entity and self._entity:is_valid() then
      self._entity:add_component('tower_defense:ai'):set_status_text_key('stonehearth:ai.actions.status_text.idle')
      self._facing_targets = {}
      -- TODO: reconsider breaking up towers into multiple models and have the base stationary while the "weapon" part rotates
      --radiant.entities.turn_to(self._entity, self._sv.original_facing)
      self:_stop_current_effect()
   end
end

function TowerComponent:_get_aoe_targets(aoe_attack_info, location)
   local cube = self:_get_attack_cube(aoe_attack_info, location)
   if cube then
      local targets = radiant.terrain.get_entities_in_cube(cube, _ignore_target_invis_filter_fn)
      return self:_filter_air_ground_attackable(targets, aoe_attack_info.hits_ground_and_air)
   end
end

function TowerComponent:_get_attack_cube(info, location)
   local range = info and info.range
   if not range then
      return nil
   end

   local cube = Cube3(Point3(-range, -range - 0.5, -range), Point3(range, range + 0.5, range))
   if info.hits_ground_and_air then
      -- note: not storing an air "height" anymore, only their paths, height could technically vary
      -- so just have some max variance that is always used
      cube = cube:extruded('y', MAX_PATH_HEIGHT_DIFFERENTIAL, MAX_PATH_HEIGHT_DIFFERENTIAL)
   end

   return cube:translated(location + Point3(0.5, 0, 0.5))
end

function TowerComponent:_filter_air_ground_attackable(targets, hits_ground_and_air)
   if not hits_ground_and_air or not self._sv.attacks_ground or not self._sv.attacks_air then
      for id, entity in pairs(targets) do
         if (entity:get_player_id() == 'monster_ground' and not self._sv.attacks_ground) or
               (entity:get_player_id() == 'monster_air' and not self._sv.attacks_air) then
            targets[id] = nil
         end
      end
   end
   return targets
end

function TowerComponent:_stop_current_effect()
   if self._current_effect then
      self._current_effect:stop()
      self._current_effect = nil
   end
end

function TowerComponent:_try_lock_facing_target(target)
   if target and target:is_valid() then
      table.insert(self._facing_targets, target)
   else
      return
   end

   if target and not self._current_facing_listener then
      self._current_facing_listener = radiant.on_game_loop('face target', function()
         local current_target = self._facing_targets[1]
         if not current_target or not current_target:is_valid() then
            self:_unlock_facing_target()
         else
            --radiant.entities.turn_to_face(self._entity, current_target)
         end
      end)
   end
end

function TowerComponent:_unlock_facing_target()
   table.remove(self._facing_targets)
   if #self._facing_targets == 0 then
      if self._current_facing_listener then
         self._current_facing_listener:destroy()
         self._current_facing_listener = nil
      end
   end
end

function TowerComponent:_find_target_and_engage(sm)
   local targets, attack_info = self:get_best_targets()
   if not targets or #targets < 1 then
      log:debug('%s couldn\'t find target, going to waiting_for_targetable', self._entity)
      sm:go_into(STATES.WAITING_FOR_TARGETABLE)
   else
      log:debug('%s found target(s), going to engage %s', self._entity, radiant.util.table_tostring(targets))
      self._current_targets = targets
      self._current_attack_info = attack_info
      sm:go_into(STATES.FINDING_TARGET)
   end
end

function TowerComponent:_engage_current_target(sm)
   local targets = self._current_targets
   local attack_info = self._current_attack_info

   if not attack_info then
      log:error('attack_info nil in _engage_current_target')
      return
   end

   if not targets or #targets < 1 then
      log:error('no targets in _engage_current_target')
      return
   end

   for i = #targets, 1, -1 do
      if not targets[i]:is_valid() then
         table.remove(targets, i)
      end
   end

   if #targets < 1 then
      log:error('no valid targets in _engage_current_target')
      return
   end

   local first_target = targets[1]
   self._entity:add_component('tower_defense:ai'):set_status_text_key('stonehearth:ai.actions.status_text.attack_melee_adjacent', { target = first_target })

   self:_stop_current_effect()
   self:_try_lock_facing_target(first_target)
   stonehearth.combat:start_cooldown(self._entity, attack_info)

   -- if we have a tower effect, start it up
   if attack_info.effect then
      self._current_effect = radiant.effects.run_effect(self._entity, attack_info.effect)
   end

   local damage_multiplier = attack_info.damage_multiplier_per_attack or 1
   local this_damage_multiplier = 1
   local buffs = stonehearth.combat:get_inflictable_debuffs(self._entity, attack_info)

   for i, time in ipairs(attack_info.attack_times) do
      local shoot_timer
      shoot_timer = stonehearth.combat:set_timer('tower attack shoot', time, function()
         -- if we have a shoot effect, start it up
         if attack_info.shoot_effect then
            radiant.effects.run_effect(self._entity, attack_info.shoot_effect)
         end

         self._shoot_timers[shoot_timer] = nil
         local dmg_mult = this_damage_multiplier
         for _, target in ipairs(targets) do
            -- only need to shoot if the target is still valid
            local target_id = target:is_valid() and target:get_id()
            if target_id then
               self:_shoot(target, attack_info, buffs, dmg_mult, 0, {[target_id] = 1})
            end
         end
         if i == #attack_info.attack_times and tower_defense.game:has_active_wave() then
            self:_unlock_facing_target()
            sm:go_into(STATES.WAITING_FOR_COOLDOWN)
         end
      end)
      self._shoot_timers[shoot_timer] = true

      this_damage_multiplier = this_damage_multiplier * damage_multiplier
   end
   
   return true
end


-- local_to_world not doing the right thing
local get_world_location = function(point, entity)
   local mob = entity:add_component('mob')
   local facing = mob:get_facing()
   local entity_location = mob:get_world_location()

   local offset = radiant.math.rotate_about_y_axis(point, facing)
   local world_location = entity_location + offset
   return world_location
end

local get_secondary_world_location = function(point, entity_id)
   local entity = radiant.entities.get_entity(entity_id)
   local location = entity and entity:is_valid() and radiant.entities.get_world_location(entity) or tower_defense.game:get_last_monster_location(entity_id)
   if location then
      local facing = entity and radiant.entities.get_facing(entity) or 0

      local offset = radiant.math.rotate_about_y_axis(point, facing)
      local world_location = location + offset
      return world_location
   end
end

local get_offsets = function(data)
   local attacker_offset = Point3(-0.5, 0.8, -0.5)
   local target_offset = Point3(0, 1, 0)

   if data then
      local start_offset = data.start_offset
      local end_offset = data.end_offset
      -- Get start and end offsets from attack_info data if provided
      if start_offset then
         attacker_offset = Point3(start_offset.x,
                                 start_offset.y,
                                 start_offset.z)
      end
      if end_offset then
         target_offset = Point3(end_offset.x,
                                 end_offset.y,
                                 end_offset.z)
      end
   end

   return attacker_offset, target_offset
end

function TowerComponent:_shoot(target, attack_info, buffs, damage_multiplier, num_attacks, attacked_targets, source_target_id)
   local attacker = self._entity
   local assault_context
   local impact_time = radiant.gamestate.now()
   local target_id = target:get_id()

   if not source_target_id then
      self:_try_lock_facing_target(target)
   end

   -- if we have projectile data, create and launch the projectile, running combat effects upon completion
   -- otherwise, run them immediately
   local finish_fn = function(attack_entity, impact_trace)
      if not attack_entity or attack_entity:is_valid() then
         if not assault_context or not assault_context.target_defending then
            local location = target:is_valid() and radiant.entities.get_world_location(target)
                                 or tower_defense.game:get_last_monster_location(target_id)
            
            -- this can trigger after the wave is done, and thus there are no remaining monsters
            -- and the wave controller has been destroyed, so there are no more last monster locations
            if location then
               if attack_info.ground_effect then
                  local proxy = radiant.entities.create_entity('stonehearth:object:transient', { debug_text = 'running death effect' })

                  radiant.terrain.place_entity(proxy, location)

                  local effect = radiant.effects.run_effect(proxy, attack_info.ground_effect)

                  effect:set_finished_cb(
                     function()
                        radiant.entities.destroy_entity(proxy)
                     end
                  )
               end

               local aoe_attack = attack_info.aoe
               local targets = aoe_attack and self:_get_aoe_targets(aoe_attack, location) or {target}

               self:_inflict_attack(targets, target, attack_info, buffs, damage_multiplier)

               local secondary_attack = attack_info.secondary_attack
               if secondary_attack and num_attacks < (secondary_attack.num_attacks or 1) then
                  local cube = self:_get_attack_cube(secondary_attack, location)
                  if cube then
                     local secondary_targets = self:get_best_targets(target_id, attacked_targets, Region3(cube), attack_info)
                     if secondary_targets and next(secondary_targets) then
                        num_attacks = num_attacks + 1
                        damage_multiplier = damage_multiplier * (secondary_attack.damage_multiplier or 1)
                        for _, secondary_target in ipairs(secondary_targets) do
                           local secondary_target_id = secondary_target:get_id()
                           attacked_targets[secondary_target_id] = (attacked_targets[secondary_target_id] or 0) + 1
                           self:_shoot(secondary_target, attack_info, buffs, damage_multiplier, num_attacks, attacked_targets, target_id)
                        end
                     end
                  end
               end
            end
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

      if not source_target_id then
         self:_unlock_facing_target()
      end
   end

   if attack_info.projectile then
      local attacker_offset, target_offset = get_offsets(attack_info.projectile)
      local projectile = self:_create_projectile(attacker, target, attack_info.projectile, attacker_offset, target_offset, source_target_id)
      local projectile_component = projectile:add_component('stonehearth:projectile')
      if attack_info.projectile.passthrough_attack then
         projectile_component:set_passthrough_attack_cb(function(targets)
               self:_inflict_attack(targets, target, attack_info, buffs, damage_multiplier)
            end, _ignore_target_invis_filter_fn)
      end
      projectile_component:start()

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
   elseif attack_info.beam then
      local attacker_offset, target_offset = get_offsets(attack_info.beam)
      local beam = self:_create_beam(attacker, target, attack_info.beam, attacker_offset, target_offset, source_target_id)
      local beam_component = beam:add_component('tower_defense:beam')
      if attack_info.beam.attack_times then
         for _, time in ipairs(attack_info.beam.attack_times) do
            local shoot_timer
            shoot_timer = stonehearth.combat:set_timer('beam attack damage', time, function()
               self._shoot_timers[shoot_timer] = nil
               if target:is_valid() and beam:is_valid() then
                  local targets = attack_info.beam.passthrough_attack and beam_component:get_intersection_targets(_ignore_target_invis_filter_fn) or {target}
                  self:_inflict_attack(targets, target, attack_info, buffs, damage_multiplier)
               end
            end)
            self._shoot_timers[shoot_timer] = true
         end
      end
      beam_component:start()

      impact_time = impact_time + (attack_info.beam.duration or 1)

      local impact_trace
      impact_trace = radiant.events.listen(beam, 'tower_defense:combat:beam_terminated', function()
            finish_fn(beam, impact_trace)
         end)

      local destroy_trace
      destroy_trace = radiant.events.listen(beam, 'radiant:entity:pre_destroy', function()
            if assault_context then
               stonehearth.combat:end_assault(assault_context)
               assault_context = nil
            end

            if destroy_trace then
               destroy_trace:destroy()
               destroy_trace = nil
            end
         end)
   elseif attack_info.ground_presence then
      local ground_presence = self:_create_ground_presence(attacker, target, attack_info.ground_presence)
      local ground_presence_component = ground_presence:add_component('tower_defense:ground_presence')
      ground_presence_component:set_attack_cb(function(target, attack_info)
            self:_inflict_attack({target}, target, attack_info, buffs, damage_multiplier)
         end, _ignore_target_invis_filter_fn)
      ground_presence_component:start()

      impact_time = impact_time + (attack_info.ground_presence.duration or 1)

      local impact_trace
      impact_trace = radiant.events.listen(ground_presence, 'tower_defense:combat:ground_presence_terminated', function()
            finish_fn(ground_presence, impact_trace)
         end)

      local destroy_trace
      destroy_trace = radiant.events.listen(ground_presence, 'radiant:entity:pre_destroy', function()
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

   if not attack_info.projectile and not attack_info.beam then
      -- if you want there to be a non-projectile delay between shooting and hitting on the primary attack, just set a later attack_time
      local hit_delay = num_attacks > 1 and attack_info.secondary_attack and attack_info.secondary_attack.hit_delay
      if hit_delay then
         local secondary_attack_timer = stonehearth.combat:set_timer('secondary attack cooldown', hit_delay, function()
            secondary_attack_timer = nil
            finish_fn()
         end)
      else
         finish_fn()
      end
   end
end

function TowerComponent:_inflict_attack(targets, primary_target, attack_info, buffs, damage_multiplier)
   local attacker = self._entity
   if not attacker or not attacker:is_valid() then
      -- this could be a delayed attack that didn't get cleaned up, and we've sold the tower
      return
   end

   local accuracy = attacker:get_component('stonehearth:attributes'):get_attribute('accuracy', 1) + (attack_info.accuracy or 0)
   local aoe_attack = attack_info.aoe
   local base_damage = attack_info.base_damage
   local secondary_damage = aoe_attack and aoe_attack.base_damage

   if attack_info.is_percentage then
      local attributes = primary_target and primary_target:get_component('stonehearth:attributes')
      damage_multiplier = damage_multiplier * (attributes and (0.01 * attributes:get_attribute('max_health', 100)) or 1)
   end

   for _, each_target in pairs(targets) do
      if each_target:is_valid() then
         local avoidance = each_target:get_component('stonehearth:attributes'):get_attribute('avoidance', 0)
         if rng:get_real(0, 1) < accuracy - avoidance then
            local is_secondary_target = each_target ~= primary_target
            local hit_effect = is_secondary_target and aoe_attack and aoe_attack.hit_effect or (not is_secondary_target and attack_info.hit_effect)
            if hit_effect then
               radiant.effects.run_effect(each_target, hit_effect)
            end

            local total_damage = stonehearth.combat:calculate_damage(attacker, each_target, attack_info,
                  is_secondary_target and secondary_damage or base_damage, damage_multiplier)
            
            if not is_secondary_target or not aoe_attack or not attack_info.apply_buffs_to_primary_target_only then
               stonehearth.combat:try_inflict_debuffs(attacker, each_target, buffs)
            end
            if total_damage > 0 then
               local battery_context = BatteryContext(attacker, each_target, total_damage, attack_info.damage_type or 'physical')
               stonehearth.combat:battery(battery_context)
            end
         end
      end
   end
end

function TowerComponent:_create_projectile(attacker, target, projectile_data, attacker_offset, target_offset, source_target_id)
   local uri = projectile_data.uri or 'stonehearth:weapons:arrow' -- default projectile is an arrow
   local projectile = radiant.entities.create_entity(uri, { owner = attacker })
   
   if projectile_data.scale_mult then
      local render_info = projectile:add_component('render_info')
      render_info:set_scale(render_info:get_scale() * projectile_data.scale_mult)
   end

   local projectile_component = projectile:add_component('stonehearth:projectile')
   projectile_component:set_speed(projectile_data.speed or 1)
   projectile_component:set_target_offset(target_offset)
   projectile_component:set_target(target)

   if source_target_id then
      local projectile_origin = get_secondary_world_location(attacker_offset, source_target_id)
      radiant.terrain.place_entity_at_exact_location(projectile, projectile_origin)
   else
      local projectile_origin = get_world_location(attacker_offset, attacker)
      radiant.terrain.place_entity_at_exact_location(projectile, projectile_origin)
   end

   return projectile
end

function TowerComponent:_create_beam(attacker, target, beam_data, attacker_offset, target_offset, source_target_id)
   local uri = beam_data.uri or 'stonehearth:object:transient'
   local beam = radiant.entities.create_entity(uri, { owner = attacker })
   
   local beam_component = beam:add_component('tower_defense:beam')
   beam_component:set_duration(beam_data.duration or 1)
   beam_component:set_target(target, target_offset)
   beam_component:set_style(beam_data.particle_effect, beam_data.particle_color, beam_data.beam_color)

   if source_target_id then
      beam_component:set_origin(source_target_id, attacker_offset, get_secondary_world_location)
      local beam_origin = get_secondary_world_location(attacker_offset, source_target_id)
      radiant.terrain.place_entity_at_exact_location(beam, beam_origin)
   else
      local beam_origin = get_world_location(attacker_offset, attacker)
      radiant.terrain.place_entity_at_exact_location(beam, beam_origin)
   end

   return beam
end

function TowerComponent:_create_ground_presence(owner, target, ground_presence_data)
   local uri = ground_presence_data.uri or 'stonehearth:object:transient'
   local ground_presence = radiant.entities.create_entity(uri, { owner = owner })
   
   local ground_presence_component = ground_presence:add_component('tower_defense:ground_presence')
   ground_presence_component:set_tower(owner)
   ground_presence_component:set_settings(ground_presence_data)

   local origin = radiant.entities.get_world_location(target)
   radiant.terrain.place_entity_at_exact_location(ground_presence, origin)
   if ground_presence_data.facing == 'target' then
      radiant.entities.turn_to(ground_presence, radiant.entities.get_facing(target))
   elseif ground_presence_data.facing == 'random_cardinal' then
      radiant.entities.turn_to(ground_presence, rng:get_int(0, 3) * 90)
   elseif ground_presence_data.facing == 'random' then
      radiant.entities.turn_to(ground_presence, rng:get_real(0, 360))
   end

   return ground_presence
end

function TowerComponent:_declare_states(sm)
   sm:add_states(STATES)
   sm:set_start_state(STATES.IDLE)
end

function TowerComponent:_declare_triggers(sm)
   sm:trigger_on_event('tower_defense:wave:started', radiant, {
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
end

function TowerComponent:_declare_state_event_handlers(sm)
   sm:on_state_event_triggered(STATES.IDLE, {
      ['tower_defense:wave:started'] = function(event_args, event_source)
         if self._attack_types and next(self._attack_types) and self._sv.targetable_path_region and not self._sv.targetable_path_region:empty() then
            sm:go_into(STATES.WAITING_FOR_TARGETABLE)
         end
      end,
   })

   sm:on_state_event_triggered(STATES.WAITING_FOR_TARGETABLE, {
      ['tower_defense:tower:monster_entered_range'] = function(event_args, event_source)
         sm:go_into(STATES.WAITING_FOR_COOLDOWN)
      end,
      ['tower_defense:wave:ended'] = function(event_args, event_source)
         sm:go_into(STATES.IDLE)
      end,
   })
   
   sm:on_state_event_triggered(STATES.WAITING_FOR_COOLDOWN, {
      ['tower_defense:wave:ended'] = function(event_args, event_source)
         sm:go_into(STATES.IDLE)
      end,
   })
   
   sm:on_state_event_triggered(STATES.FINDING_TARGET, {
      ['tower_defense:wave:ended'] = function(event_args, event_source)
         sm:go_into(STATES.IDLE)
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
         local cd = math.max(0, stonehearth.combat:get_shortest_cooldown(self._entity, self._attack_types))
         self._cooldown_listener = stonehearth.combat:set_timer('wait for attack cooldown', cd, function()
            self:_find_target_and_engage(sm)
         end)
      end, true)

   sm:on_state_enter(STATES.FINDING_TARGET, function(restoring)
         if restoring then
            self._gameloop_listener = radiant.on_game_loop_once('restored in finding target, going to waiting for cooldown', function()
               self._gameloop_listener = nil
               sm:go_into(STATES.WAITING_FOR_COOLDOWN)
            end)
         else
            self:_engage_current_target(sm)
         end
      end, true)

   sm:on_state_exit(STATES.WAITING_FOR_TARGETABLE, function(restoring)
         tower_defense.game:register_waiting_for_target(self._sv.targetable_path_region, nil)
      end, true)

   sm:on_state_exit(STATES.WAITING_FOR_COOLDOWN, function(restoring)
         self:_destroy_cooldown_listener()
      end, true)

end

return TowerComponent
