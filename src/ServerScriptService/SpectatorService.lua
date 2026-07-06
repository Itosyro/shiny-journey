-- SpectatorService.lua
-- Игрок, зашедший на сервер посреди активной фазы (не Lobby), становится
-- зрителем до конца текущего раунда, а не сразу Hider/Seeker - см.
-- DECISIONS.md, п.21. Зритель: персонаж скрыт и обездвижен (не мешает и не
-- виден остальным), а клиент включает простую "лётную" камеру
-- (SpectatorClient.lua). В начале следующего раунда зритель автоматически
-- возвращается в общий пул для распределения ролей.

local Players = game:GetService("Players")

-- Только для проверки текущей фазы раунда (RoundManager.State) - тот же
-- паттерн, что уже используется в FreezeService/PaintService, см. их
-- комментарии о том, почему это не создаёт цикл require.
local RoundManager = require(script.Parent.RoundManager)

local SpectatorService = {}

local isFullSpectator = {} -- [Player] = true, пока игрок в режиме зрителя
local remotesRef
local PlayerRoleServiceRef

local function sendModeChanged(player, isSpectating)
	if remotesRef then
		remotesRef.SpectatorModeChanged:FireClient(player, isSpectating)
	end
end

-- Прячем персонажа и лишаем его физического присутствия в мире: невидим,
-- не сталкивается, заанкорен (чтобы гравитация не тянула вниз, пока клиент
-- перемещает HumanoidRootPart вручную для полёта - см. SpectatorClient.lua).
local function hideAndImmobilize(character)
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Transparency = 1
			descendant.CanCollide = false
		end
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- WalkSpeed = 0 останавливает обычную физическую ходьбу, но
		-- Humanoid.MoveDirection всё равно остаётся живым единичным вектором
		-- ввода (подтверждено Creator Hub) - именно на нём и построен полёт.
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart then
		rootPart.Anchored = true
	end
end

-- Переводит игрока в режим зрителя: команда, скрытие персонажа, включение
-- клиентской "лётной" камеры.
function SpectatorService.EnterSpectator(player)
	if isFullSpectator[player] then
		return -- уже зритель
	end
	isFullSpectator[player] = true

	if PlayerRoleServiceRef then
		PlayerRoleServiceRef.SetSpectator(player)
	end

	local character = player.Character
	if character then
		hideAndImmobilize(character)
	end

	sendModeChanged(player, true)
end

-- Возвращает игрока к обычной игре, когда следующий раунд назначил ему роль
-- Hider/Seeker. Полностью респавним персонажа (LoadCharacter), а не пытаемся
-- восстановить/переместить старое "летающее" тело - оно могло оказаться где
-- угодно на карте (в стене, за пределами арены), респавн на стандартной точке
-- спавна надёжнее любых ручных вычислений безопасной позиции.
function SpectatorService.ExitSpectator(player)
	if not isFullSpectator[player] then
		return -- и не был зрителем - нечего возвращать
	end
	isFullSpectator[player] = false

	sendModeChanged(player, false)
	player:LoadCharacter()
end

function SpectatorService.IsSpectating(player)
	return isFullSpectator[player] == true
end

function SpectatorService.Init(remotes, playerRoleService)
	remotesRef = remotes
	PlayerRoleServiceRef = playerRoleService

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			-- Не Lobby - значит идёт активная фаза (Hiding/Seeking/RoundEnd),
			-- присоединившийся посреди неё становится зрителем до конца раунда.
			-- Если игрок уже был зрителем (например, это повторный респавн
			-- посреди той же фазы) - тоже применяем скрытие снова.
			if isFullSpectator[player] or RoundManager.State ~= "Lobby" then
				isFullSpectator[player] = true
				hideAndImmobilize(character)
				sendModeChanged(player, true)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		isFullSpectator[player] = nil
	end)
end

return SpectatorService
