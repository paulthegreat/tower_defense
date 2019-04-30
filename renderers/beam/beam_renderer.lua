local build_util = require 'lib.build_util'
local Point3 = _radiant.csg.Point3
local Region3 = _radiant.csg.Region3
local Color4 = _radiant.csg.Color4
local Quaternion = _radiant.csg.Quaternion

local BeamRenderer = class()
local log = radiant.log.create_logger('beam.renderer')
local BEAM_COLOR = Color4(0, 255, 0, 255)
local PARTICLE_COLOR = Color4(0, 1, 0, 1)

function BeamRenderer:initialize(render_entity, datastore)
   self._entity = render_entity:get_entity()
   --self._parent_node = render_entity:get_node()

   self._datastore = datastore
	self._beam_node = RenderRootNode:add_debug_shapes_node('beam for ' .. tostring(self._entity))
   self._gameloop_trace = radiant.on_game_loop('beam movement', function()
         local data = self._datastore:get_data()
         if data.target then
            if not self._cubemitter then
               self._cubemitter = _radiant.client.create_cubemitter(RenderRootNode, data.particle_effect or '/tower_defense/data/effects/beamtest.cubemitter.json')
               local color = data.particle_color or PARTICLE_COLOR
               self._cubemitter:get_particle_data():get_color():set_start():as_color(color.r, color.g, color.b, color.a)
            end
            self:_update_shape(data.target, data.target_offset, data.beam_color)
         end
		end
	)
end

function BeamRenderer:_destroy_gameloop_trace()
   if self._gameloop_trace then
      self._gameloop_trace:destroy()
      self._gameloop_trace = nil
   end
end

function BeamRenderer:destroy()
   self:_destroy_gameloop_trace()
   if self._beam_node then
      self._beam_node:destroy()
      self._beam_node = nil
   end
   if self._visible_volume_trace then
      self._visible_volume_trace:destroy()
      self._visible_volume_trace = nil
   end
   if self._cubemitter then
      self._cubemitter:destroy()
      self._cubemitter = nil
   end
end

function BeamRenderer:_update_shape(target, target_offset, beam_color)
   self._beam_node:clear()

   if target and target:is_valid() then
      local target_location = target:add_component('mob'):get_world_location()
      local target_point = target_location + (target_offset or Point3.zero)
      local location = radiant.entities.get_world_location(self._entity)
      if location then
         self._beam_node:add_line(location, target_point, beam_color or BEAM_COLOR)
      end

      local midpoint=(location+target_point)/2
      local orientation = Quaternion()
      orientation:look_at(location, target_point)
      local rot = orientation:get_euler_angle()
      local length = (target_point-location):length()

      local emission_data = self._cubemitter:get_emission_data()
      emission_data:set_origin():as_rectangle(0.25, length)--width, height
      emission_data:set_rate():as_constant(50+30*length)
      self._cubemitter:set_transform(midpoint.x, midpoint.y, midpoint.z, math.deg(rot.x)+90, math.deg(rot.y), math.deg(rot.z), 1, 1, 1)
      --emission_data:set_rotation(0,0,0)
   end
   self._beam_node:create_buffers()
end

return BeamRenderer
