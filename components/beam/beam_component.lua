local Point3 = _radiant.csg.Point3
local Color4 = _radiant.csg.Color4
local log = radiant.log.create_logger('beam')

local BeamComponent = class()

local SECONDS_PER_GAMELOOP = 0.05

function BeamComponent:initialize()
   self._duration = 0
   self._sv.color = _radiant.csg.Color4(255, 0, 0, 255)
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
   if self._origin_mover then
      self._origin_mover:destroy()
      self._origin_mover = nil
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

function BeamComponent:set_style(particle_effect, particle_color, beam_color)
   self._sv.particle_effect = particle_effect
   -- we assume colors are passed as arrays of 4 numbers
   if particle_color then
      self._sv.particle_color = Color4(unpack(particle_color))
   end
   self._sv.beam_color = beam_color and Color4(unpack(beam_color))
   self.__saved_variables:mark_changed()
end

function BeamComponent:set_origin(entity_id, offset, get_world_location_fn)
   self._origin_mover = radiant.on_game_loop('beam origin movement', function()
      local location = get_world_location_fn(offset, entity_id)
      if location and self._entity and self._entity:is_valid() then
         radiant.entities.move_to(self._entity, location)
      end
   end)
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

function BeamComponent:get_intersection_targets(target_filter_fn)
   local location = radiant.entities.get_world_location(self._entity)
   local target_location = radiant.entities.get_world_location(self._sv.target)
   local targets = {}
   
   _physics:walk_line(location, target_location, function(location)
      for id, entity in pairs(radiant.terrain.get_entities_at_point(location, target_filter_fn)) do
         targets[id] = entity
      end
   end, 0)

   return targets
end

return BeamComponent
