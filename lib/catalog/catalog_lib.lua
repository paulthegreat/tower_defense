local Entity = _radiant.om.Entity
local Point3 = _radiant.csg.Point3
local Material = require 'components.material.material'
local log = radiant.log.create_logger('catalog')

local catalog_lib = {}

local _all_buffs = {}

local DEFAULT_CATALOG_DATA = {
   display_name = '',
   description = '',
   player_id = nil,
   icon = nil,
   net_worth = nil,
   sell_cost = nil,
   shopkeeper_level = nil,
   category = nil,
   materials = nil,
   is_item = nil,
   root_entity_uri = nil,
   iconic_uri = nil
}

function catalog_lib.load_catalog(catalog, added_cb)
   local mods = radiant.resources.get_mod_list()

   -- for each mod
   for i, mod in ipairs(mods) do
      local manifest = radiant.resources.load_manifest(mod)
      -- for each alias
      local aliases = {}
      if manifest.aliases then
         radiant.util.merge_into_table(aliases, manifest.aliases)
      end
      if manifest.deprecated_aliases then
         radiant.util.merge_into_table(aliases, manifest.deprecated_aliases)
      end
      -- can be faster if give the entities aliases their own node
      for alias in pairs(aliases) do
         local full_alias = string.format('%s:%s', mod, alias)
         local json = catalog_lib._load_json(full_alias)
         local json_type = json and json.type
         if json_type == 'entity' then
            local result = catalog_lib._update_catalog_data(catalog, full_alias, json)
            if added_cb then
               added_cb(full_alias, result)
            end
         elseif json_type == 'buff' then
            catalog_lib._update_buff(full_alias, json)
         end
      end
   end

   return catalog
end

function catalog_lib._is_deprecated(alias)
   local alias_parts = alias:split(':', 1)
   if #alias_parts < 2 then
      return false
   end
   local mod = alias_parts[1]
   local local_alias = alias_parts[2]
   local manifest = radiant.resources.load_manifest(mod)
   return manifest.deprecated_aliases ~= nil and manifest.deprecated_aliases[local_alias] ~= nil
end

function catalog_lib._load_json(full_alias)
   local path = radiant.resources.convert_to_canonical_path(full_alias)

   -- needs to be fast
   if not path or string.sub(path, -5) ~= '.json' then
      return nil
   end

   local json = radiant.resources.load_json(path)
   return json
end

-- Note ghost forms and some iconics are not marked as entities in the manifest but probably should be
function catalog_lib._load_entity_json(full_alias)
   local json = catalog_lib._load_json(full_alias)
   local alias_type = json and json.type

   if alias_type == 'entity' then
      return json
   else
      return nil
   end
end

-- Add catalog description for this alias and insert in buyable items if applicable
function catalog_lib._update_catalog_data(catalog, full_alias, json)
   return catalog_lib._add_catalog_description(catalog, full_alias, json, DEFAULT_CATALOG_DATA)
end

