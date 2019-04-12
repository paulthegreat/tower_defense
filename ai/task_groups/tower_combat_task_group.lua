local TowerCombatTaskGroup = class()
TowerCombatTaskGroup.name = 'tower combat control'
TowerCombatTaskGroup.does = 'stonehearth:top'
TowerCombatTaskGroup.priority = {0.10, 0.65}
TowerCombatTaskGroup.sunk_cost_boost = 0

return stonehearth.ai:create_task_group(TowerCombatTaskGroup)
         :declare_multiple_tasks('tower_defense:tower_attack_ranged', 0.45)
