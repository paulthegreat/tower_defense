--[[
   handles special range (and whether it's being affected by the selected entity)
]]

local Point2 = _radiant.csg.Point2
local Point3 = _radiant.csg.Point3
local Color4 = _radiant.csg.Color4

local render_lib = require 'tower_defense.lib.render.render_lib'

local TowerRenderer = class()
local log = radiant.log.create_logger('tower.renderer')

function TowerRenderer:initialize(render_entity, datastore)
   self._render_entity = render_entity
   self._entity = render_entity:get_entity()
   self._entity_node = render_entity:get_node()
   self._nodes = {}
   -- instead of creating a single billboard node and destroying/recreating it every time relevant filters change,
   -- create (as necessary) each different combination node and cache it
   self._billboard_nodes = {}

   --log:debug('initializing render entity for %s: %s', self._entity, radiant.util.table_tostring(datastore))

   self._is_selected = (stonehearth.selection:get_selected() == self._entity)
   self._selection_listener = radiant.events.listen(self._entity, 'stonehearth:selection_changed', self, self._on_selection_changed)
   self._filters = tower_defense.render_filter:get_expanded_render_filters()
   self._active_filters = tower_defense.render_filter:get_active_render_filters()
   self._render_filter_listener = radiant.events.listen(tower_defense.render_filter,
         'tower_defense:render_filters_changed', self, self._on_render_filters_changed)
   self._filters_enabled = tower_defense.render_filter:get_render_filters_enabled()
   self._render_filter_enabled_listener = radiant.events.listen(tower_defense.render_filter,
         'tower_defense:render_filters_enabled_changed', self, self._on_render_filters_enabled_changed)
   self._client_game_listener = radiant.events.listen(tower_defense.client_game,
         'tower_defense:client_game:map_data_acquired', self, self._on_client_game_map_data_acquired)

   self._presence_client_listener = radiant.events.listen(stonehearth.presence_client,
         'stonehearth:presence_datastore_changed:player_color', self, self._on_player_color_changed)

   self._datastore = datastore.__saved_variables
   self._datastore_trace = self._datastore:trace_data('drawing tower')
      :on_changed(function ()
            log:debug('%s datastore trace triggered', self._entity)
            self:_update()
         end)

   if self._datastore:get_data().is_client_entity then
      self._is_client_entity = true
      self._player_id = _radiant.client.get_player_id()
   else
      self._player_id = radiant.entities.get_player_id(self._entity)
   end

   if self._is_client_entity or stonehearth.presence_client._presence_datastore then
      self._player_color = stonehearth.presence_client:get_player_color(self._player_id)
   end

   local location = radiant.entities.get_location_aligned(self._entity)
   local facing = radiant.entities.get_facing(self._entity)
   self._location_trace = radiant.entities.trace_location(self._entity, 'tower placement location changed')
      :on_changed(function()
            local new_location = radiant.entities.get_location_aligned(self._entity)
            local new_facing = radiant.entities.get_facing(self._entity)
            --log:debug('tower %s location changed from %s to %s', self._entity, tostring(location), tostring(new_location))
            if location ~= new_location or facing ~= new_facing then -- and (location == Point3.zero or location == Point3(0, -100000, 0)) then
               location = new_location
               facing = new_facing
               self:_update(location)
            end
         end)
      :push_object_state()

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
   if self._render_filter_listener then
      self._render_filter_listener:destroy()
      self._render_filter_listener = nil
   end
   if self._render_filter_enabled_listener then
      self._render_filter_enabled_listener:destroy()
      self._render_filter_enabled_listener = nil
   end
   self:_destroy_nodes()
   self:_destroy_billboard_node()
end

function TowerRenderer:_destroy_nodes()
   for _, node in ipairs(self._nodes) do
      node:destroy()
   end
   self._nodes = {}
end

function TowerRenderer:_destroy_billboard_node()
   for _, node in pairs(self._billboard_nodes) do
      node:destroy()
   end
   self._billboard_nodes = {}
end

function TowerRenderer:_on_selection_changed()
   self._is_selected = (stonehearth.selection:get_selected() == self._entity)
   self:_update_billboard_visibility()
   self:_update()
end

function TowerRenderer:_on_render_filters_changed()
   self._filters = tower_defense.render_filter:get_expanded_render_filters()
   self._active_filters = tower_defense.render_filter:get_active_render_filters()
   self:_update()
end

function TowerRenderer:_on_render_filters_enabled_changed()
   self._filters_enabled = tower_defense.render_filter:get_render_filters_enabled()
   self:_update_billboard_visibility()
   self:_update()
end

function TowerRenderer:_on_client_game_map_data_acquired()
   self:_update()
end

function TowerRenderer:_on_player_color_changed(args)
   if args.player_id == self._player_id then
      self._player_color = args.new_value
      self:_update()
   end
end

function TowerRenderer:_update_billboard_visibility()
   if self._billboard_node then
      self._billboard_node:set_visible(self._is_client_entity or self._filters_enabled or self._is_selected)
   end
end

function TowerRenderer:_hide_billboard_node()
   if self._billboard_node then
      self._billboard_node:set_visible(false)
   end
end

function TowerRenderer:_update(location)
   self:_destroy_nodes()

   local data = self._datastore:get_data()
   if not data then
      return
   end

   local region = data.targetable_region
   location = location or radiant.entities.get_world_grid_location(self._entity) or radiant.entities.get_location_aligned(self._entity)

   if (self._is_selected or self._is_client_entity) and region and location then
      log:debug('rendering %s', self._entity)

      local render_node = RenderRootNode

      if self._is_client_entity then
         -- need to rotate the region to get a proper path intersection
         log:debug('%s facing %s', self._entity, radiant.entities.get_facing(self._entity))
         region = region:translated(Point3(-0.5, 0, -0.5)):rotated(radiant.entities.get_facing(self._entity)):translated(Point3(0.5, 0, 0.5))
      end
      
      region = region:translated(location)
      local path_intersection = tower_defense.client_game:get_path_intersection_region(region, data.attacks_ground, data.attacks_air)

      local extra_path_alpha = (_radiant.client.get_player_id() == self._player_id or self._is_client_entity) and 64 or 0

      -- determine if/how this tower fits into selected render filters
      -- if it's client-based, show everything (?); if it's selected, show the regular selected style
      -- otherwise, show all included ones

      local has_base_region = false
      local has_path_region = false
      
      local specs = {}
      if self._is_selected then
         has_base_region = true
         has_path_region = true
         table.insert(specs, {
            name = 'selected',
            base_ordinal = 0,
            path_ordinal = 0,
            path_color = Color4(255, 255, 255, 255),
            base_color = Color4(255, 255, 255, 64),
            base_region = true,
            path_region = true
         })
      end

      local buffs = data.buffs or {}
      for name, filter in pairs(self._filters) do
         for uri, buff in pairs(filter.buffs or {}) do
            if buffs[uri] then
               has_base_region = has_base_region or filter.base_region
               has_path_region = has_path_region or filter.path_region
               local ordinal_adjustment = buff.ordinal and (buff.ordinal > 1 and (buff.ordinal - 1) * 3 + 0.5) or 0
               table.insert(specs, self:_get_render_spec(name .. ': ' .. uri, filter, buff.color, ordinal_adjustment))
            end
         end

         for property, property_specs in pairs(filter.tower_properties or {}) do
            if data[property] then
               has_base_region = has_base_region or filter.base_region
               has_path_region = has_path_region or filter.path_region
               table.insert(specs, self:_get_render_spec(name .. ': ' .. property, filter, property_specs.color, 0))
            end
         end
      end

      -- only show a default base region if it's a client entity
      if not has_base_region and self._is_client_entity then
         has_base_region = true
         table.insert(specs, {
            name = 'default_base',
            base_ordinal = 0,
            path_ordinal = 0,
            path_color = Color4(255, 255, 255, 255),
            base_color = Color4(255, 255, 255, 64),
            base_region = true
         })
      end

      -- show a default path intersection region for attacks if no debuffs are being applied
      if not has_path_region and self._is_client_entity and path_intersection and not path_intersection:empty() then
         has_path_region = true
         table.insert(specs, {
            name = 'default_path',
            base_ordinal = 0,
            path_ordinal = 0,
            path_color = Color4(255, 255, 255, 255),
            base_color = Color4(255, 255, 255, 64),
            path_region = true
         })
      end

      for _, spec in ipairs(specs) do
         if spec.base_region then
            table.insert(self._nodes, render_lib.draw_tower_region(render_node, region, spec.base_ordinal, spec.base_color,
                  '/stonehearth/data/horde/materials/transparent_box.material.json'))
         end

         if spec.path_region and path_intersection and not path_intersection:empty() then
            table.insert(self._nodes, render_lib.draw_tower_region(render_node, path_intersection, spec.path_ordinal, spec.path_color,
                  '/stonehearth/data/horde/materials/unlit.material.json'))
         end
      end
   end

   -- determine if we need to re-render the billboard node (it's slow to create, so we can't do it every time or it'll flicker)
   local recreate
   local icons = {}
   local key
   if self._player_color and (self._filters_enabled or self._is_selected or self._is_client_entity) then
      local buffs = data.buffs or {}
      for name, filter in pairs(self._filters) do
         if self._active_filters[name] or self._is_selected or self._is_client_entity then
            for uri, buff in pairs(filter.buffs or {}) do
               local icon = buffs[uri] and buff.icon
               if icon then
                  table.insert(icons, icon)
               end
            end

            for property, property_specs in pairs(filter.tower_properties or {}) do
               local icon = data[property] and property_specs.icon
               if icon then
                  table.insert(icons, icon)
               end
            end
         end
      end

      key = self:_get_billboard_key(icons)
      recreate = self._billboard_node == nil or key ~= self._billboard_key
   end

   if recreate then
      self:_hide_billboard_node()

      if #icons > 0 then
         self._billboard_key = key
         local node = self._billboard_nodes[key]
         if not node then
            node = self:_create_billboard_node(icons)
            self._billboard_nodes[key] = node
         end

         self._billboard_node = node
         self:_update_billboard_visibility()

         --log:debug('%s recreating billboard node', self._entity)
      else
         self._billboard_node = nil
      end
   end

   -- for _, spec in ipairs(specs) do
   --    if spec.base_region then
   --       -- have it float slightly above the ground to avoid z-fighting
   --       log:debug('%s rendering base node %s', self._entity, spec.name)
   --       table.insert(self._nodes,
   --          _radiant.client.create_region_outline_node(render_node,
   --             region:inflated(Point3(0, spec.inflate_amount, 0)):translated(Point3(0, spec.inflate_amount + 0.01, 0)),
   --             spec.edge_color, spec.face_color, '/stonehearth/data/horde/materials/transparent_box.material.json', 1)
   --          :set_casts_shadows(false)
   --          :set_can_query(false)
   --       )
   --    end
   --    if spec.path_region and path_intersection and not path_intersection:empty() then
   --       log:debug('%s rendering path intersection node %s', self._entity, spec.name)
   --       table.insert(self._nodes,
   --          _radiant.client.create_region_outline_node(RenderRootNode,
   --             path_intersection:inflated(Point3(0, spec.path_inflate_amount, 0)), --:translated(Point3(0, spec.path_inflate_amount, 0)),
   --             spec.edge_color, spec.face_color, '/stonehearth/data/horde/materials/transparent_box.material.json', 1)
   --          :set_casts_shadows(false)
   --          :set_can_query(false)
   --       )
   --    end
   -- end
end

function TowerRenderer:_get_render_spec(name, filter, color, ordinal_adjustment)
   return {
      name = name,
      base_ordinal = (filter.base_ordinal and (filter.base_ordinal + ordinal_adjustment) or 0) * 0.05,
      path_ordinal = (filter.path_ordinal and (filter.path_ordinal + ordinal_adjustment) or 0) * 0.05,
      path_color = render_lib.to_color4(color, 255),
      base_color = render_lib.to_color4(color, 128),
      base_region = filter.base_region,
      path_region = filter.path_region
   }
end

function TowerRenderer:_get_billboard_key(icons)
   return table.concat(icons, ',')
end

function TowerRenderer:_create_billboard_node(icons)
   local color = self._player_color
   local color_string = string.format('rgba(%s,%s,%s,%s)', color.x, color.y, color.z, 0.9)
   local icons_string = table.concat(icons, ',')
   local url = string.format('stonehearth/tower_defense/ui/billboards/tower_buffs.html?bgColor=%s&icons=%s', color_string, icons_string)
   local width = #icons * 46 + 10
   local height = 61
   local scale_factor = 0.012

   if #icons > 3 then
      scale_factor = scale_factor * 3 / #icons
   end

   local node = self._entity_node:add_ui_billboard_node('tower_buffs', url,
         width * scale_factor, height * scale_factor,
         width, height,
         math.min(#icons, 3) * -0.25 - 0.1, 0)
   return node
end

return TowerRenderer
