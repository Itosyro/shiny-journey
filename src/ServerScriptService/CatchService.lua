-- CatchService.lua
-- Отвечает за обнаружение (поимку) прячущихся игроков искателями.
-- Используем ProximityPrompt, но серверный Triggered - НЕ источник истины сам по
-- себе (эксплойт fireproximityprompt может вызвать его без реальной близости -
-- см. DECISIONS.md, п.4), поэтому в TryCatch мы дублируем на сервере и дистанцию,
-- и проверку прямого взгляда (line of sight).

local Teams = game:GetService("Teams")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
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
	-- ObjectText намеренно пустой - раньше тут было имя игрока (hiderPlayer.Name),
	-- но это выдавало, кто именно спрятан под маскировкой (см. DECISIONS.md, п.12).
	prompt.HoldDuration = GameConfig.CATCH_HOLD_DURATION
	prompt.MaxActivationDistance = GameConfig.CATCH_MAX_DISTANCE
	-- Требуем прямой взгляд без препятствий (это встроенная клиентская проверка
	-- Roblox - обходится тем же эксплойтом, что и дистанция, поэтому в TryCatch
	-- есть точно такая же проверка через серверный raycast, см. hasLineOfSight).
	prompt.RequiresLineOfSight = true
	prompt.Parent = rootPart

	prompt.Triggered:Connect(function(seekerPlayer)
		CatchService.TryCatch(seekerPlayer, hiderPlayer)
	end)

	activePrompts[hiderPlayer] = prompt
	return prompt
end

-- Вызывается в начале фазы поиска - расставляет промпты на всех Hiders
function CatchService.StartSeekingPhase(hiders)
	foundState = {}
	local allPrompts = {}

	for _, hider in ipairs(hiders) do
		foundState[hider] = false
		local prompt = attachPromptToHider(hider)
		if prompt then
			table.insert(allPrompts, prompt)
		end
	end

	-- Прячем подсказки "Поймать" от самих Hiders: иначе, подойдя друг к другу,
	-- они видят, где стоит другой замаскированный игрок - это убивает смысл
	-- пряток. Отправляем каждому Hider персонально, только на его клиенте
	-- подсказки локально выключаются (Seekers это событие не получают и видят
	-- подсказки как обычно). См. DECISIONS.md, п.12.
	if remotesRef then
		for _, hider in ipairs(hiders) do
			remotesRef.HideCatchPromptsFromHiders:FireClient(hider, allPrompts)
		end
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

-- Серверная проверка прямого взгляда (line of sight) между искателем и прячущимся.
-- ProximityPrompt.RequiresLineOfSight - это только клиентская подсказка (решает,
-- показывать ли кнопку тому конкретному клиенту), её тоже обходит fireproximityprompt,
-- поэтому честную проверку "не через стену ли" делаем на сервере через raycast.
local function hasLineOfSight(seekerPlayer, hiderPlayer)
	local seekerChar = seekerPlayer.Character
	local hiderChar = hiderPlayer.Character
	if not seekerChar or not hiderChar then
		return false
	end

	local seekerHead = seekerChar:FindFirstChild("Head")
	local hiderRoot = hiderChar:FindFirstChild("HumanoidRootPart")
	if not seekerHead or not hiderRoot then
		return false
	end

	local origin = seekerHead.Position
	local toTarget = hiderRoot.Position - origin

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { seekerChar, hiderChar }

	local result = Workspace:Raycast(origin, toTarget, raycastParams)
	-- Если луч долетел до цели, ничего не задев по пути - обзор чист
	return result == nil
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

	-- Защита от эксплойта fireproximityprompt: перепроверяем на сервере и
	-- дистанцию, и прямой взгляд (а не только доверяем клиентскому Triggered)
	if not seekerIsCloseEnough(seekerPlayer, hiderPlayer) then
		return
	end

	if not hasLineOfSight(seekerPlayer, hiderPlayer) then
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
