tower_defense = {}

local service_creation_order = {
   'game'
}

local monkey_patches = {
   game_creation_service = 'stonehearth.services.server.game_creation.game_creation_service'
}

local function monkey_patching()
   for from, into in pairs(monkey_patches) do
      local monkey_see = require('monkey_patches.' .. from)
      local monkey_do = radiant.mods.require(into)
      radiant.mixin(monkey_do, monkey_see)
   end
end

local function create_service(name)
   local path = string.format('services.server.%s.%s_service', name, name)
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

function tower_defense:_on_init()
   tower_defense._sv = tower_defense.__saved_variables:get_data()

   for _, name in ipairs(service_creation_order) do
      create_service(name)
   end

   radiant.events.trigger_async(radiant, 'tower_defense:server:init')
   radiant.log.write_('tower_defense', 0, 'SH:TD server initialized')
end

function tower_defense:_on_required_loaded()
   monkey_patching()
   
   radiant.events.trigger_async(radiant, 'tower_defense:server:required_loaded')
end

radiant.events.listen(tower_defense, 'radiant:init', tower_defense, tower_defense._on_init)
radiant.events.listen(radiant, 'radiant:required_loaded', tower_defense, tower_defense._on_required_loaded)

return tower_defense
