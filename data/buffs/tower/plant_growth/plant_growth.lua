local PlantGrowthBuffScript = class()

function PlantGrowthBuffScript:on_buff_added(entity, buff)
   local orig_render_info = radiant.entities.get_component_data(entity:get_uri(), 'render_info')
   self._orig_scale = orig_render_info and orig_render_info.scale

   self:_update_scale(entity, buff)
end

function PlantGrowthBuffScript:on_repeat_add(entity, buff)
   self:_update_scale(entity, buff)
   return true
end

function PlantGrowthBuffScript:_update_scale(entity, buff)
   if self._orig_scale then
      local stacks = buff:get_stacks()
      local new_scale = self._orig_scale * (1 + stacks * 0.2)
      entity:add_component('render_info'):set_scale(new_scale)
   end
end

return PlantGrowthBuffScript
