local validator = radiant.validator

local TowerCallHandler = class()
local log = radiant.log.create_logger('tower_call_handler')

function TowerCallHandler:create_and_place_entity(session, response, uri)
   local entity = radiant.entities.create_entity(uri)
   local tower_data = radiant.entities.get_entity_data(entity, 'tower_defense:tower_data')
   local placement = tower_data and tower_data.placement
   local placeable_region = tower_defense.client_game:get_tower_placeable_region()
   local placeable_terrain = tower_defense.client_game:get_tower_placeable_terrain()

   stonehearth.selection:deactivate_all_tools()
   
   -- TODO: limit selector to valid building locations
   stonehearth.selection:select_location()
      :set_cursor_entity(entity)
      :set_filter_fn(function (result, selector)
            -- the client_game service's request for map data should already be finished
            -- but worst case scenario the player can just move the mouse and reconsider   
            if not placeable_region then
               return false
            end

            local this_entity = result.entity   
            local normal = result.normal:to_int()
            local brick = result.brick

            if not this_entity then
               return stonehearth.selection.FILTER_IGNORE
            end

            local rcs = this_entity:get_component('region_collision_shape')
            local region_collision_type = rcs and rcs:get_region_collision_type()
            if region_collision_type == _radiant.om.RegionCollisionShape.NONE then
               return stonehearth.selection.FILTER_IGNORE
            end

            if normal.y ~= 1 then
               return stonehearth.selection.FILTER_IGNORE
            end

            -- only allow building within tower placeable region
            -- if it's not specified in map generation, a default region will be used,
            -- so as long as the client_game service has acquired the map data, this region will exist
            if not placeable_region:contains(brick) then
               return stonehearth.selection.FILTER_IGNORE
            end

            if this_entity:get_id() == radiant._root_entity_id then
               local kind = radiant.terrain.get_block_kind_at(brick - normal)
               if kind == nil then
                  return stonehearth.selection.FILTER_IGNORE
               elseif not placeable_terrain or kind == placeable_terrain then
                  local entities_at_point = radiant.terrain.get_entities_at_point(brick)
                  if placement then
                     if placement.type == 'replace_entity' then
                        local found_match = false
                        for _, e in pairs(entities_at_point) do
                           local catalog_data = stonehearth.catalog_client:get_catalog_data(e:get_uri())
                           if not catalog_data or catalog_data.category ~= placement.entity_category then
                              return false
                           else
                              found_match = true
                           end
                        end
                        return found_match
                     else
                        return next(entities_at_point) == nil
                     end
                  else
                     return next(entities_at_point) == nil
                  end
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
   
   local cost = self:_get_tower_cost(uri)
   local result = {}

   if not cost or not uri or not player then
      -- everything has a cost... if we can get it
      result.reject = true
      result.message = 'i18n(tower_defense:alerts.towers.build.unavailable)'
   else
      for resource, amount in pairs(cost) do
         local missing = player:can_spend_resource(resource, amount)
         if missing > 0 then
            result[resource] = missing
         end
      end
   end

   if not result.reject and next(result) then
      result.reject = true
      result.message = 'i18n(tower_defense:alerts.towers.build.missing_resources)'
   end
   
   if not result.reject then
      for resource, amount in pairs(cost) do
         player:spend_resource(resource, amount)
      end

      location = radiant.util.to_point3(location)
      local entity = radiant.entities.create_entity(uri, { owner = player_id })
      local tower_data = radiant.entities.get_entity_data(entity, 'tower_defense:tower_data')
      local placement = tower_data and tower_data.placement
      if placement and placement.type == 'replace_entity' then
         local entities_at_point = radiant.terrain.get_entities_at_point(location)
         for _, e in pairs(entities_at_point) do
            if radiant.entities.get_category(e) == placement.entity_category then
               radiant.entities.destroy_entity(e)
            end
         end
      end

      radiant.terrain.place_entity(entity, location, { force_iconic = false })
      radiant.entities.turn_to(entity, rotation)
      entity:get_component('tower_defense:tower'):placed(rotation)
      local inventory = stonehearth.inventory:get_inventory(player_id)
      if inventory and not inventory:contains_item(entity) then
         inventory:add_item(entity)
      end

      result.resolve = true
      result.message = 'i18n(tower_defense:alerts.towers.build.success)'
   end

   if result.resolve then
      response:resolve(result)
   else
      response:reject(result)
   end

   -- local can_build = cost and tower_defense.game:spend_player_gold(player_id, cost)
   -- if not can_build then
   --    response:reject({
   --       message = 'i18n(tower_defense:alerts.towers.build.not_enough_gold)',
   --       i18n_data = {
   --          needed = cost,
   --          player_gold = tower_defense.game:get_player_gold(player_id),
   --          common_gold = tower_defense.game:get_common_gold()
   --       }
   --    })
   --    return false
   -- end
end

function TowerCallHandler:sell_full(session, response, tower, gold_multiplier)
   validator.expect_argument_types({'Entity'}, tower)

   self:_sell_tower(session, response, tower, gold_multiplier)
end

function TowerCallHandler:sell_less(session, response, tower, gold_multiplier)
   validator.expect_argument_types({'Entity'}, tower)

   self:_sell_tower(session, response, tower, gold_multiplier)
end

function TowerCallHandler:_sell_tower(session, response, tower, multiplier)
   -- can't sell other players' towers!
   local player_id = session.player_id
   if player_id ~= tower:get_player_id() then
      response:reject({})
      return
   end

   -- get the value of the tower, refund it to the player, and destroy the tower
   local player = tower_defense.game:get_player(player_id)
   local cost = self:_get_tower_cost(tower:get_uri())
   for resource, amount in pairs(cost) do
      player:add_resource(resource, math.floor(amount * (multiplier or 1)))
   end
   radiant.entities.destroy_entity(tower)
   response:resolve({})
end

function TowerCallHandler:_get_tower_cost(uri)
   local entity_data = radiant.entities.get_entity_data(uri, 'tower_defense:tower_data')
   local multiplier = tower_defense.game:get_tower_gold_cost_multiplier()
   local cost = {}
   for resource, amount in pairs(entity_data.cost) do
      cost[resource] = (resource == stonehearth.constants.tower_defense.player_resources.GOLD and math.ceil(amount * multiplier)) or amount
   end
   return cost
end

function TowerCallHandler:set_tower_sticky_targeting(session, response, tower, sticky)
   validator.expect_argument_types({'Entity'}, tower)

   local tower_comp = tower:get_component('tower_defense:tower')
   if tower_comp then
      tower_comp:set_sticky_targeting(sticky)
   end
end

function TowerCallHandler:set_tower_target_filters(session, response, tower, filters)
   validator.expect_argument_types({'Entity', 'table'}, tower, filters)

   local tower_comp = tower:get_component('tower_defense:tower')
   if tower_comp then
      tower_comp:set_target_filters(filters)
   end
end

function TowerCallHandler:upgrade_tower(session, response, tower, upgrade)
   validator.expect_argument_types({'Entity'}, tower)

   local tower_comp = tower:get_component('tower_defense:tower')
   if tower_comp then
      local result = tower_comp:try_upgrade_tower(upgrade)
      if result.resolve then
         response:resolve(result)
      else
         response:reject(result)
      end
   else
      response:reject('invalid entity: has no tower component')
   end
end

function TowerCallHandler:harvest_wood_command(session, response, tower, buff_uri)
   if self:harvest_wood(tower, buff_uri) then
      response:resolve({})
   else
      response:reject({})
   end
end

function TowerCallHandler:harvest_wood(tower, buff_uri)
   local buffs_comp = tower:add_component('stonehearth:buffs')
   local buff = buffs_comp:get_buff(buff_uri)
   local wood = buff and buff:get_stacks_vis()
   if wood and wood > 0 then
      tower_defense.game:add_player_wood(tower:get_player_id(), wood)
      --buffs_comp:remove_buff(buff_uri, true)
      radiant.entities.destroy_entity(tower)
      return true
   end
end

return TowerCallHandler
