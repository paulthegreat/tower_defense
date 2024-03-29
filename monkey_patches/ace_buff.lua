local modifiers_lib = require 'stonehearth.lib.modifiers.modifiers_lib'
local Buff = require 'stonehearth.components.buffs.buff'
local AceBuff = class()

local log = radiant.log.create_logger('buff')

-- "options" were already being passed in, but the parameter didn't exist and wasn't used
AceBuff._ace_old_create = Buff.create
function AceBuff:create(entity, uri, json, options)
   self:_ace_old_create(entity, uri, json)
   self._options = options
   self._sv._inflicters = {}
end

--AceBuff._ace_old_activate = Buff.activate
function AceBuff:activate()
   if self._should_be_destroyed then
      self:destroy()
      return
   end

   local json = rawget(self, '_json')
   self._cooldown_buff = json.cooldown_buff
   local parsed_duration = self._options and self._options.parsed_duration
   local duration = self._options and self._options.duration or json.duration
   self._default_duration = parsed_duration or (duration and self:_parse_duration(duration))
   self._extend_duration = json.extend_duration and self:_parse_duration(json.extend_duration)

   -- serialize to the client for display
   local sv = rawget(self, '_sv')
   rawset(sv, 'axis', json.axis)
   rawset(sv, 'icon', json.icon)
   rawset(sv, 'display_name', json.display_name)
   rawset(sv, 'description', json.description)
   rawset(sv, 'modifiers', json.modifiers)
   rawset(sv, 'invisible_to_player', json.invisible_to_player)
   rawset(sv, 'max_stacks', json.max_stacks or 1)
   rawset(sv, 'category', json.category)
   rawset(sv, 'ordinal', json.ordinal or 999)
   rawset(sv, 'default_duration', self._default_duration)
   self.__saved_variables:mark_changed()
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
   local not_restore = not self._is_restore
   if self._json.restore_effect or not_restore then
      self:_create_effect(self._json.effect)
   end

   self:_update_inflicters(self._options and self._options.inflicter)

   self:_create_timer()
   self:_restore_modifiers()
   if not_restore then
      self:_create_injected_ai()
      self:_add_properties() -- add new properties when buff is initially created
   else
      self:_update_properties_from_json() -- update properties if they've changed (only matters for persistent buffs)
   end

   self:_set_posture(self._json.set_posture)
   self:_create_script_controller()
   self:_add_injected_commands()

   -- now do any post-create options
   if self._options then
      local stacks = self._options.stacks and self._options.stacks or 1
      if stacks > 1 then
         self._options.stacks = stacks - 1
         self:on_repeat_add(self._options)
      end
   end
end

function AceBuff:_update_inflicters(inflicter, stacks)
   if inflicter then
      local repeat_add_action = self._json.repeat_add_action
      -- if we're simply refreshing duration, replace existing inflicters with this one
      if repeat_add_action == 'renew_duration' then
         self._sv._inflicters = {[inflicter] = 1}

      elseif repeat_add_action == 'extend_duration' then
         -- if we're extending duration, set the expire time after which this inflicter is no longer inflicting
         local now = stonehearth.calendar:get_elapsed_time()
         table.insert(self._sv._inflicters, {
            inflicter = inflicter,
            start_time = self._sv.expire_time or now,
            end_time = (self._sv.expire_time or now) + (self._extend_duration or self._default_duration) * (stacks or 1)
         })

      elseif repeat_add_action == 'stack_and_refresh' then
         -- if we're stacking and refreshing, increase number of stacks
         self._sv._inflicters[inflicter] = (self._sv._inflicters[inflicter] or 0) + (stacks or 1)
      end

      self.__saved_variables:mark_changed()
   end
end

function AceBuff:get_current_inflicters()
   -- interpret the inflicters based on repeat add action, returning a table of currently relevant inflicters and weights
   local inflicters = {}

   local repeat_add_action = self._json.repeat_add_action
   if repeat_add_action == 'renew_duration' or repeat_add_action == 'stack_and_refresh' then
      return self._sv._inflicters

   elseif repeat_add_action == 'extend_duration' then
      -- if we're extending duration, remove inflicters until the current time is within an inflicter's range and return that one
      local now = stonehearth.calendar:get_elapsed_time()
      for i, entry in ipairs(self._sv._inflicters) do
         if entry.end_time < now then
            table.remove(self._sv._inflicters, i)
         elseif entry.start_time <= now then
            return {[entry.inflicter] = 1}
         end
      end
   end
end

function AceBuff:get_inflicters()
   return self._sv._inflicters
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

function AceBuff:get_axis()
   return self._sv.axis
end

function AceBuff:get_stacks()
   return self._sv.stacks
end

function AceBuff:get_max_stacks()
   return self._sv.max_stacks
end

function AceBuff:get_expire_time()
   return self._sv.expire_time
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

   if self._json.effect and self._json.reapply_effect then
      self:_destroy_effect()
      self:_create_effect(self._json.effect)
   end

   -- if passed a duration override, make sure we set that
   local parsed_duration = options and options.parsed_duration
   local duration = options and options.duration
   if parsed_duration then
      self._default_duration = parsed_duration
   elseif duration then
      self._default_duration = self:_parse_duration(duration)
   end

   self:_update_inflicters(options.inflicter, options.stacks)

   if repeat_add_action == 'renew_duration' then
      self:_destroy_timer()
      self:_create_timer()
      success = true
   end

   if not success and repeat_add_action == 'extend_duration' then
      -- assert(self._timer, string.format("Attempting to extend duration when buff %s doesn't have a duration", self._sv.uri))
      if self._sv.expire_time then
         self._sv.expire_time = self._sv.expire_time + (self._extend_duration or self._default_duration) * (options.stacks or 1)
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

function AceBuff:_parse_duration(duration)
   if type(duration) == 'number' then
      return stonehearth.calendar:realtime_to_game_seconds(duration, true)
   else
      return stonehearth.calendar:parse_duration(duration)
   end
end

return AceBuff
