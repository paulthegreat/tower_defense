--[[
   instantiated by the game service
   runs the whole wave, from monsters spawning through to all monsters being gone, either through death or end of path
]]

local Point3 = _radiant.csg.Point3
local game_master_lib = require 'stonehearth.lib.game_master.game_master_lib'
local log = radiant.log.create_logger('wave')

local Wave = class()

local TIME_TO_FIRST_SPAWN = 3000

function Wave:initialize()
   self._sv._unspawned_monsters = {}
   self._sv.spawned_monsters = {}
   self._sv.remaining_monsters = 0
   self._sv._last_monster_data = {}
   self._sv._queued_spawn_monsters = {}
end

function Wave:create(wave_data, map_data, game_options)
   self._sv._wave_data = wave_data
   self._sv._map_data = map_data
   self._sv._game_options = game_options

   self._is_create = true
end

function Wave:activate()
   self._wave_data = radiant.resources.load_json(self._sv._wave_data.uri)
   self._multipliers = self._sv._wave_data.multipliers or {}
   self._multipliers.attributes = self._multipliers.attributes or {}
   self._multipliers.gold_bounty = self._multipliers.gold_bounty or 1
   self._multipliers.wood_bounty = self._multipliers.wood_bounty or 1
   self._multipliers.escaped_monster_bounty = self._multipliers.escaped_monster_bounty or 1
   self._buffs = self._sv._wave_data.buffs or {}
   self._role_overrides = self._sv._wave_data.role_overrides or {}

   self:_apply_multipliers(self._sv._game_options.multipliers)
   self:_apply_multipliers(self._sv._map_data.multipliers)
   
   if self._sv._next_spawn_timer then
      self._sv._next_spawn_timer:bind(function()
         self:_spawn_next_monster()
      end)
   end

   if self._is_create then
      self:_load_unspawned_monsters()
   end

   for _, spawned_monster in pairs(self._sv.spawned_monsters) do
      self:_activate_monster(spawned_monster)
   end
   self:_start_queued_spawn_monsters_timer()
end

function Wave:destroy()
   self:_destroy_next_spawn_timer()
   self:_destroy_monsters()
end

function Wave:_destroy_next_spawn_timer()
   if self._sv._next_spawn_timer then
      self._sv._next_spawn_timer:destroy()
      self._sv._next_spawn_timer = nil
      self.__saved_variables:mark_changed()
   end
end

function Wave:_destroy_monsters()
   for _, monster_info in pairs(self._sv.spawned_monsters) do
      if monster_info.kill_listener then
         monster_info.kill_listener:destroy()
      end
      if monster_info.escape_listener then
         monster_info.escape_listener:destroy()
      end
      radiant.entities.destroy_entity(monster_info.monster)
   end
   self._sv.spawned_monsters = {}
   self.__saved_variables:mark_changed()
end

function Wave:_load_unspawned_monsters()
   self._sv._unspawned_monsters = {}

   for _, monster_data in ipairs(self._wave_data.monsters) do
      for i = 1, monster_data.count or 1 do
         local monsters = {}
         for _, monster in ipairs(monster_data.each_spawn) do
            local new_monster = radiant.shallow_copy(monster)
            new_monster.info = radiant.shallow_copy(monster.info)
            local from_population = radiant.shallow_copy(monster.info.from_population)
            from_population.role = self._role_overrides[from_population.role] or from_population.role
            new_monster.info.from_population = from_population

            table.insert(monsters, new_monster)
            self._sv.remaining_monsters = self._sv.remaining_monsters + (new_monster.info.from_population.max or 1)
            
            -- if an individual monster specifies a time to next monster, break it up
            -- this allows us to easily specify repeating sequences of monsters
            if new_monster.time_to_next_monster then
               table.insert(self._sv._unspawned_monsters, {
                  monsters = monsters,
                  time_to_next_monster = new_monster.time_to_next_monster
               })
               monsters = {}
            end
         end

         if #monsters > 0 then
            table.insert(self._sv._unspawned_monsters, {
               monsters = monsters,
               time_to_next_monster = monster_data.time_to_next_monster
            })
         end
      end
   end

   self.__saved_variables:mark_changed()
end

function Wave:start()
   self:_create_next_spawn_timer(self._wave_data.time_to_first_spawn or TIME_TO_FIRST_SPAWN)
end

