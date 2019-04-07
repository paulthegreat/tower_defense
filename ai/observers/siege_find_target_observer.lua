local FindTargetObserver = require 'stonehearth.ai.observers.find_target_observer'
local log = radiant.log.create_logger('combat')

local SiegeFindTargetObserver = class()
radiant.mixin(SiegeFindTargetObserver, FindTargetObserver)

function SiegeFindTargetObserver:activate()
   -- copy _entity out of _sv, since referencing _sv is expensive and _entity never changes
   self._entity = self._sv._entity
   assert(self._entity)

   self._scored_targets = {}
   self._highest_scored_target = nil
   self._highest_score = -1
   self._current_target = nil
   self._last_attacker = nil
   self._last_attacked_time = 0
   self._retaliation_window = 5000
   self._task = nil
   self._subscribed = false

   self._log = radiant.log.create_logger('combat')
                           :set_prefix('find_target_obs')
                           :set_entity(self._entity)

   self:_create_parent_trace()

   -- Subscribe to events in activate so that we catch events from other post_activates that occur before our post_activate
   -- Do not push_object_changes until post_activate though
   -- self:_subscribe_to_events()
end

function SiegeFindTargetObserver:destroy()
   self:_unsubscribe_from_events()
   if self._parent_trace then
      self._parent_trace:destroy()
      self._parent_trace = nil
   end
   if self._out_of_ammo_trace then
      self._out_of_ammo_trace:destroy()
      self._out_of_ammo_trace = nil
   end
end

function SiegeFindTargetObserver:_create_sight_sensor_trace()
   if not self._sight_sensor_trace then
      self._sight_sensor = radiant.entities.get_sight_sensor(self._entity)
      self._sight_sensor_trace = self._sight_sensor:trace_contents('find target obs')
                                                      :on_added(function (id, target)
                                                            if self._aggro_table:contains(target) then
                                                               -- target is now visible and may have a positive score
                                                               self:_update_target_score(id, target)
                                                               self:_check_for_target()
                                                            end
                                                         end)
                                                      :on_removed(function (id)
                                                            local target = radiant.entities.get_entity(id)
                                                            if self._aggro_table:contains(target) then
                                                               self._aggro_table:remove_entry(id)
                                                            end
                                                         end)
   end
end

function SiegeFindTargetObserver:_create_parent_trace()
   if not self._parent_trace then
      self._parent_trace = self._entity:add_component('mob'):trace_parent('siege weapon added or removed')
                  :on_changed(function(parent_entity)
                        if not parent_entity then
                           --we were just removed from the world
                           self:_unsubscribe_from_events() --destroy task and unsubscribe
                        else
                           self:_create_ammo_trace() -- if entity is placed, need an ammo trace to make sure it starts tracing when refilled
                           if not self._subscribed then
                              self:_subscribe_to_events()
                              self:_check_for_target()
                           end
                        end
                     end)
                  :push_object_state()
   end
end

function SiegeFindTargetObserver:_create_ammo_trace()
   if not self._out_of_ammo_trace then
      self._out_of_ammo_trace = radiant.events.listen(self._entity, 'stonehearth:siege_weapon:ammo_status_changed', self, self._on_ammo_status_changed)
   end
end

function SiegeFindTargetObserver:_subscribe_to_events()
   if self._subscribed then
      return -- already subscribed
   end
   self:_create_sight_sensor_trace()
   FindTargetObserver._subscribe_to_events(self)
   self._assaulting_trace = radiant.events.listen(self._entity, 'stonehearth:combat:assaulting_changed', self, self._on_stance_changed)
   self._subscribed = true
end

function SiegeFindTargetObserver:_unsubscribe_from_events()
   if not self._subscribed then
      return -- already unsubscribed
   end
   FindTargetObserver._unsubscribe_from_events(self)
   if self._assaulting_trace then
      self._assaulting_trace:destroy()
      self._assaulting_trace = nil
   end
   self._subscribed = false
end

function SiegeFindTargetObserver:_on_ammo_status_changed(args)
   if args.out_of_ammo then
      self:_unsubscribe_from_events()
      -- if self._parent_trace then
      --    self._parent_trace:destroy()
      --    self._parent_trace = nil
      -- end
   else
      if not self._subscribed and radiant.entities.get_parent(self._entity) then
         self:_subscribe_to_events()
         -- self:_create_parent_trace()
      end
   end
end

return SiegeFindTargetObserver
