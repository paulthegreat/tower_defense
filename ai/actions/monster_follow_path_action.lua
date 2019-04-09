local Point3 = _radiant.csg.Point3
local MonsterFollowPath = radiant.class()

MonsterFollowPath.name = 'monster follow path'
MonsterFollowPath.does = 'tower_defense:monster_follow_path'
MonsterFollowPath.args = {}
MonsterFollowPath.think_output = {
   location = Point3,
}
MonsterFollowPath.priority = 0.25

function MonsterFollowPath:start_thinking(ai, entity, args)
   local location = tower_defense.game:get_path_end_point_for_monster(entity)
   if location then
      ai:set_think_output({ location = location })
   end
end

local finished_path = function(entity)
   tower_defense.game:monster_finished_path(entity)
end

local ai = stonehearth.ai
return ai:create_compound_action(MonsterFollowPath)
         :execute('stonehearth:goto_location', {
            location = ai.PREV.location
         })
         :execute('stonehearth:call_function', {
            fn = finished_path,
            args = {ai.ENTITY}
         })
         :execute('stonehearth:destroy_entity')
