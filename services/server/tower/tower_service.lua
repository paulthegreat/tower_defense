--[[
   used for keeping track of towers and their targeting
]]

local Entity = _radiant.om.Entity
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3

local towers_lib = require 'tower_defense.lib.towers.towers_lib'

TowerService = class()

-- store towers in _sv for tracing by render filter service
-- but we don't care about actually reloading them since they'll get re-registered on load
function TowerService:initialize()
   self._sv = self.__saved_variables:get_data()

   self._sv.towers = {}
   self._detection_towers_by_coord = {}
end

function TowerService:get_registered_towers()
   return self._sv.towers
end

function TowerService:register_tower(tower, location)
   local tower_comp = tower:get_component('tower_defense:tower')
   local tower_region, targetable_region_ground, targetable_region_air = self:_cache_tower_range(tower_comp, location)
   local targetable_region = targetable_region_ground + targetable_region_air
   local detection_coords_in_range = {}
   if tower_comp:reveals_invis() and not targetable_region:empty() then
      detection_coords_in_range = self:_get_range_coords(targetable_region)
   end

   local id = tower:get_id()
   local tower_data = {
      id = id,
      tower = tower,
      detection_coords_in_range = detection_coords_in_range,
      tower_point = Region3(Cube3(location)),
      tower_region = tower_region,
      targetable_region = targetable_region,
      buffs = tower_comp:get_filter_buffs(),
      reveals_invis = tower_comp:reveals_invis()
   }
   self:_cache_detection_coords(tower_data)
   self._sv.towers[id] = tower_data
   self.__saved_variables:mark_changed()

   radiant.events.trigger(radiant, 'tower_defense:tower_registered', tower)

   return targetable_region_ground, targetable_region_air
end

function TowerService:unregister_tower(tower_id)
   if radiant.util.is_a(tower_id, Entity) then
      tower_id = tower_id:get_id()
   end

   local tower_data = self._sv.towers[tower_id]
   if tower_data then
      self._sv.towers[tower_id] = nil
      for coord, _ in pairs(tower_data.detection_coords_in_range) do
         local towers = self._detection_towers_by_coord[coord]
         if towers then
            towers[tower_id] = nil
            if not next(towers) then
               self._detection_towers_by_coord[coord] = nil
            end
         end
      end

      self.__saved_variables:mark_changed()

      radiant.events.trigger(radiant, 'tower_defense:tower_unregistered', tower_id)
   end
end

function TowerService:_cache_tower_range(tower_comp, location)
   local tower_region = tower_comp:get_targetable_region():translated(location)
   local ground_region, air_region = towers_lib.get_path_intersection_regions(tower_region, tower_defense.game:get_ground_path(),
         tower_defense.game:get_air_path(), tower_defense.game:get_air_path_height(), tower_comp:attacks_ground(), tower_comp:attacks_air())

   return tower_region, ground_region, air_region
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
