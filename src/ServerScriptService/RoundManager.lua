-- RoundManager.lua
-- Главный "мозг" игры: управляет фазами раунда
-- Lobby -> Hiding -> Seeking -> RoundEnd -> (заново).
-- Никакой другой скрипт не должен сам менять фазу - только через этот модуль.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local GameMode = require(ReplicatedStorage.Modules.GameMode)

local RoundManager = {}

RoundManager.State = "Lobby" -- Lobby | Hiding | Seeking | RoundEnd

local remotesRef
local services -- {PlayerRoleService, PaintService, FreezeService, CatchService, ScoreService, WhistleService, SpectatorService}

local currentHiders = {}
local currentSeekers = {}

local function broadcastState(state, timeLeft, extra)
	RoundManager.State = state
	remotesRef.RoundStateChanged:FireAllClients(state, timeLeft, extra or {})
end

-- Запускает таймер на duration секунд, каждую секунду шлёт тик всем клиентам.
-- earlyExitFn - необязательная функция; если возвращает true, таймер прерывается раньше времени.
local function runTimer(duration, earlyExitFn)
	local remaining = duration
	while remaining > 0 do
		remotesRef.RoundTimerTick:FireAllClients(remaining)
		task.wait(1)
		remaining -= 1
		if earlyExitFn and earlyExitFn() then
			return
		end
	end
end

local function getAvailablePlayers()
	return Players:GetPlayers()
end

-- Ждём, пока в лобби не наберётся минимум игроков
local function waitForEnoughPlayers()
	while #getAvailablePlayers() < GameConfig.MIN_PLAYERS_TO_START do
		broadcastState("Lobby", 0, {
			playersNeeded = GameConfig.MIN_PLAYERS_TO_START,
			playersCurrent = #getAvailablePlayers(),
		})
		task.wait(2)
	end
end

-- Телепортирует список игроков к заданной Part (используется для "комнаты ожидания" искателей)
-- См. DECISIONS.md, п.9 - Part с именем SeekerWaitingRoom нужно создать вручную в Workspace.
local function teleportPlayersTo(playersList, part)
	if not part then
		return
	end
	for _, player in ipairs(playersList) do
		local character = player.Character
		if character and character:FindFirstChild("HumanoidRootPart") then
			character.HumanoidRootPart.CFrame = part.CFrame + Vector3.new(0, 3, 0)
		end
	end
end

local function findSpawnByName(name)
	return Workspace:FindFirstChild(name)
end

local function setWalkable(player, canWalk)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = canWalk and 16 or 0
		humanoid.JumpPower = canWalk and 50 or 0
	end
end

local function runHidingPhase()
	broadcastState("Hiding", GameConfig.HIDING_PHASE_DURATION)

	-- Искателей запираем в комнате ожидания на время пряток
	teleportPlayersTo(currentSeekers, findSpawnByName("SeekerWaitingRoom"))
	for _, seeker in ipairs(currentSeekers) do
		setWalkable(seeker, false)
	end

	-- Прячущимся сбрасываем краску (стираем мазки прошлого раунда) и разрешаем
	-- красить/двигаться
	for _, hider in ipairs(currentHiders) do
		services.PaintService.ResetForNewRound(hider)
		services.PaintService.SetPaintingAllowed(hider, true)
	end

	runTimer(GameConfig.HIDING_PHASE_DURATION)
end

local function runSeekingPhase()
	-- Освобождаем искателей
	for _, seeker in ipairs(currentSeekers) do
		setWalkable(seeker, true)
	end

	-- Прячущиеся больше не могут красить - маскировка "заморожена" на время поиска
	for _, hider in ipairs(currentHiders) do
		services.PaintService.SetPaintingAllowed(hider, false)
	end

	services.ScoreService.StartRoundTracking(currentHiders, currentSeekers)
	services.CatchService.StartSeekingPhase(currentHiders)
	services.WhistleService.StartSeekingPhase(currentHiders)

	local allCaught = false
	services.CatchService.OnAllCaught(function()
		allCaught = true
	end)

	-- Режим Infection (по умолчанию, см. GameMode.lua и DECISIONS.md, п.18):
	-- пойманный Hider не выбывает в Spectators, а сразу продолжает раунд как
	-- Seeker. В режиме Classic этот обработчик ничего не делает - пойманный
	-- просто остаётся "найденным" до конца раунда, как и раньше.
	services.CatchService.OnCatch(function(hiderPlayer, seekerPlayer)
		if GameMode.Current ~= GameMode.Infection then
			return
		end

		-- Мгновенно снимаем позу и стираем маскировку (мазки кисти), чтобы
		-- пойманный не путал остальных Seekers остатками своего "костюма"
		services.FreezeService.ForceUnfreeze(hiderPlayer)
		services.PaintService.ClearAllPaint(hiderPlayer)

		-- Меняем команду - CatchService.TryCatch проверяет player.Team ==
		-- Seekers, так что с этого момента новый Seeker уже может ловить
		-- остальных без каких-либо дополнительных прав
		services.PlayerRoleService.ConvertHiderToSeeker(hiderPlayer)
		setWalkable(hiderPlayer, true)

		-- Переносим игрока из currentHiders в currentSeekers для остатка раунда
		-- (влияет на runRoundEnd: он получит роль "Seeker" в результатах, а не
		-- "Hider" - что и есть honest отражение того, как он доиграл раунд)
		for i, existingHider in ipairs(currentHiders) do
			if existingHider == hiderPlayer then
				table.remove(currentHiders, i)
				break
			end
		end
		table.insert(currentSeekers, hiderPlayer)
	end)

	broadcastState("Seeking", GameConfig.SEEKING_PHASE_DURATION)
	runTimer(GameConfig.SEEKING_PHASE_DURATION, function()
		return allCaught
	end)
