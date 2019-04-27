local TowerCH = require 'tower_defense.call_handlers.tower_call_handler'

local WoodInvestmentBuffScript = class()

function WoodInvestmentBuffScript:on_buff_added(entity, buff)
   local json = buff:get_json()
   self._tuning = json.script_info

   local stacks = buff:get_stacks()
   -- apply model variant based on number of stacks
   self:_set_stacks_model(entity, buff, stacks)
end

function WoodInvestmentBuffScript:on_repeat_add(entity, buff)
   local stacks = buff:get_stacks()
   -- apply model variant based on number of stacks
   self:_set_stacks_model(entity, buff, stacks)

   -- if we hit max stacks, auto-harvest
   if stacks >= buff:get_max_stacks() then
      TowerCH:harvest_wood(entity, buff:get_uri())
   end
end

function WoodInvestmentBuffScript:_set_stacks_model(entity, buff, stacks)
   local render_info = entity:add_component('render_info')
   local stacks_data = self._tuning.stacks
   local stack_data = stacks_data and stacks_data[tostring(stacks)] or {}
   
   if stack_data.model then
      render_info:set_model_variant(stack_data.model)
   end
   if stack_data.scale then
      render_info:set_scale(stack_data.scale)
   end
   if stack_data.wood then
      buff:set_stacks_vis(stack_data.wood)
   end

   local stacks_vis = buff:get_stacks_vis() or 0
   -- add command to allow the player to manually harvest
   -- we do this here instead of when initially added to avoid the command being added when harvesting would yield 0 wood
   if stacks_vis > 0 and self._tuning.harvest_command then
      entity:add_component('stonehearth:commands'):add_command(self._tuning.harvest_command)
   end
end

function WoodInvestmentBuffScript:on_buff_removed(entity, buff)
   -- remove harvest command
   if self._tuning.harvest_command then
      local commands = entity:add_component('stonehearth:commands')
      if commands then
         commands:remove_command(self._tuning.harvest_command)
      end
   end

   -- reset model variant and scale
   local render_info = entity:add_component('render_info')
   render_info:set_model_variant('default')
   render_info:set_scale(radiant.entities.get_component_data(entity, 'render_info').scale)
end

return WoodInvestmentBuffScript
