local GameCreationCallHandler = class()

function GameCreationCallHandler:start_game_command(session, response)
   stonehearth.game_creation:start_game(session)
   response:resolve({})
end

return GameCreationCallHandler
