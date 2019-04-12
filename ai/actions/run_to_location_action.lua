local Point3 = _radiant.csg.Point3
local RunToLocation = radiant.class()

RunToLocation.name = 'run to location'
RunToLocation.does = 'stonehearth:goto_location'
RunToLocation.args = {
   location = Point3,
   reason = 'string',
   stop_when_adjacent = {
      type = 'boolean',   -- whether to stop adjacent to destination
      default = false,
   },
   grid_location_changed_cb = {
      type = 'function',
      default = stonehearth.ai.NIL,
   },
}
RunToLocation.priority = 0

RunToLocation._origin_region = _radiant.sim.alloc_region3()
RunToLocation._origin_region:modify(function(cursor)
      cursor:add_point(Point3.zero)
   end)

function RunToLocation:start_thinking(ai, entity, args)
   local options = {
      debug_text = args.reason,
   }

   if not args.stop_when_adjacent then
      -- explicitly set the adjacent region to the place we want to end up
      options.destination_region = self._origin_region
      options.adjacent_region = self._origin_region
   end

   -- It's nice to just cache these temporaries.
   options.cached = true
   ai:set_think_output({
         options = options,
      })
end

local ai = stonehearth.ai
return ai:create_compound_action(RunToLocation)
         :execute('stonehearth:create_entity', {
            location = ai.ARGS.location,
            options = ai.PREV.options,
         })
         :execute('stonehearth:goto_entity', {
            entity = ai.PREV.entity,
            grid_location_changed_cb = ai.ARGS.grid_location_changed_cb,
         })
         :set_think_output({
            point_of_interest = ai.PREV.point_of_interest,
            path_length = ai.PREV.path_length,
         })
