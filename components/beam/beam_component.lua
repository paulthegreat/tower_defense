local Point3 = _radiant.csg.Point3
local log = radiant.log.create_logger('beam')

local BeamComponent = class()

local SECONDS_PER_GAMELOOP = 0.05

function BeamComponent:initialize()
   self._sv._target = nil
   self._sv._target_offset = Point3.zero
   self._duration = 0
end

function BeamComponent:create()
--   local mob = self._entity:add_component('mob')
--   mob:set_interpolate_movement(true)
--   mob:set_ignore_gravity(true)
--
--   self._mob = mob
end

function BeamComponent:restore()
   -- beams are destroyed on load
   radiant.entities.destroy_entity(self._entity)
end

function BeamComponent:activate()
end

function BeamComponent:post_activate()
end

function BeamComponent:destroy()
   if self._target_tracker then
      self._target_tracker:destroy()
      self._target_tracker = nil
   end
end

function BeamComponent:set_target(target, offset)
	self._sv.target = target
   self._sv.target_offset = offset
   self.__saved_variables:mark_changed()
end

-- in s at normal gameduration
function BeamComponent:set_duration(duration)
   self._duration = duration
end

function BeamComponent:start()
	stonehearth.combat:set_timer('beam duration', self._duration, function()
      if self._entity and self._entity:is_valid() then
         radiant.events.trigger(self._entity, 'tower_defense:combat:beam_terminated')
         radiant.entities.destroy_entity(self._entity)
      end
   end)

   -- local target = self._sv.target
   -- if target and target:is_valid() then
   --    self._target_tracker = target:add_component('mob'):trace_transform('beam target moved')
   --       :on_changed(function()
   --          radiant.entities.turn_to_face(self._entity, target)
   --       end)
   -- end
end

return BeamComponent
