-- FreezeService.lua
-- Отвечает за позу (набор конкретных пресетов - см. PosePresets.lua). Игрок
-- выбирает один из пресетов ("присесть", "лечь", "прислониться", "замереть
-- стоя"), останавливается на месте, включается анимация именно этого пресета,
-- пока он в позе - не может двигаться и красить
-- (см. PaintService.SetPaintingAllowed и DECISIONS.md, п.5, п.10, п.17).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local PosePresets = require(ReplicatedStorage.Modules.PosePresets)
local RoleUtil = require(ReplicatedStorage.Modules.RoleUtil)
-- Требуется только для проверки текущей фазы раунда (RoundManager.State).
-- Обратной зависимости нет - RoundManager получает сервисы через Init(), а не
-- через require(), так что цикла require здесь не образуется.
local RoundManager = require(script.Parent.RoundManager)

local FreezeService = {}

local frozenState = {} -- [Player] = true/false
local activePose = {}  -- [Player] = поза id (например "Crouch"), только пока frozenState[player] == true
-- Сохраняем исходные параметры движения/hitbox игрока перед заморозкой, чтобы
-- точно вернуть их при разморозке. Раньше JumpHeight обнулялся, но не
-- восстанавливался, из-за чего на современных ригах (UseJumpPower=false)
-- игрок больше не мог прыгать.
local savedLocomotion = {} -- [Player] = { walkSpeed, jumpPower, jumpHeight, hipHeight }
local PaintServiceRef

-- Приоритет анимации позы - Action4 (максимальный, выше обычного Action),
-- чтобы поза гарантированно перебивала вообще любую другую анимацию
-- (ходьба/стойка/будущие анимации-жесты), а не только Movement/Idle. См.
-- DECISIONS.md, п.17 - раньше использовался Action, теперь явный переход
-- на Action4 как более надёжный верхний приоритет.
local POSE_ANIMATION_PRIORITY = Enum.AnimationPriority.Action4

local function stopPoseAnimations(humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end

	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		if track.Priority == POSE_ANIMATION_PRIORITY then
			track:Stop(0.2)
		end
	end
end

-- Визуальный эффект "затвердевания" при входе в позу - встроенный
-- Highlight, ноль кастомного рендера (ponytail), см. DECISIONS.md, п.31.
-- Лимит платформы: одновременно рендерится максимум 31 Highlight на
-- клиенте - у нас пиково ≤24 игроков (GameConfig.MAX_PLAYERS) и каждый
-- Highlight живёт всего 0.6с, так что в любой момент кадра реально
-- активна лишь малая часть - безопасно с большим запасом.
local function playFreezeEffect(character)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.fromRGB(255, 255, 255)
	highlight.FillTransparency = 0.7
	highlight.OutlineTransparency = 1
	highlight.Parent = character

	TweenService:Create(highlight, TweenInfo.new(0.5), { FillTransparency = 1 }):Play()
	Debris:AddItem(highlight, 0.6)

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart then
		local sound = Instance.new("Sound")
		sound.SoundId = GameConfig.FREEZE_SOUND_ID
		sound.Parent = rootPart
		sound:Play()
		Debris:AddItem(sound, 2)
	end
end

local function applyFreeze(player, wantsFreeze, poseId)
	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	frozenState[player] = wantsFreeze

	if wantsFreeze then
		playFreezeEffect(character)

		-- Запоминаем текущие значения ровно один раз (чтобы повторный вызов freeze
		-- - например, переключение на другую позу прямо во время заморозки - не
		-- сохранил уже применённые/обнулённые значения)
		if not savedLocomotion[player] then
			savedLocomotion[player] = {
				walkSpeed = humanoid.WalkSpeed,
				jumpPower = humanoid.JumpPower,
				jumpHeight = humanoid.JumpHeight,
				hipHeight = humanoid.HipHeight,
			}
		end

		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0

		-- Если игрок уже был в другой позе и сразу переключился на новую -
		-- сначала останавливаем старую анимацию, чтобы они не проигрывались
		-- одновременно (Animator такое позволяет, если явно не остановить).
		stopPoseAnimations(humanoid)

		activePose[player] = poseId

		local preset = PosePresets.ById[poseId]

		-- "Hitbox-профиль": грубая имитация физического силуэта конкретного
		-- пресета через Humanoid.HipHeight (работает и на R6, и на R15 - это
		-- свойство базового класса Humanoid). Множитель, а не абсолютное
		-- значение - чтобы не ломать нестандартные по размеру аватары.
		-- Зажимаем снизу, чтобы не уйти в 0/отрицательные значения (физические
		-- глюки, провал под пол).
		if preset then
			local original = savedLocomotion[player].hipHeight
			humanoid.HipHeight = math.max(0.05, original * preset.hipHeightMultiplier)
		end

		-- Проигрываем анимацию именно этого пресета с приоритетом Action4.
		-- animationId пока заглушка (см. PosePresets.lua), поэтому оборачиваем
		-- в pcall - логика заморозки должна работать, даже если анимация не грузится.
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator and preset then
			local animation = Instance.new("Animation")
			animation.AnimationId = preset.animationId
			local ok, track = pcall(function()
				return animator:LoadAnimation(animation)
			end)
			if ok and track then
				track.Priority = POSE_ANIMATION_PRIORITY
				track:Play(0.2)
			end
		end
	else
		-- Возвращаем исходные значения движения/hitbox (или разумные значения по
		-- умолчанию, если по какой-то причине ничего не сохранили)
		local saved = savedLocomotion[player]
		humanoid.WalkSpeed = saved and saved.walkSpeed or 16
		humanoid.JumpPower = saved and saved.jumpPower or 50
		humanoid.JumpHeight = saved and saved.jumpHeight or 7.2
		if saved and saved.hipHeight then
			humanoid.HipHeight = saved.hipHeight
		end
		savedLocomotion[player] = nil
		activePose[player] = nil

		stopPoseAnimations(humanoid)
	end

	if PaintServiceRef then
		PaintServiceRef.SetPaintingAllowed(player, not wantsFreeze)
	end
end

-- Поза - механика только для Hiders, и только пока идёт раунд (Hiding ИЛИ
-- Seeking - см. DECISIONS.md, п.28, пересмотрено MEGA_PLAN 3.2/Q2: раньше
-- Hider не мог переключать позу в Seeking, но сверка с оригиналом
-- подтвердила, что там можно свободно вставать/выходить из позы и во время
-- охоты) - ПЛЮС в лобби (на платформе, см. MEGA_PLAN.md 1.3) она доступна
-- ЛЮБОМУ игроку как тренировка пресетов, роли ещё не розданы. Seekers в
-- раунде к ней не имеют доступа вообще (см. DECISIONS.md, п.13): в
-- оригинале искатели не притворяются мебелью.
local function onRequestFreeze(player, wantsFreeze, poseId)
	if typeof(wantsFreeze) ~= "boolean" then
		return
	end

	local canFreezeNow = RoundManager.State == "Lobby"
		or ((RoundManager.State == "Hiding" or RoundManager.State == "Seeking") and RoleUtil.IsHider(player))
	if not canFreezeNow then
		return
	end

	if wantsFreeze then
		if typeof(poseId) ~= "string" or not PosePresets.ById[poseId] then
			return -- запрошен несуществующий пресет позы
		end
	end

	applyFreeze(player, wantsFreeze, poseId)
end

function FreezeService.IsFrozen(player)
	return frozenState[player] == true
end

function FreezeService.GetActivePose(player)
	return activePose[player]
end

-- Принудительно снять заморозку (например, когда раунд закончился, или Hider
-- пойман в режиме Infection - см. DECISIONS.md, п.18)
function FreezeService.ForceUnfreeze(player)
	if frozenState[player] then
		applyFreeze(player, false)
	end
end

function FreezeService.Init(remotes, paintService)
	PaintServiceRef = paintService
	remotes.RequestFreeze.OnServerEvent:Connect(onRequestFreeze)

	Players.PlayerRemoving:Connect(function(player)
		frozenState[player] = nil
		activePose[player] = nil
		savedLocomotion[player] = nil
	end)

	-- Новый персонаж (например, после кнопки "Reset Character") получает
	-- дефолтные WalkSpeed/JumpPower от Roblox сам по себе, но наше СОСТОЯНИЕ
	-- заморозки о старом теле - нет: без сброса игрок "залипал" замороженным
	-- (paintingBlocked оставался true) до ручного переключения позы. Тут же
	-- не вызываем applyFreeze(false) - новому телу нечего восстанавливать, у
	-- него и так стандартные значения (см. AUDIT_FABLE5.md, V5).
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			frozenState[player] = nil
			activePose[player] = nil
			savedLocomotion[player] = nil
			if PaintServiceRef then
				PaintServiceRef.SetPaintingAllowed(player, true)
			end
		end)
	end)
end

return FreezeService
