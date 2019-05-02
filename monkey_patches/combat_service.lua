local rng = _radiant.math.get_default_rng()

local CombatService = require 'stonehearth.services.server.combat.combat_service'
local TDCombatService = class()

local DMG_TYPES = {
   PHYSICAL = 'physical',
   MAGICAL = 'magical',
   PURE = 'pure'
}

function TDCombatService:start_cooldown(entity, action_info)
   local combat_state = self:get_combat_state(entity)
   if not combat_state then
      return
   end
   if action_info.cooldown then
      local attributes_component = entity:get_component('stonehearth:attributes')
      local cooldown_modifier = attributes_component and attributes_component:get_attribute('multiplicative_cooldown_modifier') or 1
      combat_state:start_cooldown(action_info.name, action_info.cooldown * cooldown_modifier)
   end
end

function TDCombatService:calculate_damage(attacker, target, attack_info, damage_multiplier, secondary_target)
   if damage_multiplier == 0 then
      return 0
   end
   
   local base_damage
   if secondary_target and attack_info.aoe then
      base_damage = attack_info.aoe.secondary_damage or attack_info.base_damage
   else
      base_damage = attack_info.base_damage
   end

   if type(base_damage) == 'table' then
      base_damage = rng:get_real(base_damage[1], base_damage[2])
   end

   if not base_damage or base_damage == 0 then
      return 0
   end

   local damage = self:get_adjusted_damage_value(attacker, target, base_damage, attack_info.damage_type,
                                                damage_multiplier, attack_info.target_armor_multiplier)
   
   if attack_info.minimum_damage and damage <= attack_info.minimum_damage then
      damage = attack_info.minimum_damage
   elseif damage < 1 then
      -- if attack will do less than 1 damage, then randomly it will do either 1 or 0
      damage = rng:get_int(0, 1)
   end

   return damage
end

function TDCombatService:get_adjusted_damage_value(attacker, target, damage, damage_type, attack_damage_multiplier, attack_armor_multiplier)
   damage_type = damage_type or DMG_TYPES.PHYSICAL
   local total_damage = damage
   local attributes_component = attacker and attacker:get_component('stonehearth:attributes')
   
   local additive_dmg_modifier = attributes_component and attributes_component:get_attribute('additive_dmg_modifier')
   local multiplicative_dmg_modifier = attributes_component and attributes_component:get_attribute('multiplicative_dmg_modifier')

   if multiplicative_dmg_modifier then
      local dmg_to_add = damage * multiplicative_dmg_modifier
      total_damage = dmg_to_add + total_damage
   end
   if additive_dmg_modifier then
      total_damage = total_damage + additive_dmg_modifier
   end

   --Get damage from weapons
   if attack_damage_multiplier then
      total_damage = total_damage * attack_damage_multiplier
   end

   if damage_type == DMG_TYPES.PHYSICAL then
      local target_attributes_component = target and target:get_component('stonehearth:attributes')
      local multiplicative_physical_dmg_taken_modifier = target_attributes_component and target_attributes_component:get_attribute('multiplicative_physical_dmg_taken', 1) or 1

      total_damage = total_damage * multiplicative_physical_dmg_taken_modifier
   elseif damage_type == DMG_TYPES.MAGICAL then
      local target_attributes_component = target and target:get_component('stonehearth:attributes')
      local multiplicative_magical_dmg_taken_modifier = target_attributes_component and target_attributes_component:get_attribute('multiplicative_magical_dmg_taken', 1) or 1

      total_damage = total_damage * multiplicative_magical_dmg_taken_modifier
   elseif damage_type == DMG_TYPES.PURE then
      -- pure does full damage!
   end

   total_damage = radiant.math.round(total_damage)

   return total_damage
end

return TDCombatService
