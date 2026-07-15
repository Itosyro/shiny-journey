-- MapBuilder.lua
-- Строит первую играбельную карту кодом, из примитивов Part, при старте
-- сервера. Почему кодом, а не готовой картой с Marketplace/GitHub - см.
-- MAPS.md: ни один найденный бесплатный вариант нельзя было ни физически
-- вставить (нет доступа к Roblox Studio в этой сессии), ни легально
-- встроить как файл в репозиторий (лицензии Marketplace/Creator Store
-- запрещают использование вне Roblox Studio). Никаких внешних текстур/
-- ассетов не используется - только Part, Color3 и встроенные Material.
--
-- Здание карты - открытая планировка из 3 зон (Холл / Рабочая зона /
-- Гостиная), разделённых полноценными стенами с проходом, плюс точка
-- старта для зрительской камеры. Крыши у комнат нет - это не оплошность
-- (см. DECISIONS.md, п.23): дешевле по производительности и даёт зрителю
-- (SpectatorClient, вид от третьего лица) обзор сверху на всю карту.
--
-- Отдельно от здания - парящая лобби-платформа (см. MEGA_PLAN.md, Часть 1):
-- игроки ждут раунд, тренируют кисть/позы и выбирают роль позицией
-- (центр = доброволец-Seeker, врата по краю = доброволец-Hider). Раньше
-- была "земляная" зона Лобби внутри здания + отдельная запертая комната
-- ожидания Seekers на Z=150 - обе заменены платформой.

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
	if props.Shape then
		p.Shape = props.Shape
	end
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

-- Раньше называлась buildLobby и сама была местом ожидания (со спавнами
-- игроков) - теперь ожидание переехало на парящую платформу-лобби
-- (buildLobbyPlatform, см. MEGA_PLAN.md 1.1), а эта зона осталась обычным
-- игровым "Холлом" здания для пряток - спавнов тут больше нет, только
-- добавлены 2 маркера HiderSpawn (см. 1.1.7).
local function buildEntranceHall(parent)
	local color = Color3.fromRGB(205, 205, 210)
	addFloor(parent, -39, 0, 42, 80, color)

	-- Пара скамеек - просто, чтобы Холл не был пустой коробкой
	addFurniture(parent, "LobbyBench", -50, -15, Vector3.new(8, 2, 3), Color3.fromRGB(90, 70, 60), Enum.Material.Wood)
	addFurniture(parent, "LobbyBench", -50, 15, Vector3.new(8, 2, 3), Color3.fromRGB(90, 70, 60), Enum.Material.Wood)

	-- Точки для телепорта Hiders на старте пряток (см. RoundManager.
	-- teleportPlayersToRandomOf) - невидимые маркеры, одно и то же имя у
	-- всех, RoundManager сам выбирает случайный на игрока.
	newPart({ Name = "HiderSpawn", Parent = parent, Size = Vector3.new(4, 1, 4), CFrame = CFrame.new(-30, 0.5, -25), Transparency = 1, CanCollide = false })
	newPart({ Name = "HiderSpawn", Parent = parent, Size = Vector3.new(4, 1, 4), CFrame = CFrame.new(-30, 0.5, 25), Transparency = 1, CanCollide = false })

	-- Точки материализации Seekers при переходе Hiding→Seeking (эффект
	-- растворения на платформе + появление здесь, см. RoundManager.
	-- teleportWithEffect, MEGA_PLAN.md 1.6.2).
	newPart({ Name = "SeekerSpawn", Parent = parent, Size = Vector3.new(4, 1, 4), CFrame = CFrame.new(-40, 0.5, 0), Transparency = 1, CanCollide = false })
	newPart({ Name = "SeekerSpawn", Parent = parent, Size = Vector3.new(4, 1, 4), CFrame = CFrame.new(-55, 0.5, -30), Transparency = 1, CanCollide = false })
	newPart({ Name = "SeekerSpawn", Parent = parent, Size = Vector3.new(4, 1, 4), CFrame = CFrame.new(-55, 0.5, 30), Transparency = 1, CanCollide = false })
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
	-- HiderSpawn для Офиса (1) - см. комментарий в buildEntranceHall выше
	newPart({ Name = "HiderSpawn", Parent = parent, Size = Vector3.new(4, 1, 4), CFrame = CFrame.new(10, 0.5, -20), Transparency = 1, CanCollide = false })

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

	-- HiderSpawn для Склада (2) - см. комментарий в buildEntranceHall выше
	newPart({ Name = "HiderSpawn", Parent = parent, Size = Vector3.new(4, 1, 4), CFrame = CFrame.new(10, 0.5, 5), Transparency = 1, CanCollide = false })
	newPart({ Name = "HiderSpawn", Parent = parent, Size = Vector3.new(4, 1, 4), CFrame = CFrame.new(-10, 0.5, 35), Transparency = 1, CanCollide = false })
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

	-- HiderSpawn для Гостиной (2) - см. комментарий в buildEntranceHall выше
	newPart({ Name = "HiderSpawn", Parent = parent, Size = Vector3.new(4, 1, 4), CFrame = CFrame.new(30, 0.5, -35), Transparency = 1, CanCollide = false })
	newPart({ Name = "HiderSpawn", Parent = parent, Size = Vector3.new(4, 1, 4), CFrame = CFrame.new(70, 0.5, -20), Transparency = 1, CanCollide = false })

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

	-- HiderSpawn для Переговорной (1) - см. комментарий в buildEntranceHall выше
	newPart({ Name = "HiderSpawn", Parent = parent, Size = Vector3.new(4, 1, 4), CFrame = CFrame.new(65, 0.5, 5), Transparency = 1, CanCollide = false })
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

