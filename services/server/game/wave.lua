--[[
   instantiated by the game service
   runs the whole wave, from monsters spawning through to all monsters being gone, either through death or end of path
]]

local Point3 = _radiant.csg.Point3
local game_master_lib = require 'stonehearth.lib.game_master.game_master_lib'

local Wave = class()

function Wave:initialize()
   self._sv._unspawned_monsters = {}
   self._sv._spawned_monsters = {}
end

function Wave:create(json, map_data, overrides)
   self._sv._json = json
   self._sv._map_data = map_data
   self._sv._overrides = overrides or {}

   self:_load_unspawned_monsters()
end

function Wave:activate()
   self._wave_data = radiant.resources.load_json(json)

   for _, spawned_monster in pairs(self._sv._spawned_monsters) do
      self:_activate_monster(spawned_monster)
   end
end

function Wave:destroy()
   self:_destroy_next_spawn_timer()
end

function Wave:_destroy_next_spawn_timer()
   if self._next_spawn_timer then
      self._next_spawn_timer:destroy()
      self._next_spawn_timer = nil
   end
end

function Wave:_load_unspawned_monsters()
   
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
      self._next_spawn_timer = stonehearth.calendar:set_timer('spawn next monster', time, function()
         self:_spawn_next_monster()
      end)
   end
end

function Wave:_spawn_next_monster()
   local monster_info = table.remove(self._sv._unspawned_monsters, 1)
   if monster_info then
      local location = Point3(unpack(self._sv._overrides.spawn_location or self._wave_data.spawn_location or stonehearth.constants.tower_defense.wave.SPAWN_LOCATION))
      local location_offset
      if monster_info.spawn_location then
         location_offset = Point3(unpack(monster_info.spawn_location))
         location = location + location_offset
      end
      local pop = stonehearth.population:get_population(monster_info.population)
      if pop then
         local new_monsters = game_master_lib.create_citizens(pop, monster_info.info, location)
         for _, monster in ipairs(new_monsters) do
            self._sv._spawned_monsters[monster:get_id()] = {
               monster = monster,
               location_offset = location_offset,
               path_point = 0
            }
            self:_activate_monster(monster)
         end
         self.__saved_variables:mark_changed()

         if next(new_monsters) then
            self:_create_next_spawn_timer(monster_info.time_to_next)
         end
      end
   end
end

-- set up listeners and get monster moving on the path
function Wave:_activate_monster(monster)
   radiant.events.listen_once(monster.monster, 'stonehearth:kill_event', function()
         -- if it was killed, hand out gold
         -- probably better to do this by event and have the game service listen to it, but oh well!
         tower_defense.game:give_all_players_gold(self:_get_gold_amount(monster.monster))
      end)
   
   
end

function Wave:_get_gold_amount(entity)
   return 1
end

return Wave
