-- CharacterStyleService.lua
-- Единая точка "как выглядит игрок" - белый "пластилиновый" безликий стиль,
-- как у Hiders/Seekers в оригинале MECCHA CHAMELEON. См. MEGA_PLAN.md,
-- Часть 2, DECISIONS.md, п.26.
--
-- LoadCharacterAppearance=false (см. Main.server.lua) уже убирает каталожную
-- одежду/аксессуары - этот модуль дополнительно красит все части тела в
-- один белый цвет и убирает дефолтное лицо. Авторы подтвердили: лицо
-- убираем - полностью безликий стиль ближе к оригиналу (см. DECISIONS.md,
-- п.26).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local CharacterStyleService = {}

local function applyStyle(character)
	-- HumanoidRootPart нарочно пропускаем - он и так всегда невидим
	-- (Transparency=1), красить его незачем.
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			-- Transparency НЕ трогаем - SpectatorService.hideAndImmobilize
			-- управляет ею отдельно (режим зрителя), конфликтовать нельзя.
			part.Color = GameConfig.BASE_BODY_COLOR
			part.Material = Enum.Material.SmoothPlastic
		end
	end

	local head = character:FindFirstChild("Head")
	local face = head and head:FindFirstChild("face")
	if face then
		face:Destroy()
	end
end

function CharacterStyleService.Init()
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(applyStyle)
	end)
end

return CharacterStyleService
