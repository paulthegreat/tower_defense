local MonsterTaskGroup = class()
MonsterTaskGroup.name = 'monster follow path'
MonsterTaskGroup.does = 'stonehearth:compelled_behavior'
MonsterTaskGroup.priority = 0.1

return stonehearth.ai:create_task_group(MonsterTaskGroup)
         :declare_permanent_task('tower_defense:monster_follow_path', {category = 'monster'}, 0.5)
         :declare_permanent_task('tower_defense:monster_special_ability', {category = 'monster'}, 1.0)