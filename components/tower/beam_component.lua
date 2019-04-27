local Quaternion = _radiant.csg.Quaternion
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
end

function BeamComponent:set_target(target)
	self._sv._target = target
   self.__saved_variables:mark_changed()
end

-- in s at normal gameduration
function BeamComponent:set_duration(duration)
   self._duration = duration
end

function BeamComponent:set_target_offset(offset)
   -- for non-zero xz, change _get_vector_to_target to transform the offset from local to world coordinates
   assert(offset.x == 0 and offset.z == 0, 'not implemented')
   self._sv._target_offset = offset
   self.__saved_variables:mark_changed()
end

function BeamComponent:start()
	local beam_duration_timer = stonehearth.combat:set_timer('beam duration', self._duration, function()
   	   beam_duration_timer = nil
			if self._entity and self._entity:is_valid() then
				radiant.entities.destroy_entity(self._entity)
			end
		end
	)
end

return BeamComponent
