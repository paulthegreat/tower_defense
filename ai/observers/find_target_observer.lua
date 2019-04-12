local log = radiant.log.create_logger('combat')

local FindTargetObserver = class()

function FindTargetObserver:initialize()
   self._sv._entity = nil
end

function FindTargetObserver:create(entity)
   self._sv._entity = entity
   self._running = true
end

function FindTargetObserver:restore()
   self._running = false
   self._game_loaded_trace = radiant.events.listen_once(radiant, 'radiant:game_loaded', function()
         self._running = true
         self:_check_for_target()
         self._game_loaded_trace = nil
      end)
end

-- Ok to reference other datastores in activate, but do not call methods on them
function FindTargetObserver:activate()
   -- copy _entity out of _sv, since referencing _sv is expensive and _entity never changes
   self._entity = self._sv._entity
   assert(self._entity)

   self._sight_sensor = radiant.entities.get_sight_sensor(self._entity)

   self._sight_sensor_trace = self._sight_sensor:trace_contents('find target obs')
                                                   :on_added(function (id, target)
                                                         self:_on_sensor_contents_changed(id, target)
                                                      end)

   self._current_target = nil
   self._task = nil

   self._log = radiant.log.create_logger('combat')
                           :set_prefix('find_target_obs')
                           :set_entity(self._entity)

   -- Subscribe to events in activate so that we catch events from other post_activates that occur before our post_activate
   -- Do not push_object_changes until post_activate though
   self:_subscribe_to_events()
end

-- Must wait until post-activate to call methods on other datastores
function FindTargetObserver:post_activate()
   self:_check_for_target()
end

function FindTargetObserver:destroy()
   self:_unsubscribe_from_events()
end

function FindTargetObserver:_subscribe_to_events()
   self._stance_changed_trace = radiant.events.listen(self._entity, 'stonehearth:combat:stance_changed', self, self._on_stance_changed)
end

function FindTargetObserver:_unsubscribe_from_events()
   if self._sight_sensor_trace then
      self._sight_sensor_trace:destroy()
      self._sight_sensor_trace = nil
   end

   if self._stance_changed_trace then
      self._stance_changed_trace:destroy()
      self._stance_changed_trace = nil
   end

   if self._assault_trace then
      self._assault_trace:destroy()
      self._assault_trace = nil
   end

   self:_destroy_task()

   if self._game_loaded_trace then
      self._game_loaded_trace:destroy()
      self._game_loaded_trace = nil
   end
end

function FindTargetObserver:_destroy_task()
   if self._task then
      self._task:destroy()
      self._task = nil
   end
end

function FindTargetObserver:_on_sensor_contents_changed(id, target)
   self:_check_for_target()
end

function FindTargetObserver:_on_stance_changed()
   self:_check_for_target()
end

function FindTargetObserver:_check_for_target()
   if not self._entity:is_valid() then
      return
   end

   if not self._running then
      return
   end

   if self:_do_not_disturb() then
      self._log:spam('do not disturb is set. skipping target check...')
      -- don't interrupt an assault in progress
      return
   end

   -- if sticky targeting, check if current target exists and is still in range
   -- if so, continue attacking that target; otherwise, find a new target to attack

   -- ok for new_target to be nil
   local new_target
   local tower_comp = self._entity:get_component('tower_defense:tower')
   if tower_comp then
      new_target = tower_comp:get_best_target()
   end

   self:_attack_target(new_target)
end

function FindTargetObserver:_do_not_disturb()
   local assaulting = stonehearth.combat:get_assaulting(self._entity)
   return assaulting
end

-- target allowed to be nil
function FindTargetObserver:_attack_target(target)
   -- make sure we set it here unconditionally even if target == self._current_target
   -- because it might be cleared by someone else
   stonehearth.combat:set_primary_target(self._entity, target)

   if target == self._current_target and self._task then
      -- we're already attacking that target, nothing to do
      assert(target == self._task:get_args().target)
      return
   end

   self._log:info('setting target to %s', tostring(target))

   if target ~= self._current_target then
      self:_destroy_task()
      self._current_target = target
   end

   if target and target:is_valid() then
      assert(not self._task)
      self._task = self._entity:add_component('stonehearth:ai')
                         :get_task_group('tower_defense:task_groups:tower_combat')
                            :create_task('stonehearth:combat:attack_after_cooldown', { target = target })
                               :once()
                               :notify_completed(
                                 function ()
                                    self._task = nil
                                    self:_check_for_target()
                                 end
                               )
                               :start()
   end
end

return FindTargetObserver