end

local function runRoundEnd()
	-- Снимаем позы со всех прячущихся, чтобы никто не остался замороженным в лобби
	for _, hider in ipairs(currentHiders) do
		services.FreezeService.ForceUnfreeze(hider)
	end

	-- Начисляем очки выживания тем, кого не поймали
	for _, hider in ipairs(currentHiders) do
		if not services.CatchService.IsFound(hider) then
			services.ScoreService.OnHiderSurvived(hider)
		end
	end

	local results = services.ScoreService.BuildRoundResults(currentHiders, currentSeekers)
	services.CatchService.EndRound()
	services.WhistleService.EndRound()

	broadcastState("RoundEnd", GameConfig.ROUND_END_DISPLAY_DURATION, { results = results })
	remotesRef.RoundResults:FireAllClients(results)

	runTimer(GameConfig.ROUND_END_DISPLAY_DURATION)

	-- Возвращаем всех в наблюдатели на время следующего лобби - роли назначатся заново.
	-- Игрокам в полном режиме зрителя (SpectatorService, DECISIONS.md п.21) не
	-- возвращаем WalkSpeed - их HumanoidRootPart всё ещё заанкорен, а движением
	-- управляет SpectatorClient напрямую через CFrame, обычная ходьба тут не нужна
	-- и не должна путать состояние Humanoid до самого следующего ExitSpectator.
	for _, player in ipairs(getAvailablePlayers()) do
		services.PlayerRoleService.SetSpectator(player)
		if not services.SpectatorService.IsSpectating(player) then
			setWalkable(player, true)
		end
	end
end

local function gameLoop()
	while true do
		waitForEnoughPlayers()

		broadcastState("Lobby", GameConfig.LOBBY_COUNTDOWN_SECONDS)
		runTimer(GameConfig.LOBBY_COUNTDOWN_SECONDS, function()
			return #getAvailablePlayers() < GameConfig.MIN_PLAYERS_TO_START
		end)

		if #getAvailablePlayers() >= GameConfig.MIN_PLAYERS_TO_START then
			currentHiders, currentSeekers = services.PlayerRoleService.AssignRoles(getAvailablePlayers())

			-- Всем, кому только что назначили роль Hider/Seeker (то есть всем
			-- доступным игрокам - AssignRoles распределяет их без остатка),
			-- снимаем режим зрителя - на случай, если кто-то из них зашёл на
			-- сервер посреди прошлого раунда и до сих пор летает (см.
			-- SpectatorService.lua, DECISIONS.md, п.21). Делаем это именно тут,
			-- пока RoundManager.State ещё "Lobby" - ExitSpectator вызывает
			-- LoadCharacter, а обработчик CharacterAdded в SpectatorService.Init
			-- проверяет команду игрока, которую AssignRoles выше уже выставил.
			for _, player in ipairs(getAvailablePlayers()) do
				services.SpectatorService.ExitSpectator(player)
			end

			-- Оборачиваем раунд в pcall: если внутри фазы случится ошибка, весь игровой
			-- цикл не должен умереть навсегда (иначе сервер зависнет без раундов).
			-- При ошибке делаем аварийную уборку и возвращаемся в лобби.
			local ok, err = pcall(function()
				runHidingPhase()
				runSeekingPhase()
				runRoundEnd()
			end)

			if not ok then
				warn("[MecchaChameleon] Ошибка в раунде, сбрасываю в лобби: " .. tostring(err))
				services.CatchService.EndRound()
				services.WhistleService.EndRound()
				for _, player in ipairs(getAvailablePlayers()) do
					services.FreezeService.ForceUnfreeze(player)
					services.PlayerRoleService.SetSpectator(player)
					if not services.SpectatorService.IsSpectating(player) then
						setWalkable(player, true)
					end
				end
			end
		end
	end
end

function RoundManager.Init(remotes, injectedServices)
	remotesRef = remotes
	services = injectedServices
end

function RoundManager.Start()
	task.spawn(gameLoop)
end

return RoundManager
