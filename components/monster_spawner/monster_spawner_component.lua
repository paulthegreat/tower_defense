--[[
   TODO: move all monster spawning from wave controller into this
   that makes it simpler to spawn additional monster spawners (e.g., from spawn_on_death buffs) with effects/duration
]]

local MonsterSpawner = class()

function MonsterSpawner:restore()
   self._is_restore = true
end

function MonsterSpawner:post_activate()
   if self._is_restore then
      self:start()
   end
end

function MonsterSpawner:destroy()
   if self._constant_effect then
      self._constant_effect:stop()
      self._constant_effect = nil
   end
   self:_destroy_spawn_timer()
end

function MonsterSpawner:_destroy_spawn_timer()
   if self._next_spawn_timer then
      self._next_spawn_timer:destroy()
      self._next_spawn_timer = nil
   end
end

function MonsterSpawner:set_settings(settings)
   self._sv._settings = settings
   self.__saved_variables:mark_changed()
end

function MonsterSpawner:start()
   local settings = self._sv._settings
   if settings.constant_effect then
      self._constant_effect = radiant.effects.run_effect(self._entity, settings.constant_effect)
   end

   local spawn_fn
   spawn_fn = function()
      self:_destroy_spawn_timer()
      if tower_defense.game and tower_defense.game:spawn_monsters(settings.monsters, entity_id) then
         num_to_spawn = num_to_spawn - 1
         if num_to_spawn > 0 then
            self._sv._next_spawn_timer = stonehearth.calendar:set_persistent_timer('spawn next monster', settings.time_to_next_spawn, spawn_fn)
         end
      end
   end
   
   spawn_fn()
end

return MonsterSpawner
