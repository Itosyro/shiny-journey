-- FreezeService.lua
-- Отвечает за "заморозку" (позу). Игрок останавливается на месте, включается
-- анимация позы, пока он заморожен - не может двигаться и красить
-- (см. PaintService.SetPaintingAllowed и DECISIONS.md, п.5 и п.10).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local FreezeService = {}

local frozenState = {} -- [Player] = true/false
local PaintServiceRef

local function applyFreeze(player, wantsFreeze)
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
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0

		-- Проигрываем анимацию позы с высоким приоритетом, чтобы она перебивала
		-- обычную анимацию ходьбы/стойки. POSE_ANIMATION_ID пока заглушка (см. GameConfig.lua),
		-- поэтому оборачиваем в pcall - логика заморозки должна работать, даже если анимация не грузится.
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			local animation = Instance.new("Animation")
			animation.AnimationId = GameConfig.POSE_ANIMATION_ID
			local ok, track = pcall(function()
				return animator:LoadAnimation(animation)
			end)
			if ok and track then
				track.Priority = Enum.AnimationPriority.Action
				track:Play(0.2)
			end
		end
	else
		humanoid.WalkSpeed = 16
		humanoid.JumpPower = 50

		-- Останавливаем все анимации с приоритетом Action (то есть нашу позу)
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
				if track.Priority == Enum.AnimationPriority.Action then
					track:Stop(0.2)
				end
			end
		end
	end

	if PaintServiceRef then
		PaintServiceRef.SetPaintingAllowed(player, not wantsFreeze)
	end
end

local function onRequestFreeze(player, wantsFreeze)
	if typeof(wantsFreeze) ~= "boolean" then
		return
	end
	applyFreeze(player, wantsFreeze)
end

function FreezeService.IsFrozen(player)
	return frozenState[player] == true
end

-- Принудительно снять заморозку (например, когда раунд закончился)
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
	end)
end

return FreezeService
