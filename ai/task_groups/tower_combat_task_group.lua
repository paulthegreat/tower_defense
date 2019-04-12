local TowerCombatTaskGroup = class()
TowerCombatTaskGroup.name = 'tower combat control'
TowerCombatTaskGroup.does = 'stonehearth:combat'
TowerCombatTaskGroup.priority = {0.10, 0.65}
TowerCombatTaskGroup.sunk_cost_boost = 0

return stonehearth.ai:create_task_group(TowerCombatTaskGroup)
         :declare_multiple_tasks('stonehearth:combat:attack_after_cooldown_ignoring_threats', 0.45)
         :declare_task('stonehearth:unit_attack_entity', 0.45)
         :declare_multiple_tasks('stonehearth:combat:attack_after_cooldown', 0.33)
