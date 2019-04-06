GameService = class()

function GameService:initialize()
   self._sv = self.__saved_variables:get_data()

   if not self._sv.players then
      self._sv.players = {}
   end

   if not self._sv.wave then
      self._sv.wave = 0
   end
end

function GameService:add_player(player_id, game_options)
   -- if the first wave has already started, can't add a new player
   if self._sv.wave > 0 then
      return
   end
   
   if not self._sv.game_options then
      self._sv.game_options = game_options
   end

   local player = self._sv.players[player_id]
   if player then
      -- player already exists, don't re-add them
      return
   end

   self._sv.players[player_id] = radiant.create_controller('tower_defense:game_player', player_id, game_options)

   if not self._sv.common_player then
      self._sv.common_player = radiant.create_controller('tower_defense:game_player', 'common_player', game_options)
   else
      self._sv.common_player:add_player(game_options)
   end

   self.__saved_variables:mark_changed()
end

return GameService
