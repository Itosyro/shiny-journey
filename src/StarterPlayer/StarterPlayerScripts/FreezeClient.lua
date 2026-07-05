-- FreezeClient.lua
-- Кнопка "Заморозка/Поза" на экране. При нажатии игрок замирает, и сервер
-- включает анимацию позы (см. ServerScriptService/FreezeService.lua).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

local FreezeClient = {}

local isFrozen = false
local freezeRemote

-- Простой визуальный фидбек нажатия кнопки (лёгкий "щелчок" размером).
-- Настоящая анимация позы проигрывается сервером на самом персонаже
-- (см. ServerScriptService/FreezeService.lua) - здесь только фидбек на UI.
-- Примечание: масштабировать сам риг через BodyHeightScale/BodyWidthScale нельзя,
-- т.к. это работает только в R15 и сломает вид персонажей на R6 (см. GameConfig.lua,
-- список PAINTABLE_PART_NAMES поддерживает оба рига).
local function playButtonPressFeedback(button)
	local originalSize = button.Size
	local shrunk = UDim2.new(originalSize.X.Scale, originalSize.X.Offset - 8, originalSize.Y.Scale, originalSize.Y.Offset - 6)

	local tweenDown = TweenService:Create(button, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = shrunk })
	local tweenUp = TweenService:Create(button, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = originalSize })

	tweenDown:Play()
	tweenDown.Completed:Connect(function()
		tweenUp:Play()
	end)
end

local function toggleFreeze(button)
	isFrozen = not isFrozen
	freezeRemote:FireServer(isFrozen)

	button.Text = isFrozen and "Разморозиться" or "Заморозиться (Поза)"
	button.BackgroundColor3 = isFrozen and Color3.fromRGB(0, 162, 232) or Color3.fromRGB(200, 60, 60)

	playButtonPressFeedback(button)
end

function FreezeClient.Init(remotesFolder)
	freezeRemote = remotesFolder:WaitForChild("RequestFreeze")

	local playerGui = player:WaitForChild("PlayerGui")
	local screenGui = playerGui:WaitForChild("PaintGui", 5)
	if not screenGui then
		screenGui = Instance.new("ScreenGui")
		screenGui.Name = "FreezeGui"
		screenGui.Parent = playerGui
	end

	local button = Instance.new("TextButton")
	button.Name = "FreezeButton"
	button.AnchorPoint = Vector2.new(1, 1)
	button.Position = UDim2.new(1, -12, 1, -190)
	button.Size = UDim2.new(0, 160, 0, 50)
	button.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.Font = Enum.Font.GothamBold
	button.TextScaled = true
	button.Text = "Заморозиться (Поза)"
	button.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = button

	button.MouseButton1Click:Connect(function()
		toggleFreeze(button)
	end)

	-- Если персонаж возродился - сбрасываем состояние заморозки на клиенте
	player.CharacterAdded:Connect(function()
		isFrozen = false
		button.Text = "Заморозиться (Поза)"
		button.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
	end)
end

return FreezeClient
