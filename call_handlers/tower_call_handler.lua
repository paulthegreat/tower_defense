local validator = radiant.validator

local TowerCallHandler = class()
local log = radiant.log.create_logger('tower_call_handler')

function TowerCallHandler:create_and_place_entity(session, response, uri)
   local entity = radiant.entities.create_entity(uri)

   stonehearth.selection:deactivate_all_tools()
   
   -- TODO: limit selector to valid building locations
   stonehearth.selection:select_location()
      :set_cursor_entity(entity)
      :set_filter_fn(function (result, selector)
            local this_entity = result.entity   
            local normal = result.normal:to_int()
            local brick = result.brick

            local rcs = this_entity:get_component('region_collision_shape')
            local region_collision_type = rcs and rcs:get_region_collision_type()
            if region_collision_type == _radiant.om.RegionCollisionShape.NONE then
               return stonehearth.selection.FILTER_IGNORE
            end

            if normal.y ~= 1 then
               return stonehearth.selection.FILTER_IGNORE
            end

            if this_entity:get_id() == radiant._root_entity_id then
               local kind = radiant.terrain.get_block_kind_at(brick - normal)
               if kind == nil then
                  return stonehearth.selection.FILTER_IGNORE
               elseif kind == 'grass' then
                  return next(radiant.terrain.get_entities_at_point(brick)) == nil
               else
                  return false
               end
            end

            -- if the entity we're looking at is a child entity of our primary entity, ignore it
            local parent = radiant.entities.get_parent(this_entity)
            if not parent or parent == entity then
               return stonehearth.selection.FILTER_IGNORE
            end

            -- TODO: check for platform entities
            -- if this_entity:get_component('mob'):get_allow_vertical_adjacent() then
            --    return true
            -- end

            return stonehearth.selection.FILTER_IGNORE
         end)
      :done(function(selector, location, rotation)
               _radiant.call('tower_defense:create_entity', uri, location, rotation)
                  :done(function()
                     radiant.entities.destroy_entity(entity)
                     response:resolve(true)
                  end)
                  :fail(function(e)
                     response:reject(e)
                  end)
            end)
      :fail(function(selector)
            selector:destroy()
            response:reject('no location')
         end)
      :always(function()
         end)
      :go()
end

function TowerCallHandler:create_entity(session, response, uri, location, rotation)
   -- first check if the player actually has the resources to place it
   -- if not, we'll cancel out
   
   local player_id = session.player_id
   local player = tower_defense.game:get_player(player_id)
   
   local cost = radiant.entities.get_net_worth(uri)
   local can_build = cost and player and player:spend_gold(cost)
   if not can_build then
      response:reject({
         message = 'i18n(tower_defense:alerts.towers.build.not_enough_gold)',
         i18n_data = {
            needed = cost,
            player_gold = player:get_gold(),
            common_gold = tower_defense.game:get_common_gold()
         }
      })
      return false
   end
   
   local entity = radiant.entities.create_entity(uri, { owner = player_id })

   radiant.terrain.place_entity(entity, location, { force_iconic = false })
   radiant.entities.turn_to(entity, rotation)
   entity:get_component('tower_defense:tower'):placed(rotation)
   local inventory = stonehearth.inventory:get_inventory(player_id)
   if inventory and not inventory:contains_item(entity) then
      inventory:add_item(entity)
   end

   return true
end

function TowerCallHandler:sell_full(session, response, tower)
   validator.expect_argument_types({'Entity'}, tower)

   self:_sell_tower(session.player_id, tower)
end

function TowerCallHandler:sell_less(session, response, tower)
   validator.expect_argument_types({'Entity'}, tower)

   self:_sell_tower(session.player_id, tower, 0.2)
end

function TowerCallHandler:_sell_tower(player_id, tower, multiplier)
   -- can't sell other players' towers!
   if player_id ~= tower:get_player_id() then
      return
   end

   -- get the value of the tower, refund it to the player, and destroy the tower
   local value = math.floor(radiant.entities.get_net_worth(tower:get_uri()) * (multiplier or 1))
   local player = tower_defense.game:get_player(player_id)
   if player then
      player:add_gold(value)
   end
   radiant.entities.destroy_entity(tower)
end

return TowerCallHandler
