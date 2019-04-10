--[[
   handles special range (and whether it's being affected by the selected entity)
]]

local TowerRenderer = class()
local log = radiant.log.create_logger('tower.renderer')

function TowerRenderer:initialize(render_entity, datastore)
   self._render_entity = render_entity
   self._entity = render_entity:get_entity()
   self._entity_node = render_entity:get_node()

   self._datastore = datastore

   self._datastore_trace = self._datastore:trace('drawing tower')
                                          :on_changed(function ()
                                                self:_update()
                                             end)
                                          :push_object_state()
end

function TowerRenderer:destroy()
   if self._datastore_trace then
      self._datastore_trace:destroy()
      self._datastore_trace = nil
   end
end

function TowerRenderer:_update()
   local data = self._datastore:get_data()

   
end

return TowerRenderer
