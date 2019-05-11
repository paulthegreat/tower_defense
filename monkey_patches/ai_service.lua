local AIService = require 'stonehearth.services.server.ai.ai_service'
local TDAIService = class()

TDAIService._old__call_reconsider_callbacks = AIService._call_reconsider_callbacks
function TDAIService:_call_reconsider_callbacks()
   self:_old__call_reconsider_callbacks()

   if self._entity_queue then
      for entity_id, entry in pairs(self._entity_queue) do
         self._entity_queue[entity_id] = nil
         local fn = radiant.entities[entry.fn_name]
         if fn then
            fn(entry.entity)
         end
      end
   end
end

function TDAIService:entity_has_queued_action(entity)
   return self._entity_queue and self._entity_queue[entity:get_id()] ~= nil
end

function TDAIService:queue_entity_action(entity, fn_name)
   self:_ensure_entity_queue()
   self._entity_queue[entity:get_id()] = {entity = entity, fn_name = fn_name}
end

function TDAIService:_ensure_entity_queue()
   if not self._entity_queue then
      self._entity_queue = {}
   end
end

return TDAIService
