local Region3 = _radiant.csg.Region3

local towers_lib = {}

function towers_lib.get_path_intersection_regions(tower_region, ground_path_region, air_path_region, air_path_height, targets_ground, targets_air)
   local targetable_region = tower_region:extruded('y', 8, air_path_height)
   
   local ground_intersection
   if targets_ground then
      ground_intersection = targetable_region:intersect_region(ground_path_region)
      ground_intersection:optimize('targetable region')
   else
      ground_intersection = Region3()
   end

   local air_intersection
   if targets_air then
      air_intersection = targetable_region:intersect_region(air_path_region)
      air_intersection:optimize('targetable region')
   else
      air_intersection = Region3()
   end

   return ground_intersection, air_intersection
end

return towers_lib
