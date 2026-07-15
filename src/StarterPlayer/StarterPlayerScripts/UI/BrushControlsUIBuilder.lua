-- BrushControlsUIBuilder.lua
-- Панель управления кистью: слайдер размера мазка + кнопка входа/выхода в режим
-- рисования ("покрасочная камера", см. PaintClient.lua). Строится кодом, см.
-- DECISIONS.md, п.3. Новый файл - появился вместе с пересмотром механики
-- покраски на свободное рисование (см. DECISIONS.md, п.14).
--
-- Roblox не имеет готового GUI-объекта "слайдер", поэтому собираем его вручную
-- из Frame (полоса) + Frame (заполнение) + Frame (ручка) и своей обработкой
-- перетаскивания через UserInputService.

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local BrushControlsUIBuilder = {}

-- Создаёt слайдер 0..1 внутри parent; onChanged(fraction) вызывается при каждом изменении.
local function createSizeSlider(parent, defaultFraction, onChanged)
	local track = Instance.new("Frame")
	track.Name = "SizeSliderTrack"
	track.Size = UDim2.new(1, -16, 0, 24)
	track.Position = UDim2.new(0, 8, 0, 30)
	track.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	track.Parent = parent

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = Color3.fromRGB(0, 162, 232)
	fill.Size = UDim2.new(defaultFraction, 0, 1, 0)
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	local handle = Instance.new("Frame")
	handle.Name = "Handle"
	handle.AnchorPoint = Vector2.new(0.5, 0.5)
	handle.Size = UDim2.new(0, 26, 0, 26)
	handle.Position = UDim2.new(defaultFraction, 0, 0.5, 0)
	handle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	handle.ZIndex = 2
	handle.Parent = track

	local handleCorner = Instance.new("UICorner")
	handleCorner.CornerRadius = UDim.new(1, 0)
	handleCorner.Parent = handle

	local dragging = false

	local function applyFraction(fraction)
		fraction = math.clamp(fraction, 0, 1)
		fill.Size = UDim2.new(fraction, 0, 1, 0)
		handle.Position = UDim2.new(fraction, 0, 0.5, 0)
		if onChanged then
			onChanged(fraction)
		end
	end

	local function fractionFromInput(input)
		local relative = (input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X
		return math.clamp(relative, 0, 1)
	end

	local function isPointerInput(input)
		return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
	end

	local function beginDrag(input)
		dragging = true
		applyFraction(fractionFromInput(input))
	end

	handle.InputBegan:Connect(function(input)
		if isPointerInput(input) then
			beginDrag(input)
		end
	end)

	track.InputBegan:Connect(function(input)
		if isPointerInput(input) then
			beginDrag(input)
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if dragging and isPointerInput(input) then
			applyFraction(fractionFromInput(input))
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if isPointerInput(input) then
			dragging = false
		end
	end)
end

-- options: {
--   defaultSize = number,
--   OnSizeChanged = function(size: number) end,
--   OnPaintModeToggled = function(wantsActive: boolean) end,
-- }
function BrushControlsUIBuilder.Create(screenGui, options)
	local root = Instance.new("Frame")
	root.Name = "BrushControlsPanel"
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Position = UDim2.new(0.5, 0, 1, -150)
	root.Size = UDim2.new(1, -20, 0, 90)
	root.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
	root.BackgroundTransparency = 0.25
	root.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = root

	local sizeLabel = Instance.new("TextLabel")
	sizeLabel.Name = "SizeLabel"
	sizeLabel.BackgroundTransparency = 1
	sizeLabel.Size = UDim2.new(1, -16, 0, 22)
	sizeLabel.Position = UDim2.new(0, 8, 0, 2)
	sizeLabel.Font = Enum.Font.GothamBold
	sizeLabel.TextScaled = true
	sizeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	sizeLabel.TextXAlignment = Enum.TextXAlignment.Left
	sizeLabel.Text = "Размер кисти"
	sizeLabel.Parent = root

	local minSize = GameConfig.MIN_BRUSH_SIZE
	local maxSize = GameConfig.MAX_BRUSH_SIZE
	local defaultSize = options.defaultSize or GameConfig.DEFAULT_BRUSH_SIZE
	local defaultFraction = (defaultSize - minSize) / (maxSize - minSize)

	createSizeSlider(root, defaultFraction, function(fraction)
		local size = minSize + (maxSize - minSize) * fraction
		if options.OnSizeChanged then
			options.OnSizeChanged(size)
		end
	end)

	local paintButton = Instance.new("TextButton")
	paintButton.Name = "PaintModeButton"
	paintButton.Size = UDim2.new(1, -16, 0, 28)
	paintButton.Position = UDim2.new(0, 8, 0, 58)
	paintButton.BackgroundColor3 = Color3.fromRGB(60, 150, 60)
	paintButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	paintButton.Font = Enum.Font.GothamBold
	paintButton.TextScaled = true
	paintButton.Text = "Кисть (рисовать)"
	paintButton.Parent = root

	local paintButtonCorner = Instance.new("UICorner")
	paintButtonCorner.CornerRadius = UDim.new(0, 8)
	paintButtonCorner.Parent = paintButton

	local paintModeActive = false
	local function setPaintModeActive(value)
		paintModeActive = value
		paintButton.Text = paintModeActive and "Готово (выйти из кисти)" or "Кисть (рисовать)"
		paintButton.BackgroundColor3 = paintModeActive and Color3.fromRGB(0, 162, 232) or Color3.fromRGB(60, 150, 60)
	end

	paintButton.MouseButton1Click:Connect(function()
		local newValue = not paintModeActive
		setPaintModeActive(newValue)
		if options.OnPaintModeToggled then
			options.OnPaintModeToggled(newValue)
		end
	end)

	return {
		Root = root,
		SetPaintModeActive = setPaintModeActive,
	}
end

return BrushControlsUIBuilder
