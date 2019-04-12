local TowerAttack = radiant.class()

TowerAttack.name = 'tower attack'
TowerAttack.does = 'tower_defense:tower_attack'
TowerAttack.args = {}
TowerAttack.priority = 1

function TowerAttack:start_thinking(ai, entity, args)
   ai:set_think_output({})
end

local ai = stonehearth.ai
return ai:create_compound_action(TowerAttack)
         :execute('tower_defense:tower_find_target')
         :execute('tower_defense:tower_attack_ranged', {
            target = ai.PREV.target
         })
