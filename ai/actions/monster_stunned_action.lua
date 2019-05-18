local MonsterStunned = radiant.class()

MonsterStunned.name = 'monster stunned'
MonsterStunned.does = 'stonehearth:compelled_behavior'
MonsterStunned.args = {}
MonsterStunned.think_output = {}
MonsterStunned.priority = 0.8

local log = radiant.log.create_logger('monster_stunned')

function MonsterStunned:start_thinking(ai, entity, args)
   self._running = false
   self._ai = ai
   self._entity = entity
   self._listener = radiant.events.listen(entity, 'stonehearth:attribute_changed:stunned', self, self._on_stunned_changed)
end

function MonsterStunned:stop(ai, entity, args)
   self._running = false
   self:_destroy_listener()
   self:_stop_effect()
end

function MonsterStunned:run(ai, entity, args)
   ai:set_status_text_key('tower_defense:ai.actions.status_text.monster_stunned')
   self._running = true

   -- TODO: have an effect listed somewhere (but it's probably based on the attack that applied the stun)
   -- if ability.effect then
   --    local run_effect
   --    run_effect = function()
   --       self._effect = radiant.effects.run_effect(entity, ability.effect)
   --       self._effect:set_cleanup_on_finish(false)
   --       self._effect:set_finished_cb(function()
   --          self:_stop_effect()
   --          run_effect()
   --       end)
   --    end
   --    run_effect()
   -- end

   ai:suspend()
end

function MonsterStunned:_on_stunned_changed()
   if not self._entity and self._entity:is_valid() then
      return
   end

   local attributes = self._entity:get_component('stonehearth:attributes')
   local stunned = attributes and attributes:get_attribute('stunned', 0) or 0
   --log:debug('%s stunned changed: %s (running = %s)', self._entity, stunned, self._running)
   if stunned > 0 then
      if self._running then
         -- already running, don't need to do anything
      else
         self._ai:set_think_output()
      end
   else
      if self._running then
         self._ai:resume()
      else
         self._ai:clear_think_output()
      end
   end
end

function MonsterStunned:_destroy_listener()
   if self._listener then
      self._listener:destroy()
      self._listener = nil
   end
end

function MonsterStunned:_stop_effect()
   if self._effect then
      self._effect:stop()
      self._effect = nil
   end
end

return MonsterStunned
