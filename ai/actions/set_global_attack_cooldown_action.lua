local SetGlobalAttackCooldown = radiant.class()

SetGlobalAttackCooldown.name = 'set global attack cooldown'
SetGlobalAttackCooldown.does = 'stonehearth:combat:set_global_attack_cooldown'
SetGlobalAttackCooldown.args = {}
SetGlobalAttackCooldown.priority = 0

function SetGlobalAttackCooldown:__init()
   self._global_attack_recovery_cooldown = 0
end

function SetGlobalAttackCooldown:run(ai, entity, args)
   local state = stonehearth.combat:get_combat_state(entity)

   state:start_cooldown('global_attack_recovery', self._global_attack_recovery_cooldown)
end

return SetGlobalAttackCooldown
