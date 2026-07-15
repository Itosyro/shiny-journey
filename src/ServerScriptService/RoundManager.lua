-- RoundManager.lua
-- Главный "мозг" игры: управляет фазами раунда
-- Lobby -> Hiding -> Seeking -> RoundEnd -> (заново).
-- Никакой другой скрипт не должен сам менять фазу - только через этот модуль.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
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

-- Телепортирует список игроков к заданной Part (используется для лобби-
-- платформы Seekers, findSpawnByName("SeekerWaitingRoom") - см. MapBuilder.lua).
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

-- Как teleportPlayersTo, но для Hiders, у которых нет одной общей точки -
-- каждому достаётся случайный маркер из списка (см. MapBuilder.
-- HiderSpawn×8, MEGA_PLAN.md 1.1.7).
local function teleportPlayersToRandomOf(playersList, parts)
	if #parts == 0 then
		return
	end
	for _, player in ipairs(playersList) do
		local character = player.Character
		if character and character:FindFirstChild("HumanoidRootPart") then
			local part = parts[math.random(1, #parts)]
			character.HumanoidRootPart.CFrame = part.CFrame + Vector3.new(0, 3, 0)
		end
	end
end

-- ВАЖНО: все маркеры MapBuilder (SeekerWaitingRoom, HiderSpawn и т.д.)
-- лежат внутри Workspace.Map (см. MapBuilder.Build), а не прямо в
-- Workspace - раньше здесь было Workspace:FindFirstChild(name), что НИКОГДА
-- не находило маркер (он на уровень глубже) и teleportPlayersTo молча
-- ничего не делал. Найдено при реализации лобби-платформы (MEGA_PLAN.md,
-- Часть 1) - тот же паттерн поиска, что уже был в SpectatorService.lua.
local function findSpawnByName(name)
	local mapFolder = Workspace:FindFirstChild("Map")
	return mapFolder and mapFolder:FindFirstChild(name)
end

-- Эффект телепортации Seekers с лобби-платформы на карту при переходе
-- Hiding→Seeking - частицы + твин прозрачности + одновременный телепорт
-- всех разом (см. MEGA_PLAN.md 1.6). Локальная функция, а не новый
-- модуль - один потребитель (ponytail). ТОЛЬКО для этого перехода:
-- телепорт Hiders в начале Hiding - мгновенный, без эффекта (их больше,
-- и это дешевле).
local function teleportWithEffect(playersList, targetParts)
	if #targetParts == 0 then
		return
	end

	local emitters = {}

	-- Шаги 1-2 (искры + твин "исчезновения") - один проход по ВСЕМ Seekers
	-- одновременно, без task.wait между игроками - иначе они пропадали бы
	-- по очереди, а не разом.
	for _, player in ipairs(playersList) do
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if rootPart then
			local emitter = Instance.new("ParticleEmitter")
			emitter.Rate = 0 -- частицы только вручную через Emit(), не поток
			emitter.Lifetime = NumberRange.new(0.4, 0.7)
			emitter.Speed = NumberRange.new(3, 6)
			emitter.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
			-- Texture НЕ задаём - у ParticleEmitter есть встроенная искра,
			-- своя заглушка-ассет тут не нужна.
			emitter.Parent = rootPart
			emitter:Emit(25)
			emitters[player] = emitter

			-- HumanoidRootPart не трогаем - он и так всегда Transparency=1.
			for _, part in ipairs(character:GetDescendants()) do
				if part:IsA("BasePart") and part ~= rootPart then
					TweenService:Create(part, TweenInfo.new(GameConfig.TELEPORT_EFFECT_SECONDS), { Transparency = 1 }):Play()
				end
			end
		end
	end

	task.wait(GameConfig.TELEPORT_EFFECT_SECONDS)

	teleportPlayersToRandomOf(playersList, targetParts)

	-- Шаги 5 (обратный твин + вторая вспышка) - снова одним проходом по всем.
	for _, player in ipairs(playersList) do
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if rootPart then
			local emitter = emitters[player]
			if emitter then
				emitter:Emit(25)
				Debris:AddItem(emitter, 2)
			end

			for _, part in ipairs(character:GetDescendants()) do
				if part:IsA("BasePart") and part ~= rootPart then
					TweenService:Create(part, TweenInfo.new(GameConfig.TELEPORT_EFFECT_SECONDS), { Transparency = 0 }):Play()
				end
			end
		end
	end
end

-- Собирает ВСЕ части с именем name внутри Workspace.Map (не GetDescendants -
-- вся геометрия карты лежит плоско прямо в папке Map, см. MapBuilder.lua).
local function findAllSpawnsByName(name)
	local mapFolder = Workspace:FindFirstChild("Map")
	if not mapFolder then
		return {}
	end

	local result = {}
	for _, child in ipairs(mapFolder:GetChildren()) do
		if child.Name == name then
			table.insert(result, child)
		end
	end
	return result
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

	-- Экс-зритель, только что ставший Seeker, ещё может не иметь персонажа
	-- (LoadCharacter из SpectatorService.ExitSpectator асинхронный) - без
	-- ожидания teleportPlayersTo молча пропустил бы такого игрока, и он
	-- остался бы бегать по карте всю фазу пряток, увидев всех Hiders живьём.
	-- Максимум 2с на игрока, вышедших пропускаем по seeker.Parent == nil.
	for _, seeker in ipairs(currentSeekers) do
		for _ = 1, 20 do
			if seeker.Character ~= nil or seeker.Parent == nil then
				break
			end
			task.wait(0.1)
		end
	end

	-- Искателей телепортируем на лобби-платформу - там они свободно ходят,
	-- тренируют кисть/позы и ждут (WalkSpeed НЕ отнимаем: сбежать некуда,
	-- платформу окружают стены из MapBuilder.buildLobbyPlatform, а красить
	-- в Hiding им всё равно запрещает RoleUtil.IsHider в PaintService -
	-- см. MEGA_PLAN.md 1.5).
	teleportPlayersTo(currentSeekers, findSpawnByName("SeekerWaitingRoom"))

	-- Прячущихся спускаем с лобби-платформы на карту здания - каждому
	-- случайный маркер HiderSpawn (см. MapBuilder.lua, MEGA_PLAN.md 1.1.7).
	teleportPlayersToRandomOf(currentHiders, findAllSpawnsByName("HiderSpawn"))

	-- Прячущимся сбрасываем краску (стираем мазки прошлого раунда) и разрешаем
	-- красить/двигаться
	for _, hider in ipairs(currentHiders) do
		services.PaintService.ResetForNewRound(hider)
		services.PaintService.SetPaintingAllowed(hider, true)
	end

	runTimer(GameConfig.HIDING_PHASE_DURATION)
end

local function runSeekingPhase()
	-- Seekers растворяются на платформе и материализуются у входа в
	-- здание - частицы + твин прозрачности, все одновременно (см.
	-- MEGA_PLAN.md 1.6). WalkSpeed отдельно восстанавливать не нужно - в
	-- Hiding он не отнимался (см. runHidingPhase, MEGA_PLAN.md 1.5).
	teleportWithEffect(currentSeekers, findAllSpawnsByName("SeekerSpawn"))

	-- Hiders больше НЕ теряют доступ к покраске в фазу поиска - подтверждено
	-- сверкой с оригиналом, что докраска и движение продолжаются после
	-- начала охоты (см. DECISIONS.md, п.28, MEGA_PLAN 3.2/Q2). Сам механизм
	-- SetPaintingAllowed остаётся - им пользуется заморозка (FreezeService).

	services.ScoreService.StartRoundTracking(currentHiders, currentSeekers)
	services.ScoreService.StartMissedPointTracking()
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
		if GameMode.GetCurrent() ~= GameMode.Infection then
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

	services.ScoreService.EndMissedPointTracking()
	local results = services.ScoreService.BuildRoundResults(currentHiders, currentSeekers)
	services.CatchService.EndRound()
	services.WhistleService.EndRound()

	-- Итоги едут внутри extra.results того же RoundStateChanged - отдельный
	-- RoundResults:FireAllClients был лишним вторым путём доставки одних и
	-- тех же данных (см. AUDIT_FABLE5.md, S3).
	broadcastState("RoundEnd", GameConfig.ROUND_END_DISPLAY_DURATION, { results = results })

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

			-- Поза доступна прямо в лобби для тренировки (MEGA_PLAN.md 1.3) -
			-- без этого игрок мог бы войти в раунд всё ещё замороженным с
			-- платформы (unfreeze раньше делался только в конце раунда, лобби
			-- он не покрывал).
			for _, player in ipairs(getAvailablePlayers()) do
				services.FreezeService.ForceUnfreeze(player)
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
				services.ScoreService.EndMissedPointTracking()
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

-- Игрок, вышедший посреди раунда, иначе остаётся призраком в currentHiders/
-- currentSeekers - попадает на экран итогов и в BuildRoundResults, хотя его
-- уже нет на сервере. Обратный цикл, чтобы не пропустить элемент при сдвиге
-- индексов после table.remove (см. AUDIT_FABLE5.md, V3).
local function removeFromRoleLists(player)
	for i = #currentHiders, 1, -1 do
		if currentHiders[i] == player then
			table.remove(currentHiders, i)
		end
	end

	for i = #currentSeekers, 1, -1 do
		if currentSeekers[i] == player then
			table.remove(currentSeekers, i)
		end
	end
end

-- Смена режима на следующий раунд (см. GameMode.lua, DECISIONS.md, п.30) -
-- любой игрок в лобби может переключить, применяется только на СЛЕДУЮЩИЙ
-- раунд (calculateSeekersCount/OnCatch и так уже читают режим один раз в
-- нужный момент, никакой mid-round-мутации не бывает). Голосование не
-- делаем (YAGNI) - последний нажавший выигрывает.
local function onRequestGameMode(_player, mode)
	if RoundManager.State ~= "Lobby" then
		return
	end

	if mode ~= GameMode.Classic and mode ~= GameMode.Infection then
		return -- не из белого списка - подозрительный пакет
	end

	GameMode.SetCurrent(mode)
end

function RoundManager.Init(remotes, injectedServices)
	remotesRef = remotes
	services = injectedServices

	remotes.RequestGameMode.OnServerEvent:Connect(onRequestGameMode)

	Players.PlayerRemoving:Connect(removeFromRoleLists)
end

function RoundManager.Start()
	task.spawn(gameLoop)
end

return RoundManager
