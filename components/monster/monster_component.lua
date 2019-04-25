local MAT_NORMAL = '/stonehearth/data/horde/materials/voxel.material.json'
local MAT_SOME_INVIS = '/tower_defense/data/horde/materials/somewhat_invisible.json'
local MAT_MOST_INVIS = '/tower_defense/data/horde/materials/mostly_invisible.json'

local MonsterComponent = class()
local log = radiant.log.create_logger('monster')

function MonsterComponent:initialize()
   self._json = radiant.entities.get_json(self)
   self._sv.default_material = self._json.render_material or MAT_NORMAL
   self._sv.invis_material = self._json.invis_render_material or MAT_MOST_INVIS
   self._sv.seen_invis_material = self._json.seen_invis_render_material or MAT_SOME_INVIS
   self._sv.path_length = 999999
   self._sv.path_traveled = 0
end

function MonsterComponent:activate()
   if not self._sv.render_material then
      self._sv.render_material = self._sv.default_material
      self.__saved_variables:mark_changed()
   end

   self._location_trace = radiant.entities.trace_grid_location(self._entity, 'monster moved')
      :on_changed(function()
         local location = radiant.entities.get_world_grid_location(self._entity)
         if self._location and location ~= self._location then
            -- TODO: reconsider how this is calculated if knockback or path deviations are involved
            -- for now just ignore y-only changes (flying unit temporarily/permanently gaining/losing grounded status)
            if self._location.x ~= location.x or self._location.z ~= location.z then
               self._sv.path_traveled=self._sv.path_traveled+1
               self:set_path_length(self._sv.path_length - 1)
            end
         end
         self._location = location
         self:_update_seen()
         tower_defense.game:monster_moved_to(location)
      end)
      :push_object_state()
end

function MonsterComponent:destroy()
   if self._location_trace then
      self._location_trace:destroy()
      self._location_trace = nil
   end
end

function MonsterComponent:set_invisible(invisibility)
   if invisibility ~= self._sv._invisible then
      self._sv._invisible = invisibility
      self.__saved_variables:mark_changed()

      self:_update_render_material()
   end
end

function MonsterComponent:_update_seen()
   self:set_seen(self._location and tower_defense.tower:can_see_invis(self._location) or false)
end

function MonsterComponent:is_visible()
   local visible = not self._sv._invisible or self._sv._seen
   if not visible then
      local attributes = self._entity:get_component('stonehearth:attributes')
      visible = attributes:get_attribute('reveal', 0) > 0
   end
   return visible
end

function MonsterComponent:set_seen(seen)
   if self._sv._seen ~= seen then
      self._sv._seen = seen
      self.__saved_variables:mark_changed()

      self:_update_render_material()
   end
end

function MonsterComponent:_update_render_material()
   local material
   
   if self._sv._invisible and self._sv._seen then
      material = MAT_SOME_INVIS
   elseif self._sv._invisible then
      material = MAT_MOST_INVIS
   else
      material = self._sv.default_material
   end

   if material ~= self._sv.render_material then
      self._sv.render_material = material
      self.__saved_variables:mark_changed()
   end
end

function MonsterComponent:get_path_length()
   return self._sv.path_length
end

function MonsterComponent:get_path_traveled()
   return self._sv.path_traveled
end

function MonsterComponent:set_path_length(length)
   self._sv.path_length = length
   self.__saved_variables:mark_changed()
end

return MonsterComponent
