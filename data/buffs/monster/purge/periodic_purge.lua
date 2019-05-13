local Cube3 = _radiant.csg.Cube3
local Point3 = _radiant.csg.Point3
local PeriodicPurgeMonsterBuff = class()

local rng = _radiant.math.get_default_rng()

function PeriodicPurgeMonsterBuff:on_buff_added(entity, buff)
   local json = buff:get_json()
   self._tuning = json.script_info or {}
   self._entity = entity
   self:_create_pulse_listener(buff)
end

function PeriodicPurgeMonsterBuff:_create_pulse_listener(buff)
   self:_destroy_pulse_listener()
   
   local interval = self._tuning.pulse or 3000
   self._pulse_listener = stonehearth.combat:set_interval("periodic purge "..buff:get_uri().." pulse", interval, 
         function()
            self:_on_pulse(buff)
         end)
   self:_on_pulse(buff)
end

function PeriodicPurgeMonsterBuff:_destroy_pulse_listener()
   if self._pulse_listener then
      self._pulse_listener:destroy()
      self._pulse_listener = nil
   end
end

function PeriodicPurgeMonsterBuff:_on_pulse(buff)
   local location = radiant.entities.get_world_location(self._entity)

   if location then
      local entities
      if self._tuning.range then
         entities = radiant.terrain.get_entities_in_cube(Cube3(Point3.zero):inflated(Point3(self._tuning.range, 0, self._tuning.range)))
      else
         entities = {self._entity}
      end

      for _, entity in pairs(entities) do
         if entity:get_component('tower_defense:monster') then
            local buffs_comp = entity:add_component('stonehearth:buffs')
            local buffs = buffs_comp:get_debuffs()
            if #buffs > 0 then
               if self._tuning.type == 'random' then
                  buffs_comp:remove_buff(buffs[rng:get_int(1, #buffs)], true)
               else
                  for _, buff in ipairs(buffs) do
                     buffs_comp:remove_buff(buff, true)
                  end
               end
            end
         end
      end
   end
end

return PeriodicPurgeMonsterBuff
