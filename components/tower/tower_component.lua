local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3

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

   if self._sv.reveals_invis == nil then
      self._sv.reveals_invis = self._json.reveals_invis or false
      self.__saved_variables:mark_changed()
   end

   -- update commands
   -- add a listener for wave change if necessary
   local cur_wave = tower_defense.game:get_current_wave()
   self:_update_sell_command(cur_wave)

   -- make sure we have any other commands, like auto-targeting and upgrade options


   -- set up a listener for added to / removed from world for registering/unregistering with tower service
   self._parent_trace = self._entity:add_component('mob'):trace_parent('tower added or removed')
      :on_changed(function(parent_entity)
            if not parent_entity then
               --we were just removed from the world
               self:_unregister()
            else
               --we were just added to the world
               self:_register()
            end
         end)
      :push_object_state()
end

function TowerComponent:destroy()
   self:_destroy_wave_listener()
end

function TowerComponent:reveals_invis()
   return self._sv.reveals_invis
end

function TowerComponent:get_targetable_region()
   return self._sv.targetable_region
end

function TowerComponent:_destroy_wave_listener()
   if self._wave_listener then
      self._wave_listener:destroy()
      self._wave_listener = nil
   end
   if self._parent_trace then
      self._parent_trace:destroy()
      self._parent_trace = nil
   end
end

function TowerComponent:_register()
   -- calculate targetable range and translate it to our location
   -- pass that in to the tower service registration function
   -- store the resulting targetable path intersection ranges
   local location = radiant.entities.get_world_grid_location(self._entity)
   if location then
      local targetable_region = self:_create_targetable_region()
      self._sv.targetable_region = targetable_region
      if targetable_region then
         local ground_region, air_region = tower_defense.tower:register_tower(self._entity, location)
         self._sv.ground_region = ground_region
         self._sv.air_region = air_region
         self._sv.attacks_ground = self._json.targeting and self._json.targeting.attacks_ground
         self._sv.attacks_air = self._json.targeting and self._json.targeting.attacks_air
      end
      self.__saved_variables:mark_changed()
   end
end

function TowerComponent:_unregister()
   tower_defense.tower:unregister_tower(self._entity)
end

function TowerComponent:_create_targetable_region()
   local targeting = self._json.targeting or {}
   local region
   if targeting.type == 'rectangle' then
      region = Region3(radiant.util.to_cube3(targeting.region))
   elseif targeting.type == 'circle' then
      -- create a blocky circle region
      region = Region3()
      local r2 = (targeting.radius + 0.5) * (targeting.radius + 0.5)
      for x = -targeting.radius, targeting.radius do
         local z_size = math.ceil(math.sqrt(r2 - x * x) - 0.5)
         region:add_cube(Cube3(Point3(x, 0, -z_size), Point3(x + 1, 1, z_size + 1)))
      end
   end

   return region
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
