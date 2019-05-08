local Quaternion = _radiant.csg.Quaternion
local Point3 = _radiant.csg.Point3
local log = radiant.log.create_logger('projectile')

local ProjectileComponent = class()

function ProjectileComponent:set_target(target)
   self._target = target
   self._target_id = target:get_id()
end

function ProjectileComponent:set_passthrough_attack_cb(attack_cb, target_filter_fn)
   self._attack_cb = attack_cb
   self._target_filter_fn = target_filter_fn
   self._attacked_targets = {}
end

function ProjectileComponent:start()
   if self._gameloop_trace then
      return
   end

   local vector, target_location = self:_get_vector_to_target()
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

         if self._attack_cb then
            -- determine passed-through targets
            local attacked_targets = self._attacked_targets
            local targets = {}
            
            -- go through at the height of the ultimate destination
            -- this way it doesn't matter if we're shooting down from a tower at short monsters on the path below
            local start_point = Point3(projectile_location.x, target_location.y, projectile_location.z)
            local end_point = Point3(new_projectile_location.x, target_location.y, new_projectile_location.z)
            _physics:walk_line(start_point, end_point, function(location)
               for id, entity in pairs(radiant.terrain.get_entities_at_point(location, self._target_filter_fn)) do
                  if not attacked_targets[id] then
                     targets[id] = entity
                  end
               end
            end, 0)

            if next(targets) then
               self._attack_cb(targets, self._target)
               for id, _ in pairs(targets) do
                  attacked_targets[id] = true
               end
            end
         end

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
      return vector, target_location
   end
end

return ProjectileComponent
