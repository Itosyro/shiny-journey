-- CatchService.lua
-- Отвечает за обнаружение (поимку) прячущихся игроков искателями.
-- Используем ProximityPrompt: сервер сам слушает Triggered у промпта, который
-- существует в игре - это безопасно (не нужен RemoteEvent, который можно
-- подделать), т.к. Roblox передаёт срабатывание ProximityPrompt на сервер
-- напрямую (см. DECISIONS.md, п.4).

local Teams = game:GetService("Teams")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local CatchService = {}

local activePrompts = {} -- [Player] = ProximityPrompt
local foundState = {}    -- [Player] = true/false
local remotesRef
local ScoreServiceRef
local onAllCaughtCallback

local function attachPromptToHider(hiderPlayer)
	local character = hiderPlayer.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	-- Если промпт уже есть (например, от прошлого раунда) - убираем его
	local old = activePrompts[hiderPlayer]
	if old then
		old:Destroy()
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CatchPrompt"
	prompt.ActionText = "Поймать"
	prompt.ObjectText = hiderPlayer.Name
	prompt.HoldDuration = 0.6
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false -- прячущийся может быть скрыт декорацией
	prompt.Parent = rootPart

	prompt.Triggered:Connect(function(seekerPlayer)
		CatchService.TryCatch(seekerPlayer, hiderPlayer)
	end)

	activePrompts[hiderPlayer] = prompt
end

-- Вызывается в начале фазы поиска - расставляет промпты на всех Hiders
function CatchService.StartSeekingPhase(hiders)
	foundState = {}
	for _, hider in ipairs(hiders) do
		foundState[hider] = false
		attachPromptToHider(hider)
	end
end

-- Убираем все промпты в конце раунда
function CatchService.EndRound()
	for _, prompt in pairs(activePrompts) do
		if prompt then
			prompt:Destroy()
		end
	end
	activePrompts = {}
	foundState = {}
	onAllCaughtCallback = nil
end

function CatchService.CountRemaining()
	local remaining = 0
	for _, found in pairs(foundState) do
		if not found then
			remaining += 1
		end
	end
	return remaining
end

function CatchService.IsFound(player)
	return foundState[player] == true
end

function CatchService.TryCatch(seekerPlayer, hiderPlayer)
	-- Проверяем на сервере, что всё по-честному: искатель - правда искатель,
	-- а найденный - правда прячущийся и ещё не найден
	local seekersTeam = Teams:FindFirstChild(GameConfig.TEAM_SEEKERS_NAME)
	if not seekersTeam or seekerPlayer.Team ~= seekersTeam then
		return
	end

	if foundState[hiderPlayer] ~= false then
		return -- уже найден или не участвует в этом раунде
	end

	foundState[hiderPlayer] = true

	local prompt = activePrompts[hiderPlayer]
	if prompt then
		prompt.Enabled = false
	end

	if ScoreServiceRef then
		ScoreServiceRef.OnHiderCaught(hiderPlayer, seekerPlayer)
	end

	if remotesRef then
		remotesRef.PlayerCaught:FireAllClients(hiderPlayer.Name, seekerPlayer.Name, CatchService.CountRemaining())
	end

	if CatchService.CountRemaining() <= 0 and onAllCaughtCallback then
		onAllCaughtCallback()
	end
end

-- Регистрирует функцию, которая вызовется, когда найдены все Hiders (для досрочного завершения раунда)
function CatchService.OnAllCaught(callback)
	onAllCaughtCallback = callback
end

function CatchService.Init(remotes, scoreService)
	remotesRef = remotes
	ScoreServiceRef = scoreService
end

return CatchService
