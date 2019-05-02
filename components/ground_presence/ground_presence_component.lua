--[[
   this component should only be used for short-duration effects, so saving is unnecessary
   just like beams and projectiles
]]

local GroundPresenceComponent = class()

function GroundPresenceComponent:restore()
   -- ground presences are destroyed on load
   radiant.entities.destroy_entity(self._entity)
end

function GroundPresenceComponent:destroy()
   if self._periodic_listener then
      self._periodic_listener:destroy()
      self._periodic_listener = nil
   end
end

function GroundPresenceComponent:set_settings(settings)
   self._settings = settings
end

function GroundPresenceComponent:set_attack_cb(attack_cb)
   self._attack_cb = attack_cb
end

function GroundPresenceComponent:start()
   local settings = self._settings
   local location = radiant.entities.get_world_location(self._entity)
   local region = self._entity:add_component('region_collision_shape'):get_region():get():translated(location)
   
   local affected_entities = {}
   local periodic_fn = function(duration_finished)
      local entities = radiant.terrain.get_entities_in_region(region)
      for id, entity in pairs(entities) do
         if entity:get_component('tower_defense:monster') then
            if not affected_entities[id] then
               affected_entities[id] = true
               self:_do_periodic_things(settings, entity, true, duration_finished)
            else
               self:_do_periodic_things(settings, entity, false, duration_finished)
            end
         end
      end
   end

   stonehearth.combat:set_timer('ground_presence duration', settings.duration, function()
      if self._entity and self._entity:is_valid() then
         periodic_fn(true)
         radiant.events.trigger(self._entity, 'tower_defense:combat:ground_presence_terminated')
         radiant.entities.destroy_entity(self._entity)
      end
   end)
   
   if not self._attack_cb then
      return
   end

   self._periodic_listener = stonehearth.combat:set_timer('ground presence', settings.period or 1000, periodic_fn)
   periodic_fn(false)
end

function GroundPresenceComponent:_do_periodic_things(settings, entity, first_time, duration_finished)
   if duration_finished and not settings.do_on_duration_finished then
      return
   end

   if first_time and settings.first_time then
      self:_do_things(entity, settings.first_time)
   elseif not first_time and settings.other_times then
      self:_do_things(entity, settings.other_times)
   end

   if settings.every_time then
      self:_do_things(entity, settings.every_time)
   end
end

function GroundPresenceComponent:_do_things(entity, things)
   if self._attack_cb and things.attack_info then
      self._attack_cb(entity, things.attack_info)
   end

   if things.buffs then
      for uri, options in pairs(things.buffs) do
         radiant.entities.add_buff(entity, uri, options)
      end
   end
end

return GroundPresenceComponent
