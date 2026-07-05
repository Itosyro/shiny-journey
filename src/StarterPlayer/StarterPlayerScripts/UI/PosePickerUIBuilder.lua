-- PosePickerUIBuilder.lua
-- Карусель/сетка из кнопок выбора конкретного пресета позы (см.
-- ReplicatedStorage/Modules/PosePresets.lua) - touch-friendly, крупные кнопки
-- в ряд. Раньше была одна кнопка "Заморозиться/Разморозиться" без выбора
-- конкретной позы - см. DECISIONS.md, п.17.
--
-- Иконок-картинок для поз пока нет (нужны финальные ассеты, см. TASKS.md),
-- поэтому кнопки показывают текстовую подпись пресета - это уже touch-friendly
-- и рабочее решение, иконки можно добавить позже без изменения логики (просто
-- подставить ImageLabel поверх кнопки).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local PosePresets = require(ReplicatedStorage.Modules.PosePresets)

local PosePickerUIBuilder = {}

local INACTIVE_COLOR = Color3.fromRGB(60, 60, 60)
local ACTIVE_COLOR = Color3.fromRGB(0, 162, 232)

-- Лёгкий "щелчок" размером при нажатии - тот же приём, что раньше был у
-- одиночной кнопки заморозки.
local function playButtonPressFeedback(button)
	local originalSize = button.Size
	local shrunk = UDim2.new(originalSize.X.Scale, originalSize.X.Offset - 6, originalSize.Y.Scale, originalSize.Y.Offset - 6)

	local tweenDown = TweenService:Create(button, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = shrunk })
	local tweenUp = TweenService:Create(button, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = originalSize })

	tweenDown:Play()
	tweenDown.Completed:Connect(function()
		tweenUp:Play()
	end)
end

-- options: { OnPoseToggled = function(poseId: string, wantsActive: boolean) end }
function PosePickerUIBuilder.Create(screenGui, options)
	local root = Instance.new("Frame")
	root.Name = "PosePickerPanel"
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Position = UDim2.new(0.5, 0, 1, -296)
	root.Size = UDim2.new(1, -20, 0, 74)
	root.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
	root.BackgroundTransparency = 0.25
	root.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = root

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = UDim2.new(1, -16, 0, 18)
	titleLabel.Position = UDim2.new(0, 8, 0, 2)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Text = "Поза (нажми ещё раз, чтобы встать)"
	titleLabel.Parent = root

	local row = Instance.new("Frame")
	row.Name = "PoseRow"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, -16, 0, 46)
	row.Position = UDim2.new(0, 8, 0, 22)
	row.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row

	local buttons = {} -- poseId -> TextButton
	local activePoseId = nil

	local function setActivePose(poseId)
		activePoseId = poseId
		for id, button in pairs(buttons) do
			button.BackgroundColor3 = (id == poseId) and ACTIVE_COLOR or INACTIVE_COLOR
		end
	end

	for i, preset in ipairs(PosePresets.List) do
		local button = Instance.new("TextButton")
		button.Name = preset.id
		-- Масштабное (не фиксированное) распределение по ширине - адаптируется
		-- под разные размеры экрана (см. CLAUDE.md, требование адаптивного UI)
		button.Size = UDim2.new(1 / #PosePresets.List, -5, 1, 0)
		button.BackgroundColor3 = INACTIVE_COLOR
		button.TextColor3 = Color3.fromRGB(255, 255, 255)
		button.Font = Enum.Font.GothamBold
		button.TextScaled = true
		button.Text = preset.label
		button.LayoutOrder = i
		button.Parent = row

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 8)
		btnCorner.Parent = button

		button.MouseButton1Click:Connect(function()
			playButtonPressFeedback(button)

			if activePoseId == preset.id then
				setActivePose(nil)
				if options.OnPoseToggled then
					options.OnPoseToggled(preset.id, false)
				end
			else
				setActivePose(preset.id)
				if options.OnPoseToggled then
					options.OnPoseToggled(preset.id, true)
				end
			end
		end)

		buttons[preset.id] = button
	end

	return {
		Root = root,
		-- Внешний сеттер (для сброса при респауне/смене фазы) - не вызывает
		-- OnPoseToggled, только меняет подсветку кнопок, тот же паттерн, что и
		-- SetEyedropperActive в PaletteUIBuilder.
		SetActivePose = setActivePose,
	}
end

return PosePickerUIBuilder
