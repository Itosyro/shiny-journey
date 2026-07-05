-- PaintService.lua
-- Проверяет и применяет покраску частей тела персонажа.
-- Сервер главный (см. DECISIONS.md, п.1): клиент только предлагает цвет и часть
-- тела, а сервер решает, разрешено ли это, и меняет реальный цвет BasePart.Color.
-- Roblox сам разошлёт этот цвет всем остальным игрокам (см. DECISIONS.md, п.2).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local PaintService = {}

-- Заряды краски у каждого игрока: [Player] = { charges = число }
local brushData = {}

-- Заблокирована ли покраска у игрока прямо сейчас (например, он в позе)
local paintingBlocked = {}

local paintableLookup = {}
for _, name in ipairs(GameConfig.PAINTABLE_PART_NAMES) do
	paintableLookup[name] = true
end

local remotesRef

local function clamp01(n)
	return math.clamp(n, 0, 1)
end

local function sendChargesUpdate(player)
	local data = brushData[player]
	if data and remotesRef then
		remotesRef.BrushChargesUpdate:FireClient(player, data.charges, GameConfig.MAX_BRUSH_CHARGES)
	end
end

-- Фоновый цикл восстановления зарядов краски со временем
local function rechargeLoop()
	while true do
		task.wait(GameConfig.BRUSH_RECHARGE_SECONDS)
		for player, data in pairs(brushData) do
			if data.charges < GameConfig.MAX_BRUSH_CHARGES then
				data.charges += 1
				sendChargesUpdate(player)
			end
		end
	end
end

-- Сбросить заряды на полные - вызывается в начале фазы пряток
function PaintService.ResetCharges(player)
	brushData[player] = { charges = GameConfig.MAX_BRUSH_CHARGES }
	sendChargesUpdate(player)
end

-- Разрешить/запретить покраску игроку (например, запрещаем во время позы - см. FreezeService)
function PaintService.SetPaintingAllowed(player, allowed)
	paintingBlocked[player] = not allowed
end

local function isPaintingBlocked(player)
	return paintingBlocked[player] == true
end

local function onPaintCharacter(player, partName, color)
	-- Проверка типов входных данных, чтобы никто не сломал сервер левыми аргументами
	if typeof(partName) ~= "string" or typeof(color) ~= "Color3" then
		return
	end

	if not paintableLookup[partName] then
		return -- часть тела не входит в разрешённый список
	end

	if isPaintingBlocked(player) then
		return -- игрок сейчас в позе или в фазе поиска - красить нельзя
	end

	local data = brushData[player]
	if not data or data.charges <= 0 then
		return -- нет зарядов краски
	end

	local character = player.Character
	if not character then
		return
	end

	local part = character:FindFirstChild(partName)
	if not part or not part:IsA("BasePart") then
		return
	end

	-- Защита от левых цветов: пересобираем Color3 из чисел 0-1, чтобы отбросить возможный мусор
	local safeColor = Color3.new(clamp01(color.R), clamp01(color.G), clamp01(color.B))

	part.Color = safeColor

	data.charges -= 1
	sendChargesUpdate(player)
end

function PaintService.Init(remotes)
	remotesRef = remotes
	remotes.PaintCharacter.OnServerEvent:Connect(onPaintCharacter)

	Players.PlayerRemoving:Connect(function(player)
		brushData[player] = nil
		paintingBlocked[player] = nil
	end)

	task.spawn(rechargeLoop)
end

return PaintService
