local TowerComponent = class()

function TowerComponent:create()
   local wave = tower_defense.game:get_current_wave()
   if tower_defense.game:has_active_wave() then
      wave = wave - 1
   end
   self._sv._wave_created = wave
end

function TowerComponent:activate()
   self._json = radiant.entities.get_json(self) or {}

   -- update commands
   -- add a listener for wave change if necessary
   local cur_wave = tower_defense.game:get_current_wave()
   self:_update_sell_command(cur_wave)

   -- make sure we have any other commands, like auto-targeting and upgrade options


   -- set up a listener for added to / removed from world for registering/unregistering with tower service

end

function TowerComponent:destroy()
   self:_destroy_wave_listener()
end

function TowerComponent:can_see_invis()

end

function TowerComponent:get_targetable_region()

end

function TowerComponent:_destroy_wave_listener()
   if self._wave_listener then
      self._wave_listener:destroy()
      self._wave_listener = nil
   end
end

function TowerComponent:_on_wave_started(wave)
   if wave > self._sv._wave_created then
      self:_update_sell_command(wave)
   end
end

function TowerComponent:_update_sell_command(wave)
   local commands = self._entity:add_component('stonehearth:commands')
   if wave > self._sv._wave_created then
      commands:remove_command('tower_defense:commands:sell_full')
      commands:add_command('tower_defense:commands:sell_less')
   else
      commands:remove_command('tower_defense:commands:sell_less')
      commands:add_command('tower_defense:commands:sell_full')
      if not self._wave_listener then
         self._wave_listener = radiant.events.listen(radiant, 'tower_defense:wave_started', self, self._on_wave_started)
      end
   end
end

return TowerComponent
