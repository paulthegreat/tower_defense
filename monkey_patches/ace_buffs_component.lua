local BuffsComponent = radiant.mods.require('stonehearth.components.buffs.buffs_component')
local AceBuffsComponent = class()

local log = radiant.log.create_logger('buff')

AceBuffsComponent._ace_old_create = BuffsComponent.create
function AceBuffsComponent:create()
   self:_ace_old_create()
   self._is_create = true
end

AceBuffsComponent._ace_old_activate = BuffsComponent.activate
function AceBuffsComponent:activate()
   if not self._sv.disallowed_buffs then
      self._sv.disallowed_buffs = {}
   end
   if not self._sv.disallowed_categories then
      self._sv.disallowed_categories = {}
   end
   if not self._sv.buffs_by_category then
      self._sv.buffs_by_category = {}
   end
   if not self._sv.managed_properties then
      self._sv.managed_properties = {}
   end
   if not self._sv.diminishing_returns then
      self._sv.diminishing_returns = {}
   end

   if self._ace_old_activate then
      self:_ace_old_activate()
   end

   if self._is_create then
      local json = radiant.entities.get_json(self)
      if json and json.buffs then
         for buff, options in pairs(json.buffs) do
            if options then
               self:add_buff(buff, type(options) == 'table' and options)
            end
         end
      end
   end
end

function AceBuffsComponent:get_managed_property(name)
   local property = self._sv.managed_properties[name]
   return property and ((property.num_zeroes and property.num_zeroes > 0 and 0) or property.value)
end

function AceBuffsComponent:get_buffs_by_category(category)
   local category_buffs = self._sv.buffs_by_category[category]
   if category_buffs then
      local buffs = {}
      for buff_id, _ in pairs(category_buffs) do
         buffs[buff_id] = self._sv.buffs[buff_id]
      end
      return buffs
   end
end

function AceBuffsComponent:has_category_buffs(category)
   return self._sv.buffs_by_category[category] ~= nil
end

function AceBuffsComponent:get_debuffs()
   local debuffs = {}
   for uri, buff in pairs(self._sv.buffs) do
      if buff:get_axis() == 'debuff' then
         table.insert(debuffs, uri)
      end
   end
   return debuffs
end

function AceBuffsComponent:get_buff(uri)
   return self._sv.buffs[uri]
end

function AceBuffsComponent:get_buff_stacks(uri)
   local buff = self._sv.buffs[uri]
   return buff and buff:get_stacks()
end

function AceBuffsComponent:get_buff_duration(uri)
   local buff = self._sv.buffs[uri]
   return buff and buff:get_duration()
end

function AceBuffsComponent:is_buff_diminishing_disabled(uri)
   local json = radiant.resources.load_json(uri, true)
   local is_disabled = self:_is_buff_diminishing_disabled(json, now)
   return is_disabled   -- only return the true/false value of whether it's disabled, not the additional values
end

function AceBuffsComponent:_is_buff_diminishing_disabled(json, now)
   local reset_time
   local duration
   if json.diminishing_returns and json.duration then
      -- if this buff has diminishing returns, check to see if it can no longer be applied
      now = now or stonehearth.calendar:get_elapsed_time()

      local current_dr
      if json.diminishing_returns.by_category and json.category then
         current_dr = self._sv.diminishing_returns[json.category]
      else
         current_dr = self._sv.diminishing_returns[uri]
      end

      reset_time = json.diminishing_returns.reset_time and self:_parse_duration(json.diminishing_returns.reset_time)
      if reset_time and current_dr and current_dr.reset_time then
         if reset_time + current_dr.reset_time < now then
            current_dr = nil  -- reset time has passed, so ignore stored dr data (it will get overwritten if this buff is applied)
         end
      end

      if current_dr and json.diminishing_returns.times_until_disabled and current_dr.times >= json.diminishing_returns.times_until_disabled then
         return true -- this buff wouldn't be applied due to diminishing returns
      end

      duration = self:_parse_duration(json.duration)
      log:debug('initial duration for %s %s: %s', self._entity, tostring(json.category), duration)

      if current_dr then
         if json.diminishing_returns.duration_multiplier then
            for i = 1, current_dr.times do
               duration = duration * json.diminishing_returns.duration_multiplier
            end
         elseif json.diminishing_returns.duration_reduction then
            local duration_reduction = self:_parse_duration(json.diminishing_returns.duration_reduction)
            duration = duration - duration_reduction * current_dr.times
         end
      end
      log:debug('diminished duration: %s', duration)

      local expire_time = now + duration
      -- check existing buffs to see if one will already be lasting longer
      local buffs_to_check = {}
      if json.diminishing_returns.by_category and json.category then
         for buff_uri, _ in pairs(self._sv.buffs_by_category[json.category] or {}) do
            table.insert(buffs_to_check, self._sv.buffs[buff_uri])
         end
      else
         table.insert(buffs_to_check, self._sv.buffs[uri])
      end
      for _, buff in ipairs(buffs_to_check) do
         local buff_expiration = buff:get_expire_time()
         if buff_expiration and buff_expiration >= expire_time then
            return true -- this buff would be expiring before an existing buff with the same diminishing returns
         end
      end
   end

   return false, reset_time, duration
