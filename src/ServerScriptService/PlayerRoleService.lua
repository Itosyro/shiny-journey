-- PlayerRoleService.lua
-- Отвечает за команды (Teams) и распределение ролей Hiders/Seekers перед раундом.

local Teams = game:GetService("Teams")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local GameMode = require(ReplicatedStorage.Modules.GameMode)

local PlayerRoleService = {}

local hidersTeam, seekersTeam, spectatorsTeam

local function getOrCreateTeam(name, brickColor)
	local team = Teams:FindFirstChild(name)
	if not team then
		team = Instance.new("Team")
		team.Name = name
		team.TeamColor = brickColor
		team.AutoAssignable = false
		team.Parent = Teams
	end
	return team
end

function PlayerRoleService.Init()
	hidersTeam = getOrCreateTeam(GameConfig.TEAM_HIDERS_NAME, BrickColor.new("Institutional white"))
	seekersTeam = getOrCreateTeam(GameConfig.TEAM_SEEKERS_NAME, BrickColor.new("Really red"))
	spectatorsTeam = getOrCreateTeam(GameConfig.TEAM_SPECTATORS_NAME, BrickColor.new("Medium stone grey"))
end

function PlayerRoleService.GetTeams()
	return hidersTeam, seekersTeam, spectatorsTeam
end

-- Сколько искателей назначать на такое количество игроков (см. DECISIONS.md, п.19).
-- В Infection стартуем с меньшим числом Seekers, чем в Classic - оно всё равно
-- вырастет по ходу раунда (пойманные Hiders становятся Seekers, см. GameMode.lua),
-- поэтому используем более "редкий" делитель для старта.
local function calculateSeekersCount(totalPlayers)
	local playersPerSeeker = GameMode.Current == GameMode.Infection
		and GameConfig.SEEKERS_PER_PLAYERS_INFECTION
		or GameConfig.SEEKERS_PER_PLAYERS_CLASSIC

	local count = math.floor(totalPlayers / playersPerSeeker)
	count = math.max(GameConfig.MIN_SEEKERS, count)
	count = math.min(GameConfig.MAX_SEEKERS, count)
	-- Искателей не может быть больше, чем игроков минус хотя бы 1 прячущийся
	count = math.min(count, totalPlayers - 1)
	return count
end

-- Перемешать массив игроков (алгоритм Фишера-Йейтса), чтобы роли доставались случайно
local function shuffle(array)
	local result = table.clone(array)
	for i = #result, 2, -1 do
		local j = math.random(1, i)
		result[i], result[j] = result[j], result[i]
	end
	return result
end

-- Основная функция: получает список игроков, случайно распределяет роли,
-- возвращает два списка - hiders и seekers, и сразу назначает им команды.
function PlayerRoleService.AssignRoles(players)
	local shuffled = shuffle(players)
	local seekersCount = calculateSeekersCount(#shuffled)

	local seekers = {}
	local hiders = {}

	for i, player in ipairs(shuffled) do
		if i <= seekersCount then
			table.insert(seekers, player)
			player.Team = seekersTeam
		else
			table.insert(hiders, player)
			player.Team = hidersTeam
		end
	end

	return hiders, seekers
end

function PlayerRoleService.SetSpectator(player)
	player.Team = spectatorsTeam
end

-- Переводит пойманного Hider в команду Seekers "на лету", посреди раунда -
-- режим Infection (см. GameMode.lua и DECISIONS.md, п.18). В отличие от
-- AssignRoles, это не пересчёт ролей у всех игроков, а точечный перевод
-- одного конкретного игрока; список currentHiders/currentSeekers в
-- RoundManager обновляется отдельно, см. RoundManager.lua.
function PlayerRoleService.ConvertHiderToSeeker(player)
	player.Team = seekersTeam
end

return PlayerRoleService
