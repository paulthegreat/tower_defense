local Quaternion = _radiant.csg.Quaternion
local Point3 = _radiant.csg.Point3
local log = radiant.log.create_logger('projectile')

local ProjectileComponent = class()

function ProjectileComponent:set_target(target)
   self._target = target
   self._target_id = target:get_id()
end

function ProjectileComponent:start()
   if self._gameloop_trace then
      return
   end

   local vector = self:_get_vector_to_target()
   self:_face_direction(vector)

   self._gameloop_trace = radiant.on_game_loop('projectile movement', function()
         local vector = self:_get_vector_to_target()
         if not vector then
            self:_destroy_gameloop_trace()
            radiant.entities.destroy_entity(self._entity)
            return
         end

         local distance = vector:length()
         local move_distance = self:_get_distance_per_gameloop(self._speed)

         -- projectile moves speed units every gameloop
         if distance <= move_distance then
            self:_trigger_impact()

             -- no need to keep moving
            self:_destroy_gameloop_trace()

            -- remove the entity from the world while waiting for its destruction
            radiant.entities.remove_child(radiant.entities.get_root_entity(), self._entity)
            return
         end

         vector:normalize()
         vector:scale(move_distance)

         local projectile_location = self._mob:get_world_location()
         local new_projectile_location = projectile_location + vector

         self._mob:move_to(new_projectile_location)
         self:_face_direction(vector)
      end)
end

function ProjectileComponent:_get_vector_to_target()
   local projectile_location = self._mob:get_world_location()
   local target_location = self._target:is_valid() and self._target:add_component('mob'):get_world_location()
                           or tower_defense.game:get_last_monster_location(self._target_id)
   if target_location then
      local target_point = target_location + self._target_offset
      local vector = target_point - projectile_location
      return vector
   end
end

return ProjectileComponent
