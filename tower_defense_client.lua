tower_defense = {}

local service_creation_order = {
   
}

local monkey_patches = {
   
}

local function monkey_patching()
   for from, into in pairs(monkey_patches) do
      local monkey_see = require('monkey_patches.' .. from)
      local monkey_do = radiant.mods.require(into)
      radiant.mixin(monkey_do, monkey_see)
   end
end

local function create_service(name)
   local path = string.format('services.client.%s.%s_service', name, name)
   local service = require(path)()

   local saved_variables = tower_defense._sv[name]
   if not saved_variables then
      saved_variables = radiant.create_datastore()
      tower_defense._sv[name] = saved_variables
   end

   service.__saved_variables = saved_variables
   service._sv = saved_variables:get_data()
   saved_variables:set_controller(service)
   saved_variables:set_controller_name('tower_defense:' .. name)
   service:initialize()
   tower_defense[name] = service
end

local player_service_trace = nil

local function check_override_ui(players, player_id)
   -- Load ui mod
   if not player_id then
      player_id = _radiant.client.get_player_id()
   end
   
   local client_player = players[player_id]
   if client_player then
      if client_player.kingdom == "stonehearth:kingdoms:ascendancy" then
         -- hot load manifest
         radiant.log.write_('tower_defense', 0, 'SH:TD applying hot-loaded client manifest')
         _radiant.res.apply_manifest("/tower_defense/ui/manifest.json")
      end
   end
end

local function trace_player_service()
   _radiant.call('stonehearth:get_service', 'player')
      :done(function(r)
         local player_service = r.result
         check_override_ui(player_service:get_data().players)
         player_service_trace = player_service:trace('rayyas children ui change')
               :on_changed(function(o)
                     check_override_ui(player_service:get_data().players)
                  end)
         end)
end

function tower_defense:_on_init()
   tower_defense._sv = tower_defense.__saved_variables:get_data()

   for _, name in ipairs(service_creation_order) do
      create_service(name)
   end

   radiant.events.listen(radiant, 'radiant:client:server_ready', function()
      for _, name in ipairs(service_creation_order) do
         if tower_defense[name].on_server_ready then
            tower_defense[name]:on_server_ready()
         end
      end

      trace_player_service()
   end)

   radiant.events.trigger_async(radiant, 'tower_defense:client:init')
   radiant.log.write_('tower_defense', 0, 'SH:TD client initialized')
end

function tower_defense:_on_required_loaded()
   monkey_patching()

   radiant.events.trigger_async(radiant, 'tower_defense:client:required_loaded')
end

radiant.events.listen(tower_defense, 'radiant:init', tower_defense, tower_defense._on_init)
radiant.events.listen(radiant, 'radiant:required_loaded', tower_defense, tower_defense._on_required_loaded)

return tower_defense
