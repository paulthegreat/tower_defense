--[[
   handles special rendering options like invisibility
]]

local MonsterRenderer = class()
local log = radiant.log.create_logger('monster.renderer')

function MonsterRenderer:initialize(render_entity, datastore)
   self._render_entity = render_entity
   self._entity = render_entity:get_entity()
   self._entity_node = render_entity:get_node()

   self._datastore = datastore

   self._datastore_trace = self._datastore:trace('drawing monster')
                                          :on_changed(function ()
                                                self:_update()
                                             end)
                                          :push_object_state()
end

function MonsterRenderer:destroy()
   if self._datastore_trace then
      self._datastore_trace:destroy()
      self._datastore_trace = nil
   end
end

function MonsterRenderer:_update()
   local data = self._datastore:get_data()

   if data.render_material then
      self._render_entity:set_material_override(data.render_material)
   end
end

return MonsterRenderer
