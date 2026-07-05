-- PaletteUIBuilder.lua
-- Строит UI выбора цвета кодом (без ручной сборки в Studio) - см. DECISIONS.md,
-- п.3. Адаптировано под мобильные экраны: крупные кнопки, минимум мелких деталей.
--
-- Раньше здесь была ещё и кнопка выбора части тела ("Голова"/"Тело"/"Руки"/"Ноги"),
-- но механику покраски пересмотрели на свободное рисование кистью (см.
-- DECISIONS.md, п.14) - часть тела больше не выбирается заранее, а определяется
-- тем, где именно мазнула кисть, поэтому этот UI отвечает только за выбор цвета.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PaletteData = require(ReplicatedStorage.Modules.PaletteData)

local PaletteUIBuilder = {}

local SWATCH_SIZE = 44 -- размер кнопки цвета в пикселях - крупный, чтобы легко тапать пальцем

-- callbacks: {
--   OnColorPicked = function(color: Color3) end,
--   OnEyedropperToggled = function(isActive: boolean) end,
-- }
function PaletteUIBuilder.Create(screenGui, callbacks)
	local root = Instance.new("Frame")
	root.Name = "PalettePanel"
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Position = UDim2.new(0.5, 0, 1, -10)
	root.Size = UDim2.new(1, -20, 0, 130)
	root.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
	root.BackgroundTransparency = 0.25
	root.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = root

	-- Кнопка пипетки - отдельная строка сверху палитры
	local eyedropperButton = Instance.new("TextButton")
	eyedropperButton.Name = "EyedropperButton"
	eyedropperButton.Size = UDim2.new(1, -16, 0, 34)
	eyedropperButton.Position = UDim2.new(0, 8, 0, 6)
	eyedropperButton.BackgroundColor3 = Color3.fromRGB(90, 90, 20)
	eyedropperButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	eyedropperButton.Font = Enum.Font.GothamBold
	eyedropperButton.TextScaled = true
	eyedropperButton.Text = "Пипетка (взять цвет с поверхности)"
	eyedropperButton.Parent = root

	local eyedropperCorner = Instance.new("UICorner")
	eyedropperCorner.CornerRadius = UDim.new(0, 8)
	eyedropperCorner.Parent = eyedropperButton

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

	-- === Сетка готовых цветов ===
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "ColorGrid"
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.Size = UDim2.new(1, -16, 1, -48)
	scrollFrame.Position = UDim2.new(0, 8, 0, 44)
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
