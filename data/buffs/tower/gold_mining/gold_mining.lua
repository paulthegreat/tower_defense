local GoldMiningBuffScript = class()

function GoldMiningBuffScript:on_buff_added(entity, buff)
   local json = buff:get_json()
   self._tuning = json.script_info

   self:_mine_gold(entity, buff)
end

function GoldMiningBuffScript:on_repeat_add(entity, buff)
   self:_mine_gold(entity, buff)
end

function GoldMiningBuffScript:_mine_gold(entity, buff)
   local stacks = buff:get_stacks()
   local gold = math.max((self._tuning.starting_gold or 1) - stacks * (self._tuning.reduction_per_stack or 1))

   buff:set_stacks_vis(gold)
   tower_defense.game:add_player_gold(entity:get_player_id(), gold)
end

return GoldMiningBuffScript
