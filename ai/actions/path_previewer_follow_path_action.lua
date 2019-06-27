local Point3 = _radiant.csg.Point3
local PathPreviewierFollowPath = radiant.class()

PathPreviewierFollowPath.name = 'monster follow path'
PathPreviewierFollowPath.does = 'tower_defense:path_previewer_follow_path'
PathPreviewierFollowPath.args = {}
PathPreviewierFollowPath.priority = 0.25

function PathPreviewierFollowPath:start_thinking(ai, entity, args)
   local location = tower_defense.game:get_path_end_point_for_monster(entity)
   if location then
      ai:set_think_output()
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(PathPreviewierFollowPath)
         :execute('tower_defense:monster_get_path')
         :execute('stonehearth:follow_path', {
            path = ai.PREV.path
         })
         :execute('stonehearth:trigger_event', {
            source = ai.ENTITY,
            event_name = 'tower_defense:finished_path'
         })
