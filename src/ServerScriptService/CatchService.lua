-- CatchService.lua
-- Отвечает за обнаружение (поимку) прячущихся игроков искателями.
-- Два режима (GameConfig.CATCH_MODE, см. DECISIONS.md, п.29):
-- "RangedTag" (текущий, по умолчанию) - Seeker стреляет/метит с дистанции,
-- ближе к оригиналу; "Proximity" (старый) - подход вплотную с
-- ProximityPrompt, оставлен как аварийный переключатель до живого теста
-- RangedTag. В Proximity серверный Triggered - НЕ источник истины сам по
-- себе (эксплойт fireproximityprompt может вызвать его без реальной близости -
-- см. DECISIONS.md, п.4), поэтому в TryCatch мы дублируем на сервере и дистанцию,
-- и проверку прямого взгляда (line of sight).

local Teams = game:GetService("Teams")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local LineOfSightUtil = require(script.Parent.LineOfSightUtil)
local RoleUtil = require(ReplicatedStorage.Modules.RoleUtil)
-- Только для проверки текущей фазы раунда (RoundManager.State), см.
-- FreezeService.lua - там же комментарий, почему это не создаёт цикл require.
local RoundManager = require(script.Parent.RoundManager)

local CatchService = {}

local activePrompts = {} -- [Player] = ProximityPrompt (только режим Proximity)
local foundState = {}    -- [Player] = true/false
local lastTagAt = {}     -- [Player] = tick() последней попытки метки (только RangedTag)
local remotesRef
local ScoreServiceRef
local onAllCaughtCallback
local onCatchCallback

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
	-- есть точно такая же проверка через серверный raycast, см. LineOfSightUtil.lua).
	prompt.RequiresLineOfSight = true
	prompt.Parent = rootPart

	prompt.Triggered:Connect(function(seekerPlayer)
		CatchService.TryCatch(seekerPlayer, hiderPlayer)
	end)

	activePrompts[hiderPlayer] = prompt
	return prompt
end

-- Вызывается в начале фазы поиска - помечает всех Hiders как "не найден" и,
-- только в режиме Proximity, расставляет промпты.
function CatchService.StartSeekingPhase(hiders)
	foundState = {}
	lastTagAt = {}

	for _, hider in ipairs(hiders) do
		foundState[hider] = false
	end

	if GameConfig.CATCH_MODE ~= "Proximity" then
		return -- в RangedTag прятать нечего - промптов вообще нет
	end

	local allPrompts = {}
	for _, hider in ipairs(hiders) do
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
	lastTagAt = {}
	onAllCaughtCallback = nil
	onCatchCallback = nil
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

-- Общее для обоих режимов: применяет саму поимку, когда все проверки уже
-- пройдены (роль/фаза/дистанция или raycast - в зависимости от режима).
local function registerCatch(seekerPlayer, hiderPlayer)
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

	-- Даёт RoundManager шанс отреагировать на конкретную поимку (например,
	-- перевести пойманного в Seekers в режиме Infection - см. DECISIONS.md,
	-- п.18) ДО проверки "все ли найдены", чтобы переход роли гарантированно
	-- успел примениться, даже если это была поимка последнего Hider.
	if onCatchCallback then
		onCatchCallback(hiderPlayer, seekerPlayer)
	end

	if CatchService.CountRemaining() <= 0 and onAllCaughtCallback then
		onAllCaughtCallback()
	end
end

-- Режим Proximity (аварийный переключатель, см. DECISIONS.md, п.29) -
-- вызывается из Triggered промпта.
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
	-- дистанцию, и прямой взгляд (а не только доверяем клиентскому Triggered).
	-- ВАЖНО (см. DECISIONS.md, п.4): без этой проверки читер мог бы "поймать"
	-- всех Hiders с любой точки карты, т.к. серверный Triggered срабатывает
	-- без учёта дистанции. ProximityPrompt.RequiresLineOfSight - только
	-- клиентская подсказка, тоже обходится тем же эксплойтом, поэтому честную
	-- проверку "не через стену ли" всегда дублируем на сервере.
	local maxCatchDistance = GameConfig.CATCH_MAX_DISTANCE + GameConfig.CATCH_DISTANCE_TOLERANCE
	if not LineOfSightUtil.IsWithinDistance(seekerPlayer, hiderPlayer, maxCatchDistance) then
		return
	end

	if not LineOfSightUtil.HasLineOfSight(seekerPlayer, hiderPlayer) then
		return
	end

	registerCatch(seekerPlayer, hiderPlayer)
end

