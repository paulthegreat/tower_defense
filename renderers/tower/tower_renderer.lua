--[[
   handles special range (and whether it's being affected by the selected entity)
]]

local Point3 = _radiant.csg.Point3
local Color4 = _radiant.csg.Color4

local TowerRenderer = class()
local log = radiant.log.create_logger('tower.renderer')

function TowerRenderer:initialize(render_entity, datastore)
   self._render_entity = render_entity
   self._entity = render_entity:get_entity()
   self._entity_node = render_entity:get_node()
   self._player_id = radiant.entities.get_player_id(self._entity)
   self._nodes = {}

   --log:debug('initializing render entity for %s: %s', self._entity, radiant.util.table_tostring(datastore))

   --self._ui_view_mode = stonehearth.renderer:get_ui_mode()
   --self._ui_mode_listener = radiant.events.listen(radiant, 'stonehearth:ui_mode_changed', self, self._on_ui_mode_changed)
   self._is_selected = (stonehearth.selection:get_selected() == self._entity)
   self._selection_listener = radiant.events.listen(self._entity, 'stonehearth:selection_changed', self, self._on_selection_changed)
   self._filters = tower_defense.render_filter:get_expanded_render_filters()
   self._render_filter_listener = radiant.events.listen(tower_defense.render_filter, 'tower_defense:render_filters_changed', self, self._on_render_filter_changed)
   self._filters_enabled = tower_defense.render_filter:get_render_filters_enabled()
   self._render_filter_enabled_listener = radiant.events.listen(tower_defense.render_filter, 'tower_defense:render_filters_enabled_changed', self, self._on_render_filter_enabled_changed)
   self._client_game_listener = radiant.events.listen(tower_defense.client_game, 'tower_defense:client_game:map_data_acquired', self, self._on_client_game_map_data_acquired)

   self._datastore = datastore.__saved_variables
   self._datastore_trace = self._datastore:trace_data('drawing tower')
      :on_changed(function ()
            log:debug('%s datastore trace triggered', self._entity)
            self:_update()
         end)

   if self._datastore:get_data().is_client_entity then
      local location = radiant.entities.get_location_aligned(self._entity)
      self._location_trace = radiant.entities.trace_location(self._entity, 'tower placement location changed')
         :on_changed(function()
               local new_location = radiant.entities.get_location_aligned(self._entity)
               --log:debug('tower %s location changed from %s to %s', self._entity, tostring(location), tostring(new_location))
               if location ~= new_location then -- and (location == Point3.zero or location == Point3(0, -100000, 0)) then
                  location = new_location
                  self:_update(location)
               end
            end)
         :push_object_state()
   end

   self:_update()
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
   if self._render_filter_listener then
      self._render_filter_listener:destroy()
      self._render_filter_listener = nil
   end
   if self._render_filter_enabled_listener then
      self._render_filter_enabled_listener:destroy()
      self._render_filter_enabled_listener = nil
   end
   self:_destroy_nodes()
end

function TowerRenderer:_destroy_nodes()
   for _, node in ipairs(self._nodes) do
      node:destroy()
   end
   self._nodes = {}
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

function TowerRenderer:_on_render_filter_changed()
   self._filters = tower_defense.render_filter:get_expanded_render_filters()
   self:_on_render_filter_enabled_changed()
end

function TowerRenderer:_on_render_filter_enabled_changed()
   self._filters_enabled = tower_defense.render_filter:get_render_filters_enabled()
   self:_update()
end

function TowerRenderer:_on_client_game_map_data_acquired()
   self:_update()
end

function TowerRenderer:_in_correct_mode()
   return true
   --return self._ui_view_mode == 'hud'
end

function TowerRenderer:_update(location)
   self:_destroy_nodes()

   local data = self._datastore:get_data()
   local region = data.targetable_region

   if not region then
      log:debug('%s no region', self._entity)
      return
   end

   if not (self._is_selected or self:_in_correct_mode() or data.is_client_entity) then
      log:debug('%s %sselected, %sin correct mode, %sis_client_entity', self._entity, self._is_selected or 'not ', self:_in_correct_mode() or 'not ', data.is_client_entity or 'not ')
      return
   end

   location = location or radiant.entities.get_world_grid_location(self._entity) or radiant.entities.get_location_aligned(self._entity)
   if not location then
      log:debug('%s no location', self._entity)
      return
   end

   log:debug('rendering %s', self._entity)

   local extra_path_alpha = (_radiant.client.get_player_id() == self._player_id or data.is_client_entity) and 64 or 0

   -- determine if/how this tower fits into selected render filters
   -- if it's client-based, show everything (?); if it's selected, show the regular selected style
   -- otherwise, show all included ones

   local has_base_region = false
   
   local specs = {}
   if self._is_selected then
      has_base_region = true
      table.insert(specs, {
         name = 'selected',
         inflate_amount = -0.45,
         path_inflate_amount = -0.01,
         edge_color = Color4(255, 255, 255, 160),
         face_color = Color4(255, 255, 255, 64),
         base_region = true,
         path_region = true
      })
   end

   -- only apply these filters if they're toggled on
   if self._filters_enabled then
      local buffs = data.buffs or {}
      for name, filter in pairs(self._filters) do
         for uri, buff in pairs(filter.buffs or {}) do
            if buffs[uri] then
               has_base_region = has_base_region or filter.base_region
               local inflate_adjustment = buff.ordinal and (buff.ordinal - 1) * 0.15 or 0
               table.insert(specs, self:_get_render_spec(name .. ': ' .. uri, filter, buff.color, extra_path_alpha, inflate_adjustment))
            end
         end

         for property, property_specs in pairs(filter.tower_properties or {}) do
            if data[property] then
               has_base_region = has_base_region or filter.base_region
               table.insert(specs, self:_get_render_spec(name .. ': ' .. property, filter, property_specs.color, extra_path_alpha, 0))
            end
         end
      end
   end

   -- only show a default base region if it's a client entity
   if not has_base_region and data.is_client_entity then
      table.insert(specs, {
         name = 'default_base',
         inflate_amount = -0.48,
         path_inflate_amount = -0.48,
         edge_color = Color4(255, 255, 255, 96),
         face_color = Color4(255, 255, 255, 32),
         base_region = true
      })
   end

   local path_intersection = tower_defense.client_game:get_path_intersection_region(region:translated(location), data.attacks_ground, data.attacks_air)

   local render_node
   if data.is_client_entity then
      render_node = self._entity_node
   else
      -- we render it this way so that we don't have to undo the rotation of a tower turning to face an enemy it's attacking
      render_node = RenderRootNode
      region = region:translated(location)
   end

   for _, spec in ipairs(specs) do
      if spec.base_region then
         -- have it float slightly above the ground to avoid z-fighting
         log:debug('%s rendering base node %s', self._entity, spec.name)
         table.insert(self._nodes,
            _radiant.client.create_region_outline_node(render_node,
               region:inflated(Point3(0, spec.inflate_amount, 0)):translated(Point3(0, spec.inflate_amount + 0.01, 0)),
               spec.edge_color, spec.face_color, '/stonehearth/data/horde/materials/transparent_box.material.json', 1)
            :set_casts_shadows(false)
            :set_can_query(false)
         )
      end
      if spec.path_region and path_intersection and not path_intersection:empty() then
         log:debug('%s rendering path intersection node %s', self._entity, spec.name)
         table.insert(self._nodes,
            _radiant.client.create_region_outline_node(RenderRootNode,
               path_intersection:inflated(Point3(0, spec.path_inflate_amount, 0)), --:translated(Point3(0, spec.path_inflate_amount, 0)),
               spec.edge_color, spec.face_color, '/stonehearth/data/horde/materials/transparent_box.material.json', 1)
            :set_casts_shadows(false)
            :set_can_query(false)
         )
      end
   end
end

function TowerRenderer:_get_render_spec(name, filter, color, extra_path_alpha, inflate_adjustment)
   local base_alpha = filter.base_region and 32 or 0
   return {
      name = name,
      inflate_amount = filter.inflate_amount + inflate_adjustment,
      path_inflate_amount = filter.inflate_amount + inflate_adjustment,
      edge_color = radiant.util.to_color4(color, 192 + base_alpha),
      face_color = radiant.util.to_color4(color, 64 + base_alpha + extra_path_alpha),
      base_region = filter.base_region,
      path_region = filter.path_region
   }
end

return TowerRenderer
