local Point3 = _radiant.csg.Point3
local Region3 = _radiant.csg.Region3

local towers_lib = require 'tower_defense.lib.towers.towers_lib'

local ClientGameService = class()

function ClientGameService:initialize()
   _radiant.call('tower_defense:get_service', 'game'):done(function(response)
      self._game_service = response.result
      self._game_service_trace = self._game_service:trace_data('weather render')
         :on_changed(function()
               self._map_data = self._game_service:get_data().map_data
            end)
         :push_object_state()
   end)
end

function ClientGameService:destroy()
   self._game_service = nil
   if self._game_service_trace then
      self._game_service_trace:destroy()
      self._game_service_trace = nil
   end
   self._map_data = nil
end

function ClientGameService:get_tower_placeable_region()
   return self._map_data and self._map_data.tower_placeable_region
end

function ClientGameService:get_tower_placeable_terrain()
   return self._map_data and self._map_data.tower_placeable_terrain
end

function ClientGameService:get_path_intersection_region(tower_region, targets_ground, targets_air)
   if not self._map_data then
      return Region3()
   end

   local ground_intersection, air_intersection = towers_lib.get_path_intersection_regions(tower_region,
         self._map_data.ground_path_region, self._map_data.air_path_region, self._map_data.air_path.height, targets_ground, targets_air)

   return ground_intersection + air_intersection
end

return ClientGameService
