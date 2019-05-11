-- Health modification generic class
--
local PeriodicAuraTowerBuff = class()

function PeriodicAuraTowerBuff:on_buff_added(entity, buff)
   local json = buff:get_json()
   self._tuning = json.script_info
   if not self._tuning or not self._tuning.buffs then
      return
   end
   
   self._entity = entity
   self:_create_pulse_listener(buff)
end

function PeriodicAuraTowerBuff:_create_pulse_listener(buff)
   self:_destroy_pulse_listener()
   
   local interval = self._tuning.pulse or 3000
   self._pulse_listener = stonehearth.combat:set_interval("Aura Buff "..buff:get_uri().." pulse", interval, 
         function()
            self:_on_pulse(buff)
         end)
   self:_on_pulse(buff)
end

function PeriodicAuraTowerBuff:_destroy_pulse_listener()
   if self._pulse_listener then
      self._pulse_listener:destroy()
      self._pulse_listener = nil
   end
end

function PeriodicAuraTowerBuff:_on_pulse(buff)
   local tower_comp = self._entity:get_component('tower_defense:tower')
   local region = tower_comp and tower_comp:get_targetable_region()

   if region then
      local location = radiant.entities.get_world_grid_location(self._entity)
      local entities = radiant.terrain.get_entities_in_region(region:translated(location))
      for _, entity in pairs(entities) do
         if entity:get_component('tower_defense:tower') then
            for _, buff in ipairs(self._tuning.buffs) do
               radiant.entities.add_buff(entity, buff)
            end
         end
      end
   end
end

return PeriodicAuraTowerBuff
