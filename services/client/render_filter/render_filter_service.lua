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
   self._filter_regions = {}
   for name, filter in pairs(json.render_filters) do
      local regions = {}
      filter.name = name
      if filter.buffs then
         local buffs = {}
         for _, uri in ipairs(filter.buffs) do
            local buff = catalog_lib.get_buff(uri)
            local ordinal_adjustment = buff.ordinal and (buff.ordinal > 1 and (buff.ordinal - 1) * 3 + 0.5) or 0
            regions['buffs.' .. uri] = {
               ordinal_adjustment = ordinal_adjustment,
               base_color = radiant.util.to_color4(buff.color, 128),
               path_color = radiant.util.to_color4(buff.color, 255),
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
               base_color = radiant.util.to_color4(struct.color, 128),
               path_color = radiant.util.to_color4(struct.color, 255),
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
   radiant.events.trigger(self, 'tower_defense:render_filters_loaded')

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
end

function RenderFilter:set_render_filters(filters)
   self._filters = filters
   radiant.util.set_config('render_filters', filters)
   self:_set_active_filters_lookup()
end

function RenderFilter:get_render_filters()
   return self._filters
end

function RenderFilter:get_expanded_render_filters()
   return self._all_filters
end

function RenderFilter:_set_active_filters_lookup()
   self._active_filters = {}
   for _, filter in ipairs(self._filters) do
      self._active_filters[filter] = true
   end
   self:_enable_render_nodes()
end

function RenderFilter:set_render_filters_enabled(enabled)
   self._enabled = enabled
   radiant.util.set_config('render_filters_enabled', enabled)
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

function RenderFilter:_enable_render_nodes()
   for filter, nodes in pairs(self._render_nodes) do
      local visible = self._enabled and (self._active_filters[filter] ~= nil)
      for _, node in ipairs(nodes) do
         node:set_visible(visible)
      end
   end
end

function RenderFilter:_redraw_render_nodes()
   self:_destroy_render_nodes()

   if self._tower_service then
      local towers = self._tower_service:get_data().towers
      --log:debug(radiant.util.table_tostring(towers))

      for _, name in ipairs(self._filters) do
         local filter = self._all_filters[name]
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

return RenderFilter
