local Point3 = _radiant.csg.Point3
local Path = _radiant.sim.Path
local Entity = _radiant.om.Entity

local MonsterGetPath = radiant.class()

MonsterGetPath.name = 'monster get path'
MonsterGetPath.does = 'tower_defense:monster_get_path'
MonsterGetPath.args = {}
MonsterGetPath.think_output = {
	path = Path,				-- the path to destination, from the current Entity
}
MonsterGetPath.priority = 0

local log = radiant.log.create_logger('monster_get_path')

function MonsterGetPath:__init()
end

function MonsterGetPath:start_thinking(ai, entity, args)
	if not ai.CURRENT.location then
		ai:set_debug_progress('dead; no starting location (suspended?)')
		return
	end

	self._ai = ai
	self._log = log
	-- This is a hotspot, and creating loggers here is expensive, so only enable this for debugging.
	-- self._log = ai:get_log()
	self._ai:set_debug_progress('starting thinking')

	local path = tower_defense.game:get_path_for_monster(entity)
   if path then
      ai:set_think_output({ path = path })
   end
end

function MonsterGetPath:stop_thinking(ai, entity, args)
	self._log:debug('calling cleanup from stop_thinking')
	self._ai:set_debug_progress('not thinking anymore')
end

return MonsterGetPath
