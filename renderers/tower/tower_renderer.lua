--[[
   handles special range (and whether it's being affected by the selected entity)
]]

local Point3 = _radiant.csg.Point3

local TowerRenderer = class()
local log = radiant.log.create_logger('tower.renderer')

function TowerRenderer:initialize(render_entity, datastore)
   self._render_entity = render_entity
   self._entity = render_entity:get_entity()
   self._entity_node = render_entity:get_node()
   self._player_id = radiant.entities.get_player_id(self._entity)

   self._ui_view_mode = stonehearth.renderer:get_ui_mode()
   self._ui_mode_listener = radiant.events.listen(radiant, 'stonehearth:ui_mode_changed', self, self._on_ui_mode_changed)
   self._is_selected = (stonehearth.selection:get_selected() == self._entity)
   self._selection_listener = radiant.events.listen(self._entity, 'stonehearth:selection_changed', self, self._on_selection_changed)

   self._datastore = datastore
   if datastore.trace then
      self._datastore_trace = self._datastore:trace('drawing tower')
         :on_changed(function ()
               self:_update()
            end)
         :push_object_state()
   elseif self._datastore._sv.is_client_entity then
      local location = radiant.entities.get_location_aligned(self._entity)
      self._location_trace = radiant.entities.trace_location(self._entity, 'tower placement location changed')
         :on_changed(function()
               local new_location = radiant.entities.get_location_aligned(self._entity)
               --log:debug('tower %s location changed from %s to %s', self._entity, tostring(location), tostring(new_location))
               if location ~= new_location and (location == Point3.zero or location == Point3(0, -100000, 0)) then
                  location = new_location
                  self:_update()
               end
            end)
         :push_object_state()
   end
end

function TowerRenderer:destroy()
   if self._datastore_trace then
      self._datastore_trace:destroy()
      self._datastore_trace = nil
   end
   if self._location_trace then
      self._location_trace:destroy()
      self._location_trace = nil
   end
   if self._ui_mode_listener then
      self._ui_mode_listener:destroy()
      self._ui_mode_listener = nil
   end
   self:_destroy_outline_node()
end

function TowerRenderer:_destroy_outline_node()
   if self._outline_node then
      self._outline_node:destroy()
      self._outline_node = nil
   end
end

function TowerRenderer:_on_ui_mode_changed()
   local mode = stonehearth.renderer:get_ui_mode()

   if self._ui_view_mode ~= mode then
      self._ui_view_mode = mode

      self:_update()
   end
end

function TowerRenderer:_on_selection_changed()
   self._is_selected = (stonehearth.selection:get_selected() == self._entity)
   self:_update()
end

function TowerRenderer:_in_correct_mode()
   return self._ui_view_mode == 'hud'
end

function TowerRenderer:_update()
   self:_destroy_outline_node()

   if not (self._is_selected or self:_in_correct_mode()) then
      return
   end

   local data
   if self._datastore.get_data then
      data = self._datastore:get_data()
   else
      data = self._datastore._sv
   end
   local region = data.targetable_region

   if not region then
      return
   end

   local location = radiant.entities.get_world_grid_location(self._entity) or radiant.entities.get_location_aligned(self._entity)
   if not location then
      return
   end

   local EDGE_COLOR_ALPHA = 128
   local FACE_COLOR_ALPHA = 0
   local color = { x = 255, y = 192, z = 32 }
   if stonehearth.presence_client:is_multiplayer() then
      color = stonehearth.presence_client:get_player_color(self._player_id)
   end
   local edge_color = color

   local height = 0.1
   if self._is_selected or data.is_client_entity then
      height = 0.2
      EDGE_COLOR_ALPHA = 192
      FACE_COLOR_ALPHA = 64
   end

   if data.reveals_invis then
      -- make revealing tower regions stick out a little more
      height = math.max(height, 0.15)
      edge_color = { x = 255, y = 0, z = 24}
      EDGE_COLOR_ALPHA = 255
   end

   -- have it float slightly above the ground to avoid z-fighting
   local squish_amount = (height - 1) / 2
   region = region:inflated(Point3(0, squish_amount, 0)):translated(Point3(0, squish_amount + 0.01, 0))

   local render_node
   if data.is_client_entity then
      render_node = self._entity_node
   else
      -- we render it this way so that we don't have to undo the rotation of a tower turning to face an enemy it's attacking
      render_node = RenderRootNode
      region = region:translated(location)
   end

   self._outline_node = _radiant.client.create_region_outline_node(render_node, region,
         radiant.util.to_color4(edge_color, EDGE_COLOR_ALPHA), radiant.util.to_color4(color, FACE_COLOR_ALPHA),
         '/stonehearth/data/horde/materials/transparent_box_nodepth.material.json', 1)
      :set_casts_shadows(false)
      :set_can_query(false)
end

return TowerRenderer
