local Entity = _radiant.om.Entity

local SiegeCheckEntityTargetable = radiant.class()

SiegeCheckEntityTargetable.name = 'check entity targetable'
SiegeCheckEntityTargetable.does = 'stonehearth:siege:turret_check_entity_targetable'
SiegeCheckEntityTargetable.args = {
   target = Entity
}
SiegeCheckEntityTargetable.priority = 0

function SiegeCheckEntityTargetable:start_thinking(ai, entity, args)
   self._ready = false

   local update_think_output = function()
         self:_update_think_output(ai, entity, args)
      end

   update_think_output()  -- Safe to do sync since it can't call both clear_think_output and set_think_output.

   if not self._ready then
      self._target_location_trace = radiant.entities.trace_grid_location(args.target, 'turret wait for targetable location')
                                       :on_changed(update_think_output)
   end
end

-- this MUST NOT call both clear_think_output and set_think_output to be Safe to do sync
function SiegeCheckEntityTargetable:_update_think_output(ai, entity, args)
   local clear_think_output = function()
         if self._ready then
            ai:clear_think_output()
            self._ready = false
         end
      end

   local weapon = stonehearth.combat:get_main_weapon(entity)
   if not weapon or not weapon:is_valid() then
      clear_think_output()
      return
   end

   -- Don't target/attack if we (not the target) are outside the leash
   if stonehearth.combat:is_entity_outside_leash(entity) then
      clear_think_output()
      return
   end

   if not self._ready then
      self._ready = true
      ai:set_think_output()
   end
end

function SiegeCheckEntityTargetable:stop_thinking(ai, entity, args)
   if self._target_location_trace then
      self._target_location_trace:destroy()
      self._target_location_trace = nil
   end
end

return SiegeCheckEntityTargetable
