-- CatchService.lua
-- Отвечает за обнаружение (поимку) прячущихся игроков искателями.
-- Используем ProximityPrompt: сервер сам слушает Triggered у промпта, который
-- существует в игре - это безопасно (не нужен RemoteEvent, который можно
-- подделать), т.к. Roblox передаёт срабатывание ProximityPrompt на сервер
-- напрямую (см. DECISIONS.md, п.4).

local Teams = game:GetService("Teams")
local Players = game:GetService("Players")
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
	prompt.HoldDuration = GameConfig.CATCH_HOLD_DURATION
	prompt.MaxActivationDistance = GameConfig.CATCH_MAX_DISTANCE
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

-- Серверная проверка дистанции между искателем и прячущимся.
-- ВАЖНО: без неё эксплойт fireproximityprompt позволяет "поймать" всех Hiders
-- с любой точки карты, т.к. серверный Triggered срабатывает без учёта дистанции
-- (см. DECISIONS.md, п.4). Здесь мы честно меряем расстояние на сервере.
local function seekerIsCloseEnough(seekerPlayer, hiderPlayer)
	local seekerChar = seekerPlayer.Character
	local hiderChar = hiderPlayer.Character
	if not seekerChar or not hiderChar then
		return false
	end

	local seekerRoot = seekerChar:FindFirstChild("HumanoidRootPart")
	local hiderRoot = hiderChar:FindFirstChild("HumanoidRootPart")
	if not seekerRoot or not hiderRoot then
		return false
	end

	local distance = (seekerRoot.Position - hiderRoot.Position).Magnitude
	local maxAllowed = GameConfig.CATCH_MAX_DISTANCE + GameConfig.CATCH_DISTANCE_TOLERANCE
	return distance <= maxAllowed
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

	-- Защита от эксплойта fireproximityprompt: перепроверяем дистанцию на сервере
	if not seekerIsCloseEnough(seekerPlayer, hiderPlayer) then
		return
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

-- Если прячущийся вышел из игры посреди фазы поиска - убираем его из подсчёта,
-- иначе CountRemaining() никогда не дойдёт до 0 и раунд не завершится досрочно,
-- даже когда всех оставшихся уже нашли.
local function onHiderLeft(player)
	if foundState[player] == nil then
		return -- не участвует в этом раунде как прячущийся
	end

	foundState[player] = nil -- убираем из счёта (не "пойман", просто вышел)

	local prompt = activePrompts[player]
	if prompt then
		prompt:Destroy()
		activePrompts[player] = nil
	end

	if CatchService.CountRemaining() <= 0 and onAllCaughtCallback then
		onAllCaughtCallback()
	end
end

function CatchService.Init(remotes, scoreService)
	remotesRef = remotes
	ScoreServiceRef = scoreService

	Players.PlayerRemoving:Connect(onHiderLeft)
end

return CatchService
