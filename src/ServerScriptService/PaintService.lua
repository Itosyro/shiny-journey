-- PaintService.lua
-- Проверяет и применяет "мазки" кисти на теле персонажа. Раньше покраска была
-- кнопками "выбрать часть тела -> залить целиком"; после дополнительного
-- изучения референса механика переписана на свободное рисование кистью -
-- см. DECISIONS.md, п.14 (там же обоснование выбора технологии: Texture-мазки
-- вместо EditableImage).
--
-- Сервер главный (см. DECISIONS.md, п.1): клиент присылает ПАКЕТ точек мазка
-- (не по одной точке за раз - это создало бы лишнюю нагрузку, см. DECISIONS.md,
-- п.14), а сервер проверяет роль/фазу/заморозку/чернила и сам создаёт Texture-
-- инстансы на персонаже. Roblox сам разошлёт их всем остальным игрокам
-- (см. DECISIONS.md, п.2 - тот же принцип, что и раньше для Color3).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local BrushGeometry = require(ReplicatedStorage.Modules.BrushGeometry)
local RoleUtil = require(ReplicatedStorage.Modules.RoleUtil)
-- Только для проверки текущей фазы раунда (RoundManager.State), см. FreezeService.lua
-- - там же комментарий, почему это не создаёт цикл require.
local RoundManager = require(script.Parent.RoundManager)

local PaintService = {}

-- "Чернила" игрока: [Player] = { amount = число от 0 до GameConfig.MAX_INK }
local inkData = {}

-- Активные мазки-Texture каждого игрока, от старых к новым (FIFO), чтобы не
-- копить бесконечное число инстансов за долгую игровую сессию - см. GameConfig.
-- MAX_ACTIVE_STAMPS_PER_PLAYER.
local activeStamps = {}

-- Заблокирована ли покраска у игрока прямо сейчас (например, он в позе) -
-- управляется через FreezeService.SetPaintingAllowed (переиспользуем как есть).
local paintingBlocked = {}

local paintableLookup = {}
for _, name in ipairs(GameConfig.PAINTABLE_PART_NAMES) do
	paintableLookup[name] = true
end

local validFaces = {}
for _, face in ipairs(BrushGeometry.ValidFaces) do
	validFaces[face] = true
end

local remotesRef

local function clamp01(n)
	return math.clamp(n, 0, 1)
end

local function sendInkUpdate(player)
	local data = inkData[player]
	if data and remotesRef then
		remotesRef.InkUpdate:FireClient(player, data.amount, GameConfig.MAX_INK)
	end
end

-- Фоновый цикл восстановления чернил со временем (раз в секунду, небольшими шагами)
local function rechargeLoop()
	while true do
		task.wait(1)
		for player, data in pairs(inkData) do
			if data.amount < GameConfig.MAX_INK then
				data.amount = math.min(GameConfig.MAX_INK, data.amount + GameConfig.INK_REGEN_PER_SECOND)

				-- Полоска чернил видна только там, где вообще можно красить -
				-- Hiding, и будущая фаза Lobby (тренировка кисти, MEGA_PLAN 1.3) -
				-- лишний трафик клиентам, которым сейчас нечего показывать
				-- (Seeking/RoundEnd), см. AUDIT_FABLE5.md, S9.
				if RoundManager.State == "Hiding" or RoundManager.State == "Lobby" then
					sendInkUpdate(player)
				end
			end
		end
	end
end

local function clearStamps(player)
	local queue = activeStamps[player]
	if queue then
		for _, stamp in ipairs(queue) do
			stamp:Destroy()
		end
	end
	activeStamps[player] = nil
end

-- Добавляет мазок в очередь игрока; если превышен лимит - стирает самый старый,
-- чтобы количество инстансов на персонаже не росло бесконечно за долгую сессию.
local function registerStamp(player, textureInstance)
	local queue = activeStamps[player]
	if not queue then
		queue = {}
		activeStamps[player] = queue
	end

	table.insert(queue, textureInstance)

	if #queue > GameConfig.MAX_ACTIVE_STAMPS_PER_PLAYER then
		local oldest = table.remove(queue, 1)
		if oldest then
			oldest:Destroy()
		end
	end
end

-- Стирает все мазки игрока и сбрасывает чернила на полные. Общая точка входа
-- для двух случаев: (1) начало фазы пряток - Hider каждый раунд снова
-- стартует полностью белым; (2) переход Hider -> Seeker в режиме Infection
-- (см. DECISIONS.md, п.18) - пойманный не должен визуально путать остальных
-- Seekers остатками своей маскировки.
function PaintService.ClearAllPaint(player)
	clearStamps(player)
	inkData[player] = { amount = GameConfig.MAX_INK }
	sendInkUpdate(player)
