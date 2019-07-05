local Point2 = _radiant.csg.Point2
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Rect2 = _radiant.csg.Rect2
local Region2 = _radiant.csg.Region2
local Region3 = _radiant.csg.Region3
local Color4 = _radiant.csg.Color4

local catalog_lib = require 'stonehearth.lib.catalog.catalog_lib'
local render_lib = require 'tower_defense.lib.render.render_lib'

local log = radiant.log.create_logger('render_filter_service')

RenderFilter = class()

function RenderFilter:initialize()
   local json = radiant.resources.load_json('tower_defense:data:render_filters')
   local base_filters = {}
   local path_filters = {}
   self._render_nodes = {}
   self._billboard_nodes = {}
   self._billboard_node_data = {}
   self._filter_regions = {}
   self._frame_traces = {}

   for name, filter in pairs(json.render_filters) do
      local regions = {}
      filter.name = name
      if filter.buffs then
         local buffs = {}
         for _, uri in ipairs(filter.buffs) do
            local buff = catalog_lib.get_buff(uri)
            local ordinal_adjustment = buff.ordinal and (buff.ordinal > 1 and (buff.ordinal - 1) * 3.2 + 0.5) or 0
            regions['buffs.' .. uri] = {
               ordinal_adjustment = ordinal_adjustment,
               icon = buff.icon,
               base_color = render_lib.to_color4(buff.color, 128),
               path_color = render_lib.to_color4(buff.color, 255),
               base_region = Region3(),
               path_region = Region3()
            }
            buffs[uri] = buff
         end
         filter.buffs = buffs
      end
      if filter.tower_properties then
         for property, struct in pairs(filter.tower_properties) do
            regions['tower_properties.' .. property] = {
               ordinal_adjustment = 0,
               icon = struct.icon,
               base_color = render_lib.to_color4(struct.color, 128),
               path_color = render_lib.to_color4(struct.color, 255),
               base_region = Region3(),
               path_region = Region3()
            }
         end
      end

      if filter.base_region then
         table.insert(base_filters, filter)
      end
      if filter.path_region then
         table.insert(path_filters, filter)
      end
      self._filter_regions[name] = regions
   end

   table.sort(base_filters, function(a, b) return a.ordinal < b.ordinal end)
   table.sort(path_filters, function(a, b) return a.ordinal < b.ordinal end)

   local filters = {}
   for i, filter in ipairs(base_filters) do
      filter.base_ordinal = i
      filters[filter.name] = filter
   end
   for i, filter in ipairs(path_filters) do
      filter.path_ordinal = i
      filters[filter.name] = filter -- shouldn't matter if we're overwriting an existing filter reference, since the table for it should be the same
   end

   self._all_filters = filters
   

   self._filters = radiant.util.get_config('render_filters')
   self._enabled = radiant.util.get_config('render_filters_enabled', true)
   if not self._filters then
      self._filters = json.default
   end
   self:_set_active_filters_lookup()

   _radiant.call('tower_defense:get_service', 'tower'):done(function(response)
         self._tower_service = response.result
         self._tower_trace = self._tower_service:trace_data('render towers')
            :on_changed(function()
                  self:_redraw_render_nodes()
               end)
            :push_object_state()
      end)
end

function RenderFilter:destroy()
   self._tower_service = nil
   if self._tower_trace then
      self._tower_trace:destroy()
      self._tower_trace = nil
   end
   self:_destroy_render_nodes()
   --self:_destroy_billboard_nodes()
   --self:_destroy_frame_traces()
end

function RenderFilter:set_render_filters(filters)
   self._filters = filters
   radiant.util.set_config('render_filters', filters)
   self:_set_active_filters_lookup()
end

function RenderFilter:get_render_filters()
   return self._filters
end

function RenderFilter:get_active_render_filters()
   return self._active_filters
end

function RenderFilter:get_expanded_render_filters()
   return self._all_filters
end

function RenderFilter:_set_active_filters_lookup()
   self._active_filters = {}
   for _, filter in ipairs(self._filters) do
      self._active_filters[filter] = true
   end
   radiant.events.trigger(self, 'tower_defense:render_filters_changed')
   self:_enable_render_nodes()
end

