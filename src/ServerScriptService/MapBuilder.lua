-- MapBuilder.lua
-- Строит первую играбельную карту кодом, из примитивов Part, при старте
-- сервера. Почему кодом, а не готовой картой с Marketplace/GitHub - см.
-- MAPS.md: ни один найденный бесплатный вариант нельзя было ни физически
-- вставить (нет доступа к Roblox Studio в этой сессии), ни легально
-- встроить как файл в репозиторий (лицензии Marketplace/Creator Store
-- запрещают использование вне Roblox Studio). Никаких внешних текстур/
-- ассетов не используется - только Part, Color3 и встроенные Material.
--
-- Карта - открытая планировка из 3 зон (Лобби / Рабочая зона / Гостиная),
-- разделённых полноценными стенами с проходом, плюс отдельная запертая
-- комната ожидания для Seekers и точка старта для зрительской камеры.
-- Крыши у комнат нет - это не оплошность (см. DECISIONS.md, п.23): дешевле
-- по производительности и даёт зрителю (SpectatorClient, вид от третьего
-- лица) обзор сверху на всю карту.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local MapBuilder = {}

local WALL_HEIGHT = 12
-- Разделяет зоны визуально. Не блокирует обзор на СТОЯЧИХ игроков (луч идёт
-- от головы Seeker'а, ~4.3 стада, к HumanoidRootPart Hider'а) - но для
-- лежащего Hider'а (HipHeight×0.2, корень ~0.6 стада) перегородка высотой 4
-- МОЖЕТ перекрыть луч на части дистанций. Это осознанный геймплейный бонус:
-- лечь за перегородкой - реальное укрытие (см. DECISIONS.md, п.23; найдено
-- и переформулировано аудитом Fable 5, S7 - раньше комментарий обещал
-- обратное).
local LOW_DIVIDER_HEIGHT = 4

local function newPart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = if props.CanCollide == nil then true else props.CanCollide
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = props.Material or Enum.Material.SmoothPlastic
	p.Color = props.Color or Color3.fromRGB(200, 200, 200)
	p.Size = props.Size
	p.CFrame = props.CFrame
	p.Name = props.Name or "Part"
	p.Transparency = props.Transparency or 0
	p.Parent = props.Parent
	return p
end

local function addFloor(parent, centerX, centerZ, sizeX, sizeZ, color)
	newPart({
		Name = "Floor",
		Parent = parent,
		Size = Vector3.new(sizeX, 1, sizeZ),
		CFrame = CFrame.new(centerX, -0.5, centerZ),
		Color = color,
		Material = Enum.Material.WoodPlanks,
	})
end

local function addWall(parent, centerX, centerZ, sizeX, sizeZ, height, color, material)
	newPart({
		Name = "Wall",
		Parent = parent,
		Size = Vector3.new(sizeX, height, sizeZ),
		CFrame = CFrame.new(centerX, height / 2, centerZ),
		Color = color or Color3.fromRGB(210, 205, 195),
		Material = material or Enum.Material.Concrete,
	})
end

-- Мебель - обычный BasePart с именем, размером и цветом, ничего больше.
-- Разнообразие цвета/размера - осознанно (нужно для маскировки кистью, см.
-- CLAUDE.md и DECISIONS.md, п.14).
-- yOffset (опционально) - для предмета, который должен стоять НЕ на полу,
-- а поверх другого предмета мебели (например, монитор на столе) - высота
-- нижнего предмета (см. AUDIT_FABLE5.md, S6).
local function addFurniture(parent, name, centerX, centerZ, size, color, material, yOffset)
	newPart({
		Name = name,
		Parent = parent,
		Size = size,
		CFrame = CFrame.new(centerX, size.Y / 2 + (yOffset or 0), centerZ),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
	})
end

