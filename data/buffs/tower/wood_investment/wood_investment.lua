local TowerCH = require 'tower_defense.call_handlers.tower_call_handler'

local WoodInvestmentBuffScript = class()

function WoodInvestmentBuffScript:on_buff_added(entity, buff)
   local json = buff:get_json()
   self._tuning = json.script_info

   -- add command to allow the player to manually harvest
   if self._tuning.harvest_command then
      entity:add_component('stonehearth:commands'):add_command(self._tuning.harvest_command)
   end

   local stacks = buff:get_stacks()
   -- apply model variant based on number of stacks
   self:_set_stacks_model(entity, stacks)
end

function WoodInvestmentBuffScript:on_repeat_add(entity, buff)
   local stacks = buff:get_stacks()
   -- apply model variant based on number of stacks
   self:_set_stacks_model(entity, stacks)

   -- if we hit max stacks, auto-harvest
   if stacks >= buff:get_max_stacks() then
      TowerCH:harvest_wood(entity, buff:get_uri())
   end
end

function WoodInvestmentBuffScript:_set_stacks_model(entity, stacks)
   entity:add_component('render_info'):set_model_variant(stacks .. '_stacks')
end

function WoodInvestmentBuffScript:on_buff_removed(entity, buff)
   -- remove harvest command
   if self._tuning.harvest_command then
      local commands = entity:add_component('stonehearth:commands')
      if commands then
         commands:remove_command(self._tuning.harvest_command)
      end
   end

   -- reset model variant
   entity:add_component('render_info'):set_model_variant('default')
end

return WoodInvestmentBuffScript