-- Режим RangedTag (текущий, см. DECISIONS.md, п.29) - Seeker "стреляет"
-- направлением камеры; сервер сам считает origin и raycast, клиенту
-- доверяем только направление (юнит-вектор - непроверяемая честная
-- граница доверия, как у любого шутера).
local function onRequestTag(seekerPlayer, direction)
	if typeof(direction) ~= "Vector3" then
		return
	end

	local magnitude = direction.Magnitude
	if magnitude < 0.99 or magnitude > 1.01 then
		return -- не юнит-вектор - подозрительный пакет
	end

	if not RoleUtil.IsSeeker(seekerPlayer) then
		return
	end

	if RoundManager.State ~= "Seeking" then
		return
	end

	if tick() - (lastTagAt[seekerPlayer] or 0) < GameConfig.TAG_COOLDOWN_SECONDS then
		return -- рейт-лимит: не чаще одной попытки в TAG_COOLDOWN_SECONDS
	end
	lastTagAt[seekerPlayer] = tick()

	local character = seekerPlayer.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end

	-- Origin - серверная позиция головы стрелка (НЕ присланная клиентом!) -
	-- иначе читер мог бы "стрелять" из чужой/произвольной точки карты.
	-- Exclude - ТОЛЬКО персонаж стрелка: мы ХОТИМ попасть в чужие тела.
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { character }

	local result = Workspace:Raycast(head.Position, direction * GameConfig.TAG_MAX_DISTANCE, raycastParams)

	if result and result.Instance then
		local hitCharacter = result.Instance:FindFirstAncestorOfClass("Model")
		local hitPlayer = hitCharacter and Players:GetPlayerFromCharacter(hitCharacter)
		if hitPlayer and RoleUtil.IsHider(hitPlayer) and foundState[hitPlayer] == false then
			registerCatch(seekerPlayer, hitPlayer)
			return
		end
	end

	-- Промах: луч ни во что не попал, попал в мир/декорации, или попал в
	-- уже найденного Hider'а/не-игрока - простое правило "не попал в живую
	-- цель = промах", штрафуем очки.
	if ScoreServiceRef then
		ScoreServiceRef.AddRoundPoints(seekerPlayer, -GameConfig.TAG_MISS_PENALTY_POINTS)
	end
end

-- Регистрирует функцию, которая вызовется, когда найдены все Hiders (для досрочного завершения раунда)
function CatchService.OnAllCaught(callback)
	onAllCaughtCallback = callback
end

-- Регистрирует функцию, которая вызовется при КАЖДОЙ поимке с (hiderPlayer, seekerPlayer)
function CatchService.OnCatch(callback)
	onCatchCallback = callback
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

-- Если Hider нажал "Reset Character" посреди фазы поиска - старый
-- ProximityPrompt пропадает вместе со старым телом, и до этого фикса
-- CatchService переставал давать Seekers возможность поймать этого игрока
-- (foundState оставался false, но ловить было физически нечего) - раунд в
-- Infection не мог закончиться, если оставался только ресетнувшийся Hider.
-- Перевешиваем промпт на новое тело и снова прячем его от других Hiders.
-- См. AUDIT_FABLE5.md, K1. Актуально ТОЛЬКО для режима Proximity - в
-- RangedTag промптов нет вообще, перевешивать нечего (raycast и так бьёт
-- по актуальному персонажу через Players:GetPlayerFromCharacter).
local function onCharacterRespawn(player)
	if GameConfig.CATCH_MODE ~= "Proximity" then
		return
	end

	if foundState[player] ~= false then
		return -- не участвует в этом раунде как непойманный Hider
	end

	task.defer(function()
		local character = player.Character
		if not character then
			return
		end
		if not character:FindFirstChild("HumanoidRootPart") then
			character:WaitForChild("HumanoidRootPart", 5)
		end

		local prompt = attachPromptToHider(player)
		if not prompt or not remotesRef then
			return
		end

		-- Тот же приём, что в StartSeekingPhase: прячем новый промпт от всех
		-- Hiders, чтобы ресет персонажа не выдал позицию другим прячущимся.
		for _, otherPlayer in ipairs(Players:GetPlayers()) do
			if RoleUtil.IsHider(otherPlayer) then
				remotesRef.HideCatchPromptsFromHiders:FireClient(otherPlayer, { prompt })
			end
		end
	end)
end

function CatchService.Init(remotes, scoreService)
	remotesRef = remotes
	ScoreServiceRef = scoreService

	if GameConfig.CATCH_MODE == "RangedTag" then
		remotes.RequestTag.OnServerEvent:Connect(onRequestTag)
	end

	Players.PlayerRemoving:Connect(onHiderLeft)
	Players.PlayerRemoving:Connect(function(player)
		lastTagAt[player] = nil
	end)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			onCharacterRespawn(player)
		end)
	end)
end

return CatchService