end

function AceBuffsComponent:add_buff(uri, options)
   assert(not string.find(uri, '%.'), 'tried to add a buff with a uri containing "." Use an alias instead')

   if self:_buff_is_disallowed(uri) then
      return -- don't add this buff if it's disallowed by other active buffs
   end

   local json = radiant.resources.load_json(uri, true)

   if json.category and self:_category_is_disallowed(json.category) then
      return -- don't add this buff if its whole category is disallowed by other active buffs
   end

   if self:_buff_on_cooldown(json) then
      return -- don't add this buff if it's cooldown buff is still active
   end

   options = options or {}
   options.stacks = options.stacks or 1

   local now = stonehearth.calendar:get_elapsed_time()
   -- if this buff has diminishing returns, check to see if it should currently be applied
   local is_dr_disabled, reset_time, duration = self:_is_buff_diminishing_disabled(json, now)
   if is_dr_disabled then
      return -- don't add this buff if it's hit disabled status
   end

   if duration then
      options.parsed_duration = duration
   end

   if json.category then
      local buffs_by_category = self._sv.buffs_by_category[json.category]
      if not buffs_by_category then
         buffs_by_category = {}
         self._sv.buffs_by_category[json.category] = buffs_by_category
      end

      if json.unique_in_category and json.rank then
         -- if this buff should be unique in this category, check if there are any buffs of a higher or equal rank already in it
         -- if there are, cancel out; otherwise, remove all lower rank buffs and continue
         for buff_id, _ in pairs(buffs_by_category) do
            local rank = self._sv.buffs[buff_id]:get_json().rank
            if rank and rank >= json.rank then
               return
            end
         end

         for buff_id, _ in pairs(buffs_by_category) do
            self:remove_buff(buff_id, true)
         end
      end

      buffs_by_category[uri] = true
   end

   if json.diminishing_returns then
      local current_dr
      if json.category then
         current_dr = self._sv.diminishing_returns[json.category]
         if not current_dr then
            current_dr = {
               times = 1
            }
            self._sv.diminishing_returns[json.category] = current_dr
         else
            current_dr.times = current_dr.times + 1
         end
         current_dr.reset_time = reset_time and (reset_time + now)
      end

      current_dr = self._sv.diminishing_returns[uri]
      if not current_dr then
         current_dr = {
            times = 1
         }
         self._sv.diminishing_returns[uri] = current_dr
      else
         current_dr.times = current_dr.times + 1
      end
      current_dr.reset_time = reset_time and (reset_time + now)
   end

   local buff
   local cur_count = self._sv.ref_counts[uri] or 0
   local new_count = options.stacks
   local ref_count = cur_count + new_count
   self._sv.ref_counts[uri] = ref_count

   if cur_count == 0 then
      buff = radiant.create_controller('stonehearth:buff', self._entity, uri, json, options)
      self._sv.buffs[uri] = buff

      -- if this buff disallows others, track that and remove any that are currently active
      if json.disallowed_buffs then
         for _, dis_buff in ipairs(json.disallowed_buffs) do
            local cur_disallowed = self._sv.disallowed_buffs[dis_buff]
            if not cur_disallowed then
               cur_disallowed = {}
               self._sv.disallowed_buffs[dis_buff] = cur_disallowed
            end
            cur_disallowed[uri] = true
            if self:has_buff(dis_buff) then
               self:remove_buff(dis_buff, true)
            end
         end
      end

      -- if this buff disallows any buff categories, track that and remove any buffs in those categories
      if json.disallowed_categories then
         for _, dis_category in ipairs(json.disallowed_categories) do
            local cur_disallowed = self._sv.disallowed_categories[dis_category]
            if not cur_disallowed then
               cur_disallowed = {}
               self._sv.disallowed_categories[dis_category] = cur_disallowed
            end
            cur_disallowed[uri] = true

            local category_buffs = self:get_buffs_by_category(dis_category)
            if category_buffs then
               for buff_id, _ in pairs(category_buffs) do
                  self:remove_buff(buff_id, true)
               end
            end
         end
      end

      -- if this buff should apply any managed properties that just get dealt with through the buffs component
      -- this allows buffs to interact with one another
      if json.managed_properties then
         for name, details in pairs(json.managed_properties) do
            self:_apply_managed_property(name, details)
         end
      end

      self.__saved_variables:mark_changed()

      radiant.events.trigger_async(self._entity, 'stonehearth:buff_added', {
            entity = self._entity,
            uri = uri,
            buff = buff,
         })
   else
      buff = self._sv.buffs[uri]
      assert(buff)
      if buff:on_repeat_add(options) then
         self.__saved_variables:mark_changed()
      end
   end

   return buff
end

