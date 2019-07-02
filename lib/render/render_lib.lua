local Point3 = _radiant.csg.Point3
local Color4 = _radiant.csg.Color4

local NO_COLOR = Color4(0,0,0,0)

local csg_lib = require 'stonehearth.lib.csg.csg_lib'

local render_lib = {}

-- https://en.wikipedia.org/wiki/HSL_and_HSV#HSV_to_RGB
function render_lib.hsv_table_to_rgb(hsv)
   local h = hsv.hue or hsv.h or hsv.x
   local s = hsv.saturation or hsv.s or hsv.y
   local v = hsv.value or hsv.v or hsv.z
   return render_lib.hsv_to_rgb(h, s, v)
end

function render_lib.hsv_to_rgb(h, s, v)
   local chroma = v * s
   local m = v - chroma
   local h60 = (h % 360) / 60
   local x = chroma * (1 - math.abs(h60 % 2 - 1)) + m
   chroma = chroma + m

   local result
   if h60 <= 1 then
      result = Point3(chroma, x, m)
   elseif h60 <= 2 then
      result = Point3(x, chroma, m)
   elseif h60 <= 3 then
      result = Point3(m, chroma, x)
   elseif h60 <= 4 then
      result = Point3(m, x, chroma)
   elseif h60 <= 5 then
      result = Point3(x, m, chroma)
   else
      result = Point3(chroma, m, x)
   end

   return Point3(result.x * 255, result.y * 255, result.z * 255)
end

function render_lib.to_color4(pt, a)
   -- if it already has a .a, we assume it's a Color4 and we don't want its alpha, we want to use our own or a default
   -- can always call it like (pt, pt.a) if we want it specified that way
   return Color4(pt[1] or pt.r or pt.x, pt[2] or pt.g or pt.y, pt[3] or pt.b or pt.z, pt[4] or a or 255)
end

-- returns a cube from p1 to the point just shy of p2
function render_lib.shy_cube(p1, p2)
   return csg_lib.create_cube(p1, render_lib.shy_point(p1, p2))
end

-- returns the point just shy of p2 from p1
function render_lib.shy_point(p1, p2)
   local x_dir = (p2.x > p1.x and 1) or (p2.x < p1.x and -1) or 0
   local y_dir = (p2.y > p1.y and 1) or (p2.y < p1.y and -1) or 0
   local z_dir = (p2.z > p1.z and 1) or (p2.z < p1.z and -1) or 0
   return p2 - Point3(x_dir, y_dir, z_dir)
end

function render_lib.draw_tower_region(render_node, region, y_adjustment, color, material)
   local n = _radiant.client.create_region_outline_node(render_node,
         region:inflated(Point3(0, -0.495, 0)):translated(Point3(0, y_adjustment - 0.495, 0)),
         NO_COLOR, color, material, 1)
   --n:set_position(Point3(0, cube.min.y + y_adjustment, 0))
   n:set_casts_shadows(false)
   n:set_can_query(false)
   return n
end

return render_lib
