-- WhistleClient.lua
-- Кнопка "Свистнуть" + индикатор обратного отсчёта до автоматического свистка.
-- Видна только Hiders, и только в фазу поиска (Seeking) - см. WhistleService.lua
-- и DECISIONS.md, п.15. Новый файл - механика свистка появилась по прямому
-- запросу автора после аудита Opus.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local player = Players.LocalPlayer

local WhistleClient = {}

local currentPhase = "Lobby"

local function isHider()
	return player.Team ~= nil and player.Team.Name == GameConfig.TEAM_HIDERS_NAME
end

function WhistleClient.Init(remotesFolder)
	local requestWhistleRemote = remotesFolder:WaitForChild("RequestWhistle")
	local countdownRemote = remotesFolder:WaitForChild("WhistleCountdownUpdate")
	local roundStateRemote = remotesFolder:WaitForChild("RoundStateChanged")

	local playerGui = player:WaitForChild("PlayerGui")
	local screenGui = playerGui:WaitForChild("PaintGui", 5)
	if not screenGui then
		screenGui = Instance.new("ScreenGui")
		screenGui.Name = "WhistleGui"
		screenGui.Parent = playerGui
	end

	local root = Instance.new("Frame")
	root.Name = "WhistlePanel"
	root.AnchorPoint = Vector2.new(0, 1)
	-- Позиция поднята выше PosePickerPanel (см. UI/PosePickerUIBuilder.lua),
	-- которая теперь занимает всю ширину экрана там, где раньше была кнопка
	-- заморозки (см. DECISIONS.md, п.17)
	root.Position = UDim2.new(0, 12, 1, -380)
	root.Size = UDim2.new(0, 160, 0, 76)
	root.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
	root.BackgroundTransparency = 0.25
	root.Visible = false
	root.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = root

	local countdownLabel = Instance.new("TextLabel")
	countdownLabel.Name = "CountdownLabel"
	countdownLabel.BackgroundTransparency = 1
	countdownLabel.Size = UDim2.new(1, -12, 0, 20)
	countdownLabel.Position = UDim2.new(0, 6, 0, 4)
	countdownLabel.Font = Enum.Font.Gotham
	countdownLabel.TextScaled = true
	countdownLabel.TextColor3 = Color3.fromRGB(255, 220, 0)
	countdownLabel.Text = "До свистка: --"
	countdownLabel.Parent = root

	-- Полоска обратного отсчёта - "тает" по мере приближения принудительного свистка
	local barTrack = Instance.new("Frame")
	barTrack.Name = "CountdownBarTrack"
	barTrack.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	barTrack.Size = UDim2.new(1, -12, 0, 10)
	barTrack.Position = UDim2.new(0, 6, 0, 26)
	barTrack.Parent = root

	local barTrackCorner = Instance.new("UICorner")
	barTrackCorner.CornerRadius = UDim.new(1, 0)
	barTrackCorner.Parent = barTrack

	local barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.BorderSizePixel = 0
	barFill.BackgroundColor3 = Color3.fromRGB(255, 220, 0)
	barFill.Size = UDim2.new(1, 0, 1, 0)
	barFill.Parent = barTrack

	local barFillCorner = Instance.new("UICorner")
	barFillCorner.CornerRadius = UDim.new(1, 0)
	barFillCorner.Parent = barFill

	local whistleButton = Instance.new("TextButton")
	whistleButton.Name = "WhistleButton"
	whistleButton.Size = UDim2.new(1, -12, 0, 28)
	whistleButton.Position = UDim2.new(0, 6, 0, 42)
	whistleButton.BackgroundColor3 = Color3.fromRGB(90, 90, 20)
	whistleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	whistleButton.Font = Enum.Font.GothamBold
	whistleButton.TextScaled = true
	whistleButton.Text = "Свистнуть"
	whistleButton.Parent = root

	local whistleButtonCorner = Instance.new("UICorner")
	whistleButtonCorner.CornerRadius = UDim.new(0, 8)
	whistleButtonCorner.Parent = whistleButton

	whistleButton.MouseButton1Click:Connect(function()
		requestWhistleRemote:FireServer()
	end)

	local function updateVisibility()
		root.Visible = isHider() and currentPhase == "Seeking"
	end

	countdownRemote.OnClientEvent:Connect(function(secondsLeft)
		countdownLabel.Text = string.format("До свистка: %d", secondsLeft)
		local fraction = math.clamp(secondsLeft / GameConfig.WHISTLE_AUTO_INTERVAL_SECONDS, 0, 1)
		barFill.Size = UDim2.new(fraction, 0, 1, 0)
	end)

	roundStateRemote.OnClientEvent:Connect(function(state)
		currentPhase = state
		updateVisibility()
	end)

	player:GetPropertyChangedSignal("Team"):Connect(updateVisibility)

	updateVisibility()
end

return WhistleClient
