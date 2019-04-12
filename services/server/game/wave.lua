--[[
   instantiated by the game service
   runs the whole wave, from monsters spawning through to all monsters being gone, either through death or end of path
]]

local Point3 = _radiant.csg.Point3
local game_master_lib = require 'stonehearth.lib.game_master.game_master_lib'
local log = radiant.log.create_logger('wave')

local Wave = class()

function Wave:initialize()
   self._sv._unspawned_monsters = {}
   self._sv._spawned_monsters = {}
   self._sv.remaining_monsters = 0
end

function Wave:create(wave_data, map_data)
   self._sv._wave_data = wave_data
   self._sv._map_data = map_data

   self._is_create = true
end

function Wave:activate()
   self._wave_data = radiant.resources.load_json(self._sv._wave_data.uri)
   
   if self._sv._next_spawn_timer then
      self._sv._next_spawn_timer:bind(function()
         self:_spawn_next_monster()
      end)
   end

   if self._is_create then
      self:_load_unspawned_monsters()
   end

   for _, spawned_monster in pairs(self._sv._spawned_monsters) do
      self:_activate_monster(spawned_monster)
   end
end

function Wave:destroy()
   self:_destroy_next_spawn_timer()
end

function Wave:_destroy_next_spawn_timer()
   if self._sv._next_spawn_timer then
      self._sv._next_spawn_timer:destroy()
      self._sv._next_spawn_timer = nil
      self.__saved_variables:mark_changed()
   end
end

function Wave:_load_unspawned_monsters()
   self._sv._unspawned_monsters = {}

   for _, monster_data in ipairs(self._wave_data.monsters) do
      -- ignoring wave modifiers for now
      for i = 1, monster_data.count or 1 do
         local monsters = {}
         for _, monster in ipairs(monster_data.each_spawn) do
            table.insert(monsters, monster)
            self._sv.remaining_monsters = self._sv.remaining_monsters + (monster.info.from_population.max or 1)
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
   self:_spawn_next_monster()
end

function Wave:_create_next_spawn_timer(time)
   self:_destroy_next_spawn_timer()
   
   if not time then
      time = self._wave_data.time_to_next_monster
   end

   if time and #self._sv._unspawned_monsters > 0 then
      self._sv._next_spawn_timer = stonehearth.calendar:set_persistent_timer('spawn next monster', time, function()
         self:_spawn_next_monster()
      end)
   end
end

function Wave:_spawn_next_monster()
   local monster_info = table.remove(self._sv._unspawned_monsters, 1)
   if monster_info then
      local location = self._sv._map_data.spawn_location

      local did_spawn = false
      for _, monster in ipairs(monster_info.monsters) do
         local pop = stonehearth.population:get_population(monster.population)
         if pop then
            local this_location = location
            if monster.population == 'air' then
               this_location.y = this_location.y + self._sv._map_data.air_path.height
            end

            local new_monsters = game_master_lib.create_citizens(pop, monster.info, this_location, {player_id = ''})
            for _, monster in ipairs(new_monsters) do
               local this_monster = {
                  monster = monster,
                  damage = monster.damage
               }
               self._sv._spawned_monsters[monster:get_id()] = this_monster
               self:_activate_monster(this_monster)

               did_spawn = true
            end
            self.__saved_variables:mark_changed()
         end
      end

      if did_spawn then
         self:_create_next_spawn_timer(monster_info.time_to_next_monster)
      end
   end
end

-- set up listeners and get monster moving on the path
function Wave:_activate_monster(monster)
   local id = monster.monster:get_id()
   monster.kill_listener = radiant.events.listen_once(monster.monster, 'stonehearth:kill_event', function()
         -- if it was killed, hand out gold
         -- probably better to do this by event and have the game service listen to it, but oh well!
         tower_defense.game:give_all_players_gold(self:_get_gold_amount(monster.monster))
         
         self:_remove_monster(id)
      end)
   
   -- 'monster' is a table containing monster entity and any other information we need
   -- (like last path checkpoint reached)

end

function Wave:_remove_monster(id)
   if self._sv._spawned_monsters[id] then
      self._sv._spawned_monsters[id] = nil
      self._sv.remaining_monsters = math.max(0, self._sv.remaining_monsters - 1)
      self.__saved_variables:mark_changed()
      self:_check_wave_end()
   end
end

function Wave:_get_gold_amount(entity)
   return 1
end

-- again, should probably do this with events, but directly calling game service instead
function Wave:_check_wave_end()
   if #self._sv._unspawned_monsters < 1 and not next(self._sv._spawned_monsters) then
      -- just make sure we're properly reporting all monsters gone
      self._sv.remaining_monsters = 0
      self.__saved_variables:mark_changed()
      tower_defense.game:_end_of_round()
   end
end

-- TODO: implement as event?
function Wave:monster_finished_path(monster)
   local id = monster:get_id()
   local monster_info = self._sv._spawned_monsters[id]
   if monster_info then
      if monster_info.kill_listener then
         monster_info.kill_listener:destroy()
         monster_info.kill_listener = nil
      end

      -- subtract hit points?
      tower_defense.game:remove_health(monster_info.damage)

      self:_remove_monster(id)
   end
end

return Wave