function catalog_lib._add_catalog_description(catalog, full_alias, json, base_data)
   if catalog[full_alias] ~= nil then
      return
   end

   local catalog_data = radiant.shallow_copy(base_data)

   local result = {
      buyable = false,
      likeable = false
   }

   local entity_data = json.entity_data

   if entity_data ~= nil then
      local net_worth = entity_data['stonehearth:net_worth']
      if net_worth ~= nil then
         catalog_data.net_worth = net_worth.value_in_gold or 0
         catalog_data.sell_cost = net_worth.value_in_gold or 0
         catalog_data.sell_cost = math.ceil(catalog_data.sell_cost * stonehearth.constants.shop.SALE_MULTIPLIER)
         if net_worth.rarity then
            catalog_data.rarity = net_worth.rarity
         end
         if net_worth and net_worth.shop_info then
            catalog_data.shopkeeper_level = net_worth.shop_info.shopkeeper_level or -1
            if net_worth.shop_info.buyable then
               result.buyable = true
            end
         end
      end

      local catalog = entity_data['stonehearth:catalog']
      if catalog ~= nil then
         if catalog.display_name ~= nil then
            catalog_data.display_name = catalog.display_name
         end
         if catalog.description ~= nil then
            catalog_data.description = catalog.description
         end
         if catalog.icon ~= nil then
            catalog_data.icon = catalog.icon
         end
         if catalog.category ~= nil then
            catalog_data.category = catalog.category
         end
         if catalog.is_item ~= nil then
            catalog_data.is_item = catalog.is_item
         end
         if catalog.material_tags ~= nil then
            catalog_data.materials = catalog.material_tags
         end
         if catalog.player_id ~= nil then
            catalog_data.player_id = catalog.player_id
         end
         if catalog.subject_override ~= nil then
            catalog_data.subject_override = catalog.subject_override
         end
      end
   end

   if base_data.deprecated or catalog_lib._is_deprecated(full_alias) then
      catalog_data.deprecated = true
   end

   if json.components then
      if json.components['stonehearth:material'] then
         catalog_data.materials = json.components['stonehearth:material'].tags or ''
      end

      local entity_forms = json.components['stonehearth:entity_forms']
      if entity_forms then
         catalog_data.root_entity_uri = full_alias

         local iconic_path = entity_forms.iconic_form
         if iconic_path then
            local iconic_json = catalog_lib._load_json(iconic_path)
            catalog_lib._add_catalog_description(catalog, iconic_path, iconic_json, catalog_data)
            catalog_data.iconic_uri = iconic_path
         end

         local ghost_path = entity_forms.ghost_form
         if ghost_path then
            local ghost_json = catalog_lib._load_json(ghost_path)
            catalog_lib._add_catalog_description(catalog, ghost_path, ghost_json, catalog_data)
         end
      end
      
      if json.components['stonehearth:equipment_piece'] then
         catalog_data.equipment_required_level = json.components['stonehearth:equipment_piece'].required_job_level
         catalog_data.equipment_roles = json.components['stonehearth:equipment_piece'].roles
      end
   end

   if entity_data ~= nil then
      local appeal = entity_data['stonehearth:appeal']
      if appeal then
         catalog_data.appeal = appeal['appeal']
         if json.components then
            local entity_forms = json.components['stonehearth:entity_forms']
            if entity_forms then
               result.likeable = (catalog_data.appeal > 0 and
                                  not catalog_data.deprecated and
                                  (entity_forms.placeable_on_ground or entity_forms.placeable_on_walls))
            end
         end
      end

      local reembarkation = entity_data['stonehearth:reembarkation']
      if reembarkation and reembarkation.reembark_version then
         catalog_data.reembark_version = reembarkation.reembark_version
      end

      local workshop = entity_data['stonehearth:workshop']
      if workshop and workshop.equivalents then
         catalog_data.workshop_equivalents = workshop.equivalents
      end
      
      local weapon_data = entity_data['stonehearth:combat:weapon_data']
      if weapon_data and weapon_data.base_damage then
         catalog_data.combat_damage = weapon_data.base_damage
      end

      local armor_data = entity_data['stonehearth:combat:armor_data']
      if armor_data and armor_data.base_damage_reduction then
         catalog_data.combat_armor = armor_data.base_damage_reduction
      end
   end

   catalog_data.uri = full_alias
   if json and json.components and json.components['stonehearth:equipment_piece'] then
      catalog_data.injected_buffs = catalog_lib.get_buffs(json.components['stonehearth:equipment_piece'].injected_buffs)
   end

   if json and json.entity_data and json.entity_data['stonehearth:buffs'] and json.entity_data['stonehearth:buffs'].inflictable_debuffs then
      catalog_data.inflictable_debuffs = catalog_lib.get_buffs(json.entity_data['stonehearth:buffs'].inflictable_debuffs)
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

         local ground_presence = catalog_data.tower_weapon_attack_info.ground_presence
         if ground_presence then
            for _, instance in ipairs({'first_time', 'other_times', 'every_time'}) do
               if ground_presence[instance] and ground_presence[instance].buffs then
                  ground_presence[instance].expanded_buffs = catalog_lib.get_buffs(ground_presence[instance].buffs)
               end
            end
         end
      end
   end

   catalog[full_alias] = catalog_data
   result.catalog_data = catalog_data
   return result
end

function catalog_lib._update_buff(full_alias, json)
   local buff = _all_buffs[full_alias]
   if not buff then
      if not json then
         json = radiant.resources.load_json(full_alias)
         if json.type ~= 'buff' then
            return
         end
      end
      if json then
         buff = {
            uri = full_alias,
            axis = json.axis,
            category = json.category,
            ordinal = json.ordinal,
            display_name = json.display_name,
            description = json.description,
            icon = json.icon,
            max_stacks = json.max_stacks or 1,
            invisible_to_player = json.invisible_to_player,
            invisible_on_crafting = json.invisible_on_crafting,
            script_buffs = json.invisible_to_player and json.script_info and json.script_info.buffs
         }
         _all_buffs[full_alias] = buff
      end
   end

   return buff
end

function catalog_lib.get_all_buffs()
   return _all_buffs
end

function catalog_lib.get_buffs(buff_data)
   local buffs = {}
   if buff_data then
      for buff, data in pairs(buff_data) do
         local uri = type(data) == 'table' and data.uri or data
         local jsons = {}
         local json = catalog_lib._update_buff(uri)
         if json then
            -- check if this buff is just being used to apply other buffs
            if json.script_buffs then
               for _, sub_uri in ipairs(json.script_buffs) do
                  table.insert(buffs, catalog_lib._update_buff(sub_uri))
               end
            else
               table.insert(buffs, json)
            end
         end
      end
   end
   return buffs
end

function catalog_lib.get_tower_equipment(items)
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

return catalog_lib
