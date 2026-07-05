-- PaintClient.lua
-- Логика покраски на клиенте: свободное рисование кистью по своему телу.
-- Механика была пересмотрена после дополнительного изучения референса (раньше
-- тут были кнопки "выбрать часть тела -> залить целиком") - см. DECISIONS.md,
-- п.14.
--
-- Два независимых режима, не мешающих друг другу:
--  - Пипетка: работает в обычной (следящей) камере, берёт цвет с мировой
--    поверхности (стена, пол, мебель) через raycast от камеры - как и раньше.
--  - Кисть: включает "покрасочную камеру" (фиксированный ракурс на своего
--    персонажа) и позволяет рисовать зажатием пальца/кнопки мыши и мазками
--    по собственному телу. Пипетка недоступна, пока активна кисть, т.к. камера
--    смотрит на себя, а не на окружение.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local BrushGeometry = require(ReplicatedStorage.Modules.BrushGeometry)
local PaletteUIBuilder = require(script.Parent.UI.PaletteUIBuilder)
local BrushControlsUIBuilder = require(script.Parent.UI.BrushControlsUIBuilder)

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local PaintClient = {}

local paintableLookup = {}
for _, name in ipairs(GameConfig.PAINTABLE_PART_NAMES) do
	paintableLookup[name] = true
end

-- Пакет мазков шлём на сервер раз в столько секунд, а не по одной точке за раз -
-- дешевле для сети/сервера при непрерывном рисовании (см. DECISIONS.md, п.14).
local STROKE_BATCH_INTERVAL = 0.15
local PAINT_RAYCAST_DISTANCE = 15 -- дальше своего же тела луч не долетит, но с запасом

local currentColor = Color3.fromRGB(255, 255, 255)
local currentBrushSize = GameConfig.DEFAULT_BRUSH_SIZE
local eyedropperActive = false
local paintModeActive = false
local isDragging = false
local strokeBuffer = {}

local paintRemote
local previousCameraType
local paintCameraConnection

-- === Пипетка (логика та же, что и раньше - меняется только то, что делается с
-- выбранным цветом дальше: раньше сразу заливала часть тела, теперь только
-- запоминает currentColor, которым потом рисует кисть) ===
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

local function handleEyedropperTap(screenPosition, paletteUI)
	if not eyedropperActive then
		return
	end

	local color = pickColorAtScreenPosition(screenPosition)
	if color then
		currentColor = color
	end

	eyedropperActive = false
	if paletteUI then
		paletteUI.SetEyedropperActive(false)
	end
end

-- === Покрасочная камера ===
-- Фиксированный ракурс спереди-сверху на собственного персонажа, чтобы удобно
-- было водить пальцем/курсором по телу (см. DECISIONS.md, п.14). Обновляется
-- каждый кадр, пока активна кисть, т.к. персонаж всё ещё может немного двигаться.
local function updatePaintCamera()
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	local forwardOffset = rootPart.CFrame:VectorToWorldSpace(Vector3.new(0, 1.2, 4))
	local focusPoint = rootPart.Position + Vector3.new(0, 1, 0)
	camera.CFrame = CFrame.new(rootPart.Position + forwardOffset, focusPoint)
end

local function enterPaintMode(brushControlsUI)
	if paintModeActive then
		return
	end

	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then
		return
	end

	paintModeActive = true
	eyedropperActive = false

	previousCameraType = camera.CameraType
	camera.CameraType = Enum.CameraType.Scriptable
	updatePaintCamera()
	paintCameraConnection = RunService.RenderStepped:Connect(updatePaintCamera)

	if brushControlsUI then
		brushControlsUI.SetPaintModeActive(true)
	end
end

local function exitPaintMode(brushControlsUI)
	if not paintModeActive then
		return
	end

	paintModeActive = false
	isDragging = false
	strokeBuffer = {}

	if paintCameraConnection then
		paintCameraConnection:Disconnect()
		paintCameraConnection = nil
	end

	camera.CameraType = previousCameraType or Enum.CameraType.Custom

	if brushControlsUI then
		brushControlsUI.SetPaintModeActive(false)
	end
end

-- === Рисование мазками по своему телу ===
local function raycastOwnCharacter(screenPosition)
	local character = player.Character
	if not character then
		return nil
	end

	local unitRay = camera:ViewportPointToRay(screenPosition.X, screenPosition.Y)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = { character }

	return Workspace:Raycast(unitRay.Origin, unitRay.Direction * PAINT_RAYCAST_DISTANCE, raycastParams)
