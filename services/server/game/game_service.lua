GameService = class()

local COMMON_PLAYER = 'common_player'

function GameService:initialize()
   self._sv = self.__saved_variables:get_data()

   if not self._sv.players then
      self._sv.players = {}
   end

   if not self._sv.wave then
      self._sv.wave = 0
   end

   if self._sv.countdown_timer then
      self._sv.countdown_timer:bind(function()
         self:_start_round()
      end)
   end

   self._waves = radiant.resources.load_json('tower_defense:data:waves')
end

function GameService:start()
   self:_end_of_round()
end

function GameService:destroy()
   self:_destroy_countdown_timer()
end

function GameService:_end_of_round()
   local countdown = radiant.util.get_config('round_countdown', '10m')
   if radiant.util.get_config('pause_at_end_of_round', true) then
      stonehearth.game_speed:set_game_speed(0, false)
   end

   self:_destroy_countdown_timer()
   self:_create_countdown_timer(countdown)
end

function GameService:_destroy_countdown_timer()
   if self._sv.countdown_timer then
      self._sv.countdown_timer:destroy()
      self._sv.countdown_timer = nil
   end
end

function GameService:_create_countdown_timer(countdown)
   self._sv.countdown_timer = stonehearth.calendar:set_persistent_timer('next wave countdown', countdown, function()
      self:_start_round()
   end)
end

function GameService:_start_round()
   self:_destroy_countdown_timer()

   self._sv.wave = self._sv.wave + 1
   self.__saved_variables:mark_changed()
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
      self._sv.common_player = radiant.create_controller('tower_defense:game_player', COMMON_PLAYER, game_options)
   else
      self._sv.common_player:add_player(game_options)
   end

   self.__saved_variables:mark_changed()
end

function GameService:get_player(player_id)
   return self._sv.players[player_id]
end

function GameService:get_common_player()
   return self._sv.common_player
end

function GameService:get_common_gold()
   return self._sv.common_player and self._sv.common_player:get_gold() or 0
end

-- gold can only be given to the common player
function GameService:give_gold(player_id, amount)
   if player_id ~= COMMON_PLAYER then
      local player = self._sv.players[player_id]
      local common_player = self._sv.common_player
      if player and common_player then
         amount = player:take_gold(amount)
         common_player:add_gold(amount)
      end
   end
end

-- this is used to add an amount of gold to all players, like when a monster is killed
function GameService:give_all_players_gold(amount)
   for _, player in pairs(self._sv.players) do
      player:add_gold(amount)
   end
   self._sv.common_player:add_gold(amount)
end

return GameService
