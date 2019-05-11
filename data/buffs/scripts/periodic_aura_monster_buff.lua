-- Health modification generic class
--
local PeriodicAuraMonsterBuff = class()

function PeriodicAuraMonsterBuff:on_buff_added(entity, buff)
   local json = buff:get_json()
   self._tuning = json.script_info
   if not self._tuning or not self._tuning.buffs then
      return
   end
   
   self._entity = entity
   self:_create_pulse_listener(buff)
end

function PeriodicAuraMonsterBuff:_create_pulse_listener(buff)
   self:_destroy_pulse_listener()
   
   local interval = self._tuning.pulse or 2000
   self._pulse_listener = stonehearth.combat:set_interval("Aura Buff "..buff:get_uri().." pulse", interval, 
         function()
            self:_on_pulse(buff)
         end)
   self:_on_pulse(buff)
end

function PeriodicAuraMonsterBuff:_destroy_pulse_listener()
   if self._pulse_listener then
      self._pulse_listener:destroy()
      self._pulse_listener = nil
   end
end

function PeriodicAuraMonsterBuff:_on_pulse(buff)
   -- if there's no active wave, cancel out
   if not tower_defense.game:has_active_wave() then
      return
   end

   local tower_comp = self._entity:get_component('tower_defense:tower')
   local region = tower_comp and tower_comp:get_targetable_path_region()

   if region then
      local entities = radiant.terrain.get_entities_in_region(region)
      for _, entity in pairs(entities) do
         if entity:get_component('tower_defense:monster') then
            for _, buff in ipairs(self._tuning.buffs) do
               radiant.entities.add_buff(entity, buff)
            end
         end
      end
   end
end

return PeriodicAuraMonsterBuff