function Wave:get_last_monster_location(monster_id)
   local data = self._sv._last_monster_data[monster_id]
   return data and data.location
end

function Wave:get_num_escaped()
   return self._sv.num_escaped
end

function Wave:_create_next_spawn_timer(time)
   self:_destroy_next_spawn_timer()
   
   if not time then
      time = self._wave_data.time_to_next_monster
   end

   if time and #self._sv._unspawned_monsters > 0 then
      self._sv._next_spawn_timer = stonehearth.combat:set_persistent_timer('spawn next monster', time, function()
         self:_spawn_next_monster()
      end)
   end
end

function Wave:_spawn_next_monster()
   local monster_info = table.remove(self._sv._unspawned_monsters, 1)
   if monster_info then
      if self:_spawn_monsters(monster_info.monsters) then
         self:_create_next_spawn_timer(monster_info.time_to_next_monster)
      end
   end
end

function Wave:queue_spawn_monsters(monsters, at_monster_id)
   table.insert(self._sv._queued_spawn_monsters, {monsters = monsters, at_monster_id = at_monster_id})
   self.__saved_variables:mark_changed()

   self:_start_queued_spawn_monsters_timer()
end

function Wave:_start_queued_spawn_monsters_timer()
   if #self._sv._queued_spawn_monsters > 0 and not self._queued_spawn_monsters_timer then
      self._queued_spawn_monsters_timer = stonehearth.calendar:set_timer("queued monster spawning", 1, function()
         self._queued_spawn_monsters_timer = nil
         while #self._sv._queued_spawn_monsters > 0 do
            local queued = table.remove(self._sv._queued_spawn_monsters, 1)
            self:_spawn_monsters(queued.monsters, queued.at_monster_id)
         end
         self.__saved_variables:mark_changed()
      end)
   end
end

function Wave:_spawn_monsters(monsters, at_monster_id)
   local multiplayer_health_multiplier = tower_defense.game:get_num_players()
   local did_spawn = false
   
   local at_monster_data
   if at_monster_id then
      local at_monster = radiant.entities.get_entity(at_monster_id)
      if at_monster then
         at_monster_data = at_monster:add_component('tower_defense:monster'):get_path_data()
      else
         at_monster_data = self._sv._last_monster_data[at_monster_id]
      end
      if not at_monster_data then
         return false
      end
   end

   for _, monster in ipairs(monsters) do
      local pop = stonehearth.population:get_population(monster.population)
      if pop then
         local location = at_monster_data and at_monster_data.location
         if not location then
            location = self._sv._map_data.spawn_location
            if monster.population == 'monster_air' then
               location = self._sv._map_data.air_spawn_location
            end
         end

         local bounty = radiant.shallow_copy(monster.bounty or {})
         if bounty.gold then
            bounty.gold = bounty.gold * self._multipliers.gold_bounty
         end
         if bounty.wood then
            bounty.wood = bounty.wood * self._multipliers.wood_bounty
         end

         local new_monsters = game_master_lib.create_citizens(pop, monster.info, location, {player_id = ''})
         for _, new_monster in ipairs(new_monsters) do
            if at_monster_data then
               new_monster:add_component('tower_defense:monster'):inherit_path_data(at_monster_data)
            end
            
            radiant.terrain.place_entity_at_exact_location(new_monster, location)
            
            -- TODO: add entity and ground effects for spawning
            if monster.spawn_effect then

            end
            if monster.spawn_ground_effect then

            end

            -- for any abilities that should start on cooldown, do that
            local abilities = radiant.entities.get_entity_data(new_monster, 'stonehearth:combat:ranged_attacks')
            if abilities then
               local combat_state = new_monster:add_component('stonehearth:combat_state')
               for _, ability in ipairs(abilities) do
                  if ability.created_cooldown then
                     combat_state:start_cooldown(ability.name, ability.created_cooldown)
                  end
               end
            end

            local attrib_component = new_monster:add_component('stonehearth:attributes')
            -- multiply monster health by number of players
            if multiplayer_health_multiplier ~= 1 then
               attrib_component:set_attribute('max_health', attrib_component:get_attribute('max_health') * multiplayer_health_multiplier)
            end
            -- apply any other wave-based attribute multipliers
            for attribute, multiplier in pairs(self._multipliers.attributes or {}) do
               attrib_component:set_attribute(attribute, attrib_component:get_attribute(attribute) * multiplier)
            end
            attrib_component:set_attribute('max_health', math.ceil(attrib_component:get_attribute('max_health')))
            
            self:_apply_buffs(new_monster, self._buffs)
            if monster.buffs then
               self:_apply_buffs(new_monster, monster.buffs)
            end

            radiant.events.trigger(radiant, 'tower_defense:monster_created', new_monster)

            local this_monster = {
               monster = new_monster,
               damage = monster.damage,
               bounty = bounty,
               counts_as_remaining = at_monster_id == nil
            }
            self._sv.spawned_monsters[new_monster:get_id()] = this_monster
            self:_activate_monster(this_monster)

            did_spawn = true
         end
         self.__saved_variables:mark_changed()
      end
   end

   return did_spawn
