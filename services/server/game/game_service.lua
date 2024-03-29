local Point3 = _radiant.csg.Point3
local catalog_lib = require 'stonehearth.lib.catalog.catalog_lib'
local game_master_lib = require 'stonehearth.lib.game_master.game_master_lib'

local log = radiant.log.create_logger('game_service')

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

   if self._sv.game_options then
      self:_load_game_options()
   end

   if not self._sv.health then
      self._sv.health = self._game_options and self._game_options.starting_health or 100
   end

   self:_load_waves()

   if not self._sv.map_data then
      radiant.events.listen_once(radiant, 'radiant:game_loaded', function(e)
         self:_create_path_previewers()
      end)
   else
      self:_create_path_previewers()
   end

   self._wave_listeners = {}
   self:_create_wave_listeners()

   self._waiting_for_target_cbs = {}
end

function GameService:destroy()
  --self:_destroy_countdown_timer()
   self:_destroy_wave_controller()
   self:_destroy_path_previewers()
end

-- function GameService:_destroy_countdown_timer()
--    if self._countdown_timer then
--       self._countdown_timer:destroy()
--       self._countdown_timer = nil
--    end
-- end

function GameService:_destroy_wave_controller()
   for _, listener in ipairs(self._wave_listeners) do
      listener:destroy()
   end
   self._wave_listeners = {}
   if self._sv.wave_controller then
      local num_escaped = self._sv.wave_controller:get_num_escaped()
      self._sv.wave_controller:destroy()
      self._sv.wave_controller = nil
      return num_escaped
   end
end

function GameService:_destroy_path_previewers()
   if self._create_path_previewers_timer then
      self._create_path_previewers_timer:destroy()
      self._create_path_previewers_timer = nil
   end
   if self._sv._ground_path_previewer then
      radiant.entities.destroy_entity(self._sv._ground_path_previewer)
      self._sv._ground_path_previewer = nil
   end
   if self._ground_path_previewer_listener then
      self._ground_path_previewer_listener:destroy()
      self._ground_path_previewer_listener = nil
   end
   if self._sv._air_path_previewer then
      radiant.entities.destroy_entity(self._sv._air_path_previewer)
      self._sv._air_path_previewer = nil
   end
   if self._air_path_previewer_listener then
      self._air_path_previewer_listener:destroy()
      self._air_path_previewer_listener = nil
   end
   self.__saved_variables:mark_changed()
end

function GameService:_load_waves()
   if self._sv.map_data then
      local uri = self._sv.map_data.wave_index or 'tower_defense:data:waves'
      self._waves = radiant.resources.load_json(uri).waves
   else
      self._waves = {}
   end
end

function GameService:_create_wave_listeners()
   if self._sv.wave_controller then
      table.insert(self._wave_listeners, radiant.events.listen(self._sv.wave_controller, 'tower_defense:wave:monster_escaped', self, self._on_wave_monster_escaped))
      table.insert(self._wave_listeners, radiant.events.listen(self._sv.wave_controller, 'tower_defense:wave:monster_killed', self, self._on_wave_monster_killed))
      table.insert(self._wave_listeners, radiant.events.listen(self._sv.wave_controller, 'tower_defense:wave:succeeded', self, self._on_wave_succeeded))
   end
end

function GameService:_on_wave_monster_escaped(damage, bounty)
   if damage then
      self:remove_health(damage)
   end
   self:_on_wave_monster_killed(bounty)
end

function GameService:_on_wave_monster_killed(bounty)
   if bounty then
      for resource, amount in pairs(bounty) do
         self:_give_all_players_resource(resource, amount)
      end
   end
end

function GameService:_on_wave_succeeded(bonus)
   for resource, amount in pairs(bonus) do
      self:_give_all_players_resource(resource, amount)
   end
   self:_end_of_round()
end

