-- LobbyUIClient.lua
-- Показывает экран лобби (см. UI/LobbyUIBuilder.lua) только пока фаза раунда -
-- "Lobby": список игроков, статус ожидания/отсчёта, кнопки приватных комнат.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local GameMode = require(ReplicatedStorage.Modules.GameMode)
local LobbyUIBuilder = require(script.Parent.UI.LobbyUIBuilder)

local LobbyUIClient = {}

function LobbyUIClient.Init(remotesFolder)
	local playerGui = player:WaitForChild("PlayerGui")
	local screenGui = playerGui:WaitForChild("PaintGui", 5)
	if not screenGui then
		screenGui = Instance.new("ScreenGui")
		screenGui.Name = "LobbyGui"
		screenGui.Parent = playerGui
	end

	local roundStateRemote = remotesFolder:WaitForChild("RoundStateChanged")
	local timerRemote = remotesFolder:WaitForChild("RoundTimerTick")
	local createRoomRemote = remotesFolder:WaitForChild("CreatePrivateRoom")
	local joinRoomRemote = remotesFolder:WaitForChild("JoinPrivateRoom")
	local errorRemote = remotesFolder:WaitForChild("PrivateRoomError")
	local requestGameModeRemote = remotesFolder:WaitForChild("RequestGameMode")

	local currentPhase = "Lobby"
	-- true, пока сервер шлёт playersNeeded/playersCurrent (см. RoundManager.waitForEnoughPlayers) -
	-- как только начнётся отсчёт до старта раунда, extra перестаёт их нести, и
	-- статус переключается на обратный отсчёт (см. ниже, RoundTimerTick).
	local isWaitingForPlayers = true

	local lobbyUI = LobbyUIBuilder.Create(screenGui, {
		OnCreateRoom = function(password)
			createRoomRemote:FireServer(password)
		end,
		OnJoinRoom = function(password)
			joinRoomRemote:FireServer(password)
		end,
		-- Голосования нет (YAGNI, см. DECISIONS.md, п.30) - любой игрок в лобби
		-- переключает режим на следующий, последний нажавший выигрывает.
		OnToggleGameMode = function()
			local nextMode = (GameMode.GetCurrent() == GameMode.Infection) and GameMode.Classic or GameMode.Infection
			requestGameModeRemote:FireServer(nextMode)
		end,
	})

	local function updateGameModeText()
		lobbyUI.SetGameModeText(string.format("Режим: %s ▸", GameMode.GetCurrent()))
	end

	updateGameModeText()
	GameMode.GetChangedSignal():Connect(updateGameModeText)

	local function refreshPlayerList()
		lobbyUI.UpdatePlayers(Players:GetPlayers())
	end

	refreshPlayerList()
	Players.PlayerAdded:Connect(refreshPlayerList)
	Players.PlayerRemoving:Connect(function()
		-- Игрок, который уходит, ещё присутствует в Players:GetPlayers() в момент
		-- этого события - обновляем список на следующем кадре, когда он уже уйдёт.
		task.defer(refreshPlayerList)
	end)

	-- Единая точка обновления статуса - вызывается и из RoundStateChanged (когда
	-- меняется сам режим ожидания/отсчёта), и из каждого RoundTimerTick (когда
	-- меняется только число секунд) - без дублирования string.format в двух местах.
	local function applyStatus(timeLeft)
		if isWaitingForPlayers then
			return -- текст уже выставлен из extra.playersNeeded/playersCurrent
		end
		lobbyUI.SetStatusText(string.format("Раунд начнётся через: %d", timeLeft or 0))
	end

	roundStateRemote.OnClientEvent:Connect(function(state, timeLeft, extra)
		currentPhase = state
		lobbyUI.SetVisible(state == "Lobby")

		if state ~= "Lobby" then
			return
		end

		if extra and extra.playersNeeded then
			isWaitingForPlayers = true
			lobbyUI.SetStatusText(string.format("Ждём игроков: %d/%d", extra.playersCurrent, extra.playersNeeded))
		else
			isWaitingForPlayers = false
			applyStatus(timeLeft)
		end
	end)

	timerRemote.OnClientEvent:Connect(function(timeLeft)
		if currentPhase == "Lobby" then
			applyStatus(timeLeft)
		end
	end)

	errorRemote.OnClientEvent:Connect(function(message)
		lobbyUI.ShowError(message)
	end)
end

return LobbyUIClient
