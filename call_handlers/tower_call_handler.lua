local validator = radiant.validator

local TowerCallHandler = class()

function TowerCallHandler:create_and_place_entity(session, response, uri)
   local entity = radiant.entities.create_entity(uri)

   stonehearth.selection:deactivate_all_tools()
   
   -- TODO: limit selector to valid building locations
   stonehearth.selection:select_location()
      :set_cursor_entity(entity)
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
