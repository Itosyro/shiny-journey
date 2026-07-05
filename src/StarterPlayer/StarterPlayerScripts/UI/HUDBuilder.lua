-- HUDBuilder.lua
-- Верхняя панель HUD: показывает текущую фазу раунда, таймер, роль игрока и
-- счётчик найденных Hiders. Строится кодом (см. DECISIONS.md, п.3).

local HUDBuilder = {}

function HUDBuilder.Create(screenGui)
	local root = Instance.new("Frame")
	root.Name = "HUD"
	root.AnchorPoint = Vector2.new(0.5, 0)
	root.Position = UDim2.new(0.5, 0, 0, 10)
	root.Size = UDim2.new(0, 260, 0, 70)
	root.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	root.BackgroundTransparency = 0.2
	root.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = root

	local phaseLabel = Instance.new("TextLabel")
	phaseLabel.Name = "PhaseLabel"
	phaseLabel.BackgroundTransparency = 1
	phaseLabel.Size = UDim2.new(1, -10, 0, 26)
	phaseLabel.Position = UDim2.new(0, 5, 0, 4)
	phaseLabel.Font = Enum.Font.GothamBold
	phaseLabel.TextScaled = true
	phaseLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	phaseLabel.Text = "Лобби"
	phaseLabel.Parent = root

	local timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "TimerLabel"
	timerLabel.BackgroundTransparency = 1
	timerLabel.Size = UDim2.new(1, -10, 0, 30)
	timerLabel.Position = UDim2.new(0, 5, 0, 32)
	timerLabel.Font = Enum.Font.GothamBold
	timerLabel.TextScaled = true
	timerLabel.TextColor3 = Color3.fromRGB(255, 220, 0)
	timerLabel.Text = "--:--"
	timerLabel.Parent = root

	local roleLabel = Instance.new("TextLabel")
	roleLabel.Name = "RoleLabel"
	roleLabel.AnchorPoint = Vector2.new(0.5, 0)
	roleLabel.Position = UDim2.new(0.5, 0, 0, -26)
	roleLabel.Size = UDim2.new(0, 220, 0, 22)
	roleLabel.BackgroundTransparency = 1
	roleLabel.Font = Enum.Font.Gotham
	roleLabel.TextScaled = true
	roleLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	roleLabel.Text = ""
	roleLabel.Parent = root

	local foundLabel = Instance.new("TextLabel")
	foundLabel.Name = "FoundLabel"
	foundLabel.AnchorPoint = Vector2.new(0.5, 0)
	foundLabel.Position = UDim2.new(0.5, 0, 1, 4)
	foundLabel.Size = UDim2.new(0, 260, 0, 22)
	foundLabel.BackgroundTransparency = 1
	foundLabel.Font = Enum.Font.Gotham
	foundLabel.TextScaled = true
	foundLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	foundLabel.Text = ""
	foundLabel.Parent = root

	local function formatTime(seconds)
		seconds = math.max(0, math.floor(seconds))
		local minutes = math.floor(seconds / 60)
		local secs = seconds % 60
		return string.format("%02d:%02d", minutes, secs)
	end

	return {
		SetPhaseText = function(text)
			phaseLabel.Text = text
		end,
		SetTimerSeconds = function(seconds)
			timerLabel.Text = formatTime(seconds)
		end,
		SetRoleText = function(text)
			roleLabel.Text = text
		end,
		SetFoundText = function(text)
			foundLabel.Text = text
		end,
	}
end

return HUDBuilder
