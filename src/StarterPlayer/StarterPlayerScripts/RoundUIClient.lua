-- RoundUIClient.lua
-- Слушает события раунда с сервера и обновляет HUD (фаза, таймер, роль) и
-- экран результатов.

local Players = game:GetService("Players")

local HUDBuilder = require(script.Parent.UI.HUDBuilder)
local ResultsUIBuilder = require(script.Parent.UI.ResultsUIBuilder)

local player = Players.LocalPlayer

local RoundUIClient = {}

local PHASE_NAMES_RU = {
	Lobby = "Лобби - ждём игроков",
	Hiding = "Прячьтесь и красьтесь!",
	Seeking = "Искатели ищут!",
	RoundEnd = "Раунд окончен",
}

function RoundUIClient.Init(remotesFolder)
	local playerGui = player:WaitForChild("PlayerGui")
	local screenGui = playerGui:WaitForChild("PaintGui", 5)
	if not screenGui then
		screenGui = Instance.new("ScreenGui")
		screenGui.Name = "RoundGui"
		screenGui.Parent = playerGui
	end

	local hud = HUDBuilder.Create(screenGui)
	local resultsUI = ResultsUIBuilder.Create(screenGui)

	local roundStateRemote = remotesFolder:WaitForChild("RoundStateChanged")
	local timerRemote = remotesFolder:WaitForChild("RoundTimerTick")
	local caughtRemote = remotesFolder:WaitForChild("PlayerCaught")
	local resultsRemote = remotesFolder:WaitForChild("RoundResults")

	local function isLocalPlayerSeeker()
		return player.Team ~= nil and player.Team.Name == "Seekers"
	end

	roundStateRemote.OnClientEvent:Connect(function(state, timeLeft, extra)
		hud.SetPhaseText(PHASE_NAMES_RU[state] or state)
		hud.SetTimerSeconds(timeLeft or 0)

		if state == "Lobby" then
			resultsUI.Hide()
			hud.SetRoleText("")
			hud.SetFoundText("")
		elseif state == "Hiding" then
			resultsUI.Hide()
			hud.SetRoleText(isLocalPlayerSeeker() and "Ты Искатель (жди в комнате)" or "Ты Прячущийся - красься!")
			hud.SetFoundText("")
		elseif state == "Seeking" then
			hud.SetRoleText(isLocalPlayerSeeker() and "Ты Искатель - ищи всех!" or "Ты Прячущийся - замри!")
		elseif state == "RoundEnd" then
			if extra and extra.results then
				resultsUI.Show(extra.results)
			end
		end
	end)

	timerRemote.OnClientEvent:Connect(function(timeLeft)
		hud.SetTimerSeconds(timeLeft)
	end)

	caughtRemote.OnClientEvent:Connect(function(hiderName, seekerName, remainingCount)
		hud.SetFoundText(string.format("Найден: %s (искателем %s). Осталось: %d", hiderName, seekerName, remainingCount))
	end)

	resultsRemote.OnClientEvent:Connect(function(results)
		resultsUI.Show(results)
	end)
end

return RoundUIClient
