local CombatStateComponent = class()

-- duration is in milliseconds at game speed 1
function CombatStateComponent:start_cooldown(name, duration)
   -- TODO: could set a trigger after expiration to remove old cooldowns
   self:_remove_expired_cooldowns()

   if duration and duration > 0 then
      local now = radiant.gamestate.now()
      self._sv.cooldowns[name] = now + duration
      self.__saved_variables:mark_changed()
   end
end

function CombatStateComponent:_get_time_to_impact(action)
   return nil
end

return CombatStateComponent
