local WaveEndAddBuffScript = class()

function WaveEndAddBuffScript:on_buff_added(entity, buff)
   local json = buff:get_json()
   self._tuning = json.script_info
   if not self._tuning or not self._tuning.buff_to_add then
      return
   end
   
   -- listen for both wave start and wave end:
   -- only grow after it's been planted for a full wave, to avoid incentivizing last-second pauses at the end of waves to build
   local script_data = buff:get_script_data()
   if script_data and script_data.wave_started then
      self:_create_wave_end_listener(entity)
   else
      self._wave_start_listener = radiant.events.listen_once(radiant, 'tower_defense:wave:started', function()
         self._wave_start_listener = nil
         script_data = buff:get_script_data() or {}
         script_data.wave_started = true
         buff:set_script_data(script_data)
         self:_create_wave_end_listener(entity)
      end)
   end
end

function WaveEndAddBuffScript:_create_wave_end_listener(entity)
   self._wave_end_listener = radiant.events.listen(radiant, 'tower_defense:wave:ended', function()
      radiant.entities.add_buff(entity, self._tuning.buff_to_add, self._tuning.buff_to_add_options)
   end)
end

function WaveEndAddBuffScript:on_buff_removed(entity, buff)
   if self._wave_start_listener then
      self._wave_start_listener:destroy()
      self._wave_start_listener = nil
   end
   if self._wave_end_listener then
      self._wave_end_listener:destroy()
      self._wave_end_listener = nil
   end
end

return WaveEndAddBuffScript
