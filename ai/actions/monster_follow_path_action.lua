local Point3 = _radiant.csg.Point3
local MonsterFollowPath = radiant.class()

MonsterFollowPath.name = 'monster follow path'
MonsterFollowPath.does = 'tower_defense:monster_follow_path'
MonsterFollowPath.args = {}
MonsterFollowPath.priority = 0.25

function MonsterFollowPath:start_thinking(ai, entity, args)
   local location = tower_defense.game:get_path_end_point_for_monster(entity)
   if location then
      ai:set_think_output()
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(MonsterFollowPath)
         :execute('tower_defense:monster_get_path')
         :execute('stonehearth:follow_path', {
            path = ai.PREV.path
         })
         :execute('stonehearth:trigger_event', {
            source = ai.ENTITY,
            event_name = 'tower_defense:escape_event'
         })
