-- WhistleService.lua
-- Добровольный свисток-провокация Hiders в фазе поиска: игрок сам решает
-- рискнуть и подать голос, чтобы приманить Seekers - стратегический выбор,
-- а не принудительный анти-кемпинг таймер, как было раньше (пересмотрено,
-- см. DECISIONS.md, п.15 и п.27, MEGA_PLAN 3.2/Q3). Звук намеренно смещён
-- от реальной позиции игрока - оригинал не выдаёт точное место свистнувшего.
-- Есть небольшой бонус очков за смелость, если рядом реально есть Seeker.

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local RoleUtil = require(ReplicatedStorage.Modules.RoleUtil)
-- Только для проверки текущей фазы раунда (RoundManager.State), см.
-- FreezeService.lua - там же комментарий, почему это не создаёт цикл require.
local RoundManager = require(script.Parent.RoundManager)

local WhistleService = {}

local lastWhistleAt = {} -- [Player] = tick() последнего свистка (кулдаун)
local remotesRef
local CatchServiceRef
local ScoreServiceRef

local function sendCountdown(player, cooldownSeconds)
	if remotesRef then
		remotesRef.WhistleCountdownUpdate:FireClient(player, cooldownSeconds)
	end
end

-- Очки за смелость, если хоть один Seeker оказался в радиусе - дешёвая
-- проверка по дистанции (magnitude), БЕЗ raycast: свисток намеренно щедрый,
-- это не честная "видимость", а просто "рискнул рядом с живым Seeker'ом".
local function awardBraveryIfSeekerNearby(player, rootPart)
	if not ScoreServiceRef then
		return
	end

	for _, other in ipairs(Players:GetPlayers()) do
		if RoleUtil.IsSeeker(other) then
			local otherCharacter = other.Character
			local otherRoot = otherCharacter and otherCharacter:FindFirstChild("HumanoidRootPart")
			if otherRoot and (otherRoot.Position - rootPart.Position).Magnitude <= GameConfig.WHISTLE_BRAVERY_RADIUS then
				ScoreServiceRef.AddRoundPoints(player, GameConfig.WHISTLE_BRAVERY_POINTS)
				return
			end
		end
	end
end

-- Проигрывает звук из точки, случайно смещённой от игрока - оригинал
-- намеренно не выдаёт точную позицию свистнувшего. Одноразовая невидимая
-- Part с Sound, самоуничтожается через Debris.
local function playOffsetWhistleSound(rootPart)
	local angle = math.random() * math.pi * 2
	local distance = math.random(GameConfig.WHISTLE_SOUND_OFFSET_MIN, GameConfig.WHISTLE_SOUND_OFFSET_MAX)
	local offset = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)

	local part = Instance.new("Part")
	part.Name = "WhistleSoundSource"
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.CFrame = CFrame.new(rootPart.Position + offset)
	part.Parent = Workspace

	local sound = Instance.new("Sound")
	sound.Name = "WhistleSound"
	sound.SoundId = GameConfig.WHISTLE_SOUND_ID
	sound.Volume = GameConfig.WHISTLE_VOLUME
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = GameConfig.WHISTLE_ROLLOFF_MIN_DISTANCE
	sound.RollOffMaxDistance = GameConfig.WHISTLE_ROLLOFF_MAX_DISTANCE
	sound.Parent = part
	sound:Play()

	Debris:AddItem(part, 4)
end

local function fireWhistle(player)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	playOffsetWhistleSound(rootPart)
	awardBraveryIfSeekerNearby(player, rootPart)

	lastWhistleAt[player] = tick()
	sendCountdown(player, GameConfig.WHISTLE_COOLDOWN_SECONDS)
end

-- Добровольный свисток по запросу клиента - сервер сам решает, разрешено ли
-- это (роль, фаза, не пойман ли, кулдаун), а не доверяет клиенту.
local function onRequestWhistle(player)
	if not RoleUtil.IsHider(player) then
		return
	end

	if RoundManager.State ~= "Seeking" then
		return -- свистеть можно только во время фазы поиска
	end

	if CatchServiceRef and CatchServiceRef.IsFound(player) then
		return -- уже пойман - свистеть незачем
	end

	if tick() - (lastWhistleAt[player] or 0) < GameConfig.WHISTLE_COOLDOWN_SECONDS then
		return
	end

	fireWhistle(player)
end

-- Интерфейс сохранён (зовёт RoundManager), но тело сжато - без автосвистка
-- нечего запускать, кроме сброса кулдаунов прошлого раунда.
function WhistleService.StartSeekingPhase(_hiders)
	lastWhistleAt = {}
end

function WhistleService.EndRound()
	lastWhistleAt = {}
end

function WhistleService.Init(remotes, catchService, scoreService)
	remotesRef = remotes
	CatchServiceRef = catchService
	ScoreServiceRef = scoreService

	remotes.RequestWhistle.OnServerEvent:Connect(onRequestWhistle)

	Players.PlayerRemoving:Connect(function(player)
		lastWhistleAt[player] = nil
	end)
end

return WhistleService
