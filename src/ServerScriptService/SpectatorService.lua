-- SpectatorService.lua
-- Игрок, зашедший на сервер посреди активной фазы (не Lobby), становится
-- зрителем до конца текущего раунда, а не сразу Hider/Seeker - см.
-- DECISIONS.md, п.21. Зритель: персонаж скрыт и обездвижен (не мешает и не
-- виден остальным), а клиент включает простую "лётную" камеру
-- (SpectatorClient.lua). В начале следующего раунда зритель автоматически
-- возвращается в общий пул для распределения ролей.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

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
		-- Перемещаем к SpectatorSpawn (см. MapBuilder.lua, DECISIONS.md, п.23) -
		-- даёт зрителю сразу общий вид на карту сверху, а не случайную точку
		-- пола (обычно там же, где стоял, будучи ещё не-зрителем). Part с этим
		-- именем - необязательный контракт: если карта его не создала (Part не
		-- найден), просто оставляем персонажа на месте, как и раньше.
		local spectatorSpawn = Workspace:FindFirstChild("Map") and Workspace.Map:FindFirstChild("SpectatorSpawn")
		if spectatorSpawn then
			rootPart.CFrame = spectatorSpawn.CFrame
		end
		rootPart.Anchored = true
	end
end

-- Общая часть перехода в режим зрителя: команда, скрытие персонажа (если уже
-- заспавнен), уведомление клиента. Вынесена отдельно, т.к. нужна и из
-- EnterSpectator (первый вход), и из обработчика CharacterAdded ниже (тот же
-- игрок повторно заспавнился, пока всё ещё зритель).
local function becomeSpectator(player, character)
	isFullSpectator[player] = true

	if PlayerRoleServiceRef then
		PlayerRoleServiceRef.SetSpectator(player)
	end

	if character then
		hideAndImmobilize(character)
	end

	sendModeChanged(player, true)
end

-- Переводит игрока в режим зрителя: команда, скрытие персонажа, включение
-- клиентской "лётной" камеры.
function SpectatorService.EnterSpectator(player)
	if isFullSpectator[player] then
		return -- уже зритель
	end
	becomeSpectator(player, player.Character)
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
			if isFullSpectator[player] then
				-- Уже был зрителем - это повторный респавн (например, персонаж
				-- провалился в бесконечность), применяем скрытие снова к новому телу.
				hideAndImmobilize(character)
				sendModeChanged(player, true)
				return
			end

			if RoundManager.State == "Lobby" then
				return
			end

			-- Игрок уже участвует в текущем раунде как Hider/Seeker (роль
			-- назначена в PlayerRoleService.AssignRoles, команда выставлена) -
			-- CharacterAdded здесь означает не "новый игрок зашёл посреди
			-- раунда", а обычный респавн уже играющего (например, кнопка
			-- "Reset Character" в меню паузы). Зрителем становиться не нужно -
			-- иначе живой Hider/Seeker окажется невидимым и обездвиженным до
			-- конца раунда без возможности играть дальше.
			local team = player.Team
			local isActiveRoundParticipant = team ~= nil
				and (team.Name == GameConfig.TEAM_HIDERS_NAME or team.Name == GameConfig.TEAM_SEEKERS_NAME)
			if isActiveRoundParticipant then
				return
			end

			-- Действительно новый зритель: зашёл посреди активной фазы (Hiding/
			-- Seeking/RoundEnd) и ещё не участвует в текущем раунде.
			becomeSpectator(player, character)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		isFullSpectator[player] = nil
	end)
end

return SpectatorService