function RenderFilter:set_render_filters_enabled(enabled)
   self._enabled = enabled
   radiant.util.set_config('render_filters_enabled', enabled)
   radiant.events.trigger(self, 'tower_defense:render_filters_enabled_changed')
   self:_enable_render_nodes()
end

function RenderFilter:get_render_filters_enabled()
   return self._enabled
end

function RenderFilter:_destroy_render_nodes()
   for filter, nodes in pairs(self._render_nodes) do
      for _, node in ipairs(nodes) do
         node:destroy()
      end
   end
   self._render_nodes = {}
end

-- function RenderFilter:_destroy_billboard_nodes(filter_change)
--    for entity, node_data in pairs(self._billboard_nodes) do
--       local destroy = true
--       if filter_change and self._enabled then
--          -- check if any of the currently active filters coincide with the billboard node data for this entity
--          -- but aren't in the current node, or vice-versa
--          local all_filters = self._billboard_node_data[entity]
--          if all_filters then
--             destroy = false
--             for filter, _ in pairs(all_filters) do
--                if (self._active_filters[filter] ~= nil) ~= (node_data.filters[filter] ~= nil) then
--                   destroy = true
--                   break
--                end
--             end
--          end
--       end

--       if destroy then
--          node_data.node:destroy()
--          self._billboard_nodes[entity] = nil
--       end
--    end
-- end

-- function RenderFilter:_destroy_frame_traces()
--    for trace, _ in pairs(self._frame_traces) do
--       trace:destroy()
--    end
--    self._frame_traces = {}
-- end

function RenderFilter:_enable_render_nodes()
   --self:_destroy_billboard_nodes(true)
   --self:_destroy_frame_traces()

   for filter, nodes in pairs(self._render_nodes) do
      local visible = self._enabled and (self._active_filters[filter] ~= nil)
      for _, node in ipairs(nodes) do
         node:set_visible(visible)
         node:set_can_query(false)
      end
   end

   -- if self._enabled then
   --    for entity, effects in pairs(self._billboard_node_data) do
   --       if not self._billboard_nodes[entity] then
   --          local active = {}
   --          local filters = {}

   --          for filter, icons in pairs(effects) do
   --             if self._active_filters[filter] then
   --                filters[filter] = true
   --                for _, icon in ipairs(icons) do
   --                   table.insert(active, icon)
   --                end
   --             end
   --          end

   --          if #active > 0 then
   --             self._billboard_nodes[entity] = {
   --                filters = filters,
   --                node = self:_create_billboard_node(entity, active)
   --             }
   --          end
   --       end
   --    end
   -- end
end

function RenderFilter:_redraw_render_nodes()
   self:_destroy_render_nodes()
   --self._billboard_node_data = {}

   if self._tower_service then
      local towers = self._tower_service:get_data().towers
      --log:debug(radiant.util.table_tostring(towers))
      local overlay_id = 0

      for name, filter in pairs(self._all_filters) do
         local regions = self._filter_regions[name]
         for id, data in pairs(regions) do
            data.base_region = Region3()
            data.path_region = Region3()
         end

         for id, tower in pairs(towers) do
            for uri, buff in pairs(filter.buffs or {}) do
               if tower.buffs[uri] then
                  local region_data = regions['buffs.' .. uri]
                  if filter.base_region and tower.tower_region then
                     --log:debug('added %s to base_region of %s', tower.tower_region:get_bounds(), tower.tower)
                     region_data.base_region = region_data.base_region + tower.tower_region
                  end
                  if filter.path_region and tower.targetable_region then
                     region_data.path_region = region_data.path_region + tower.targetable_region
                  end
                  -- if region_data.icon then
                  --    self:_add_billboard_node_icon(tower.tower, name, region_data.icon)
                  -- end
               end
            end

            for property, property_specs in pairs(filter.tower_properties or {}) do
               if tower[property] then
                  local region_data = regions['tower_properties.' .. property]
                  if filter.base_region and tower.tower_region then
                     region_data.base_region = region_data.base_region + tower.tower_region
                  end
                  if filter.path_region and tower.targetable_region then
                     region_data.path_region = region_data.path_region + tower.targetable_region
                  end
                  -- if region_data.icon then
                  --    self:_add_billboard_node_icon(tower.tower, name, region_data.icon)
                  -- end
               end
            end
         end

         self._render_nodes[name] = self:_draw_regions(regions, filter)
      end

      self:_enable_render_nodes()
   end
