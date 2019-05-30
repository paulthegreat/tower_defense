local TowerStats = class()

function TowerStats:initialize()
   self._sv.damage = 0
   self._sv.damage_by_type = {}
   self._sv.wave_damage = {}
   self._sv.kills = 0
end

function TowerStats:create(wave_created)
   self._sv.wave_created = wave_created
   self.__saved_variables:mark_changed()
end

function TowerStats:activate()
   self._wave_listener = radiant.events.listen(radiant, 'tower_defense:wave:ended', self, self._on_wave_ended)
end

function TowerStats:destroy()
   if self._wave_listener then
      self._wave_listener:destroy()
      self._wave_listener = nil
   end
end

function TowerStats:_on_wave_ended(wave)
   self._sv.wave_damage[wave] = self._sv.damage_by_type
   self._sv.damage_by_type = {}
   self.__saved_variables:mark_changed()
end

function TowerStats:increment_damage(amount, damage_type)
   self._sv.damage = self._sv.damage + (amount or 1)
   if damage_type then
      self._sv.damage_by_type[damage_type] = (self._sv.damage_by_type[damage_type] or 0) + (amount or 1)
   end
   self.__saved_variables:mark_changed()
end

function TowerStats:increment_kills(amount)
   self._sv.kills = self._sv.kills + (amount or 1)
   self.__saved_variables:mark_changed()
end

return TowerStats
