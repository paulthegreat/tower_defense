-- Health modification generic class
--
local PeriodicHealthModificationBuff = class()

function PeriodicHealthModificationBuff:on_buff_added(entity, buff)
   local json = buff:get_json()
   self._tuning = json.script_info
   if not self._tuning or (not self._tuning.health_change and not self._tuning.damage) then
      return
   end
   
   self._entity = entity
   self:_create_pulse_listener(buff)
end

function PeriodicHealthModificationBuff:on_repeat_add(entity, buff)
   if not self._entity then
      return
   end

   if self._tuning.pulse_immediately then
      self:_create_pulse_listener(buff)
   end
   return true
end

function PeriodicHealthModificationBuff:_create_pulse_listener(buff)
   self:_destroy_pulse_listener()
   
   local interval = self._tuning.pulse or "1m"
   self._pulse_listener = stonehearth.calendar:set_interval("Aura Buff "..buff:get_uri().." pulse", interval, 
         function()
            self:_on_pulse(buff)
         end)
   if self._tuning.pulse_immediately then
      self:_on_pulse(buff)
   end
end

function PeriodicHealthModificationBuff:_destroy_pulse_listener()
   if self._pulse_listener then
      self._pulse_listener:destroy()
      self._pulse_listener = nil
   end
end

function PeriodicHealthModificationBuff:_on_pulse(buff)
   local resources = self._entity:get_component('stonehearth:expendable_resources')
   if not resources then
      return
   end

   local health_change = buff:get_stacks()
   if self._tuning.health_change then
      health_change = health_change * self._tuning.health_change
      if self._tuning.is_percentage then
         health_change = resources:get_max_value('health') * health_change * 0.01
      end
      if health_change > 0 then
         local attributes = self._entity:get_component('stonehearth:attributes')
         local healing_multiplier = attributes and attributes:get_attribute('multiplicative_healing_modifier', 1) or 1
         health_change = health_change * healing_multiplier
      end
   elseif self._tuning.damage then
      local damage = stonehearth.combat:get_adjusted_damage_value(nil, self._entity, self._tuning.damage, self._tuning.damage_type)
      health_change = health_change * -damage
   end
   
   local current_health = resources:get_value('health')
   local current_guts = resources:get_percentage('guts') or 1
   if current_health <= 0 or current_guts < 1 then
      return  -- don't beat a dead (or incapacitated) horse
   end

   if self._tuning.cannot_kill then
      --if this would kill, leave them at 1 hp instead. "max" and "-" because health_change is negative
      health_change = math.max(health_change, -(current_health - 1))
   end

   radiant.entities.modify_health(self._entity, health_change)
end

function PeriodicHealthModificationBuff:on_buff_removed(entity, buff)
   self:_destroy_pulse_listener()
   if self._tuning.pulse_on_destroy then
      self:_on_pulse(buff)
   end
end

return PeriodicHealthModificationBuff
