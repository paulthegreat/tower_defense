local MAT_NORMAL = '/stonehearth/data/horde/materials/voxel.material.json'
local MAT_SOME_INVIS = '/tower_defense/data/horde/materials/somewhat_invisible.json'
local MAT_MOST_INVIS = '/tower_defense/data/horde/materials/mostly_invisible.json'

local MonsterComponent = class()

function MonsterComponent:initialize()
   self._json = radiant.entities.get_json(self)
   self._sv.default_material = self._json.render_material or MAT_NORMAL
   self._sv.path_length = 999999
   self._sv._seen_by = {}
end

function MonsterComponent:activate()
   if not self._sv.render_material then
      self._sv.render_material = self._sv.default_material
      self.__saved_variables:mark_changed()
   end

   self._location_trace = radiant.entities.trace_grid_location(self._entity, 'monster moved')
      :on_changed(function()
         local location = radiant.entities.get_world_grid_location(self._entity)
         if not self._location then
            self._location = location
         elseif location ~= self._location then
            self:set_path_length(self._sv.path_length - 1)
         end
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

function MonsterComponent:set_seen(by_entity_id, seen)
   seen = seen ~= false or nil
   if self._sv._seen_by[by_entity_id] ~= seen then
      self._sv._seen_by[by_entity_id] = seen
      self.__saved_variables:mark_changed()

      self:_update_render_material()
   end
end

function MonsterComponent:_update_render_material()
   local material
   
   if self._sv._invisible and next(self._sv._seen_by) then
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

function MonsterComponent:set_path_length(length)
   self._sv.path_length = length
   self.__saved_variables:mark_changed()
end

return MonsterComponent
