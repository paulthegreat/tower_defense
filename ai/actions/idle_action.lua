local Idle = radiant.class()

Idle.name = 'idle'
Idle.does = 'stonehearth:idle'
Idle.args = {
   hold_position = {    -- is the unit allowed to move around in the action?
      type = 'boolean',
      default = false,
   },
   set_status_text = {
      type = 'boolean',
      default = true,
   }
}
Idle.priority = 0

function Idle:start_thinking(ai, entity, args)
   self._timer = stonehearth.calendar:set_timer("wait to set status and reset facing", "2m",
      function(self, entity)
         ai:set_think_output()
      end
   )
end

function Idle:stop_thinking(ai, entity, args)
   if self._timer then
      self._timer:destroy()
      self._timer=nil
   end
end

function Idle:run(ai, entity, args)
   if args.set_status_text then
      ai:set_status_text_key('stonehearth:ai.actions.status_text.idle')
   end

   if entity:get_component('tower_defense:tower') then
      radiant.entities.turn_to(entity, entity:get_component('tower_defense:tower'):get_original_facing() or 0)
   end

   if self._timer then
      self._timer:destroy()
      self._timer=nil
   end
end

return Idle
