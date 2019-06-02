local rng = _radiant.math.get_default_rng()

local CombatService = require 'stonehearth.services.server.combat.combat_service'
local TDCombatService = class()

local DMG_TYPES = {
   PHYSICAL = 'physical',
   MAGICAL = 'magical',
   PURE = 'pure'
}

function TDCombatService:try_inflict_debuffs(inflicter, target, debuff_list)
   for i, debuff_data in ipairs(debuff_list) do
      for name, debuff in pairs(debuff_data) do
         local infliction_chance = debuff.chance or 1
         if rng:get_real(0, 1) < infliction_chance then
            target:add_component('stonehearth:buffs'):add_buff(debuff.uri, {inflicter = inflicter})
         end
      end
   end
end

function TDCombatService:set_interval(reason, duration, fn)
   local game_seconds = stonehearth.calendar:realtime_to_game_seconds(duration, true)
   return stonehearth.calendar:set_interval(reason, game_seconds, fn)
end

function TDCombatService:set_persistent_interval(reason, duration, fn)
   local game_seconds = stonehearth.calendar:realtime_to_game_seconds(duration, true)
   return stonehearth.calendar:set_persistent_interval(reason, game_seconds, fn)
end

function TDCombatService:set_persistent_timer(reason, duration, fn)
   local game_seconds = stonehearth.calendar:realtime_to_game_seconds(duration, true)
   return stonehearth.calendar:set_persistent_timer(reason, game_seconds, fn)
end

function TDCombatService:start_cooldown(entity, action_info)
   local combat_state = self:get_combat_state(entity)
   if not combat_state then
      return
   end
   if action_info.cooldown then
      local attributes_component = entity:get_component('stonehearth:attributes')
      local cooldown_modifier = attributes_component and attributes_component:get_attribute('multiplicative_cooldown_modifier', 1) or 1
      combat_state:start_cooldown(action_info.name, action_info.cooldown * cooldown_modifier)
   end
end

function TDCombatService:get_shortest_cooldown(entity, attack_types)
   local combat_state = entity:add_component('stonehearth:combat_state')
   if not combat_state then
      return 0
   end
   
   local shortest_cd
   local now = radiant.gamestate.now()

   for _, action_info in ipairs(attack_types) do
      local cd = combat_state:get_cooldown_end_time(action_info.name)
      cd = cd and (cd - now) or 0
      if not shortest_cd or cd < shortest_cd then
         shortest_cd = cd
         if cd <= 0 then
            break
         end
      end
   end

   return shortest_cd or 0
end

function TDCombatService:calculate_damage(attacker, target, attack_info, damage_multiplier, base_damage)
   if damage_multiplier == 0 then
      return 0
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
   if attack_damage_multiplier then
      total_damage = total_damage * attack_damage_multiplier
   end

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
