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
		label.TextWrapped = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = color or Color3.fromRGB(255, 255, 255)
		label.Text = text
		label.Parent = row
	end

	-- Небольшой заголовок-разделитель секции (Топ раунда / Лучшая маскировка /
	-- полный список) - тот же ряд, что и addRow, только жирным и бледнее.
	local function addHeader(order, text)
		addRow(order, text, Color3.fromRGB(190, 190, 190))
	end

	return {
		-- results: массив {name, role, roundScore, totalScore, missedPoints}
		-- (missedPoints - очки Missed Point Ranking за раунд, см. DECISIONS.md,
		-- п.22). Показываем топ-3 раунда по roundScore и отдельную шуточную
		-- номинацию "Лучшая маскировка" (максимальный missedPoints), а затем
		-- полный список всех участников - как и раньше.
		Show = function(results)
			clearRows()
			local order = 0

			local sortedByRoundScore = table.clone(results)
			table.sort(sortedByRoundScore, function(a, b)
				return a.roundScore > b.roundScore
			end)

			local topCount = math.min(3, #sortedByRoundScore)
			if topCount > 0 then
				order += 1
				addHeader(order, "🏆 Топ раунда")
				for i = 1, topCount do
					local entry = sortedByRoundScore[i]
					order += 1
					addRow(order, string.format("%d. %s - %d очков", i, entry.name, entry.roundScore), Color3.fromRGB(255, 215, 0))
				end
			end

			-- Показываем номинацию, только если кто-то реально заработал очки
			-- Missed Point Ranking - иначе пустая номинация выглядела бы как
			-- баг, а не как честное "в этот раз никто не рискнул прятаться на виду".
			local bestMasking = nil
			for _, entry in ipairs(results) do
				local missedPoints = entry.missedPoints or 0
				if missedPoints > 0 and (not bestMasking or missedPoints > bestMasking.missedPoints) then
					bestMasking = entry
				end
			end
			if bestMasking then
				order += 1
				addHeader(order, "🎭 Лучшая маскировка раунда")
				order += 1
				addRow(order, string.format("%s (+%d - был на виду и не попался)", bestMasking.name, bestMasking.missedPoints), Color3.fromRGB(150, 255, 180))
			end

			order += 1
			addHeader(order, "Все игроки")
			for _, entry in ipairs(results) do
				local roleText = entry.role == "Seeker" and "Искатель" or "Прячущийся"
				local color = entry.role == "Seeker" and Color3.fromRGB(255, 120, 120) or Color3.fromRGB(150, 220, 255)
				order += 1
				addRow(order, string.format("%s (%s): +%d очков (всего %d)", entry.name, roleText, entry.roundScore, entry.totalScore), color)
			end

			root.Visible = true
		end,
		Hide = function()
			root.Visible = false
		end,
	}
end

return ResultsUIBuilder
