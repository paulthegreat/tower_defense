--[[
   used for keeping track of towers and their targeting
]]

local Entity = _radiant.om.Entity
local Point3 = _radiant.csg.Point3
local Region3 = _radiant.csg.Region3

TowerService = class()

function TowerService:initialize()
   self._sv = self.__saved_variables:get_data()

   self._towers = {}
   self._detection_towers_by_coord = {}
end

function TowerService:set_ground_path(path)
   self._sv.ground_path = path
   self.__saved_variables:mark_changed()
end

function TowerService:set_air_path(path, height)
   self._sv.air_path = path
   self._sv.air_height = height
   self.__saved_variables:mark_changed()
end

function TowerService:register_tower(tower, location)
   local tower_comp = tower:get_component('tower_defense:tower')
   local targetable_region = self:_cache_tower_range(tower_comp, location)
   local detection_coords_in_range = {}
   if tower_comp:reveals_invis() and not targetable_region:empty() then
      detection_coords_in_range = self:_get_range_coords(targetable_region)
   end

   local id = tower:get_id()
   local tower_data = {
      id = id,
      tower = tower_comp,
      detection_coords_in_range = detection_coords_in_range
   }
   self:_cache_detection_coords(tower_data)
   self._towers[id] = tower_data

   return targetable_region
end

function TowerService:unregister_tower(tower_id)
   if radiant.util.is_a(tower_id, Entity) then
      tower_id = tower_id:get_id()
   end

   local tower_data = self._towers[tower_id]
   if tower_data then
      self._towers = nil
      for coord, _ in pairs(tower_data.detection_coords_in_range) do
         local towers = self._detection_towers_by_coord[coord]
         if towers then
            towers[tower_id] = nil
            if not next(towers) then
               self._detection_towers_by_coord[coord] = nil
            end
         end
      end
   end
end

function TowerService:_cache_tower_range(tower_comp, location)
   local targetable_region = tower_comp:get_targetable_region():translated(Point3(location.x, 0, location.z))
   
   local ground_intersection
   if tower_comp:attacks_ground() then
      ground_intersection = targetable_region:intersect_region(self._sv.ground_path)
      if not ground_intersection:empty() then
         ground_intersection:translate(Point3(0, tower_defense.game:get_ground_spawn_location().y, 0))
      end
      ground_intersection:optimize('targetable region')
   else
      ground_intersection = Region3()
   end

   local air_intersection
   if tower_comp:attacks_air() then
      air_intersection = targetable_region:intersect_region(self._sv.air_path)
      if not air_intersection:empty() then
         air_intersection:translate(Point3(0, tower_defense.game:get_air_spawn_location().y, 0))
      end
      air_intersection:optimize('targetable region')
   else
      air_intersection = Region3()
   end

   targetable_region = ground_intersection + air_intersection

   return targetable_region
end

function TowerService:_get_range_coords(region)
   local coords = {}
   for cube in region:each_cube() do
      local min = cube.min
      local max = cube.max
      for x = min.x, max.x - 1 do
         for z = min.z, max.z - 1 do
            coords[string.format('%s,%s', x, z)] = true
         end
      end
   end

   return coords
end

function TowerService:_cache_detection_coords(tower_data)
   for coord, _ in pairs(tower_data.detection_coords_in_range) do
      local towers = self._detection_towers_by_coord[coord]
      if not towers then
         towers = {}
         self._detection_towers_by_coord[coord] = towers
      end
      towers[tower_data.id] = true
   end
end

function TowerService:can_see_invis(location)
   -- check to see if any towers can see invis at that grid location
   if type(location) ~= 'string' then
      location = string.format('%s,%s', location.x, location.z)
   end
   local towers = self._detection_towers_by_coord[location]

   return towers and next(towers) ~= nil
end

return TowerService
