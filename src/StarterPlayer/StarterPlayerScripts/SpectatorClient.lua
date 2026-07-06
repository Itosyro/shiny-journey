-- SpectatorClient.lua
-- Клиентская часть режима зрителя (см. ServerScriptService/SpectatorService.lua,
-- DECISIONS.md, п.21). Персонаж уже скрыт и заанкорен сервером - этот скрипт
-- только двигает HumanoidRootPart каждый кадр, имитируя свободный полёт:
-- горизонталь берётся из Humanoid.MoveDirection (живой юнит-вектор ввода,
-- не зависящий от WalkSpeed - подтверждено официальной документацией Creator
-- Hub), вертикаль - от двух простых touch-friendly кнопок Вверх/Вниз.
-- Камера не трогается: стандартная Enum.CameraType.Custom и так уже следует
-- за (невидимым) персонажем со всеми стандартными desktop/touch-управлениями.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local player = Players.LocalPlayer

local SpectatorClient = {}

function SpectatorClient.Init(remotesFolder)
	local modeChangedRemote = remotesFolder:WaitForChild("SpectatorModeChanged")

	local playerGui = player:WaitForChild("PlayerGui")
	local screenGui = playerGui:WaitForChild("PaintGui", 5)
	if not screenGui then
		screenGui = Instance.new("ScreenGui")
		screenGui.Name = "SpectatorGui"
		screenGui.Parent = playerGui
	end

	local root = Instance.new("Frame")
	root.Name = "SpectatorFlyControls"
	root.AnchorPoint = Vector2.new(1, 1)
	root.Position = UDim2.new(1, -16, 1, -16)
	root.Size = UDim2.new(0, 72, 0, 156)
	root.BackgroundTransparency = 1
	root.Visible = false
	root.Parent = screenGui

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = root

	local function createFlyButton(text, order)
		local button = Instance.new("TextButton")
		button.Size = UDim2.new(1, 0, 0, 72)
		button.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
		button.BackgroundTransparency = 0.25
		button.TextColor3 = Color3.fromRGB(255, 255, 255)
		button.Font = Enum.Font.GothamBold
		button.TextScaled = true
		button.Text = text
		button.LayoutOrder = order
		button.Parent = root

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = button

		return button
	end

	local upButton = createFlyButton("▲", 1)
	local downButton = createFlyButton("▼", 2)

	-- verticalInput меняется зажатием кнопки - работает и от мыши, и от тача
	-- (GuiButton транслирует тач в те же MouseButton1Down/Up события).
	local verticalInput = 0

	upButton.MouseButton1Down:Connect(function()
		verticalInput = 1
	end)
	upButton.MouseButton1Up:Connect(function()
		verticalInput = 0
	end)
	downButton.MouseButton1Down:Connect(function()
		verticalInput = -1
	end)
	downButton.MouseButton1Up:Connect(function()
		verticalInput = 0
	end)

	local flyConnection = nil
	-- Растёт при каждом старте/остановке полёта - если за время ожидания
	-- Humanoid/HumanoidRootPart (см. ниже) режим зрителя успел выключиться и
	-- снова включиться, "устаревший" запуск не должен запустить полёт поверх
	-- нового - что и проверяется через myGeneration.
	local flyGeneration = 0

	local function stopFlying()
		flyGeneration += 1
		if flyConnection then
			flyConnection:Disconnect()
			flyConnection = nil
		end
		verticalInput = 0
		root.Visible = false
	end

	local function startFlying()
		local character = player.Character
		if not character then
			return
		end

		flyGeneration += 1
		local myGeneration = flyGeneration

		-- WaitForChild без таймаута вместо возможного тихого no-op при таймауте:
		-- Humanoid/HumanoidRootPart - стандартные части любого персонажа и рано
		-- или поздно точно появятся, а без task.spawn ожидание здесь заблокировало
		-- бы обработчик SpectatorModeChanged.OnClientEvent для этого игрока.
		task.spawn(function()
			local humanoid = character:WaitForChild("Humanoid")
			local rootPart = character:WaitForChild("HumanoidRootPart")

			if flyGeneration ~= myGeneration then
				return -- режим зрителя уже выключили (или включили заново), пока ждали
			end

			root.Visible = true

			flyConnection = RunService.Heartbeat:Connect(function(deltaTime)
				-- rootPart мог перестать существовать (например, персонаж уже начал
				-- пересоздаваться) - защищаемся от гонки, просто останавливая полёт.
				if not rootPart.Parent then
					stopFlying()
					return
				end

				local horizontal = humanoid.MoveDirection
				local offset = (horizontal + Vector3.new(0, verticalInput, 0)) * GameConfig.SPECTATOR_FLY_SPEED * deltaTime
				rootPart.CFrame = rootPart.CFrame + offset
			end)
		end)
	end

	modeChangedRemote.OnClientEvent:Connect(function(isSpectating)
		stopFlying()
		if isSpectating then
			startFlying()
		end
	end)
end

return SpectatorClient
