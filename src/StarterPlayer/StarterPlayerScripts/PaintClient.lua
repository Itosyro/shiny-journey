-- PaintClient.lua
-- Логика покраски на клиенте: строит UI палитры, обрабатывает нажатия на цвета,
-- и реализует "пипетку" - берём цвет поверхности, на которую смотрит игрок,
-- через raycast от камеры (одинаково работает и для мыши, и для тача на телефоне).

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local PaletteUIBuilder = require(script.Parent.UI.PaletteUIBuilder)

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local PaintClient = {}

local selectedPartNames = { "Head" }
local eyedropperActive = false
local paintRemote

-- Достаём цвет поверхности под пальцем/курсором через raycast от камеры
local function pickColorAtScreenPosition(screenPosition)
	local unitRay = camera:ViewportPointToRay(screenPosition.X, screenPosition.Y)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { player.Character }

	local result = Workspace:Raycast(unitRay.Origin, unitRay.Direction * GameConfig.EYEDROPPER_MAX_DISTANCE, raycastParams)
	if result and result.Instance and result.Instance:IsA("BasePart") then
		return result.Instance.Color
	end
	return nil
end

local function applyColorToSelectedParts(color)
	for _, partName in ipairs(selectedPartNames) do
		paintRemote:FireServer(partName, color)
	end
end

local function handleTapPosition(screenPosition, ui)
	if not eyedropperActive then
		return
	end

	local color = pickColorAtScreenPosition(screenPosition)
	if color then
		applyColorToSelectedParts(color)
	end

	eyedropperActive = false
	if ui then
		ui.SetEyedropperActive(false)
	end
end

function PaintClient.Init(remotesFolder)
	paintRemote = remotesFolder:WaitForChild("PaintCharacter")
	local chargesRemote = remotesFolder:WaitForChild("BrushChargesUpdate")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PaintGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = player:WaitForChild("PlayerGui")

	-- Подпись с оставшимися зарядами краски
	local chargesLabel = Instance.new("TextLabel")
	chargesLabel.Name = "ChargesLabel"
	chargesLabel.AnchorPoint = Vector2.new(0.5, 1)
	chargesLabel.Position = UDim2.new(0.5, 0, 1, -180)
	chargesLabel.Size = UDim2.new(0, 200, 0, 30)
	chargesLabel.BackgroundTransparency = 1
	chargesLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	chargesLabel.Font = Enum.Font.GothamBold
	chargesLabel.TextScaled = true
	chargesLabel.Text = "Краска: -/-"
	chargesLabel.Parent = screenGui

	chargesRemote.OnClientEvent:Connect(function(charges, maxCharges)
		chargesLabel.Text = "Краска: " .. charges .. "/" .. maxCharges
	end)

	local ui
	ui = PaletteUIBuilder.Create(screenGui, {
		OnColorPicked = function(color)
			applyColorToSelectedParts(color)
		end,
		OnEyedropperToggled = function(isActive)
			eyedropperActive = isActive
		end,
		OnBodyPartSelected = function(partNamesList)
			selectedPartNames = partNamesList
		end,
	})

	-- Ловим тап/клик в любом месте экрана, когда активна пипетка.
	-- InputBegan одинаково работает и для мыши (MouseButton1), и для тача на телефоне (Touch).
	UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
		if gameProcessedEvent then
			return -- игрок нажал на кнопку UI, а не на мир игры - это не тап пипетки
		end

		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			handleTapPosition(input.Position, ui)
		end
	end)

	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		camera = Workspace.CurrentCamera
	end)
end

return PaintClient
