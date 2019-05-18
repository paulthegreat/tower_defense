local catalog_lib = require 'stonehearth.lib.catalog.catalog_lib'
local log = radiant.log.create_logger('td_catalog_lib')
local td_catalog_lib = {}

local _all_buffs = {}

function td_catalog_lib.load_catalog(catalog, added_cb)
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
            local result = td_catalog_lib._update_catalog_data(catalog, full_alias, json)
            if added_cb then
               added_cb(full_alias, result)
            end
         elseif json_type == 'buff' then
            td_catalog_lib._update_buff(full_alias, json)
         end
      end
   end

   return catalog
end

function td_catalog_lib._update_buff(full_alias, json)
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

function td_catalog_lib.get_all_buffs()
   return _all_buffs
end

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

         local ground_presence = catalog_data.tower_weapon_attack_info.ground_presence
         if ground_presence then
            for _, instance in ipairs({'first_time', 'other_times', 'every_time'}) do
               if ground_presence[instance] and ground_presence[instance].buffs then
                  ground_presence[instance].expanded_buffs = td_catalog_lib.get_buffs(ground_presence[instance].buffs)
               end
            end
         end
      end
   end
end

function td_catalog_lib.get_buffs(buff_data)
   local buffs = {}
   if buff_data then
      for buff, data in pairs(buff_data) do
         local uri = type(data) == 'table' and data.uri or data
         local jsons = {}
         local json = td_catalog_lib._update_buff(uri)
         if json then
            -- check if this buff is just being used to apply other buffs
            if json.invisible_to_player and json.script_info and json.script_info.buffs then
               for _, sub_uri in ipairs(json.script_info.buffs) do
                  table.insert(buffs, td_catalog_lib._update_buff(sub_uri))
               end
            else
               table.insert(buffs, json)
            end
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