-- Лобби-платформа: парит высоко над картой и в стороне от здания (см.
-- MEGA_PLAN.md, Часть 1). Заменяет собой старую запертую "комнату
-- ожидания" Seekers (buildSeekerWaitingRoom, была на Z=150) - теперь на
-- этой же платформе все игроки ждут начала раунда, тренируют кисть и
-- позы, а Seekers остаются на ней и во время фазы Hiding (см. 1.5).
-- Имя маркера SeekerWaitingRoom - тот же контракт с RoundManager.lua,
-- что и раньше (findSpawnByName), просто маркер переехал сюда.
local LOBBY_PLATFORM_CENTER = Vector3.new(12, 120, -160)
local LOBBY_PLATFORM_RADIUS = 32 -- диаметр 64 - просторно на 24 игрока, но не пусто
local LOBBY_SPAWN_RING_RADIUS = 18
local LOBBY_GATE_RING_RADIUS = 26
local LOBBY_PLATFORM_TOP_Y = LOBBY_PLATFORM_CENTER.Y + 1 -- толщина платформы 2, половина = 1

local function buildLobbyPlatform(parent)
	-- Сама платформа - плоский цилиндр ("блин"). У цилиндра Roblox ось
	-- лежит вдоль X, поэтому размер задаём как (толщина, диаметр, диаметр)
	-- и поворачиваем на 90° вокруг Z, чтобы он лёг горизонтально.
	newPart({
		Name = "LobbyPlatform",
		Parent = parent,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, LOBBY_PLATFORM_RADIUS * 2, LOBBY_PLATFORM_RADIUS * 2),
		CFrame = CFrame.new(LOBBY_PLATFORM_CENTER) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(235, 235, 240),
		Material = Enum.Material.SmoothPlastic,
	})

	-- Бортик (видимый) + невидимая стена - один и тот же цикл по 8
	-- сегментам строит и то, и то (ponytail: не два отдельных цикла).
	-- Ширина сегмента взята с запасом над хордой (~24.5 стада при радиусе
	-- 32 и 8 сегментах), чтобы соседние сегменты перекрывались и не
	-- оставляли щели, через которые можно провалиться.
	local SEGMENT_COUNT = 8
	local SEGMENT_WIDTH = 28
	local WALL_HEIGHT_LOBBY = 20
	for i = 0, SEGMENT_COUNT - 1 do
		local angle = (i / SEGMENT_COUNT) * math.pi * 2
		local segmentPos = Vector3.new(
			LOBBY_PLATFORM_CENTER.X + math.cos(angle) * LOBBY_PLATFORM_RADIUS,
			LOBBY_PLATFORM_TOP_Y,
			LOBBY_PLATFORM_CENTER.Z + math.sin(angle) * LOBBY_PLATFORM_RADIUS
		)
		-- "Смотрит" на центр платформы - Size.X сегмента ложится по касательной
		local lookAtCenter = Vector3.new(LOBBY_PLATFORM_CENTER.X, LOBBY_PLATFORM_TOP_Y, LOBBY_PLATFORM_CENTER.Z)
		local segmentCFrame = CFrame.new(segmentPos, lookAtCenter)

		newPart({
			Name = "PlatformCurb",
			Parent = parent,
			Size = Vector3.new(SEGMENT_WIDTH, 1.5, 2),
			CFrame = segmentCFrame * CFrame.new(0, 0.75, 0),
			Color = Color3.fromRGB(210, 210, 215),
		})

		newPart({
			Name = "PlatformWall",
			Parent = parent,
			Size = Vector3.new(SEGMENT_WIDTH, WALL_HEIGHT_LOBBY, 2),
			CFrame = segmentCFrame * CFrame.new(0, WALL_HEIGHT_LOBBY / 2, 0),
			Transparency = 1,
			CanCollide = true,
		})
	end

	-- Зона добровольного Seeker (центр платформы) - контракт имени
	-- SeekerVolunteerZone с PlayerRoleService.getRoleIntent (см. 1.2).
	newPart({
		Name = "SeekerZoneGlow",
		Parent = parent,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, 12, 12),
		CFrame = CFrame.new(LOBBY_PLATFORM_CENTER.X, LOBBY_PLATFORM_TOP_Y + 0.1, LOBBY_PLATFORM_CENTER.Z)
			* CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(220, 90, 90),
		Material = Enum.Material.Neon,
		CanCollide = false,
	})

	local seekerZoneMarker = newPart({
		Name = "SeekerVolunteerZone",
		Parent = parent,
		Size = Vector3.new(12, 8, 12),
		CFrame = CFrame.new(LOBBY_PLATFORM_CENTER.X, LOBBY_PLATFORM_TOP_Y + 4, LOBBY_PLATFORM_CENTER.Z),
		Transparency = 1,
		CanCollide = false,
	})

	local seekerBillboard = Instance.new("BillboardGui")
	seekerBillboard.Name = "RoleLabel"
	seekerBillboard.Size = UDim2.new(0, 200, 0, 50)
	seekerBillboard.StudsOffset = Vector3.new(0, 5, 0)
	seekerBillboard.Parent = seekerZoneMarker

	local seekerLabel = Instance.new("TextLabel")
	seekerLabel.BackgroundTransparency = 1
	seekerLabel.Size = UDim2.new(1, 0, 1, 0)
	seekerLabel.Font = Enum.Font.GothamBold
	seekerLabel.TextScaled = true
	seekerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	seekerLabel.Text = "ХОЧУ БЫТЬ ИСКАТЕЛЕМ"
	seekerLabel.Parent = seekerBillboard

	-- 4 врат Hider по краю платформы - контракт имени HiderGateZone с
	-- PlayerRoleService.getRoleIntent (см. 1.2). Одинаковое имя у всех
	-- четырёх - getRoleIntent проверяет каждую по очереди.
	local GATE_COLOR = Color3.fromRGB(90, 200, 120)
	for i = 0, 3 do
		local angle = (i / 4) * math.pi * 2
		local gateX = LOBBY_PLATFORM_CENTER.X + math.cos(angle) * LOBBY_GATE_RING_RADIUS
		local gateZ = LOBBY_PLATFORM_CENTER.Z + math.sin(angle) * LOBBY_GATE_RING_RADIUS

		newPart({ Name = "HiderGatePost", Parent = parent, Size = Vector3.new(1, 6, 1), CFrame = CFrame.new(gateX - 3, LOBBY_PLATFORM_TOP_Y + 3, gateZ), Color = GATE_COLOR })
		newPart({ Name = "HiderGatePost", Parent = parent, Size = Vector3.new(1, 6, 1), CFrame = CFrame.new(gateX + 3, LOBBY_PLATFORM_TOP_Y + 3, gateZ), Color = GATE_COLOR })
		newPart({ Name = "HiderGateBeam", Parent = parent, Size = Vector3.new(6, 1, 1), CFrame = CFrame.new(gateX, LOBBY_PLATFORM_TOP_Y + 6, gateZ), Color = GATE_COLOR })

		local gateMarker = newPart({
			Name = "HiderGateZone",
			Parent = parent,
			Size = Vector3.new(8, 8, 8),
			CFrame = CFrame.new(gateX, LOBBY_PLATFORM_TOP_Y + 4, gateZ),
			Transparency = 1,
			CanCollide = false,
		})

		local gateBillboard = Instance.new("BillboardGui")
		gateBillboard.Name = "RoleLabel"
		gateBillboard.Size = UDim2.new(0, 200, 0, 50)
		gateBillboard.StudsOffset = Vector3.new(0, 5, 0)
		gateBillboard.Parent = gateMarker

		local gateLabel = Instance.new("TextLabel")
		gateLabel.BackgroundTransparency = 1
		gateLabel.Size = UDim2.new(1, 0, 1, 0)
		gateLabel.Font = Enum.Font.GothamBold
		gateLabel.TextScaled = true
		gateLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		gateLabel.Text = "ХОЧУ ПРЯТАТЬСЯ"
		gateLabel.Parent = gateBillboard
	end

	-- Точки спавна на платформе - Neutral, чтобы работали независимо от
	-- команды игрока (роли ещё не назначены/сброшены в Spectators между
	-- раундами) - переехали сюда из старой buildLobby (см. buildEntranceHall).
	for i = 1, 6 do
		local angle = (i / 6) * math.pi * 2
		local spawnPart = Instance.new("SpawnLocation")
		spawnPart.Name = "LobbySpawn" .. i
		spawnPart.Neutral = true
		spawnPart.Anchored = true
		spawnPart.CanCollide = false
		spawnPart.Size = Vector3.new(6, 1, 6)
		spawnPart.Color = Color3.fromRGB(90, 170, 255)
		spawnPart.Material = Enum.Material.Neon
		spawnPart.CFrame = CFrame.new(
			LOBBY_PLATFORM_CENTER.X + math.cos(angle) * LOBBY_SPAWN_RING_RADIUS,
			LOBBY_PLATFORM_TOP_Y + 0.5,
			LOBBY_PLATFORM_CENTER.Z + math.sin(angle) * LOBBY_SPAWN_RING_RADIUS
		)
		spawnPart.Parent = parent
	end

	-- Маркер "комнаты ожидания" Seekers - контракт имени с RoundManager.lua
	-- (findSpawnByName("SeekerWaitingRoom")), просто переехал на платформу.
	-- Смещён от центра (X+10), чтобы не совпадать с SeekerVolunteerZone.
	newPart({
		Name = "SeekerWaitingRoom",
		Parent = parent,
		Size = Vector3.new(4, 1, 4),
		CFrame = CFrame.new(LOBBY_PLATFORM_CENTER.X + 10, LOBBY_PLATFORM_TOP_Y + 0.5, LOBBY_PLATFORM_CENTER.Z),
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

	buildEntranceHall(mapFolder)
	buildWorkArea(mapFolder)
	buildLounge(mapFolder)
	buildOuterShellAndDoorways(mapFolder)
	buildLobbyPlatform(mapFolder)
	buildSpectatorSpawn(mapFolder)

	print("[MecchaChameleon] Процедурная карта построена (MapBuilder.lua).")
end

return MapBuilder
