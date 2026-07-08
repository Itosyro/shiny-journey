-- WhistleService.lua
-- Автоматический свисток Hiders в фазе поиска: каждые WHISTLE_AUTO_INTERVAL_SECONDS
-- секунд молчания у каждого Hider срабатывает звук, слышимый в радиусе - см.
-- DECISIONS.md, п.15. Hider может свистнуть вручную раньше - это сбрасывает
-- таймер ещё на полный интервал (стратегический выбор: рискнуть сейчас, пока
-- искателя нет рядом, или подождать и понадеяться, что автосвисток сработает
-- в более безопасный момент).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local RoleUtil = require(ReplicatedStorage.Modules.RoleUtil)

local WhistleService = {}

local nextWhistleAt = {} -- [Player] = tick(), когда сработает следующий свисток
local whistleSounds = {} -- [Player] = Sound (создаётся один раз и переиспользуется)
local lastManualWhistleAt = {} -- [Player] = tick() последнего РУЧНОГО свистка (антиспам)
local remotesRef
local CatchServiceRef

-- Увеличивается на каждый StartSeekingPhase/EndRound, чтобы предыдущий фоновый
-- цикл watchLoop сам понял, что раунд закончился, и не работал поверх нового.
local roundToken = 0

local function sendCountdown(player, secondsLeft)
	if remotesRef then
		remotesRef.WhistleCountdownUpdate:FireClient(player, math.max(0, math.floor(secondsLeft)))
	end
end

-- Проигрывает звук свистка - позиционный 3D Sound с ограничением дальности
-- (RollOff), поэтому его слышно только игрокам поблизости, а не всему серверу.
local function playWhistleSound(player)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	local sound = whistleSounds[player]
	if not sound or sound.Parent ~= rootPart then
		sound = Instance.new("Sound")
		sound.Name = "WhistleSound"
		sound.SoundId = GameConfig.WHISTLE_SOUND_ID
		sound.Volume = GameConfig.WHISTLE_VOLUME
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = GameConfig.WHISTLE_ROLLOFF_MIN_DISTANCE
		sound.RollOffMaxDistance = GameConfig.WHISTLE_ROLLOFF_MAX_DISTANCE
		sound.Parent = rootPart
		whistleSounds[player] = sound
	end

	sound:Play()
end

-- Сбрасывает таймер игрока на полный интервал и сразу проигрывает звук.
-- Используется и автосвистком, и ручным запросом от клиента.
local function fireWhistle(player)
	playWhistleSound(player)
	nextWhistleAt[player] = tick() + GameConfig.WHISTLE_AUTO_INTERVAL_SECONDS
	sendCountdown(player, GameConfig.WHISTLE_AUTO_INTERVAL_SECONDS)
end

-- Ручной свисток по запросу клиента - сервер сам решает, разрешено ли это
-- (роль, активна ли фаза поиска, не пойман ли уже), а не доверяет клиенту.
local function onRequestWhistle(player)
	if not RoleUtil.IsHider(player) then
		return
	end

	if nextWhistleAt[player] == nil then
		return -- свисток сейчас не активен (не фаза поиска)
	end

	if CatchServiceRef and CatchServiceRef.IsFound(player) then
		return -- уже пойман - свистеть незачем
	end

	-- Без кулдауна спам-клики по кнопке "Свистнуть" проигрывали бы звук
	-- заново на каждый клик (см. AUDIT_FABLE5.md, S1).
	if tick() - (lastManualWhistleAt[player] or 0) < GameConfig.WHISTLE_MANUAL_COOLDOWN_SECONDS then
		return
	end
	lastManualWhistleAt[player] = tick()

	fireWhistle(player)
end

-- Фоновый цикл: раз в секунду проверяет всех Hiders текущего раунда, шлёт им
-- обновление обратного отсчёта и запускает автосвисток, если время вышло.
local function watchLoop(hiders, myToken)
	while myToken == roundToken do
		for _, hider in ipairs(hiders) do
			local deadline = nextWhistleAt[hider]
			if deadline then
				if CatchServiceRef and CatchServiceRef.IsFound(hider) then
					nextWhistleAt[hider] = nil -- поймали - таймер больше не нужен
				else
					local secondsLeft = deadline - tick()
					if secondsLeft <= 0 then
						fireWhistle(hider)
					else
						sendCountdown(hider, secondsLeft)
					end
				end
			end
		end

		task.wait(1)
	end
end

-- Вызывается в начале фазы поиска - запускает таймеры свистка для всех Hiders
function WhistleService.StartSeekingPhase(hiders)
	roundToken += 1
	local myToken = roundToken

	local now = tick()
	for _, hider in ipairs(hiders) do
		nextWhistleAt[hider] = now + GameConfig.WHISTLE_AUTO_INTERVAL_SECONDS
		sendCountdown(hider, GameConfig.WHISTLE_AUTO_INTERVAL_SECONDS)
	end

	task.spawn(watchLoop, hiders, myToken)
end

-- Останавливает фоновый цикл (через смену токена) и сбрасывает таймеры в конце раунда
function WhistleService.EndRound()
	roundToken += 1
	nextWhistleAt = {}
end

function WhistleService.Init(remotes, catchService)
	remotesRef = remotes
	CatchServiceRef = catchService

	remotes.RequestWhistle.OnServerEvent:Connect(onRequestWhistle)

	Players.PlayerRemoving:Connect(function(player)
		nextWhistleAt[player] = nil
		whistleSounds[player] = nil
		lastManualWhistleAt[player] = nil
	end)
end

return WhistleService
