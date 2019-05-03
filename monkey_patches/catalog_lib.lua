local catalog_lib = require 'stonehearth.lib.catalog.catalog_lib'
local log = radiant.log.create_logger('td_catalog_lib')
local td_catalog_lib = {}

td_catalog_lib._td_old__add_catalog_description = catalog_lib._add_catalog_description
function td_catalog_lib._add_catalog_description(catalog, full_alias, json, base_data)
   local result = td_catalog_lib._td_old__add_catalog_description(catalog, full_alias, json, base_data)

   if result and result.catalog_data then
      td_catalog_lib._update_catalog_data(result.catalog_data)
   end

   return result
end

-- if the catalog has already been loaded without accounting for our changes (likely), update all entries
function td_catalog_lib.update_catalog(catalog)
   for uri, catalog_data in pairs(catalog) do
      td_catalog_lib._update_catalog_data(catalog_data, uri)
   end
end

function td_catalog_lib._update_catalog_data(catalog_data, uri, json)
   json = json or radiant.resources.load_json(uri)
   catalog_data.uri = uri
   if json and json.components and json.components['stonehearth:equipment_piece'] then
      catalog_data.injected_buffs = td_catalog_lib.get_buffs(json.components['stonehearth:equipment_piece'].injected_buffs)
   end

   if json and json.entity_data and json.entity_data['stonehearth:buffs'] and json.entity_data['stonehearth:buffs'].inflictable_debuffs then
      catalog_data.inflictable_debuffs = td_catalog_lib.get_buffs(json.entity_data['stonehearth:buffs'].inflictable_debuffs)
   end

   if json and json.entity_data and json.entity_data['tower_defense:tower_data'] then
      catalog_data.tower = json.entity_data['tower_defense:tower_data']
      if json.components and json.components['tower_defense:tower'] then
         catalog_data.tower.weapons = json.components['tower_defense:tower']
      end
   end

   if catalog_data.category == 'tower_weapon' and json.entity_data['stonehearth:combat:weapon_data'] then
      catalog_data.tower_weapon_targeting = json.entity_data['stonehearth:combat:weapon_data'].targeting
      local attacks = json.entity_data['stonehearth:combat:ranged_attacks']
      if attacks then
         -- we only care about the primary attack (if there even are any extra attacks)
         catalog_data.tower_weapon_attack_info = attacks[1]
      end
   end
end

function td_catalog_lib.get_buffs(buff_data)
   local buffs = {}
   if buff_data then
      for buff, data in pairs(buff_data) do
         local uri = type(data) == 'table' and data.uri or data
         local json = radiant.resources.load_json(uri)
         if json then
            table.insert(buffs, {
               uri = uri,
               axis = json.axis,
               display_name = json.display_name,
               description = json.description,
               icon = json.icon,
               max_stacks = json.max_stacks or 1,
               invisible_to_player = json.invisible_to_player,
               invisible_on_crafting = json.invisible_on_crafting
            })
         end
      end
   end
   return buffs
end

function td_catalog_lib.get_tower_equipment(items)
   local equipment = {}
   for _, item in ipairs(items) do
      local json = radiant.resources.load_json(item)
      json = json and json.entity_data
      if json then
         table.insert(equipment, json)
      end
   end

   if #equipment > 1 then
      table.sort(equipment, function(a, b)
         local a_twd = a['tower_defense:tower_weapon_data']
         local b_twd = b['tower_defense:tower_weapon_data']
         if not a_twd then
            return b_twd == nil
         elseif not b_twd then
            return true
         else
            return (a_twd.ordinal or 1) < (b_twd.ordinal or 1)
         end
      end)
   end

   return equipment
end

return td_catalog_lib