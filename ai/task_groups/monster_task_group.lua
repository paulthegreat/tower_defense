local MonsterTaskGroup = class()
MonsterTaskGroup.name = 'monster follow path'
MonsterTaskGroup.does = 'stonehearth:work'
MonsterTaskGroup.priority = 0.5

return stonehearth.ai:create_task_group(MonsterTaskGroup)
         :declare_permanent_task('tower_defense:monster_follow_path', {}, 1.0)