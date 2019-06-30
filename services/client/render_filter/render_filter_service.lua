local catalog_lib = require 'stonehearth.lib.catalog.catalog_lib'

local log = radiant.log.create_logger('render_filter_service')

RenderFilter = class()

function RenderFilter:initialize()
   local json = radiant.resources.load_json('tower_defense:data:render_filters')
   self._all_filters = json.render_filters
   for name, filter in pairs(self._all_filters) do
      if filter.buffs then
         local buffs = {}
         for _, uri in ipairs(filter.buffs) do
            buffs[uri] = catalog_lib.get_buff(uri)
         end
         filter.buffs = buffs
      end
   end

   self._filters = radiant.util.get_config('render_filters')
   self._enabled = radiant.util.get_config('render_filters_enabled', true)
   if not self._filters then
      self._filters = json.default
   end
   self:_set_expanded_render_filters()
end

function RenderFilter:set_render_filters(filters)
   self._filters = filters
   radiant.util.set_config('render_filters', filters)
   self:_set_expanded_render_filters()
end

function RenderFilter:get_render_filters()
   return self._filters
end

function RenderFilter:get_expanded_render_filters()
   return self._expanded_filters
end

function RenderFilter:_set_expanded_render_filters()
   self._expanded_filters = {}
   for _, filter in ipairs(self._filters) do
      self._expanded_filters[filter] = self._all_filters[filter]
   end
   radiant.events.trigger(self, 'tower_defense:render_filters_changed')
end

function RenderFilter:set_render_filters_enabled(enabled)
   self._enabled = enabled
   radiant.util.set_config('render_filters_enabled', enabled)
   radiant.events.trigger(self, 'tower_defense:render_filters_enabled_changed', enabled)
end

function RenderFilter:get_render_filters_enabled()
   return self._enabled
end

return RenderFilter