end

-- Сбросить чернила на полные и стереть все мазки прошлого раунда - вызывается
-- в начале фазы пряток.
function PaintService.ResetForNewRound(player)
	PaintService.ClearAllPaint(player)
end

-- Разрешить/запретить покраску игроку (например, запрещаем во время позы - см. FreezeService)
function PaintService.SetPaintingAllowed(player, allowed)
	paintingBlocked[player] = not allowed
end

local function isPaintingBlocked(player)
	return paintingBlocked[player] == true
end

local function applyStamp(player, part, face, u, v, color, size)
	local texture = Instance.new("Texture")
	texture.Name = "BrushStamp"
	texture.Texture = GameConfig.BRUSH_STAMP_IMAGE_ID
	texture.Face = face
	texture.Color3 = color

	texture.StudsPerTileU = size
	texture.StudsPerTileV = size

	local offsetU, offsetV = BrushGeometry.UVToOffset(part, face, u, v, size)
	texture.OffsetStudsU = offsetU
	texture.OffsetStudsV = offsetV

	texture.Parent = part

	registerStamp(player, texture)
end

-- points: массив { partName: string, face: Enum.NormalId, u: number, v: number }
-- Клиент шлёт пакет точек раз в ~0.15с (не по одной точке за раз), см. DECISIONS.md, п.14.
local function onPaintStroke(player, points, brushColor, brushSize)
	if typeof(points) ~= "table" or typeof(brushColor) ~= "Color3" or typeof(brushSize) ~= "number" then
		return
	end

	-- В лобби (на платформе, см. MEGA_PLAN.md 1.3) красить может ЛЮБОЙ
	-- игрок - это тренировка кисти, роли ещё не розданы (все в команде
	-- Spectators). В самом раунде - только Hider, и только в фазу пряток.
	local canPaintNow = RoundManager.State == "Lobby"
		or (RoundManager.State == "Hiding" and RoleUtil.IsHider(player))
	if not canPaintNow then
		return
	end

	if isPaintingBlocked(player) then
		return -- заморожен (в позе) - красить нельзя
	end

	if #points > GameConfig.MAX_STROKE_POINTS_PER_BATCH then
		return -- подозрительно большой пакет - отклоняем целиком, не тратя чернила
	end

	local character = player.Character
	if not character then
		return
	end

	local ink = inkData[player]
	if not ink then
		return
	end

	local size = math.clamp(brushSize, GameConfig.MIN_BRUSH_SIZE, GameConfig.MAX_BRUSH_SIZE)
	local safeColor = Color3.new(clamp01(brushColor.R), clamp01(brushColor.G), clamp01(brushColor.B))
	-- Чем крупнее кисть, тем дороже мазок - пропорционально площади (size в квадрате)
	local costPerStamp = GameConfig.INK_COST_PER_STAMP * (size / GameConfig.MIN_BRUSH_SIZE) ^ 2

	for _, point in ipairs(points) do
		if ink.amount < costPerStamp then
			break -- чернила кончились - молча останавливаемся, уже нанесённые мазки не отменяем
		end

		if
			typeof(point) == "table"
			and typeof(point.partName) == "string"
			and typeof(point.u) == "number"
			and typeof(point.v) == "number"
			and validFaces[point.face]
			and paintableLookup[point.partName]
		then
			local part = character:FindFirstChild(point.partName)
			if part and part:IsA("BasePart") then
				local u = math.clamp(point.u, 0, 1)
				local v = math.clamp(point.v, 0, 1)
				applyStamp(player, part, point.face, u, v, safeColor, size)
				ink.amount -= costPerStamp
			end
		end
	end

	sendInkUpdate(player)
end

function PaintService.Init(remotes)
	remotesRef = remotes
	remotes.PaintStroke.OnServerEvent:Connect(onPaintStroke)

	Players.PlayerRemoving:Connect(function(player)
		inkData[player] = nil
		paintingBlocked[player] = nil
		activeStamps[player] = nil -- сами инстансы Texture уничтожатся вместе с персонажем
	end)

	-- Игрок может красить прямо в лобби (тренировка кисти на платформе,
	-- см. MEGA_PLAN.md 1.3) - без этого inkData появлялась бы только в
	-- начале фазы пряток (ResetForNewRound), и полоска чернил у только что
	-- зашедшего была бы пустой/несуществующей.
	Players.PlayerAdded:Connect(function(player)
		PaintService.ClearAllPaint(player)
	end)

	task.spawn(rechargeLoop)
end

return PaintService