function GameService:get_wave_index_command(session, response)
   -- go through all the waves and get "catalog" buff data for the buffs and category indicators for the spawns
   -- also list all monster types that will be spawned
   local waves = {}
   for _, wave in ipairs(self._waves) do
      local wave_detail = radiant.resources.load_json(wave.uri) or {}
      local wave_data = {
         display_name = wave_detail.display_name,
         category = wave.category
      }
      if wave.buffs then
         wave_data.buffs = catalog_lib.get_buffs(wave.buffs)
      end
      wave_data.monsters = {}
      for _, monster in ipairs(wave_detail.monsters) do
         for _, spawn in ipairs(monster.each_spawn) do
            local pop = stonehearth.population:get_population(spawn.population)
            local role = spawn.info.from_population.role
            role = wave.role_overrides and wave.role_overrides[role] or role
            for _, uri in ipairs(pop:get_role_entity_uris(role)) do
               local monster_data = wave_data.monsters[uri]
               if not monster_data then
                  monster_data = {
                     damage = spawn.damage,
                     count = 0,
                     summons = {}
                  }
                  wave_data.monsters[uri] = monster_data
               end
               monster_data.count = monster_data.count + (monster.count or 1) * (spawn.info.from_population.max or 1)

               -- also check if this monster spawns additional monsters
               self:_insert_monster_summons(monster_data.summons, uri)
            end
         end
      end

      table.insert(waves, wave_data)
   end
   
   response:resolve({waves = waves, last_wave = math.min(#waves, self._game_options.final_wave)})
end

function GameService:_insert_monster_summons(array, uri)
   local monster_info = radiant.entities.get_entity_data(uri, 'tower_defense:monster_info')
   if monster_info and monster_info.summons then
      for _, summon_uri in ipairs(monster_info.summons) do
         if not array[summon_uri] then
            array[summon_uri] = true
            self:_insert_monster_summons(array, summon_uri)
         end
      end
   end
end

function GameService:get_tower_gold_cost_multiplier_command(session, response)
   response:resolve({multiplier = self:get_tower_gold_cost_multiplier()})
end

function GameService:get_tower_gold_cost_multiplier()
   return self._tower_gold_cost_multiplier
end

function GameService:get_tower_placeable_region()
   return self._sv.map_data.tower_placeable_region
end

function GameService:get_game_options()
   return self._sv.game_options
end

function GameService:set_game_options(options)
   self._sv.game_options = options
   self:_load_game_options()
   if self._game_options.starting_health then
      self._sv.health = self._game_options.starting_health
   end
   self.__saved_variables:mark_changed()
   stonehearth.weather:start(options.game_mode)
end

function GameService:_load_game_options()
   self._game_options = radiant.resources.load_json(self._sv.game_options.game_mode)
   self._tower_gold_cost_multiplier = self._game_options.multipliers and self._game_options.multipliers.tower_gold_cost or 1
end

function GameService:get_ground_spawn_location()
   return self._sv.map_data.spawn_location
end

function GameService:get_air_spawn_location()
   return self._sv.map_data.air_spawn_location
end

function GameService:get_air_path_height()
   return self._sv.map_data.air_path.height
end

function GameService:get_ground_path()
   return self._sv.map_data.ground_path_region
end

function GameService:get_air_path()
   return self._sv.map_data.air_path_region
end

function GameService:get_path_end_point_for_monster(monster)
   -- if it's an air monster, return the air point
   if monster:get_player_id() == 'monster_air' then
      return self._sv.map_data.air_end_point
   end
   return self._sv.map_data.end_point
end

function GameService:get_path_for_monster(monster)
   -- first check if the monster already has path points
   local monster_comp = monster:get_component('tower_defense:monster')
   local path_points = monster_comp and monster_comp:get_path_points()

   if not path_points then
      if monster:get_player_id() == 'monster_air' then
         path_points = self:_get_translated_points(self._sv.map_data.air_path.points, self._sv.map_data.air_spawn_location)
      else
         path_points = self:_get_translated_points(self._sv.map_data.path.points, self._sv.map_data.spawn_location)
      end
   end

   if path_points and #path_points > 0 then
      local pathsegments = {}
      local prev_point = radiant.entities.get_world_location(monster)

      for _, point in pairs(path_points) do
         if prev_point ~= point then
            local path = _radiant.sim.create_direct_path_finder(monster)
                                    :set_start_location(prev_point)
                                    :set_end_location(point)
                                    :set_allow_incomplete_path(false)
                                    :set_reversible_path(false)
                                    :get_path()
            table.insert(pathsegments, path)
         end
         prev_point = point
      end

      local full_path = _radiant.sim.combine_paths(pathsegments)
      if monster_comp then
         monster_comp:set_path(full_path)
      end

      return full_path
   end
end

function GameService:_get_translated_points(points, spawn)
   if points and #points > 0 then
      local trans_points = {}

      local offset = spawn - Point3(unpack(points[1]))
      for _, point in ipairs(points) do
         table.insert(trans_points, Point3(unpack(point)) + offset)
      end

      return trans_points
   end
end

function GameService:get_last_monster_location(monster_id)
   local wave_controller = self._sv.wave_controller
   return wave_controller and wave_controller:get_last_monster_location(monster_id)
end

function GameService:queue_spawn_monsters(monsters, at_monster_id)
   local wave_controller = self._sv.wave_controller
   if wave_controller then
      return wave_controller:queue_spawn_monsters(monsters, at_monster_id)
   end
end

function GameService:set_map_data(map_data)
   self._sv.map_data = map_data
   self.__saved_variables:mark_changed()
   self:_create_path_previewers()
   self:_load_waves()
end

function GameService:start_game_command(session, response)
   self:start()
   response:resolve({})
end

function GameService:start()
   self._sv.started = true
   self.__saved_variables:mark_changed()
   --self:_create_countdown_timer()
   self:_start_round()
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

function GameService:_create_path_previewers()
   if not self._sv.wave_controller then
      -- delay this a tick; for some reason AI doesn't kick in if it's being created instantly
      self._create_path_previewers_timer = radiant.on_game_loop_once('delayed create path previewers', function()
         self:_destroy_path_previewers()  -- just in case
         self._sv._ground_path_previewer, self._ground_path_previewer_listener = self:_create_path_previewer('monster_ground', self._sv.map_data.spawn_location)
         self._sv._air_path_previewer, self._air_path_previewer_listener = self:_create_path_previewer('monster_air', self._sv.map_data.air_spawn_location)
         self.__saved_variables:mark_changed()
      end)
   end
end

function GameService:_create_path_previewer(population, location)
   local pop = stonehearth.population:get_population(population)
   local previewer = game_master_lib.create_citizens(pop, {
      from_population = {
         role = 'path_previewer',
         min = 1,
         max = 1
      }}, location, {player_id = ''})[1]
   radiant.terrain.place_entity_at_exact_location(previewer, location)
   
   local listener = radiant.events.listen(previewer, 'tower_defense:finished_path', function()
      radiant.terrain.place_entity_at_exact_location(previewer, location)
   end)

   return previewer, listener
end

function GameService:_set_game_alert(message, data, is_important)
   self._sv.game_alert = message
   self._sv.game_alert_data = data
   self._sv.game_alert_is_important = is_important
   self.__saved_variables:mark_changed()
end

function GameService:_end_of_round()
   local num_escaped = self:_destroy_wave_controller()
   --self:_destroy_countdown_timer()

   self._waiting_for_target_cbs = {}
   radiant.events.trigger(radiant, 'tower_defense:wave:ended', self._sv.wave)
   
   if self._sv.health < 1 then
      -- no more health! you lost!
      self._sv.finished = true
      self:_set_game_alert('i18n(tower_defense:alerts.game.game_lost)', nil, true)
      return
   end

   self:_set_game_alert('i18n(tower_defense:alerts.game.wave_ended)', {wave = self._sv.wave, num_escaped = num_escaped or 0})

   self:_create_path_previewers()

   --self:_create_countdown_timer()
end

-- function GameService:_create_countdown_timer(second)
--    if not self._waves[self._sv.wave + 1] or (self._game_options.final_wave and self._sv.wave >= self._game_options.final_wave) then
--       -- no more waves! you won!
--       self:_set_game_alert('i18n(tower_defense:alerts.game.game_won)', nil, true)
--       return
--    end

--    local countdown = radiant.util.get_config('round_countdown', '5m')
--    self._countdown_timer = stonehearth.calendar:set_timer('next wave countdown', countdown, function()
--       if second then
--          self:_start_round()
--       else
--          if self._sv.wave > 0 and radiant.util.get_config('pause_at_end_of_round', true) then
--             stonehearth.game_speed:set_game_speed(0, true)
--          end
--          self:_create_countdown_timer(true)
--       end
--    end)
-- end

function GameService:start_round_command(session, response)
   self:_start_round()
   response:resolve({})
end

function GameService:_start_round()
   self:_destroy_path_previewers()
   
   if not self._waves[self._sv.wave + 1] or (self._game_options.final_wave and self._sv.wave >= self._game_options.final_wave) then
      -- no more waves! you won!
      self:_set_game_alert('i18n(tower_defense:alerts.game.game_won)', nil, true)
      return
   end

   if self._sv.wave_controller then
      -- this shouldn't happen, but you're not allowed to request a new round starting while the previous one is still happening
      return
   end

   --self:_destroy_countdown_timer()

   self._sv.wave = self._sv.wave + 1
   self:_set_game_alert('i18n(tower_defense:alerts.game.wave_starting)', {wave = self._sv.wave})

   -- load the wave data, create the controller, and start it up
   local next_wave = self._waves[self._sv.wave]
   if next_wave then
      local wave_controller = radiant.create_controller('tower_defense:wave', next_wave, self._sv.map_data, self._game_options)
      self._sv.wave_controller = wave_controller
      self:_create_wave_listeners()
      self._waiting_for_target_cbs = {}

      radiant.events.trigger(radiant, 'tower_defense:wave:started', self._sv.wave)
      wave_controller:start()
   else
      -- no more waves! you won!
      self._sv.finished = true
      self:_set_game_alert('i18n(tower_defense:alerts.game.game_won)', nil, true)
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
