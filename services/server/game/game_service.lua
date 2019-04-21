local Point3 = _radiant.csg.Point3

GameService = class()

local COMMON_PLAYER = 'common_player'
local constants = stonehearth.constants

function GameService:initialize()
   self._sv = self.__saved_variables:get_data()

   if not self._sv.num_players then
      self._sv.num_players = 0
   end

   if not self._sv.players then
      self._sv.players = {}
   end

   if not self._sv.wave then
      self._sv.wave = 0
   end

   if not self._sv.health then
      self._sv.health = 100
   end

   if self._sv.game_options then
      self._game_options = radiant.resources.load_json(self._sv.game_options.game_mode)
   end

   if not self._sv.wave_controller and self._sv.started then
      self:_create_countdown_timer(true)
   end

   self._wave_listeners = {}
   self:_create_wave_listeners()

   self._waves = radiant.resources.load_json('tower_defense:data:waves')
   self._waiting_for_target_cbs = {}
end

function GameService:destroy()
   self:_destroy_countdown_timer()
   self:_destroy_wave_controller()
end

function GameService:_destroy_countdown_timer()
   if self._countdown_timer then
      self._countdown_timer:destroy()
      self._countdown_timer = nil
   end
end

function GameService:_destroy_wave_controller()
   for _, listener in ipairs(self._wave_listeners) do
      listener:destroy()
   end
   self._wave_listeners = {}
   if self._sv.wave_controller then
      self._sv.wave_controller:destroy()
      self._sv.wave_controller = nil
   end
end

function GameService:_create_wave_listeners()
   if self._sv.wave_controller then
      table.insert(self._wave_listeners, radiant.events.listen(self._sv.wave_controller, 'tower_defense:wave:monster_escaped', self, self._on_wave_monster_escaped))
      table.insert(self._wave_listeners, radiant.events.listen(self._sv.wave_controller, 'tower_defense:wave:monster_killed', self, self._on_wave_monster_killed))
      table.insert(self._wave_listeners, radiant.events.listen(self._sv.wave_controller, 'tower_defense:wave:succeeded', self, self._on_wave_succeeded))
   end
end

function GameService:_on_wave_monster_escaped(damage)
   self:remove_health(damage)
end

function GameService:_on_wave_monster_killed(bounty)
   for resource, amount in pairs(bounty) do
      self:_give_all_players_resource(resource, amount)
   end
end

function GameService:_on_wave_succeeded(bonus)
   for resource, amount in pairs(bonus) do
      self:_give_all_players_resource(resource, amount)
   end
   self:_end_of_round()
end

function GameService:get_tower_gold_cost_multiplier_command(session, response)
   response:resolve({multiplier = self:get_tower_gold_cost_multiplier()})
end

function GameService:get_tower_gold_cost_multiplier()
   return self._game_options and self._game_options.tower_gold_cost_multiplier or 1
end

function GameService:get_game_options()
   return self._sv.game_options
end

function GameService:set_game_options(options)
   self._game_options = radiant.resources.load_json(options.game_mode)
   self._sv.game_options = options
   self.__saved_variables:mark_changed()
   stonehearth.weather:start(options.game_mode)
end

function GameService:get_ground_spawn_location()
   return self._sv.map_data.spawn_location
end

function GameService:get_air_spawn_location()
   return self._sv.map_data.air_spawn_location
end

function GameService:get_path_end_point_for_monster(monster)
   -- if it's an air monster, return the air point
   if monster:get_player_id() == 'monster_air' then
      return self._sv.map_data.air_end_point
   end
   return self._sv.map_data.end_point
end

function GameService:set_map_data(map_data)
   self._sv.map_data = map_data
   if map_data.starting_health then
      self._sv.health = map_data.starting_health
   end
   self.__saved_variables:mark_changed()
end

function GameService:start()
   self._sv.started = true
   self.__saved_variables:mark_changed()
   self:_create_countdown_timer()
end

function GameService:get_health()
   return self._sv.health
end

function GameService:remove_health(amount)
   self._sv.health = math.max(0, self._sv.health - amount)
   self.__saved_variables:mark_changed()

   -- if it's zero, you lost!
   if self._sv.health < 1 then
      self:_end_of_round()
   end
end

function GameService:get_current_wave()
   return self._sv.wave
end

function GameService:has_active_wave()
   return self._sv.wave_controller ~= nil
end

function GameService:_end_of_round()
   self:_destroy_wave_controller()
   self:_destroy_countdown_timer()

   self._waiting_for_target_cbs = {}
   radiant.events.trigger(radiant, 'tower_defense:wave:ended', self._sv.wave)
   
   if self._sv.health < 1 then
      -- no more health! you lost!
      return
   end

   if not self._waves.waves[self._sv.wave + 1] or (self._game_options.final_wave and self._sv.wave > self._game_options.final_wave) then
      -- no more waves! you won!
      return
   end

   self:_create_countdown_timer()
end

function GameService:_create_countdown_timer(second)
   local countdown = radiant.util.get_config('round_countdown', '5m')
   self._countdown_timer = stonehearth.calendar:set_timer('next wave countdown', countdown, function()
      if second then
         self:_start_round()
      else
         if self._sv.wave > 0 and radiant.util.get_config('pause_at_end_of_round', true) then
            stonehearth.game_speed:set_game_speed(0, true)
         end
         self:_create_countdown_timer(true)
      end
   end)