end

function RenderFilter:_draw_regions(regions, filter)
   local nodes = {}
   for id, data in pairs(regions) do
      if not data.base_region:empty() then
         data.base_region:optimize('pre-draw regions')
         table.insert(nodes, render_lib.draw_tower_region(RenderRootNode, data.base_region, (filter.base_ordinal + data.ordinal_adjustment) * 0.05, data.base_color,
               '/stonehearth/data/horde/materials/transparent_box.material.json'))
      end
      if not data.path_region:empty() then
         data.path_region:optimize('pre-draw regions')
         table.insert(nodes, render_lib.draw_tower_region(RenderRootNode, data.path_region, (filter.path_ordinal + data.ordinal_adjustment) * 0.05, data.path_color,
               '/stonehearth/data/horde/materials/unlit.material.json'))
      end
   end
   return nodes
end

-- function RenderFilter:_add_billboard_node_icon(entity, filter, icon)
--    local entity_data = self._billboard_node_data[entity]
--    if not entity_data then
--       entity_data = {}
--       self._billboard_node_data[entity] = entity_data
--    end
--    if not entity_data[filter] then
--       entity_data[filter] = {}
--    end
--    table.insert(entity_data[filter], icon)
-- end

-- function RenderFilter:_create_billboard_node(entity, icons)
--    local render_entity = _radiant.client.get_render_entity(entity)
--    local render_node = render_entity:get_node()
--    local player_id = radiant.entities.get_player_id(entity)
--    local player_color = stonehearth.presence_client:get_player_color(player_id)
--    local color_string = string.format('rgba(%s,%s,%s,%s)', player_color.x, player_color.y, player_color.z, 0.9)
--    local icons_string = table.concat(icons, ',')
--    local url = string.format('stonehearth/tower_defense/ui/billboards/tower_buffs.html?bgColor=%s&icons=%s', color_string, icons_string)
--    local width = #icons * 46 + 10
--    local height = 61
--    local scale_factor = 0.012

--    local node = render_node:add_ui_billboard_node('tower_buffs', url, width * scale_factor, height * scale_factor, width, height, #icons * -0.25 - 0.15, -0.25)
--    return node
-- end

-- function RenderFilter:_setup_overlay_node_args(client_effect_data, entity, args)
--    local effects = client_effect_data[entity]
--    if not effects then
--       effects = {}
--       client_effect_data[entity] = effects
--    end
--    table.insert(effects, args)
-- end

-- function RenderFilter:_create_overlay_node(render_entity, name, icon, color, offset)
--    local e = render_entity:start_client_only_effect('tower_defense:effects:overlay:buff_overlay', {renderNodeName = name})
--    local trace
--    trace = _radiant.client.trace_render_frame()
--       :on_frame_finished('create render_filter overlay nodes', function()
--          local n = render_entity:find_node(name)
--          if n then
--             trace:destroy()
--             self._frame_traces[name] = nil
--             log:debug('modifying overlay node: %s', name)
--             local material = n:as_billboard():get_material()
--             material:set_texture_parameter('albedoMap', icon)
--             material:set_vector_parameter('playerColor', color.x, color.y, color.z, 1)
--             n:set_scale(Point3.one * 0.25)
--             n:set_position(offset)
--             n:set_casts_shadows(false)
--             n:set_can_query(false)
--          end
--       end)
--    self._frame_traces[name] = trace

--    return e
-- end

-- function RenderFilter:_create_overlay_node(location, icon, color)
--    local n = RenderRootNode:add_ui_billboard_node('/stonehearth/data/horde/materials/overlay.material.json')
--    local material = n:as_billboard():get_material()
--    material:set_texture_parameter('foregroundMap', icon)
--    material:set_vector_parameter('playerColor', color.r, color.g, color.b, color.a)
--    n:set_position(location)
--    n:set_casts_shadows(false)
--    n:set_can_query(false)
--    return n
-- end

return RenderFilter
