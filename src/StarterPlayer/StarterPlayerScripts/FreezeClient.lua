-- FreezeClient.lua
-- Панель выбора позы на экране. При нажатии на пресет игрок замирает в нём, и
-- сервер включает анимацию именно этого пресета (см.
-- ServerScriptService/FreezeService.lua). Раньше здесь была одна кнопка
-- "Заморозиться/Разморозиться" без выбора конкретной позы - см. DECISIONS.md,
-- п.17. UI-часть (сама карусель кнопок) вынесена в UI/PosePickerUIBuilder.lua.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoleUtil = require(ReplicatedStorage.Modules.RoleUtil)
local PosePickerUIBuilder = require(script.Parent.UI.PosePickerUIBuilder)

local player = Players.LocalPlayer

local FreezeClient = {}

local currentPhase = "Lobby"
local freezeRemote

local function updatePanelAvailability(panel)
	-- Панель доступна ТОЛЬКО в фазе Hiding (см. требование задачи) - полностью
	-- скрываем её в остальных фазах и для Seekers. Полное скрытие, а не просто
	-- затемнение: Frame.Active не блокирует клики по дочерним кнопкам (в отличие
	-- от TextButton.Active у старой одиночной кнопки), поэтому только Visible
	-- надёжно защищает от нажатий, когда переключать позу нельзя. Это лишь
	-- клиентское зеркало серверного ограничения в FreezeService.onRequestFreeze
	-- (см. DECISIONS.md, п.13) - даже обойдя клиент, сервер всё равно откажет.
	panel.Root.Visible = RoleUtil.IsHider(player) and currentPhase == "Hiding"
end

function FreezeClient.Init(remotesFolder)
	freezeRemote = remotesFolder:WaitForChild("RequestFreeze")

	local playerGui = player:WaitForChild("PlayerGui")
	local screenGui = playerGui:WaitForChild("PaintGui", 5)
	if not screenGui then
		screenGui = Instance.new("ScreenGui")
		screenGui.Name = "FreezeGui"
		screenGui.Parent = playerGui
	end

	local posePicker = PosePickerUIBuilder.Create(screenGui, {
		OnPoseToggled = function(poseId, wantsActive)
			freezeRemote:FireServer(wantsActive, poseId)
		end,
	})

	-- Если персонаж возродился - сбрасываем подсветку выбранной позы на клиенте
	-- (сервер и так снимает реальную заморозку между раундами, см. RoundManager)
	player.CharacterAdded:Connect(function()
		posePicker.SetActivePose(nil)
		updatePanelAvailability(posePicker)
	end)

	-- Следим за фазой раунда и за сменой команды, чтобы прятать/блокировать
	-- панель для Seekers и вне фазы Hiding (см. isHider/updatePanelAvailability выше)
	local roundStateRemote = remotesFolder:WaitForChild("RoundStateChanged")
	roundStateRemote.OnClientEvent:Connect(function(state)
		currentPhase = state
		updatePanelAvailability(posePicker)

		-- Новый раунд/лобби - сбрасываем подсветку, чтобы не осталась "залипшей"
		-- с прошлого раунда
		if state == "Lobby" then
			posePicker.SetActivePose(nil)
		end
	end)

	player:GetPropertyChangedSignal("Team"):Connect(function()
		updatePanelAvailability(posePicker)
	end)

	updatePanelAvailability(posePicker)
end

return FreezeClient