end

-- Копит точку мазка в буфер (в нормализованных face/u/v, см. BrushGeometry) -
-- реальная отправка идёт пакетом в strokeBatchLoop, не отсюда.
local function addStrokePoint(screenPosition)
	local result = raycastOwnCharacter(screenPosition)
	if not result or not result.Instance or not result.Instance:IsA("BasePart") then
		return
	end

	local part = result.Instance
	if not paintableLookup[part.Name] then
		return
	end

	local localNormal = part.CFrame:VectorToObjectSpace(result.Normal)
	local face = BrushGeometry.DetectFace(localNormal)
	local localPosition = part.CFrame:PointToObjectSpace(result.Position)
	local u, v = BrushGeometry.PositionToUV(part, localPosition, face)

	table.insert(strokeBuffer, { partName = part.Name, face = face, u = u, v = v })
end

local function strokeBatchLoop()
	while true do
		task.wait(STROKE_BATCH_INTERVAL)
		if #strokeBuffer > 0 then
			paintRemote:FireServer(strokeBuffer, currentColor, currentBrushSize)
			strokeBuffer = {}
		end
	end
end

function PaintClient.Init(remotesFolder)
	paintRemote = remotesFolder:WaitForChild("PaintStroke")
	local inkRemote = remotesFolder:WaitForChild("InkUpdate")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PaintGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = player:WaitForChild("PlayerGui")

	-- Полоска "чернил" (раньше был счётчик дискретных "зарядов")
	local inkLabel = Instance.new("TextLabel")
	inkLabel.Name = "InkLabel"
	inkLabel.AnchorPoint = Vector2.new(0.5, 1)
	inkLabel.Position = UDim2.new(0.5, 0, 1, -260)
	inkLabel.Size = UDim2.new(0, 200, 0, 26)
	inkLabel.BackgroundTransparency = 1
	inkLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	inkLabel.Font = Enum.Font.GothamBold
	inkLabel.TextScaled = true
	inkLabel.Text = "Чернила: -/-"
	inkLabel.Parent = screenGui

	inkRemote.OnClientEvent:Connect(function(amount, maxAmount)
		inkLabel.Text = string.format("Чернила: %d/%d", math.floor(amount), maxAmount)
	end)

	local paletteUI
	paletteUI = PaletteUIBuilder.Create(screenGui, {
		OnColorPicked = function(color)
			currentColor = color
		end,
		OnEyedropperToggled = function(isActive)
			if paintModeActive then
				-- Пипетка недоступна, пока включена кисть (камера смотрит на себя) -
				-- возвращаем кнопку в невключённое состояние, чтобы не было
				-- визуального рассогласования (кнопка "горит", а пипетка не работает).
				paletteUI.SetEyedropperActive(false)
				return
			end
			eyedropperActive = isActive
		end,
	})

	local brushControlsUI
	brushControlsUI = BrushControlsUIBuilder.Create(screenGui, {
		defaultSize = currentBrushSize,
		OnSizeChanged = function(size)
			currentBrushSize = size
		end,
		OnPaintModeToggled = function(wantsActive)
			if wantsActive then
				enterPaintMode(brushControlsUI)
			else
				exitPaintMode(brushControlsUI)
			end
		end,
	})

	-- InputBegan одинаково работает и для мыши (MouseButton1), и для тача на телефоне (Touch).
	UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
		if gameProcessedEvent then
			return -- нажатие пришлось на кнопку UI, а не на персонажа/мир
		end

		local isPointerInput = input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch

		if not isPointerInput then
			return
		end

		if paintModeActive then
			isDragging = true
			addStrokePoint(input.Position)
		elseif eyedropperActive then
			handleEyedropperTap(input.Position, paletteUI)
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not isDragging then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			addStrokePoint(input.Position)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			isDragging = false
		end
	end)

	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		camera = Workspace.CurrentCamera
	end)

	-- Если персонаж возродился во время активной кисти - выходим из режима,
	-- чтобы не держать камеру в Scriptable "в никуда" на новом теле
	player.CharacterAdded:Connect(function()
		exitPaintMode(brushControlsUI)
	end)

	task.spawn(strokeBatchLoop)
end

return PaintClient
