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
   self._sv._path_length = 999999
   self._sv._path_traveled = 0
end

function MonsterComponent:activate()
   if not self._sv.render_material then
      self._sv.render_material = self._sv.default_material
      self.__saved_variables:mark_changed()
   end

   local prev_location, prev_grid_location
   local get_xz_distance = function(p1, p2)
      return math.abs(p1.x - p2.x) + math.abs(p1.z - p2.z)
   end

   local mob = self._entity:get_component('mob')
   self._location_trace = radiant.entities.trace_location(self._entity, 'monster moved')
      :on_changed(function()
         local location = mob:get_world_location()
         local grid_location = mob:get_world_grid_location()

         if prev_location then
            local distance = get_xz_distance(location, prev_location)
            self._sv._path_length = self._sv._path_length - distance
            self._sv._path_traveled = self._sv._path_traveled + distance
            self.__saved_variables:mark_changed()
         end
         prev_location = location

         if prev_grid_location ~= grid_location then
            prev_grid_location = grid_location
            self:_update_seen()
            tower_defense.game:monster_moved_to(location)
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
   return self._sv._path_length
end

function MonsterComponent:get_path_traveled()
   return self._sv._path_traveled
end

function MonsterComponent:get_path()
   return self._sv.path
end

function MonsterComponent:set_path(path)
   self._sv.path = path
   self._sv._path_length = path:get_path_length()
   self.__saved_variables:mark_changed()
end

return MonsterComponent
