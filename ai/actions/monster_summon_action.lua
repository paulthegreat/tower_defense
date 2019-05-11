local Point3 = _radiant.csg.Point3
local Entity = _radiant.om.Entity

local MonsterSummon = radiant.class()

MonsterSummon.name = 'monster get path'
MonsterSummon.does = 'tower_defense:monster_summon'
MonsterSummon.args = {
   ability = 'table'
}
MonsterSummon.think_output = {}
MonsterSummon.priority = 0

local log = radiant.log.create_logger('monster_summon')

function MonsterSummon:stop(ai, entity, args)
   self:_destroy_suspend_timer()
   self:_stop_effect()
end

function MonsterSummon:run(ai, entity, args)
   local ability = args.ability
   local entity_id = entity:get_id()
   self._ai = ai

   if ability.effect then
      local run_effect
      run_effect = function()
         self._effect = radiant.effects.run_effect(entity, ability.effect)
         self._effect:set_cleanup_on_finish(false)
         self._effect:set_finished_cb(function()
            self:_stop_effect()
            run_effect()
         end)
      end
      run_effect()
   end

   if ability.initial_delay then
      self:_suspend(ability.initial_delay)
   end

   local pre_delay = ability.pre_delay or 0
   local post_delay = ability.post_delay or 0

   for _, spawn in ipairs(ability.monsters) do
      for i = 1, spawn.count or 1 do
         local delay = spawn.pre_delay or pre_delay
         if delay > 0 then
            self:_suspend(delay)
         end

         tower_defense.game:queue_spawn_monsters(spawn.each_spawn, entity_id)

         delay = spawn.post_delay or post_delay
         if delay > 0 then
            self:_suspend(delay)
         end
      end
   end

   if ability.final_delay then
      self:_suspend(ability.final_delay)
   end
end

function MonsterSummon:_suspend(duration)
   self._suspend_timer = stonehearth.combat:set_timer('summon action suspend', duration, function()
      self._ai:resume()
   end)
   self._ai:suspend()
end

function MonsterSummon:_destroy_suspend_timer()
   if self._suspend_timer then
      self._suspend_timer:destroy()
      self._suspend_timer = nil
   end
end

function MonsterSummon:_stop_effect()
   if self._effect then
      self._effect:stop()
      self._effect = nil
   end
end

return MonsterSummon
