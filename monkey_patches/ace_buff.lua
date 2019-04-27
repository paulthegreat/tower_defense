local modifiers_lib = require 'stonehearth.lib.modifiers.modifiers_lib'
local Buff = require 'stonehearth.components.buffs.buff'
local AceBuff = class()

local log = radiant.log.create_logger('buff')

-- "options" were already being passed in, but the parameter didn't exist and wasn't used
AceBuff._ace_old_create = Buff.create
function AceBuff:create(entity, uri, json, options)
   self:_ace_old_create(entity, uri, json)
   self._options = options
end

AceBuff._ace_old_activate = Buff.activate
function AceBuff:activate()
   self:_ace_old_activate()
   if not self._json.max_stacks then
      self._sv.max_stacks = 1
      self.__saved_variables:mark_changed()
   end
end

AceBuff._ace_old_destroy = Buff.destroy
function AceBuff:destroy()
   if self._duration_timer then
      self._duration_timer:destroy()
      self._duration_timer = nil
   end
   if self._timer then
      self._timer:destroy()
      self._timer = nil
   end
   if self._json.duration_statistics_key then
      self:_update_duration_stat()
   end

   if self._ace_old_destroy then
      self:_ace_old_destroy()
   end
end

AceBuff._ace_old__create_buff = Buff._create_buff
function AceBuff:_create_buff()
   self:_ace_old__create_buff()

   -- now do any post-create options
   if self._options then
      if self._options.stacks and self._options.stacks > 1 then
         self._options.stacks = self._options.stacks - 1
         self:on_repeat_add(self._options)
      end
   end
end

function AceBuff:_create_modifiers(modifiers)
   if modifiers then
      local new_modifiers = modifiers_lib.add_attribute_modifiers(self._sv._entity, modifiers, { invisible_to_player = self._json.invisible_to_player})
      table.insert(self._attribute_modifiers, new_modifiers)   -- insert the table of modifiers into it so we can easily remove a single stack
   end
end

function AceBuff:_destroy_modifiers()
   while #self._attribute_modifiers > 0 do
      self:_destroy_last_stack_modifiers()
   end
end

function AceBuff:_destroy_last_stack_modifiers()
   local modifiers = table.remove(self._attribute_modifiers)
   if modifiers then
      for i, modifier in ipairs(modifiers) do
         modifier:destroy()
      end
   end
end

function AceBuff:remove_stack()
   self._sv.stacks = self._sv.stacks - 1
   self:_destroy_last_stack_modifiers()
   self.__saved_variables:mark_changed()

   if self._sv.stacks < 1 then
      self:destroy()
   end
end

function AceBuff:get_stacks()
   return self._sv.stacks
end

function AceBuff:get_max_stacks()
   return self._sv.max_stacks
end

function AceBuff:get_duration()
   local expire_time = self._sv.expire_time
   return expire_time and (expire_time - stonehearth.calendar:get_elapsed_time()) or -1
end

function AceBuff:get_stacks_vis()
   return self._sv.stacks_vis
end

function AceBuff:set_stacks_vis(stacks_vis)
   self._sv.stacks_vis = stacks_vis
   self.__saved_variables:mark_changed()
end

function AceBuff:get_script_data()
   return self._sv._script_data
end

function AceBuff:set_script_data(data)
   self._sv._script_data = data
   self.__saved_variables:mark_changed()
end

-- override to allow removing stacks instead of entire buff on expire
function Buff:_create_timer()
   local duration = self._default_duration
   if self._sv.expire_time then
      duration = self._sv.expire_time - stonehearth.calendar:get_elapsed_time()
      if self._timer then
         self._timer:destroy()
         self._timer = nil
      end
   end

   -- called when timer expires
   local destroy_fn
   destroy_fn = function()
      local stacks_to_remove = self._json.remove_stacks_on_expire
      if stacks_to_remove then
         self._sv.stacks = self._sv.stacks - (type(stacks_to_remove) == 'number' and stacks_to_remove or 1)
         if self._sv.stacks > 0 then
            self:_destroy_last_stack_modifiers()

            self:_set_expiration_timer(self._default_duration, destroy_fn)
            return
         end
      end

      -- Set a flat so we'll know the buff is being destroyed because its timer expired
      self._removed_due_to_expiration = true
      self._sv.stacks = 0
      -- once we've expired, add cooldown buff
      if self._cooldown_buff then
         radiant.entities.add_buff(self._sv._entity, self._cooldown_buff)
      end
      self:destroy()
   end

   self:_set_expiration_timer(duration, destroy_fn)
end

function AceBuff:_set_expiration_timer(duration, destroy_fn)
   if duration then
      self._timer = stonehearth.calendar:set_timer('Buff removal timer', duration, destroy_fn)
      self._sv.expire_time = self._timer:get_expire_time()
      self.__saved_variables:mark_changed()
   end
end

function AceBuff:on_repeat_add(options)
   local success = false
   local repeat_add_action = self._json.repeat_add_action
   if repeat_add_action == 'renew_duration' then
      self:_destroy_timer()
      self:_create_timer()
      success = true
   end

   if not success and repeat_add_action == 'extend_duration' then
      -- assert(self._timer, string.format("Attempting to extend duration when buff %s doesn't have a duration", self._sv.uri))
      if self._sv.expire_time then
         self._sv.expire_time = self._sv.expire_time + self._default_duration
      end
      self:_create_timer()
      success = true
   elseif not success and repeat_add_action == 'stack_and_refresh' then
      -- if we've hit max stacks, refresh the timer duration but don't add a new stack
      for i = 1, options.stacks do
         self:_add_stack()
      end
      self:_destroy_timer()
      self:_create_timer()
      success = true
   end

   if self._script_controller and self._script_controller.on_repeat_add then
      return self._script_controller:on_repeat_add(self._sv._entity, self, options)
   end

   return success
end

return AceBuff
