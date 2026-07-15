-- RoleUtil.lua
-- Маленький общий помощник для клиентских скриптов: проверка текущей роли
-- игрока по его Team. Раньше isHider() была скопирована по отдельности в
-- FreezeClient.lua и PaintClient.lua - вынесено сюда, чтобы не расходились.

local GameConfig = require(script.Parent.GameConfig)

local RoleUtil = {}

function RoleUtil.IsHider(player)
	return player.Team ~= nil and player.Team.Name == GameConfig.TEAM_HIDERS_NAME
end

function RoleUtil.IsSeeker(player)
	return player.Team ~= nil and player.Team.Name == GameConfig.TEAM_SEEKERS_NAME
end

return RoleUtil
