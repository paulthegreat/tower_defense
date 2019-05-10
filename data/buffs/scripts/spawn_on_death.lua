local SpawnOnDeathScript = class()

function SpawnOnDeathScript:on_buff_added(entity, buff)
   local json = buff:get_json()
   local tuning = json.script_info
   if not tuning or not tuning.monsters then
      return
   end

   local entity_id = entity:get_id()
   
   self._killed_listener = radiant.events.listen_once(entity, 'stonehearth:kill_event', function()
      self._killed_listener = nil
      local stacks = buff and buff:get_stacks() or 1
      local monsters = {}
      for _, monster in ipairs(tuning.monsters) do
         monster = radiant.shallow_copy(monster)
         monster.info = radiant.shallow_copy(monster.info)
         local from_population = radiant.shallow_copy(monster.info.from_population)
         from_population.min = stacks * (from_population.min or 1)
         from_population.max = math.max(from_population.min, stacks * (from_population.max or 1))
         monster.info.from_population = from_population

         table.insert(monsters, monster)
      end
      
      tower_defense.game:spawn_monsters(monsters, entity_id)
   end)
end

function SpawnOnDeathScript:on_buff_removed(entity, buff)
   if self._killed_listener then
      self._killed_listener:destroy()
      self._killed_listener = nil
   end
end

return SpawnOnDeathScript
