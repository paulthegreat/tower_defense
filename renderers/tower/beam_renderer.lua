local build_util = require 'lib.build_util'
local Point3 = _radiant.csg.Point3
local Region3 = _radiant.csg.Region3
local Color4 = _radiant.csg.Color4

local BeamRenderer = class()
local log = radiant.log.create_logger('beam.renderer')
local COLOR = Color4(0, 255, 0, 255)

function BeamRenderer:initialize(render_entity, datastore)
   self._entity = render_entity:get_entity()
   self._color = COLOR

   self._datastore = datastore
	self._beam_node = RenderRootNode:add_debug_shapes_node('beam for ' .. tostring(self._entity))
   self._gameloop_trace = radiant.on_game_loop('beam movement', function()
			self._target = self._datastore:get_data()._target
			self._target_offset = self._datastore:get_data()._target_offset

         if self._target and self._target:is_valid() then
				self:_update_shape()
         end
		end
	)

   self._visible_volume_trace = radiant.events.listen(stonehearth.subterranean_view, 'stonehearth:visible_volume_changed', self, self._update_shape)
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
end

function BeamRenderer:_update_shape()
   self._beam_node:clear()

	if stonehearth.subterranean_view:is_visible(self._entity) then
		local target_location = self._target:add_component('mob'):get_world_location()
		local target_point = target_location + self._target_offset
		local location = radiant.entities.get_world_location(self._entity)
		if location then
			x, y, z = beam_point:get_xyz()
			point:set(x, y + Y_OFFSET, z)
			self._beam_node:add_line(location, target_point, self._color)
		end
	end
   self._beam_node:create_buffers()
end

return BeamRenderer
