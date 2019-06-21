local RegionRendererComponent = class()

function RegionRendererComponent:initialize()
   self._sv.render_regions = {}
   self._component_listeners = {}
end

function RegionRendererComponent:create()
   self._is_create = true
end

function RegionRendererComponent:post_activate()
   if self._is_create then
      local json = radiant.entities.get_json(self)
      if json and json.render_regions then
         for name, options in pairs(json.render_regions) do
            self:add_render_region(name, radiant.deep_copy(options))
         end
      end
   else
      -- go through all saved render regions and create listeners as necessary
      for name, options in pairs(self._sv.render_regions) do
         if options.component then
            self._component_listeners[name] = self:_create_component_listener(options)
         end
      end
   end
end

function RegionRendererComponent:destroy()
   for _, listener in pairs(self._component_listeners) do
      listener:destroy()
   end
   self._component_listeners = nil
end

function RegionRendererComponent:add_render_region(name, options)
   self:remove_render_region(name)

   self._sv.render_regions[name] = options
   if options.component then
      local listener = self:_create_component_listener(options)
      if listener then
         self._component_listeners[name] = listener:push_object_state()
      end
   end
   self.__saved_variables:mark_changed()
end

function RegionRendererComponent:remove_render_region(name)
   self._sv.render_regions[name] = nil
   if self._component_listeners[name] then
      self._component_listeners[name]:destroy()
      self._component_listeners[name] = nil
   end
   self.__saved_variables:mark_changed()
end

-- doesn't remove unmentioned options, only adds or overrides existing options that are specified
function RegionRendererComponent:set_options(name, options)
   local render_region = self._sv.render_regions[name]
   if render_region then
      for option, value in pairs(options) do
         render_region[option] = value
      end
      self.__saved_variables:mark_changed()
   end
end

function RegionRendererComponent:_create_component_listener(options)
   local component = self._entity:add_component(options.component)
   local listener = component and component[options.component_region_tracer or 'trace_region'](component, 'drawing region')
      :on_changed(function ()
            local region = component:get_region()
            options.region = region and region:get()
            self.__saved_variables:mark_changed()
         end)
   return listener
end

return RegionRendererComponent
