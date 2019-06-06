local ClientGameService = class()

function ClientGameService:initialize()
   _radiant.call('tower_defense:get_service', 'game'):done(function(response)
      self._game_service = response.result
      self._game_service_trace = self._game_service:trace_data('weather render')
         :on_changed(function()
               self._map_data = self._game_service:get_data().map_data
            end)
         :push_object_state()
   end)
end

function ClientGameService:destroy()
   self._game_service = nil
   if self._game_service_trace then
      self._game_service_trace:destroy()
      self._game_service_trace = nil
   end
   self._map_data = nil
end

function ClientGameService:get_tower_placeable_region()
   return self._map_data and self._map_data.tower_placeable_region
end

return ClientGameService
