-- PlayerRoleService.lua
-- Отвечает за команды (Teams) и распределение ролей Hiders/Seekers перед раундом.

local Teams = game:GetService("Teams")
local Workspace = game:GetService("Workspace")
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
	local playersPerSeeker = GameMode.GetCurrent() == GameMode.Infection
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

-- Читает позицию игрока на лобби-платформе ОДИН раз в момент раздачи
-- ролей (не следит циклом за зонами - правило мобильной оптимизации №1,
-- CLAUDE.md) и определяет его "заявку" на роль: встал в центр
-- (SeekerVolunteerZone) - хочет быть Seeker; встал под одной из 4 арок
-- (HiderGateZone) - хочет быть Hider; иначе - как выпадет (см.
-- MapBuilder.buildLobbyPlatform, MEGA_PLAN.md 1.2).
local function getRoleIntent(player)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return "Random"
	end

	local mapFolder = Workspace:FindFirstChild("Map")
	if not mapFolder then
		return "Random"
	end

	local pos = rootPart.Position

	local seekerZone = mapFolder:FindFirstChild("SeekerVolunteerZone")
	if seekerZone then
		local flatOffset = Vector3.new(pos.X - seekerZone.Position.X, 0, pos.Z - seekerZone.Position.Z)
		if flatOffset.Magnitude <= GameConfig.LOBBY_SEEKER_ZONE_RADIUS then
			return "Seeker"
		end
	end

	-- 4 арки-врат Hider используют одно и то же имя - проверяем каждую
	-- (попадание в прямоугольный объём, высота не важна).
	for _, child in ipairs(mapFolder:GetChildren()) do
		if child.Name == "HiderGateZone" then
			local dx = math.abs(pos.X - child.Position.X)
			local dz = math.abs(pos.Z - child.Position.Z)
			if dx <= child.Size.X / 2 and dz <= child.Size.Z / 2 then
				return "Hider"
			end
		end
	end

	return "Random"
end

-- Основная функция: получает список игроков, распределяет роли с учётом
-- их заявки (позиция на лобби-платформе, см. getRoleIntent выше) и сразу
-- назначает им команды. Сигнатура не изменилась - вызывающий код
-- (RoundManager) не правится.
function PlayerRoleService.AssignRoles(players)
	local seekersCount = calculateSeekersCount(#players)

	-- Три пула по заявке на роль.
	local volunteers, hiderWish, randomPool = {}, {}, {}
	for _, player in ipairs(players) do
		local intent = getRoleIntent(player)
		if intent == "Seeker" then
			table.insert(volunteers, player)
		elseif intent == "Hider" then
			table.insert(hiderWish, player)
		else
			table.insert(randomPool, player)
		end
	end

	-- Заполняем слоты Seeker по приоритету: сначала добровольцы, потом
	-- случайный пул, и только если совсем не хватило (например, все
	-- встали во врата Hider) - из желающих прятаться. "Лишние" добровольцы
	-- (больше желающих, чем слотов) отправляются в Hiders - центр
	-- гарантирует роль только пока есть слоты, а не обещание.
	local seekers = {}
	for _, pool in ipairs({ shuffle(volunteers), shuffle(randomPool), shuffle(hiderWish) }) do
		for _, player in ipairs(pool) do
			if #seekers >= seekersCount then
				break
			end
			table.insert(seekers, player)
		end
	end

	local seekerSet = {}
	for _, player in ipairs(seekers) do
		seekerSet[player] = true
		player.Team = seekersTeam
	end

	local hiders = {}
	for _, player in ipairs(players) do
		if not seekerSet[player] then
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
