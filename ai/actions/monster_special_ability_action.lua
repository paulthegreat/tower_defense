local Point3 = _radiant.csg.Point3
local Entity = _radiant.om.Entity

local MonsterSpecialAbility = radiant.class()

MonsterSpecialAbility.name = 'monster get path'
MonsterSpecialAbility.does = 'tower_defense:monster_special_ability'
MonsterSpecialAbility.args = {}
MonsterSpecialAbility.think_output = {}
MonsterSpecialAbility.priority = 0

local log = radiant.log.create_logger('monster_special_ability')

function MonsterSpecialAbility:start_thinking(ai, entity, args)
   local abilities = radiant.entities.get_entity_data(entity, 'stonehearth:combat:ranged_attacks')
   if abilities then
      self._ai = ai
      self._entity = entity
      self._abilities = abilities
      local cd = math.max(0, stonehearth.combat:get_shortest_cooldown(entity, abilities))
      if cd == 0 then
         self:_try_set_think_output()
      else
         self._cooldown_timer = stonehearth.combat:set_timer('wait for ability cooldown', cd, function()
            self:_try_set_think_output()
         end)
      end
   end
end

function MonsterSpecialAbility:_try_set_think_output()
   if self:_is_silenced() then
      -- we're silenced, try again in a second
      self._cooldown_timer = stonehearth.combat:set_timer('wait for silence', 1000, function()
         self:_try_set_think_output()
      end)
   else
      self._ai:set_think_output()
   end
end

function MonsterSpecialAbility:stop_thinking(ai, entity, args)
   self:_destroy_cooldown_timer()
end

function MonsterSpecialAbility:stop(ai, entity, args)
   self:_destroy_cooldown_timer()
end

function MonsterSpecialAbility:run(ai, entity, args)
   local ability = stonehearth.combat:choose_attack_action(entity, self._abilities)
   if not ability or not ability.action then
      return
   end

   stonehearth.combat:start_cooldown(entity, ability)
   ai:execute(ability.action, {ability = ability})
end

function MonsterSpecialAbility:_destroy_cooldown_timer()
   if self._cooldown_timer then
      self._cooldown_timer:destroy()
      self._cooldown_timer = nil
   end
end

function MonsterSpecialAbility:_is_silenced()
   local attributes = self._entity:is_valid() and self._entity:get_component('stonehearth:attributes')
   return (attributes and attributes:get_attribute('silence', 0) or 0) > 0
end

return MonsterSpecialAbility
