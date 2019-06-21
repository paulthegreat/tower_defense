--[[
   generic region renderer whose data is maintained by the region_renderer component
   can manually set regions or trace components with regions (e.g., region_collision_shape)
]]

local Point3 = _radiant.csg.Point3
local Color4 = _radiant.csg.Color4

local RegionRenderer = class()
local log = radiant.log.create_logger('region_renderer_renderer')

function RegionRenderer:initialize(render_entity, datastore)
   self._render_entity = render_entity
   self._entity = render_entity:get_entity()
   self._entity_node = render_entity:get_node()
   self._render_nodes = {}

   self._ui_view_mode = stonehearth.renderer:get_ui_mode()
   self._ui_mode_listener = radiant.events.listen(radiant, 'stonehearth:ui_mode_changed', self, self._on_ui_mode_changed)

   -- consider also having listeners for selection, player_id, etc.

   self._datastore = datastore
   self._datastore_trace = self._datastore:trace('drawing regions')
         :on_changed(function ()
               self:_update()
            end)
         :push_object_state()
end

function RegionRenderer:destroy()
   if self._datastore_trace then
      self._datastore_trace:destroy()
      self._datastore_trace = nil
   end
   if self._ui_mode_listener then
      self._ui_mode_listener:destroy()
      self._ui_mode_listener = nil
   end
   self:_destroy_nodes()
end

function RegionRenderer:_destroy_nodes()
   for _, node in ipairs(self._render_nodes) do
      node:destroy()
   end
   self._render_nodes = {}
end

function RegionRenderer:_on_ui_mode_changed()
   local mode = stonehearth.renderer:get_ui_mode()

   if self._ui_view_mode ~= mode then
      self._ui_view_mode = mode

      self:_update()
   end
end

function RegionRenderer:_on_selection_changed()
   self._is_selected = (stonehearth.selection:get_selected() == self._entity)
   self:_update()
end

function RegionRenderer:_in_correct_mode(modes)
   return not modes or modes[self._ui_view_mode]
end

function RegionRenderer:_update()
   self:_destroy_nodes()

   local data = self._datastore:get_data()

   for name, render_region in pairs(data.render_regions) do
      local region = render_region.region

      if not region or not self:_in_correct_mode(render_region.ui_modes) then
         log:debug('no region (%s) or incorrect ui mode %s (requires %s)', tostring(region), self._ui_view_mode, render_region.ui_modes and radiant.util.table_tostring(render_region.ui_modes) or '[ANY]')
         return
      end

      -- apply any transformations to the region
      if render_region.transformations then
         for _, transform in pairs(render_region.transformations) do
            region = region[transform.name](region, self:_cast_params(transform.params))
         end
      end

      local edge_color
      if render_region.edge_color then
         local r, g, b, a = unpack(render_region.edge_color)
         edge_color = Color4(r, g, b, a or 1)
      else
         edge_color = Color4(0, 0, 0, 0)
      end

      local face_color
      if render_region.face_color then
         local r, g, b, a = unpack(render_region.face_color)
         face_color = Color4(r, g, b, a or 1)
      else
         face_color = Color4(0, 0, 0, 0)
      end

      log:debug('rendering region %s with material "%s", edge_color %s, face_color %s', region:get_bounds(), render_region.material, edge_color, face_color)

      table.insert(self._render_nodes, _radiant.client.create_region_outline_node(self._entity_node, region, edge_color, face_color, render_region.material, 1)
         :set_casts_shadows(render_region.casts_shadows or false)
         :set_can_query(render_region.can_query or false))
   end
end

-- parameters for region transformations
-- often just a Point3 object/table (x/y/z properties), could be a sequence of params like for 'extruded'
function RegionRenderer:_cast_params(params)
   return radiant.util.to_point3(params) or unpack(params)
end

return RegionRenderer
