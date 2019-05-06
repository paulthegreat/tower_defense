-- A weather state, instances of which are maintained by the weather service
-- and remoted to the client for UI (and VFX?) display. Usually wraps a specific
-- weather controller (e.g. rain, sandstorm, etc.).

local rng = _radiant.math.get_default_rng()

local WeatherState = class()

function WeatherState:initialize()
   -- Constants
   self._sv.uri = nil
   self._sv.icon = nil
   self._sv.display_name = nil
   self._sv.description = nil
   self._sv.thoughts = nil
   self._sv.ambient_sound_key = nil
   self._sv.camera_attached_effect = nil
   self._sv.vision_multiplier = nil
   self._sv.sky_settings = nil
   self._sv.renderer = nil
   self._sv.hide_cloud_shadows = false
   self._sv.snow_accumulation_per_minute = nil

   -- Dynamics
   self._sv.script_controller = nil
   self._sv.is_active = false
end

function WeatherState:create(day_data)
   self._sv.uri = day_data.weather
   self._sv.wave = day_data.wave

   local json = radiant.resources.load_json(self._sv.uri, true, true)
   self._sv.display_name = json.display_name
   self._sv.description = json.description
   self._sv.icon = json.icon
   self._sv.thoughts = json.thoughts
   self._sv.ambient_sound_key = json.ambient_sound_key
   self._sv.camera_attached_effect = json.camera_attached_effect
   self._sv.vision_multiplier = json.vision_multiplier
   self._sv.sky_settings = json.sky_settings
   self._sv.renderer = json.renderer
   self._sv.hide_cloud_shadows = json.hide_cloud_shadows or false
   self._sv.snow_accumulation_per_minute = json.snow_accumulation_per_minute
   self._sv.is_dark_during_daytime = json.is_dark_during_daytime
   
   if json.tower_buffs and next(json.tower_buffs) then
      self._sv.tower_buffs = json.tower_buffs
   end
   if json.monster_buffs and next(json.monster_buffs) then
      self._sv.monster_buffs = json.monster_buffs
   end

   if json.controller then
      self._sv.script_controller = radiant.create_controller(json.controller)
   end

   self.__saved_variables:mark_changed()
end

function WeatherState:destroy()
   if self._sv.is_active then
      self:stop()
   end
   if self._sv.script_controller then
      self._sv.script_controller:destroy()
      self._sv.script_controller = nil
   end
   if self._tower_added_listener then
      self._tower_added_listener:destroy()
      self._tower_added_listener = nil
   end
end

function WeatherState:get_uri()
   return self._sv.uri
end

function WeatherState:restore()
   if self._sv.is_active then
      if self._sv.vision_multiplier then
         stonehearth.terrain:set_sight_radius_multiplier(self._sv.vision_multiplier)  -- We could technically be overriding something, but fine for now.
      end
   end
end

function WeatherState:activate()
   if self._sv.is_active then
      self:_create_listeners()
   end
end

function WeatherState:start(instigating_player_id)
   self._sv.is_active = true

   self:_create_listeners()

   if self._sv.tower_buffs then
      self:_apply_tower_buffs()
   end

   if self._sv.vision_multiplier then
      stonehearth.terrain:set_sight_radius_multiplier(self._sv.vision_multiplier)  -- We could technically be overriding something, but fine for now.
   end

   if self._sv.script_controller and self._sv.script_controller.start then
      self._sv.script_controller:start(instigating_player_id)
   end

   self.__saved_variables:mark_changed()
end

function WeatherState:stop()
   self._sv.is_active = false

   if self._tower_added_listener then
      self._tower_added_listener:destroy()
      self._tower_added_listener = nil
   end

   if self._monster_created_listener then
      self._monster_created_listener:destroy()
      self._monster_created_listener = nil
   end

   if self._sv.tower_buffs then
      self:_remove_tower_buffs()
   end

   if self._sv.vision_multiplier then
      stonehearth.terrain:set_sight_radius_multiplier(1)
   end

   if self._sv.script_controller and self._sv.script_controller.stop then
      self._sv.script_controller:stop()
   end

   self.__saved_variables:mark_changed()
end

function WeatherState:_create_listeners()
   if self._sv.tower_buffs then
      self._tower_added_listener = radiant.events.listen(radiant, 'tower_defense:tower_registered', function(tower)
         self:_apply_buffs(self._sv.tower_buffs, tower)
      end)
   end

   if self._sv.monster_buffs then
      self._monster_created_listener = radiant.events.listen(radiant, 'tower_defense:monster_created', function(monster)
         self:_apply_buffs(self._sv.monster_buffs, monster)
      end)
   end
end

function WeatherState:_apply_tower_buffs()
   local tower_buffs = self._sv.tower_buffs
   for _, tower_data in pairs(tower_defense.tower:get_registered_towers()) do
      self:_apply_buffs(tower_buffs, tower_data.tower)
   end
end

function WeatherState:_apply_buffs(buffs, entity)
   for _, buff_data in ipairs(buffs) do
      radiant.entities.add_buff(entity, buff_data.uri, buff_data.options)
   end
end

function WeatherState:_remove_tower_buffs()
   local tower_buffs = self._sv.tower_buffs
   for _, tower_data in pairs(tower_defense.tower:get_registered_towers()) do
      self:_remove_buffs(tower_buffs, tower_data.tower)
   end
end

function WeatherState:_remove_buffs(buffs, entity)
   for _, buff_data in ipairs(buffs) do
      radiant.entities.remove_buff(entity, buff_data.uri, buff_data.options)
   end
end

return WeatherState
