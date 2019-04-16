local WeightedSet = require 'stonehearth.lib.algorithms.weighted_set'
local rng = _radiant.math.get_default_rng()

local WeatherService = class()

local NUM_DAYS_TO_PLAN_AHEAD = 3
local DEFAULT_SNOW_DECAY_PER_MINUTE = 1 / 60 / 24
local SNOW_ADJUST_INTERVAL_GAME_MINUTES = 4

function WeatherService:initialize()
   self._sv = self.__saved_variables:get_data()

   if not self._sv._is_initialized then
      self._sv._is_initialized = true
      self._sv.current_weather_state = nil
      self._sv.last_weather_state = nil  -- we let states hang around for a day so we don't have sharp transitions (e.g. sandstorms instantly disappearing)
      self._sv.weather_override = nil
      self._sv.current_weather_stamp = 0
      self._sv.next_weather_types = {}
      self._sv.current_snow_amount = 0
   end
   
   if self._sv._snow_adjust_interval then  -- Used to be persistent.
      self._sv._snow_adjust_interval:destroy()
   end
   
   self._snow_adjust_interval = stonehearth.calendar:set_interval('adjust snow', SNOW_ADJUST_INTERVAL_GAME_MINUTES .. 'm', function()
         self:_update_snow_amount()
      end)
   
   self._wave_listener = radiant.events.listen(radiant, 'tower_defense:wave_started', function(wave)
         self:_switch_weather()
      end)

   -- Initialize weather state.
   self:_initialize()
end

function WeatherService:destroy()
   if self._sv.current_weather_state then
      self._sv.current_weather_state:destroy()
      self._sv.current_weather_state = nil
   end
   if self._sv.last_weather_state then
      self._sv.last_weather_state:destroy()
      self._sv.last_weather_state = nil
   end
   if self._snow_adjust_interval then
      self._snow_adjust_interval:destroy()
      self._snow_adjust_interval = nil
   end
   self._sv._is_initialized = false
end

function WeatherService:get_current_weather()
   return self._sv.current_weather_state
end

function WeatherService:is_dark_during_daytime()
   local state = self._sv.current_weather_state
   return state and state._sv.is_dark_during_daytime or false
end

-- called by tower_defense.game
function WeatherService:start(difficulty)
   self._sv.difficulty = difficulty
   self.__saved_variables:mark_changed()
   self:_initialize()
end

function WeatherService:_initialize()
   if not self._sv.difficulty then
      return
   end

   local difficulty = radiant.resources.load_json(self._sv.difficulty) or {}
   self._weather_data = difficulty.weather or {}
   self._weather_data.starting_weather = self._weather_data.starting_weather or {}
   if not next(self._weather_data.starting_weather) then
      table.insert(self._weather_data.starting_weather, {uri = 'tower_defense:weather:sunny', weight = 1})
   end
   self._weather_data.difficulty_weather = self._weather_data.difficulty_weather or {}
   if not next(self._weather_data.difficulty_weather) then
      table.insert(self._weather_data.difficulty_weather, {uri = 'tower_defense:weather:sunny', weight = 1})
   end

   -- Generate weather types if we haven't already.
   -- Paul: we generate an extra day of weather because we essentially skip the first one,
   -- which only exists until the start of wave 1
   if not next(self._sv.next_weather_types) then
      for i = 0, NUM_DAYS_TO_PLAN_AHEAD do
         table.insert(self._sv.next_weather_types, self:_get_starting_weather())
      end
   end

   self:_switch_weather()
end

function WeatherService:_switch_weather(instigating_player_id)
   self:_switch_to(self._sv.next_weather_types[1], instigating_player_id)

   -- Consume the oldest weather choice and generate a new weather choice at the end.
   -- worst queue pop ever.
   local new_weather_types = {}
   for i, v in ipairs(self._sv.next_weather_types) do
      if i > 1 then
         table.insert(new_weather_types, v)
      end
   end
   
   local newly_selected_weather_type = self._sv.weather_override or self:_get_difficulty_weather()
   table.insert(new_weather_types, newly_selected_weather_type)
   self._sv.next_weather_types = new_weather_types
   self.__saved_variables:mark_changed()
end

function WeatherService:set_weather_override(weather_uri, instigating_player_id)  -- nil clears override
   self._sv.weather_override = weather_uri
   self._sv.next_weather_types = {}
   for i = 0, NUM_DAYS_TO_PLAN_AHEAD do
      table.insert(self._sv.next_weather_types, self._sv.weather_override or self:_get_difficulty_weather())
   end
   self:_switch_weather(instigating_player_id)
end

function WeatherService:_get_starting_weather()
   local weighted_set = WeightedSet(rng)
   for _, entry in ipairs(self._weather_data.starting_weather) do
      weighted_set:add(entry.uri, entry.weight)
   end
   return weighted_set:choose_random()
end

function WeatherService:_get_difficulty_weather()
   local weighted_set = WeightedSet(rng)
   for _, entry in ipairs(self._weather_data.difficulty_weather) do
      weighted_set:add(entry.uri, entry.weight)
   end
   return weighted_set:choose_random()
end

function WeatherService:_switch_to(weather_uri, instigating_player_id)
   if self._sv.current_weather_state then
      self._sv.current_weather_state:stop()
   end
   if self._sv.last_weather_state then
      self._sv.last_weather_state:destroy()
   end
   self._sv.last_weather_state = self._sv.current_weather_state
   self._sv.current_weather_state = nil

   self._sv.current_weather_state = radiant.create_controller('stonehearth:weather_state', weather_uri)
   self._sv.current_weather_state:start(instigating_player_id)
   
   self._sv.current_weather_stamp = self._sv.current_weather_stamp + 1

   self.__saved_variables:mark_changed()
end

function WeatherService:_update_snow_amount()
   if self._sv.current_weather_state then
      local delta = self._sv.current_weather_state._sv.snow_accumulation_per_minute or -DEFAULT_SNOW_DECAY_PER_MINUTE
      local old_snow_amount = self._sv.current_snow_amount
      self._sv.current_snow_amount = old_snow_amount + delta * SNOW_ADJUST_INTERVAL_GAME_MINUTES
      self._sv.current_snow_amount = math.max(0, math.min(self._sv.current_snow_amount, 1))
      if old_snow_amount ~= self._sv.current_snow_amount then
         self.__saved_variables:mark_changed()
      end
   end
end

return WeatherService
