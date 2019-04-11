--[[
   used for keeping track of towers and their targeting
]]

local Entity = _radiant.om.Entity
local Point3 = _radiant.csg.Point3

TowerService = class()

function TowerService:initialize()
   self._sv = self.__saved_variables:get_data()

   self._towers = {}
   self._towers_by_coord = {}
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
   local region, air_region = self:_cache_tower_range(tower_comp, location)
   local coords_in_range = {}
   if tower_comp:reveals_invis() and (not region:empty() or not air_region:empty()) then
      coords_in_range = self:_get_range_coords(region + air_region)
   end

   local tower_data = {
      tower = tower_comp,
      coords_in_range = coords_in_range
   }
   self:_cache_range_coords(tower_data)
   self._towers[tower:get_id()] = tower_data

   return region, air_region
end

function TowerService:unregister_tower(tower)
   if radiant.util.is_a(tower, Entity) then
      tower = tower:get_id()
   end

   local tower_data = self._towers[tower]
   if tower_data then
      self._towers = nil
      for coord, _ in pairs(tower_data.coords_in_range) do
         local towers = self._towers_by_coord[coord]
         if towers then
            towers[tower] = nil
            if not next(towers) then
               self._towers_by_coord[coord] = nil
            end
         end
      end
   end
end

function TowerService:_cache_tower_range(tower_comp, location)
   local targetable_region = tower_comp:get_targetable_region():translated(Point3(location.x, 0, location.z))
   local ground_intersection = targetable_region:intersect_region(self._sv.ground_path)
   local air_intersection = targetable_region:intersect_region(self._sv.air_path)
   return ground_intersection, air_intersection + Point3(0, self._sv.air_height, 0)
end

function TowerService:_get_range_coords(region)
   local coords = {}
   region:each_cube(function(cube)
      local bounds = cube:get_bounds()
      local min = bounds.min
      local max = bounds.max
      for x = min.x, max.x do
         for z = min.z, max.z do
            coords[string.format('%s,%s', x, z)] = true
         end
      end
   end)

   return coords
end

function TowerService:_cache_range_coords(tower_data)
   for coord, _ in pairs(tower_data.coords_in_range) do
      local towers = self._towers_by_coord[coord]
      if not towers then
         towers = {}
         self._towers_by_coord[coord] = towers
      end
      towers[coord] = true
   end
end

function TowerService:can_see_invis(location)
   -- check to see if any towers can see invis at that grid location
   local towers = self._towers_by_coord[location]

   return towers and next(towers) ~= nil
end

return TowerService
