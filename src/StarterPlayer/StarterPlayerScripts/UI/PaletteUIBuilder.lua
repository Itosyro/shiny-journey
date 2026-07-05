-- PaletteUIBuilder.lua
-- Строит весь UI палитры цветов кодом (без ручной сборки в Studio),
-- чтобы всё синхронизировалось через Rojo вместе с остальным кодом
-- (см. DECISIONS.md, п.3). Адаптировано под мобильные экраны: крупные кнопки,
-- минимум мелких деталей.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PaletteData = require(ReplicatedStorage.Modules.PaletteData)

local PaletteUIBuilder = {}

local SWATCH_SIZE = 44 -- размер кнопки цвета в пикселях - крупный, чтобы легко тапать пальцем

local BODY_PARTS_UI = {
	{ label = "Голова", partNames = { "Head" } },
	{ label = "Тело", partNames = { "UpperTorso", "LowerTorso", "Torso" } },
	{
		label = "Руки",
		partNames = {
			"LeftUpperArm", "LeftLowerArm", "LeftHand",
			"RightUpperArm", "RightLowerArm", "RightHand",
			"Left Arm", "Right Arm",
		},
	},
	{
		label = "Ноги",
		partNames = {
			"LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
			"RightUpperLeg", "RightLowerLeg", "RightFoot",
			"Left Leg", "Right Leg",
		},
	},
}

-- callbacks: {
--   OnColorPicked = function(color: Color3) end,
--   OnEyedropperToggled = function(isActive: boolean) end,
--   OnBodyPartSelected = function(partNamesList: {string}) end,
-- }
function PaletteUIBuilder.Create(screenGui, callbacks)
	local root = Instance.new("Frame")
	root.Name = "PaintPanel"
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Position = UDim2.new(0.5, 0, 1, -10)
	root.Size = UDim2.new(1, -20, 0, 170)
	root.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
	root.BackgroundTransparency = 0.25
	root.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = root

	-- === Ряд выбора части тела + кнопка пипетки ===
	local partsRow = Instance.new("Frame")
	partsRow.Name = "PartsRow"
	partsRow.BackgroundTransparency = 1
	partsRow.Size = UDim2.new(1, -16, 0, 40)
	partsRow.Position = UDim2.new(0, 8, 0, 6)
	partsRow.Parent = root

	local partsLayout = Instance.new("UIListLayout")
	partsLayout.FillDirection = Enum.FillDirection.Horizontal
	partsLayout.Padding = UDim.new(0, 6)
	partsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	partsLayout.Parent = partsRow

	local selectedPartButtons = {}
	local function highlightSelected(selectedButton)
		for _, btn in ipairs(selectedPartButtons) do
			btn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
		end
		selectedButton.BackgroundColor3 = Color3.fromRGB(0, 162, 232)
	end

	for i, partGroup in ipairs(BODY_PARTS_UI) do
		local button = Instance.new("TextButton")
		button.Name = partGroup.label
		button.Size = UDim2.new(0, 76, 1, 0)
		button.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
		button.TextColor3 = Color3.fromRGB(255, 255, 255)
		button.Font = Enum.Font.GothamBold
		button.TextScaled = true
		button.Text = partGroup.label
		button.LayoutOrder = i
		button.AutoButtonColor = true
		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 8)
		btnCorner.Parent = button
		button.Parent = partsRow

		table.insert(selectedPartButtons, button)

		button.MouseButton1Click:Connect(function()
			highlightSelected(button)
			if callbacks.OnBodyPartSelected then
				callbacks.OnBodyPartSelected(partGroup.partNames)
			end
		end)

		if i == 1 then
			highlightSelected(button)
		end
	end

	-- Кнопка пипетки - отдельная, в конце ряда
	local eyedropperButton = Instance.new("TextButton")
	eyedropperButton.Name = "EyedropperButton"
	eyedropperButton.Size = UDim2.new(0, 76, 1, 0)
	eyedropperButton.LayoutOrder = 99
	eyedropperButton.BackgroundColor3 = Color3.fromRGB(90, 90, 20)
	eyedropperButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	eyedropperButton.Font = Enum.Font.GothamBold
	eyedropperButton.TextScaled = true
	eyedropperButton.Text = "Пипетка"
	local eyedropperCorner = Instance.new("UICorner")
	eyedropperCorner.CornerRadius = UDim.new(0, 8)
	eyedropperCorner.Parent = eyedropperButton
	eyedropperButton.Parent = partsRow

	local eyedropperActive = false
	local function setEyedropperActive(value)
		eyedropperActive = value
		eyedropperButton.BackgroundColor3 = eyedropperActive and Color3.fromRGB(255, 220, 0) or Color3.fromRGB(90, 90, 20)
	end

	eyedropperButton.MouseButton1Click:Connect(function()
		setEyedropperActive(not eyedropperActive)
		if callbacks.OnEyedropperToggled then
			callbacks.OnEyedropperToggled(eyedropperActive)
		end
	end)

	-- === Сетка цветов ===
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "ColorGrid"
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.Size = UDim2.new(1, -16, 1, -56)
	scrollFrame.Position = UDim2.new(0, 8, 0, 50)
	scrollFrame.ScrollBarThickness = 6
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.Parent = root

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0, SWATCH_SIZE, 0, SWATCH_SIZE)
	gridLayout.CellPadding = UDim2.new(0, 6, 0, 6)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = scrollFrame

	for i, color in ipairs(PaletteData.Colors) do
		local swatch = Instance.new("TextButton")
		swatch.Name = "Swatch" .. i
		swatch.Text = ""
		swatch.BackgroundColor3 = color
		swatch.LayoutOrder = i
		swatch.AutoButtonColor = false
		local swatchCorner = Instance.new("UICorner")
		swatchCorner.CornerRadius = UDim.new(1, 0) -- круглые кнопки цвета
		swatchCorner.Parent = swatch
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = Color3.fromRGB(255, 255, 255)
		stroke.Transparency = 0.4
		stroke.Parent = swatch
		swatch.Parent = scrollFrame

		swatch.MouseButton1Click:Connect(function()
			setEyedropperActive(false)
			if callbacks.OnEyedropperToggled then
				callbacks.OnEyedropperToggled(false)
			end
			if callbacks.OnColorPicked then
				callbacks.OnColorPicked(color)
			end
		end)
	end

	return {
		Root = root,
		SetEyedropperActive = setEyedropperActive,
	}
end

return PaletteUIBuilder
