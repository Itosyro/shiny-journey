-- RoundUIClient.lua
-- Слушает события раунда с сервера и обновляет HUD (фаза, таймер, роль) и
-- экран результатов.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameMode = require(ReplicatedStorage.Modules.GameMode)
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
	local missedPointRemote = remotesFolder:WaitForChild("MissedPointRankingUpdate")

	local currentPhase = "Lobby"

	local function isLocalPlayerSeeker()
		return player.Team ~= nil and player.Team.Name == "Seekers"
	end

	-- Вынесено в отдельную функцию и переиспользуется и при смене фазы, и при
	-- смене команды (Team) - иначе в режиме Infection (см. DECISIONS.md, п.18)
	-- HUD игрока, которого поймали и превратили в Seeker посреди фазы Seeking,
	-- продолжал бы показывать устаревшую роль "Ты Прячущийся" до конца раунда.
	local function updateRoleText()
		if currentPhase == "Hiding" then
			hud.SetRoleText(isLocalPlayerSeeker() and "Ты Искатель (жди в комнате)" or "Ты Прячущийся - красься!")
		elseif currentPhase == "Seeking" then
			hud.SetRoleText(isLocalPlayerSeeker() and "Ты Искатель - ищи всех!" or "Ты Прячущийся - замри!")
		end
	end

	roundStateRemote.OnClientEvent:Connect(function(state, timeLeft, extra)
		currentPhase = state
		hud.SetPhaseText(PHASE_NAMES_RU[state] or state)
		hud.SetTimerSeconds(timeLeft or 0)

		if state == "Lobby" then
			resultsUI.Hide()
			hud.SetRoleText("")
			hud.SetFoundText("")
			hud.SetMissedPointText("")
		elseif state == "Hiding" then
			resultsUI.Hide()
			updateRoleText()
			hud.SetFoundText("")
			hud.SetMissedPointText("")
		elseif state == "Seeking" then
			updateRoleText()
		elseif state == "RoundEnd" then
			if extra and extra.results then
				resultsUI.Show(extra.results)
			end
		end
	end)

	-- В режиме Infection роль игрока может смениться прямо во время фазы
	-- Seeking (пойманный Hider становится Seeker) - подхватываем это здесь.
	player:GetPropertyChangedSignal("Team"):Connect(updateRoleText)

	timerRemote.OnClientEvent:Connect(function(timeLeft)
		hud.SetTimerSeconds(timeLeft)
	end)

	caughtRemote.OnClientEvent:Connect(function(hiderName, seekerName, remainingCount)
		if hiderName == player.Name and GameMode.Current == GameMode.Infection then
			-- Личное уведомление тому, кого только что поймали - роль сменилась
			-- незаметно (без перезахода/лобби), стоит явно объяснить, что произошло.
			hud.SetFoundText("Тебя поймали! Теперь ты Искатель - лови остальных!")
		else
			hud.SetFoundText(string.format("Найден: %s (искателем %s). Осталось: %d", hiderName, seekerName, remainingCount))
		end
	end)

	resultsRemote.OnClientEvent:Connect(function(results)
		resultsUI.Show(results)
	end)

	-- Личный фидбек Missed Point Ranking (см. DECISIONS.md, п.22) - сервер
	-- шлёт это событие только самому Hider'у, поэтому никакой проверки роли
	-- тут не нужно: если это событие вообще пришло, значит получатель - Hider.
	missedPointRemote.OnClientEvent:Connect(function(total)
		hud.SetMissedPointText(string.format("Замечен, но не пойман! Маскировка: %d", total))
	end)
end

return RoundUIClient
