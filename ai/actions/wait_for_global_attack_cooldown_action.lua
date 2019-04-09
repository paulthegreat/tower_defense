local log = radiant.log.create_logger('combat')

local WaitForGlobalAttackCooldown = radiant.class()

WaitForGlobalAttackCooldown.name = 'wait for global attack cooldown'
WaitForGlobalAttackCooldown.does = 'stonehearth:combat:wait_for_global_attack_cooldown'
WaitForGlobalAttackCooldown.args = {}
WaitForGlobalAttackCooldown.priority = 0

function WaitForGlobalAttackCooldown:start_thinking(ai, entity, args)
   ai:set_think_output()
end

return WaitForGlobalAttackCooldown