end

function Wave:_apply_buffs(monster, buffs)
   for _, buff in ipairs(buffs) do
      radiant.entities.add_buff(monster, buff)
   end
end

-- set up listeners
function Wave:_activate_monster(monster)
   local id = monster.monster:get_id()
   monster.kill_listener = radiant.events.listen_once(monster.monster, 'stonehearth:kill_event', function()
         log:debug('monster %s killed!', monster.monster)
         radiant.events.trigger(self, 'tower_defense:wave:monster_killed', monster.bounty)
         
         self:_remove_monster(id)
      end)
   
   monster.escape_listener = radiant.events.listen_once(monster.monster, 'tower_defense:escape_event', function()
         log:debug('monster %s escaped!', monster.monster)
         self._sv.num_escaped = (self._sv.num_escaped or 0) + 1
         radiant.events.trigger(self, 'tower_defense:wave:monster_escaped', monster.damage or 1, self:_get_escaped_monster_bounty(monster.bounty))

         self:_remove_monster(id)
         radiant.entities.destroy_entity(monster.monster)
      end)
end

function Wave:_remove_monster(id)
   local monster_info = self._sv.spawned_monsters[id]
   if monster_info then
      if monster_info.kill_listener then
         monster_info.kill_listener:destroy()
         monster_info.kill_listener = nil
      end
      if monster_info.escape_listener then
         monster_info.escape_listener:destroy()
         monster_info.escape_listener = nil
      end

      self._sv._last_monster_data[id] = monster_info.monster:add_component('tower_defense:monster'):get_path_data()

      self._sv.spawned_monsters[id] = nil
      if monster_info.counts_as_remaining then
         self._sv.remaining_monsters = math.max(0, self._sv.remaining_monsters - 1)
      end
      self.__saved_variables:mark_changed()
      self:_check_wave_end()
   end
end

function Wave:_check_wave_end()
   if #self._sv._unspawned_monsters < 1 and not next(self._sv.spawned_monsters) and #self._sv._queued_spawn_monsters < 1 then
      -- just make sure we're properly reporting all monsters gone
      self._sv.remaining_monsters = 0
      self.__saved_variables:mark_changed()

      log:debug('wave succeeded!')
      local bonus = radiant.shallow_copy(self._wave_data.completion_bonus or {})
      if bonus.gold then
         bonus.gold = bonus.gold * self._multipliers.gold_bounty
      end
      if bonus.wood then
         bonus.wood = bonus.wood * self._multipliers.wood_bounty
      end
      radiant.events.trigger(self, 'tower_defense:wave:succeeded', bonus)
   end
end

function Wave:_apply_multipliers(multipliers)
   if multipliers then
      if multipliers.attributes then
         for attr, mult in pairs(multipliers.attributes) do
            self._multipliers.attributes[attr] = (self._multipliers.attributes[attr] or 1) * mult
         end
      end
      if multipliers.gold_bounty then
         self._multipliers.gold_bounty = self._multipliers.gold_bounty * multipliers.gold_bounty
      end
      if multipliers.wood_bounty then
         self._multipliers.wood_bounty = self._multipliers.wood_bounty * multipliers.wood_bounty
      end
      if multipliers.escaped_monster_bounty then
         self._multipliers.escaped_monster_bounty = self._multipliers.escaped_monster_bounty * multipliers.escaped_monster_bounty
      end
   end
end

function Wave:_get_escaped_monster_bounty(bounty)
   local mult = self._multipliers.escaped_monster_bounty or 1
   if mult > 0 then
      for resource, amount in pairs(bounty) do
         bounty[resource] = math.ceil(amount * mult)
      end
      return bounty
   end
end

return Wave
