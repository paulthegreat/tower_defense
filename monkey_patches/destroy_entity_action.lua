local log = radiant.log.create_logger('death')

local DestroyEntity = class()

function DestroyEntity:start_thinking(ai, entity, args)
   if not entity and not entity:is_vaild() then
      ai:set_think_output()
      return
   end
   if not stonehearth.ai:entity_has_queued_action(entity)  then
      log:info('%s is dying', entity)
      ai:set_think_output()
   end
end

function DestroyEntity:run(ai, entity, args)
   log:detail('%s in DestroyEntity:run()', entity)

   if entity and entity:is_valid() then
      stonehearth.ai:queue_entity_action(entity, 'destroy_entity')
   end
end

return DestroyEntity
