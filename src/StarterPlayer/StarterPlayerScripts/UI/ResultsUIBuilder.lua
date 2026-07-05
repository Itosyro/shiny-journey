-- ResultsUIBuilder.lua
-- Экран результатов раунда: список игроков, их роль, очки за раунд и общий счёт.

local ResultsUIBuilder = {}

function ResultsUIBuilder.Create(screenGui)
	local root = Instance.new("Frame")
	root.Name = "ResultsPanel"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.new(0.5, 0, 0.5, 0)
	root.Size = UDim2.new(0, 320, 0, 360)
	root.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
	root.BackgroundTransparency = 0.1
	root.Visible = false
	root.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = root

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -20, 0, 36)
	title.Position = UDim2.new(0, 10, 0, 10)
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Text = "Итоги раунда"
	title.Parent = root

	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.Size = UDim2.new(1, -20, 1, -56)
	scrollFrame.Position = UDim2.new(0, 10, 0, 50)
	scrollFrame.ScrollBarThickness = 6
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.Parent = root

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 4)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = scrollFrame

	local function clearRows()
		for _, child in ipairs(scrollFrame:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
	end

	local function addRow(order, text, color)
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 26)
		row.LayoutOrder = order
		row.Parent = scrollFrame

		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 1, 0)
		label.Font = Enum.Font.Gotham
		label.TextScaled = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = color or Color3.fromRGB(255, 255, 255)
		label.Text = text
		label.Parent = row
	end

	return {
		Show = function(results)
			clearRows()
			for i, entry in ipairs(results) do
				local roleText = entry.role == "Seeker" and "Искатель" or "Прячущийся"
				local color = entry.role == "Seeker" and Color3.fromRGB(255, 120, 120) or Color3.fromRGB(150, 220, 255)
				addRow(i, string.format("%s (%s): +%d очков (всего %d)", entry.name, roleText, entry.roundScore, entry.totalScore), color)
			end
			root.Visible = true
		end,
		Hide = function()
			root.Visible = false
		end,
	}
end

return ResultsUIBuilder
