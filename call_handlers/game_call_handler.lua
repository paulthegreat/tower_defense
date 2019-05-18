local validator = radiant.validator
local catalog_lib = require 'stonehearth.lib.catalog.catalog_lib'

local GameCallHandler = class()

function GameCallHandler:get_service(session, response, name)
   validator.expect_argument_types({'string'}, name)
   if tower_defense and tower_defense[name] then
      -- we'd like to just send the store address rather than the actual
      -- store, but there's no way for the client to receive a store
      -- address and *not* automatically convert it back!
      return tower_defense[name].__saved_variables
   end
   response:reject('no such service')
end

function GameCallHandler:get_all_buffs(session, response)
   response:resolve({buffs = catalog_lib.get_all_buffs()})
end

return GameCallHandler
