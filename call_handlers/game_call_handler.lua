local validator = radiant.validator

local GameCallHandler = class()


function GameCallHandler:get_service(session, request, name)
   validator.expect_argument_types({'string'}, name)
   if tower_defense[name] then
      -- we'd like to just send the store address rather than the actual
      -- store, but there's no way for the client to receive a store
      -- address and *not* automatically convert it back!
      return tower_defense[name].__saved_variables
   end
   request:reject('no such service')
end

return GameCallHandler
