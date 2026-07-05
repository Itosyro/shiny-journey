-- FreezeService.lua
-- Отвечает за "заморозку" (позу). Игрок останавливается на месте, включается
-- анимация позы, пока он заморожен - не может двигаться и красить
-- (см. PaintService.SetPaintingAllowed и DECISIONS.md, п.5 и п.10).

local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
-- Требуется только для проверки текущей фазы раунда (RoundManager.State).
-- Обратной зависимости нет - RoundManager получает сервисы через Init(), а не
-- через require(), так что цикла require здесь не образуется.
local RoundManager = require(script.Parent.RoundManager)

local FreezeService = {}

local frozenState = {} -- [Player] = true/false
-- Сохраняем исходные параметры движения игрока перед заморозкой, чтобы точно
-- вернуть их при разморозке. Раньше JumpHeight обнулялся, но не восстанавливался,
-- из-за чего на современных ригах (UseJumpPower=false) игрок больше не мог прыгать.
local savedLocomotion = {} -- [Player] = { walkSpeed, jumpPower, jumpHeight }
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
		-- Запоминаем текущие значения ровно один раз (чтобы повторный вызов freeze
		-- не сохранил уже обнулённые значения)
		if not savedLocomotion[player] then
			savedLocomotion[player] = {
				walkSpeed = humanoid.WalkSpeed,
				jumpPower = humanoid.JumpPower,
				jumpHeight = humanoid.JumpHeight,
			}
		end

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
		-- Возвращаем исходные значения движения (или разумные значения по умолчанию,
		-- если по какой-то причине ничего не сохранили)
		local saved = savedLocomotion[player]
		humanoid.WalkSpeed = saved and saved.walkSpeed or 16
		humanoid.JumpPower = saved and saved.jumpPower or 50
		humanoid.JumpHeight = saved and saved.jumpHeight or 7.2
		savedLocomotion[player] = nil

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

-- Поза - механика только для Hiders, и только пока идёт фаза пряток (Hiding).
-- Seekers к ней не имеют доступа вообще (см. DECISIONS.md, п.13): в оригинале
-- искатели не притворяются мебелью. Ограничение "только в Hiding" также не даёт
-- Hider на ходу переключать позу во время поиска (подстроиться под шаги Seeker
-- или внезапно встать/сняться с позы, чтобы сбить с толку) - решение зафиксировано
-- в DECISIONS.md, п.13, включая обсуждение компромисса.
local function isHider(player)
	local hidersTeam = Teams:FindFirstChild(GameConfig.TEAM_HIDERS_NAME)
	return hidersTeam ~= nil and player.Team == hidersTeam
end

local function onRequestFreeze(player, wantsFreeze)
	if typeof(wantsFreeze) ~= "boolean" then
		return
	end

	if not isHider(player) then
		return -- Seekers не могут вставать в позу
	end

	if RoundManager.State ~= "Hiding" then
		return -- переключать позу можно только во время фазы пряток
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
		savedLocomotion[player] = nil
	end)
end

return FreezeService
