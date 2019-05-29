local TowerStats = class()

function TowerStats:initialize()
   self._sv.damage = 0
   self._sv.kills = 0
end

function TowerStats:create(wave_created)
   self._sv.wave_created = wave_created
   self.__saved_variables:mark_changed()
end

function TowerStats:increment_damage(amount)
   self._sv.damage = self._sv.damage + (amount or 1)
   self.__saved_variables:mark_changed()
end

function TowerStats:increment_kills(amount)
   self._sv.kills = self._sv.kills + (amount or 1)
   self.__saved_variables:mark_changed()
end

return TowerStats