function AceBuffsComponent:remove_buff(uri, remove_all_stacks)
   local cur_count = self._sv.ref_counts[uri]
   if not cur_count or cur_count == 0 then
      return
   end

   local ref_count = cur_count - 1

   if ref_count == 0 or remove_all_stacks then
      self._sv.ref_counts[uri] = 0 -- Just in case we're doing a remove_all_stacks
      local buff = self._sv.buffs[uri]
      if buff then
         local json = radiant.resources.load_json(uri, true, false)
         if json then
            if json.disallowed_buffs then
               for _, dis_buff in ipairs(json.disallowed_buffs) do
                  local cur_disallowed = self._sv.disallowed_buffs[dis_buff]
                  if cur_disallowed then
                     cur_disallowed[uri] = nil
                     if not next(cur_disallowed) then
                        self._sv.disallowed_buffs[dis_buff] = nil
                     end
                  end
               end
            end

            if json.disallowed_categories then
               for _, dis_category in ipairs(json.disallowed_categories) do
                  local cur_disallowed = self._sv.disallowed_categories[dis_category]
                  if cur_disallowed then
                     cur_disallowed[uri] = nil
                     if not next(cur_disallowed) then
                        self._sv.disallowed_categories[dis_category] = nil
                     end
                  end
               end
            end

            if json.category then
               local buffs_by_category = self._sv.buffs_by_category[json.category]
               if buffs_by_category then
                  buffs_by_category[uri] = nil
                  if not next(buffs_by_category) then
                     self._sv.buffs_by_category[json.category] = nil
                  end
               end
            end

            if json.managed_properties then
               for name, details in pairs(json.managed_properties) do
                  self:_remove_managed_property(name, details)
               end
            end
         end

         self._sv.buffs[uri] = nil
         buff:destroy()
         self.__saved_variables:mark_changed()

         radiant.events.trigger_async(self._entity, 'stonehearth:buff_removed', uri)
      end
   else
      -- otherwise we just want to remove a single stack
      local buff = self._sv.buffs[uri]
      if buff then
         buff:remove_stack()
      end
   end
end

function AceBuffsComponent:_apply_managed_property(name, details)
   local property = self._sv.managed_properties[name]
   if not property then
      property = {type = details.type}
      self._sv.managed_properties[name] = property
   end

   if details.type == 'number' then
      if property.value then
         property.value = property.value + details.value
      else
         property.value = details.value
      end
   elseif details.type == 'multiplier' then
      if details.value == 0 then
         property.num_zeroes = (property.num_zeroes or 0) + 1
      else
         if property.value then
            property.value = property.value * details.value
         else
            property.value = details.value
         end
      end
   elseif details.type == 'array' then
      -- not yet implemented
   elseif details.type == 'chance_table' then
      if not property.value then
         property.value = {}
      end
      for _, chance_entry in ipairs(details.value) do
         local found
         for index, sv_chance_entry in ipairs(property.value) do
            if sv_chance_entry[1] == chance_entry[1] then
               sv_chance_entry[2] = sv_chance_entry[2] + chance_entry[2]
               found = true
               break
            end
         end
         if not found then
            table.insert(property.value, {chance_entry[1], chance_entry[2]})
         end
      end
   end
end

function AceBuffsComponent:_remove_managed_property(name, details)
   local property = self._sv.managed_properties[name]
   if not property then
      return
   end
   if property.value == nil then
      self._sv.managed_properties[name] = nil
      return
   end

   if details.type == 'number' then
      -- a number can intentionally be zero, so we can't just remove this property when the buffs are all gone
      -- unless we're also tracking buff references... TODO maybe?
      property.value = property.value - details.value
   elseif details.type == 'multiplier' then
      if details.value == 0 then
         property.num_zeroes = property.num_zeroes - 1
      else
         property.value = property.value / details.value
      end
   elseif details.type == 'array' then
      -- not yet implemented
   elseif details.type == 'chance_table' then
      local indexes_to_remove = {}
      for _, chance_entry in ipairs(details.value) do
         for index, sv_chance_entry in ipairs(property.value) do
            if sv_chance_entry[1] == chance_entry[1] then
               sv_chance_entry[2] = sv_chance_entry[2] - chance_entry[2]
               if sv_chance_entry[2] == 0 then
                  table.insert(indexes_to_remove, index)
               end
               break
            end
         end
      end

      table.sort(indexes_to_remove)

      for i = #indexes_to_remove, 1, -1 do
         table.remove(property.value, indexes_to_remove[i])
      end

      if not next(property.value) then
         self._sv.managed_properties[name] = nil
      end
   end
end

function AceBuffsComponent:_buff_is_disallowed(uri)
   return self._sv.disallowed_buffs[uri] ~= nil
end

function AceBuffsComponent:_category_is_disallowed(category)
   return self._sv.disallowed_categories[category] ~= nil
end

function AceBuffsComponent:_parse_duration(duration)
   if type(duration) == 'number' then
      return stonehearth.calendar:realtime_to_game_seconds(duration, true)
   else
      return stonehearth.calendar:parse_duration(duration)
   end
end

return AceBuffsComponent
