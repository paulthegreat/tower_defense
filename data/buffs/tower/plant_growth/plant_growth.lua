local PlantGrowthBuffScript = class()

function PlantGrowthBuffScript:on_buff_added(entity, buff)
   local orig_render_info = radiant.entities.get_component_data(entity:get_uri(), 'render_info')
   local orig_mob = radiant.entities.get_component_data(entity:get_uri(), 'mob')
   self._orig_scale = orig_render_info and orig_render_info.scale
   self._orig_origin = orig_mob and orig_mob.model_origin

   self:_update_scale(entity, buff)
end

function PlantGrowthBuffScript:on_repeat_add(entity, buff)
   self:_update_scale(entity, buff)
   return true
end

function PlantGrowthBuffScript:_update_scale(entity, buff)
   local stacks = buff:get_stacks()
   local mult = (1 + stacks * 0.2)

   if self._orig_scale then
      local new_scale = self._orig_scale * mult
      entity:add_component('render_info'):set_scale(new_scale)
   end
   if self._orig_origin then
      local new_origin = radiant.util.to_point3(self._orig_origin):scaled(mult)
      entity:add_component('mob'):set_model_origin(new_origin)
   end
end

return PlantGrowthBuffScript
