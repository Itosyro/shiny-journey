-- LobbyUIBuilder.lua
-- Экран лобби: список текущих игроков, статус ожидания/отсчёта и кнопки
-- "Создать приватную комнату" / "Присоединиться по паролю" (см. DECISIONS.md, п.20).
-- Пароль вводится обычным видимым TextBox, без маскировки - пароли тут не для
-- защиты аккаунта, а просто "код доступа для друзей", прятать его не нужно.

local LobbyUIBuilder = {}

local BUTTON_COLOR = Color3.fromRGB(0, 122, 200)
local ERROR_COLOR = Color3.fromRGB(255, 90, 90)

-- options: { OnCreateRoom = function(password) end, OnJoinRoom = function(password) end }
function LobbyUIBuilder.Create(screenGui, options)
	local root = Instance.new("Frame")
	root.Name = "LobbyPanel"
	-- Правый верхний угол, компактнее - раньше панель по центру экрана
	-- перекрывала бы покрасочную камеру лобби (см. MEGA_PLAN.md 1.3.6).
	root.AnchorPoint = Vector2.new(1, 0)
	root.Position = UDim2.new(1, -10, 0, 10)
	root.Size = UDim2.new(0, 280, 0, 330)
	root.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
	root.BackgroundTransparency = 0.1
	root.Visible = false
	root.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = root

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -20, 0, 32)
	title.Position = UDim2.new(0, 10, 0, 8)
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Text = "Лобби"
	title.Parent = root

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.BackgroundTransparency = 1
	statusLabel.Size = UDim2.new(1, -20, 0, 24)
	statusLabel.Position = UDim2.new(0, 10, 0, 40)
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.TextScaled = true
	statusLabel.TextColor3 = Color3.fromRGB(200, 220, 255)
	statusLabel.Text = "Ждём игроков..."
	statusLabel.Parent = root

	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "PlayerList"
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.Size = UDim2.new(1, -20, 0, 150)
	scrollFrame.Position = UDim2.new(0, 10, 0, 68)
	scrollFrame.ScrollBarThickness = 6
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.Parent = root

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 4)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = scrollFrame

	-- Тоггл режима (Classic/Infection, см. DECISIONS.md, п.30) - в свободном
	-- промежутке между списком игроков и кнопками приватных комнат.
	local gameModeButton = Instance.new("TextButton")
	gameModeButton.Name = "GameModeButton"
	gameModeButton.Size = UDim2.new(1, -20, 0, 28)
	gameModeButton.Position = UDim2.new(0, 10, 0, 222)
	gameModeButton.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
	gameModeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	gameModeButton.Font = Enum.Font.GothamBold
	gameModeButton.TextScaled = true
	gameModeButton.Text = "Режим: Infection ▸"
	gameModeButton.Parent = root

	local gameModeButtonCorner = Instance.new("UICorner")
	gameModeButtonCorner.CornerRadius = UDim.new(0, 8)
	gameModeButtonCorner.Parent = gameModeButton

	gameModeButton.MouseButton1Click:Connect(function()
		if options.OnToggleGameMode then
			options.OnToggleGameMode()
		end
	end)

	local buttonsRow = Instance.new("Frame")
	buttonsRow.BackgroundTransparency = 1
	buttonsRow.Size = UDim2.new(1, -20, 0, 44)
	buttonsRow.Position = UDim2.new(0, 10, 1, -56)
	buttonsRow.Parent = root

	local buttonsLayout = Instance.new("UIListLayout")
	buttonsLayout.FillDirection = Enum.FillDirection.Horizontal
	buttonsLayout.Padding = UDim.new(0, 8)
	buttonsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	buttonsLayout.Parent = buttonsRow

	local function createButton(text, order)
		local button = Instance.new("TextButton")
		button.Size = UDim2.new(0.5, -4, 1, 0)
		button.BackgroundColor3 = BUTTON_COLOR
		button.TextColor3 = Color3.fromRGB(255, 255, 255)
		button.Font = Enum.Font.GothamBold
		button.TextScaled = true
		button.Text = text
		button.LayoutOrder = order
		button.Parent = buttonsRow

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 10)
		btnCorner.Parent = button

		return button
	end

	local createRoomButton = createButton("Создать комнату", 1)
	local joinRoomButton = createButton("Войти по паролю", 2)

	-- Оверлей ввода пароля - один и тот же для создания и входа, режим
	-- определяется полем mode ("Create" | "Join"), выставляется перед показом.
	local passwordOverlay = Instance.new("Frame")
	passwordOverlay.Name = "PasswordOverlay"
	passwordOverlay.AnchorPoint = Vector2.new(0.5, 0.5)
	passwordOverlay.Position = UDim2.new(0.5, 0, 0.5, 0)
	passwordOverlay.Size = UDim2.new(1, 0, 1, 0)
	passwordOverlay.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
	passwordOverlay.BackgroundTransparency = 0.05
	passwordOverlay.Visible = false
	passwordOverlay.ZIndex = 5
	passwordOverlay.Parent = root

	local overlayCorner = Instance.new("UICorner")
	overlayCorner.CornerRadius = UDim.new(0, 14)
	overlayCorner.Parent = passwordOverlay

	local overlayTitle = Instance.new("TextLabel")
	overlayTitle.Name = "OverlayTitle"
	overlayTitle.BackgroundTransparency = 1
	overlayTitle.Size = UDim2.new(1, -20, 0, 32)
	overlayTitle.Position = UDim2.new(0, 10, 0, 16)
	overlayTitle.Font = Enum.Font.GothamBold
	overlayTitle.TextScaled = true
	overlayTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	overlayTitle.ZIndex = 5
	overlayTitle.Parent = passwordOverlay

	local passwordBox = Instance.new("TextBox")
	passwordBox.Name = "PasswordBox"
	passwordBox.Size = UDim2.new(1, -40, 0, 44)
	passwordBox.Position = UDim2.new(0, 20, 0, 60)
	passwordBox.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
	passwordBox.TextColor3 = Color3.fromRGB(255, 255, 255)
	-- Подсказка про регистр кириллицы - see AUDIT_FABLE5.md S5:
	-- string.lower() в Luau не трогает кириллицу, поэтому "ДОМ1" и "дом1" -
	-- разные пароли (в отличие от латиницы, где регистр не важен).
	passwordBox.PlaceholderText = "Пароль комнаты (кириллица регистрозависима)"
	passwordBox.PlaceholderColor3 = Color3.fromRGB(150, 150, 150)
	passwordBox.Font = Enum.Font.Gotham
	passwordBox.TextScaled = true
	passwordBox.ClearTextOnFocus = false
	passwordBox.Text = ""
	passwordBox.ZIndex = 5
	passwordBox.Parent = passwordOverlay

	local boxCorner = Instance.new("UICorner")
	boxCorner.CornerRadius = UDim.new(0, 8)
	boxCorner.Parent = passwordBox

	local errorLabel = Instance.new("TextLabel")
	errorLabel.Name = "ErrorLabel"
	errorLabel.BackgroundTransparency = 1
	errorLabel.Size = UDim2.new(1, -20, 0, 44)
	errorLabel.Position = UDim2.new(0, 10, 0, 108)
	errorLabel.Font = Enum.Font.Gotham
	errorLabel.TextScaled = true
	errorLabel.TextWrapped = true
	errorLabel.TextColor3 = ERROR_COLOR
	errorLabel.Text = ""
	errorLabel.ZIndex = 5
	errorLabel.Parent = passwordOverlay

	local overlayButtonsRow = Instance.new("Frame")
	overlayButtonsRow.BackgroundTransparency = 1
	overlayButtonsRow.Size = UDim2.new(1, -40, 0, 44)
	overlayButtonsRow.Position = UDim2.new(0, 20, 1, -60)
	overlayButtonsRow.ZIndex = 5
	overlayButtonsRow.Parent = passwordOverlay

	local overlayButtonsLayout = Instance.new("UIListLayout")
	overlayButtonsLayout.FillDirection = Enum.FillDirection.Horizontal
	overlayButtonsLayout.Padding = UDim.new(0, 8)
	overlayButtonsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	overlayButtonsLayout.Parent = overlayButtonsRow

	local confirmButton = Instance.new("TextButton")
	confirmButton.Size = UDim2.new(0.5, -4, 1, 0)
	confirmButton.BackgroundColor3 = BUTTON_COLOR
	confirmButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	confirmButton.Font = Enum.Font.GothamBold
	confirmButton.TextScaled = true
	confirmButton.Text = "Подтвердить"
	confirmButton.LayoutOrder = 1
	confirmButton.ZIndex = 5
	confirmButton.Parent = overlayButtonsRow

	local confirmCorner = Instance.new("UICorner")
	confirmCorner.CornerRadius = UDim.new(0, 10)
	confirmCorner.Parent = confirmButton

	local cancelButton = Instance.new("TextButton")
	cancelButton.Size = UDim2.new(0.5, -4, 1, 0)
	cancelButton.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
	cancelButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	cancelButton.Font = Enum.Font.GothamBold
	cancelButton.TextScaled = true
	cancelButton.Text = "Отмена"
	cancelButton.LayoutOrder = 2
	cancelButton.ZIndex = 5
	cancelButton.Parent = overlayButtonsRow

	local cancelCorner = Instance.new("UICorner")
	cancelCorner.CornerRadius = UDim.new(0, 10)
	cancelCorner.Parent = cancelButton

	local overlayMode = nil -- "Create" | "Join"

	local function openOverlay(mode)
		overlayMode = mode
		overlayTitle.Text = (mode == "Create") and "Создать приватную комнату" or "Присоединиться по паролю"
		passwordBox.Text = ""
		errorLabel.Text = ""
		passwordOverlay.Visible = true
	end

	local function closeOverlay()
		passwordOverlay.Visible = false
		overlayMode = nil
	end

	createRoomButton.MouseButton1Click:Connect(function()
		openOverlay("Create")
	end)

	joinRoomButton.MouseButton1Click:Connect(function()
		openOverlay("Join")
	end)

	cancelButton.MouseButton1Click:Connect(closeOverlay)

	confirmButton.MouseButton1Click:Connect(function()
		local password = passwordBox.Text
		if overlayMode == "Create" and options.OnCreateRoom then
			options.OnCreateRoom(password)
		elseif overlayMode == "Join" and options.OnJoinRoom then
			options.OnJoinRoom(password)
		end
	end)

	local function clearPlayerRows()
		-- Строки списка - TextLabel (см. UpdatePlayers ниже), НЕ Frame. Проверка
		-- именно по TextLabel: раньше тут стояло IsA("Frame"), из-за чего строки
		-- никогда не удалялись и список дублировался при каждом входе/выходе
		-- игрока (найдено аудитом Fable 5, см. AUDIT_FABLE5.md).
		for _, child in ipairs(scrollFrame:GetChildren()) do
			if child:IsA("TextLabel") then
				child:Destroy()
			end
		end
	end

	return {
		SetVisible = function(visible)
			root.Visible = visible
			if not visible then
				closeOverlay()
			end
		end,
		SetStatusText = function(text)
			statusLabel.Text = text
		end,
		SetGameModeText = function(text)
			gameModeButton.Text = text
		end,
		UpdatePlayers = function(players)
			clearPlayerRows()
			for i, plr in ipairs(players) do
				local row = Instance.new("TextLabel")
				row.BackgroundTransparency = 1
				row.Size = UDim2.new(1, 0, 0, 24)
				row.LayoutOrder = i
				row.Font = Enum.Font.Gotham
				row.TextScaled = true
				row.TextXAlignment = Enum.TextXAlignment.Left
				row.TextColor3 = Color3.fromRGB(255, 255, 255)
				row.Text = plr.Name
				row.Parent = scrollFrame
			end
		end,
		-- Ошибка приходит с сервера уже во время открытого оверлея (создание/вход
		-- ждёт ответа секунду-две) - просто показываем текст, оверлей не закрываем,
		-- чтобы игрок мог сразу поправить пароль и повторить попытку.
		ShowError = function(message)
			errorLabel.Text = message
		end,
	}
end

return LobbyUIBuilder
