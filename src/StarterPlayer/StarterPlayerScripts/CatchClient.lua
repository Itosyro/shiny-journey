-- CatchClient.lua
-- Режим Proximity (см. DECISIONS.md, п.12): прячет от Hiders подсказку
-- "Поймать" над другими Hiders. Сервер шлёт этот RemoteEvent только
-- клиентам-Hiders (CatchService.StartSeekingPhase), поэтому Seekers его не
-- получают и видят подсказки как обычно.
--
-- Режим RangedTag (текущий, см. DECISIONS.md, п.29): прицел + большая
-- кнопка "Метка" для Seekers в фазу Seeking - клиент лишь отправляет
-- направление камеры (юнит-вектор), вся честная проверка (кто, откуда,
-- дистанция, попадание) - на сервере (CatchService.onRequestTag).

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local RoleUtil = require(ReplicatedStorage.Modules.RoleUtil)

local player = Players.LocalPlayer

local CatchClient = {}

function CatchClient.Init(remotesFolder)
	local hideRemote = remotesFolder:WaitForChild("HideCatchPromptsFromHiders")

	hideRemote.OnClientEvent:Connect(function(prompts)
		for _, prompt in ipairs(prompts) do
			if prompt and prompt:IsA("ProximityPrompt") then
				prompt.Enabled = false
			end
		end
	end)

	if GameConfig.CATCH_MODE ~= "RangedTag" then
		return -- Proximity-режим: прицел/кнопка метки не нужны
	end

	local requestTagRemote = remotesFolder:WaitForChild("RequestTag")
	local roundStateRemote = remotesFolder:WaitForChild("RoundStateChanged")

	local playerGui = player:WaitForChild("PlayerGui")
	local screenGui = playerGui:WaitForChild("PaintGui", 5)
	if not screenGui then
		screenGui = Instance.new("ScreenGui")
		screenGui.Name = "CatchGui"
		screenGui.Parent = playerGui
	end

	local currentPhase = "Lobby"
	local tagButtonDefaultColor = Color3.fromRGB(200, 30, 30)

	-- Прицел - маленькая точка по центру экрана, видна только Seeker'ам в
	-- фазу поиска (тот же гейтинг-паттерн, что WhistlePanel).
	local crosshair = Instance.new("Frame")
	crosshair.Name = "Crosshair"
	crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
	crosshair.Position = UDim2.new(0.5, 0, 0.5, 0)
	crosshair.Size = UDim2.new(0, 8, 0, 8)
	crosshair.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
	crosshair.BackgroundTransparency = 0.2
	crosshair.BorderSizePixel = 0
	crosshair.Visible = false
	crosshair.Parent = screenGui

	local crosshairCorner = Instance.new("UICorner")
	crosshairCorner.CornerRadius = UDim.new(1, 0)
	crosshairCorner.Parent = crosshair

	-- Кнопка справа-по-центру экрана - основной способ метки на телефоне
	-- (палец не закрывает прицел в центре).
	local tagButton = Instance.new("TextButton")
	tagButton.Name = "TagButton"
	tagButton.AnchorPoint = Vector2.new(1, 0.5)
	tagButton.Position = UDim2.new(1, -20, 0.5, 0)
	tagButton.Size = UDim2.new(0, 84, 0, 84)
	tagButton.BackgroundColor3 = tagButtonDefaultColor
	tagButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	tagButton.Font = Enum.Font.GothamBold
	tagButton.TextScaled = true
	tagButton.Text = "🎯 Метка"
	tagButton.Visible = false
	tagButton.Parent = screenGui

	local tagButtonCorner = Instance.new("UICorner")
	tagButtonCorner.CornerRadius = UDim.new(1, 0)
	tagButtonCorner.Parent = tagButton

	local function updateVisibility()
		local visible = RoleUtil.IsSeeker(player) and currentPhase == "Seeking"
		crosshair.Visible = visible
		tagButton.Visible = visible
	end

	local function fireTag()
		requestTagRemote:FireServer(Workspace.CurrentCamera.CFrame.LookVector)

		-- Кулдаун-фидбек - чисто клиентская косметика (серая кнопка на
		-- время кулдауна), сервер всё равно проверяет реальный кулдаун сам.
		tagButton.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
		task.delay(GameConfig.TAG_COOLDOWN_SECONDS, function()
			tagButton.BackgroundColor3 = tagButtonDefaultColor
		end)
	end

	tagButton.MouseButton1Click:Connect(fireTag)

	-- ЛКМ на десктопе - клик в любом месте экрана (не только по кнопке)
	-- целится центром камеры, как в обычном шутере.
	UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
		if gameProcessedEvent or not tagButton.Visible then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			fireTag()
		end
	end)

	roundStateRemote.OnClientEvent:Connect(function(state)
		currentPhase = state
		updateVisibility()
	end)

	player:GetPropertyChangedSignal("Team"):Connect(updateVisibility)

	updateVisibility()
end

return CatchClient
