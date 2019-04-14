local InvisibleBuff = class()

function InvisibleBuff:on_buff_added(entity, buff)
   local monster_comp = entity and entity:is_valid() and entity:get_component('tower_defense:monster')
   if monster_comp then
      monster_comp:set_invisible(true)
   end
end

function InvisibleBuff:on_buff_removed(entity, buff)
   local monster_comp = entity and entity:is_valid() and entity:get_component('tower_defense:monster')
   if monster_comp then
      monster_comp:set_invisible(false)
   end
end

return InvisibleBuff
