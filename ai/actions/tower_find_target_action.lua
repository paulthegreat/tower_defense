local Entity = _radiant.om.Entity
local Point3 = _radiant.csg.Point3

local log = radiant.log.create_logger('combat')

local FindTarget = radiant.class()

FindTarget.name = 'tower attack ranged'
FindTarget.does = 'tower_defense:tower_find_target'
FindTarget.args = {}
FindTarget.priority = 0
FindTarget.weight = 1
FindTarget.think_output = {
   target = Entity
}

function FindTarget:start_thinking(ai, entity, args)
   self:_rethink(ai, entity, args)
end

function FindTarget:_rethink(ai, entity, args)
   local target = entity:get_component('tower_defense:tower'):get_best_target()
   if target then
      if self._timer then
         self._timer:destroy()
         self._timer = nil
      end
      ai:set_think_output({target = target})
   elseif not self._timer then
      self._timer = stonehearth.calendar:set_interval('tower find target', '1m', function()
         self:_rethink(ai, entity, args)
      end)
   end
end

return FindTarget