local function buildLobby(parent)
	local color = Color3.fromRGB(205, 205, 210)
	addFloor(parent, -39, 0, 42, 80, color)

	-- Пара скамеек - просто, чтобы Лобби не было пустой коробкой
	addFurniture(parent, "LobbyBench", -50, -15, Vector3.new(8, 2, 3), Color3.fromRGB(90, 70, 60), Enum.Material.Wood)
	addFurniture(parent, "LobbyBench", -50, 15, Vector3.new(8, 2, 3), Color3.fromRGB(90, 70, 60), Enum.Material.Wood)

	-- Точки спавна лобби - Neutral, чтобы работали независимо от команды
	-- игрока (роли ещё не назначены/сброшены в Spectators между раундами).
	for i, offsetZ in ipairs({ -25, -12, 0, 12, 25, -25 }) do
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "LobbySpawn" .. i
		spawn.Neutral = true
		spawn.Anchored = true
		spawn.CanCollide = false
		spawn.Size = Vector3.new(6, 1, 6)
		spawn.Color = Color3.fromRGB(90, 170, 255)
		spawn.Material = Enum.Material.Neon
		spawn.CFrame = CFrame.new(-52 + (i % 2) * 6, 0.5, offsetZ)
		spawn.Parent = parent
	end
end

local function buildWorkArea(parent)
	local floorColor = Color3.fromRGB(170, 140, 100)
	-- Размер/центр подобраны так, чтобы края (X -18.5..25.5) перекрывались с
	-- полами соседних зон - раньше пол заканчивался на X=24.5, а пол гостиной
	-- начинался на 25, и в дверном проёме на X=25 оставалась открытая щель
	-- 0.5 стада (найдено аудитом Fable 5).
	addFloor(parent, 3.5, 0, 44, 80, floorColor)

	-- Низкая перегородка между "Офисом" (Z<0) и "Складом" (Z>0) - разделяет
	-- зону визуально, но специально НЕ на полную высоту: для стоящего игрока
	-- обзор/поимку не блокирует, для лежащего даёт частичное укрытие (см.
	-- комментарий у LOW_DIVIDER_HEIGHT выше).
	addWall(parent, 3, 0, 43, 0.6, LOW_DIVIDER_HEIGHT, Color3.fromRGB(150, 150, 155), Enum.Material.Metal)

	-- === Офис (Z от -40 до 0) ===
	local deskColor = Color3.fromRGB(120, 85, 60)
	local chairColors = { Color3.fromRGB(60, 110, 190), Color3.fromRGB(190, 90, 90), Color3.fromRGB(90, 170, 110) }
	for i, offsetZ in ipairs({ -30, -18, -6 }) do
		addFurniture(parent, "Desk", -8, offsetZ, Vector3.new(6, 2.4, 3), deskColor, Enum.Material.Wood)
		addFurniture(parent, "Chair", -8, offsetZ + 2.5, Vector3.new(2, 3, 2), chairColors[i], Enum.Material.Fabric)
		-- yOffset = высота стола (2.4) - монитор стоит НА столе, а не в полу под ним
		addFurniture(parent, "Monitor", -9.5, offsetZ - 0.5, Vector3.new(1.4, 1.2, 0.3), Color3.fromRGB(25, 25, 25), Enum.Material.SmoothPlastic, 2.4)
	end
	addFurniture(parent, "Shelf", 20, -35, Vector3.new(2, 8, 10), Color3.fromRGB(140, 140, 140), Enum.Material.Wood)
	addFurniture(parent, "Shelf", 20, -5, Vector3.new(2, 8, 10), Color3.fromRGB(140, 140, 140), Enum.Material.Wood)
	-- X=-15 (не -20) - иначе растение попадает в зону Лобби (X < -18), а не Офиса
	addFurniture(parent, "OfficePlant", -15, -35, Vector3.new(2, 4, 2), Color3.fromRGB(70, 150, 80), Enum.Material.Grass)

	-- === Склад (Z от 0 до 40) - разноцветные/разноразмерные ящики ===
	local crateColors = {
		Color3.fromRGB(180, 140, 90),
		Color3.fromRGB(170, 60, 60),
		Color3.fromRGB(70, 140, 80),
		Color3.fromRGB(90, 90, 190),
		Color3.fromRGB(200, 190, 80),
	}
	local crateIndex = 0
	for _, offsetX in ipairs({ -15, -5, 5, 15 }) do
		for _, offsetZ in ipairs({ 10, 20, 30 }) do
			crateIndex += 1
			local size = Vector3.new(3 + (crateIndex % 3), 3 + ((crateIndex + 1) % 3), 3 + (crateIndex % 2))
			addFurniture(parent, "Crate", offsetX, offsetZ, size, crateColors[(crateIndex % #crateColors) + 1], Enum.Material.WoodPlanks)
		end
	end
	addFurniture(parent, "Shelf", 20, 35, Vector3.new(2, 9, 12), Color3.fromRGB(90, 90, 90), Enum.Material.Metal)
end

local function buildLounge(parent)
	local floorColor = Color3.fromRGB(110, 75, 55)
	addFloor(parent, 55, 0, 60, 80, floorColor)

	-- Низкая перегородка между "Гостиной" (Z<0) и "Переговорной" (Z>0) -
	-- та же логика, что и в рабочей зоне (см. комментарий у
	-- LOW_DIVIDER_HEIGHT выше).
	addWall(parent, 55, 0, 60, 0.6, LOW_DIVIDER_HEIGHT, Color3.fromRGB(150, 150, 155), Enum.Material.Metal)

	-- === Гостиная (Z от -40 до 0) ===
	addFurniture(parent, "Sofa", 40, -25, Vector3.new(10, 3, 4), Color3.fromRGB(140, 60, 70), Enum.Material.Fabric)
	addFurniture(parent, "Sofa", 40, -10, Vector3.new(10, 3, 4), Color3.fromRGB(50, 120, 120), Enum.Material.Fabric)
	addFurniture(parent, "CoffeeTable", 40, -17, Vector3.new(5, 1.5, 3), Color3.fromRGB(110, 80, 55), Enum.Material.Wood)
	for _, pos in ipairs({ { 65, -30 }, { 75, -10 }, { 65, -5 } }) do
		addFurniture(parent, "PlantPot", pos[1], pos[2], Vector3.new(2, 1.5, 2), Color3.fromRGB(180, 90, 60), Enum.Material.SmoothPlastic)
		-- yOffset = высота горшка (1.5) - крона растёт ИЗ горшка, а не сквозь него
		addFurniture(parent, "PlantTop", pos[1], pos[2], Vector3.new(2.4, 3, 2.4), Color3.fromRGB(60, 140, 70), Enum.Material.Grass, 1.5)
	end
	addFurniture(parent, "FloorLamp", 78, -32, Vector3.new(1.2, 7, 1.2), Color3.fromRGB(230, 200, 80), Enum.Material.Neon)

	-- === Переговорная (Z от 0 до 40) ===
	addFurniture(parent, "MeetingTable", 55, 20, Vector3.new(12, 2, 5), Color3.fromRGB(160, 160, 160), Enum.Material.SmoothPlastic)
	local meetingChairColors = {
		Color3.fromRGB(220, 90, 90), Color3.fromRGB(90, 220, 140), Color3.fromRGB(90, 140, 220),
		Color3.fromRGB(230, 200, 80), Color3.fromRGB(200, 100, 200), Color3.fromRGB(100, 200, 200),
	}
	for i, offsetX in ipairs({ 48, 51, 54, 57, 60, 63 }) do
		addFurniture(parent, "MeetingChair", offsetX, 12, Vector3.new(2, 3, 2), meetingChairColors[i], Enum.Material.Fabric)
	end
	addFurniture(parent, "Whiteboard", 55, 38, Vector3.new(8, 5, 0.3), Color3.fromRGB(240, 240, 240), Enum.Material.SmoothPlastic)
	addFurniture(parent, "Bookshelf", 78, 30, Vector3.new(2, 8, 8), Color3.fromRGB(120, 90, 70), Enum.Material.Wood)
end

-- Внешний периметр всего здания (одна общая коробка на все 3 зоны) плюс
-- 2 внутренние стены-разделителя с проходом посередине - единственные
-- полновысотные стены на карте, реально блокирующие обзор Seekers.
local function buildOuterShellAndDoorways(parent)
	local minX, maxX = -60, 85
	local minZ, maxZ = -40, 40
	local wallColor = Color3.fromRGB(225, 220, 210)

	addWall(parent, (minX + maxX) / 2, minZ, maxX - minX, 1, WALL_HEIGHT, wallColor)
	addWall(parent, (minX + maxX) / 2, maxZ, maxX - minX, 1, WALL_HEIGHT, wallColor)
	addWall(parent, minX, (minZ + maxZ) / 2, 1, maxZ - minZ, WALL_HEIGHT, wallColor)
	addWall(parent, maxX, (minZ + maxZ) / 2, 1, maxZ - minZ, WALL_HEIGHT, wallColor)

	-- Проход шириной 12 стадов - достаточно широкий, чтобы не создавать
	-- затор при 24 игроках одновременно (см. GameConfig.MAX_PLAYERS,
	-- DECISIONS.md, п.19), но не настолько, чтобы стена перестала что-то
	-- значить для укрытия/line-of-sight.
	local DOORWAY_HALF_WIDTH = 6

	for _, doorX in ipairs({ -18, 25 }) do
		addWall(parent, doorX, (-40 + -DOORWAY_HALF_WIDTH) / 2, 1, (40 - DOORWAY_HALF_WIDTH), WALL_HEIGHT, wallColor)
		addWall(parent, doorX, (40 + DOORWAY_HALF_WIDTH) / 2, 1, (40 - DOORWAY_HALF_WIDTH), WALL_HEIGHT, wallColor)
	end
end

-- Отдельная запертая комната ожидания для Seekers на время фазы Hiding -
-- см. DECISIONS.md, п.9/23. Специально вынесена далеко в сторону и не
-- имеет дверей: попасть внутрь можно только телепортом
-- (RoundManager.teleportPlayersTo), выйти - только автоматически при
-- старте фазы Seeking. Имя корневой Part - контракт с RoundManager.lua
-- (findSpawnByName("SeekerWaitingRoom")).
local function buildSeekerWaitingRoom(parent)
	local center = Vector3.new(10, 0, 150)

	addFloor(parent, center.X, center.Z, 30, 30, Color3.fromRGB(80, 40, 40))
	addWall(parent, center.X, center.Z - 15, 30, 1, WALL_HEIGHT, Color3.fromRGB(60, 30, 30))
	addWall(parent, center.X, center.Z + 15, 30, 1, WALL_HEIGHT, Color3.fromRGB(60, 30, 30))
	addWall(parent, center.X - 15, center.Z, 1, 30, WALL_HEIGHT, Color3.fromRGB(60, 30, 30))
	addWall(parent, center.X + 15, center.Z, 1, 30, WALL_HEIGHT, Color3.fromRGB(60, 30, 30))
	addFurniture(parent, "WaitingBench", center.X, center.Z, Vector3.new(10, 2, 3), Color3.fromRGB(90, 70, 60), Enum.Material.Wood)

	-- Невидимый функциональный маркер (не часть видимой геометрии) - именно
	-- его ищет RoundManager по имени и телепортирует Seekers к его CFrame.
	newPart({
		Name = "SeekerWaitingRoom",
		Parent = parent,
		Size = Vector3.new(4, 1, 4),
		CFrame = CFrame.new(center.X, 0.5, center.Z),
		Transparency = 1,
		CanCollide = false,
	})
end

-- Невидимая точка старта для зрительской "лётной" камеры (SpectatorService/
-- SpectatorClient, см. DECISIONS.md, п.21) - высоко над центром здания, даёт
-- новому зрителю сразу общий вид на карту сверху, а не случайную точку
-- спавна на уровне пола. Имя - тот же паттерн "Part-контракт по имени", что
-- и у SeekerWaitingRoom.
local function buildSpectatorSpawn(parent)
	newPart({
		Name = "SpectatorSpawn",
		Parent = parent,
		Size = Vector3.new(4, 1, 4),
		CFrame = CFrame.new(12, 60, 0),
		Transparency = 1,
		CanCollide = false,
	})
end

-- Строит карту один раз при старте сервера. Идемпотентно - если Map уже
-- есть в Workspace (например, по ошибке вызвано дважды), выходит без
-- пересоздания, а не плодит дубликаты геометрии.
function MapBuilder.Build()
	if not GameConfig.USE_PROCEDURAL_MAP then
		return
	end

	if Workspace:FindFirstChild("Map") then
		return
	end

	local mapFolder = Instance.new("Folder")
	mapFolder.Name = "Map"
	mapFolder.Parent = Workspace

	buildLobby(mapFolder)
	buildWorkArea(mapFolder)
	buildLounge(mapFolder)
	buildOuterShellAndDoorways(mapFolder)
	buildSeekerWaitingRoom(mapFolder)
	buildSpectatorSpawn(mapFolder)

	print("[MecchaChameleon] Процедурная карта построена (MapBuilder.lua).")
end

return MapBuilder