end

function GameService:_start_round()
   self:_destroy_countdown_timer()

   self._sv.wave = self._sv.wave + 1

   -- load the wave data, create the controller, and start it up
   local next_wave = self._waves.waves[self._sv.wave]
   if next_wave then
      local wave_controller = radiant.create_controller('tower_defense:wave', next_wave, self._sv.map_data)
      self._sv.wave_controller = wave_controller
      self:_create_wave_listeners()
      self._waiting_for_target_cbs = {}

      radiant.events.trigger(radiant, 'tower_defense:wave:started', self._sv.wave)
      wave_controller:start()
   else
      -- no more waves! you won!
   end

   self.__saved_variables:mark_changed()
end

function GameService:register_waiting_for_target(region, cb)
   self._waiting_for_target_cbs[region] = cb
end

function GameService:monster_moved_to(location)
   -- when a monster moves to a new grid location, check if it intersects with any towers waiting for targets and inform them
   local cbs = {}
   for region, cb in pairs(self._waiting_for_target_cbs) do
      if region:contains(location) then
         self._waiting_for_target_cbs[region] = nil
         table.insert(cbs, cb)
      end
   end
   for _, cb in ipairs(cbs) do
      cb()
   end
end

function GameService:get_num_players()
   return self._sv.num_players
end

function GameService:add_player(player_id)
   -- if the first wave has already started, can't add a new player
   if self._sv.wave > 0 then
      return
   end
   
   local player = self._sv.players[player_id]
   if player then
      -- player already exists, don't re-add them
      return
   end

   self._sv.num_players = self._sv.num_players + 1

   local starting_resources = self._game_options.starting_resources or {}
   local common_starting_resources = self._game_options.common_starting_resources or {}

   self._sv.players[player_id] = radiant.create_controller('tower_defense:game_player', player_id, starting_resources)

   if not self._sv.common_player then
      self._sv.common_player = radiant.create_controller('tower_defense:game_player', COMMON_PLAYER, starting_resources)
   end
   self._sv.common_player:add_player(common_starting_resources)

   self.__saved_variables:mark_changed()
end

function GameService:get_current_player_command(session, response)
   response:resolve({player = self:get_player(session.player_id)})
end

function GameService:get_player(player_id)
   return self._sv.players[player_id]
end

function GameService:get_common_player()
   return self._sv.common_player
end

function GameService:get_player_gold(player_id)
   return self:_get_player_resource(player_id, constants.tower_defense.player_resources.GOLD)
end

function GameService:get_player_wood(player_id)
   return self:_get_player_resource(player_id, constants.tower_defense.player_resources.WOOD)
end

function GameService:_get_player_resource(player_id, resource)
   local player = self._sv.players[player_id]
   return player and player:get_resource(resource) or 0
end

function GameService:get_common_gold()
   return self._sv.common_player and self._sv.common_player:get_resource(constants.tower_defense.player_resources.GOLD) or 0
end

function GameService:add_player_gold(player_id, amount)
   self:_add_player_resource(player_id, constants.tower_defense.player_resources.GOLD, amount)
end

function GameService:add_player_wood(player_id, amount)
   self:_add_player_resource(player_id, constants.tower_defense.player_resources.WOOD, amount)
end

function GameService:_add_player_resource(player_id, resource, amount)
   local player = self._sv.players[player_id]
   if player then
      player:add_resource(resource, amount)
   end
end

function GameService:spend_player_gold(player_id, amount)
   return self:_spend_player_resource(player_id, constants.tower_defense.player_resources.GOLD, amount)
end

function GameService:spend_player_wood(player_id, amount)
   return self:_spend_player_resource(player_id, constants.tower_defense.player_resources.WOOD, amount)
end

function GameService:_spend_player_resource(player_id, resource, amount)
   local player = self._sv.players[player_id]
   if player then
      return player:spend_resource(resource, amount)
   end
end

-- gold can only be given to the common player
function GameService:donate_gold(from_player_id, amount)
   if from_player_id ~= COMMON_PLAYER then
      local from_player = self._sv.players[from_player_id]
      local common_player = self._sv.common_player
      if from_player and common_player then
         amount = from_player:take_resource(constants.tower_defense.player_resources.GOLD, amount)
         if amount > 0 then
            common_player:add_resource(constants.tower_defense.player_resources.GOLD, amount)
            return true
         end
      end
   end

   return false
end

-- this is used to add an amount of gold to all players, like when a monster is killed
function GameService:give_all_players_gold(amount)
   self:_give_all_players_resource(constants.tower_defense.player_resources.GOLD, amount)
end

function GameService:give_all_players_wood(amount)
   self:_give_all_players_resource(constants.tower_defense.player_resources.WOOD, amount)
end

function GameService:_give_all_players_resource(resource, amount)
   for _, player in pairs(self._sv.players) do
      player:add_resource(resource, amount)
   end
   self._sv.common_player:add_resource(resource, amount)
end

return GameService
