-- PrivateRoomService.lua
-- Приватные комнаты по паролю - "Custom Game" из оригинала MECCHA CHAMELEON.
-- Пароль сопоставляется с зарезервированным сервером (TeleportService) через
-- MemoryStoreService - см. DECISIONS.md, п.20 для полного обоснования выбора
-- MemoryStoreService вместо DataStoreService/обычной Lua-таблицы.
--
-- ВАЖНО: TeleportService **не работает** во время Play-тестирования в Roblox
-- Studio - только в опубликованной, живой игре. Эту часть нельзя проверить
-- в Studio Play-режиме вообще, только после публикации - см. TASKS.md.

local TeleportService = game:GetService("TeleportService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local PrivateRoomService = {}

-- Один SortedMap на всю игру (общий для ВСЕХ серверов этой игры одновременно -
-- MemoryStoreService специально для этого и нужен: обычная Lua-таблица видна
-- только внутри одного серверного процесса, а игрок, вводящий пароль, обычно
-- находится на другом сервере, чем тот, где комнату создали - см. DECISIONS.md, п.20).
local passwordMap = MemoryStoreService:GetSortedMap("PrivateRoomPasswords")

-- Защита от подбора пароля: [Player] = { count, windowStart }
local joinAttempts = {}

local remotesRef

local function sendError(player, message)
	if remotesRef then
		remotesRef.PrivateRoomError:FireClient(player, message)
	end
end

-- Обрезаем пробелы и приводим к нижнему регистру - чтобы "Friends2026" и
-- "friends2026" считались одним и тем же паролем.
local function normalizePassword(rawPassword)
	if typeof(rawPassword) ~= "string" then
		return nil
	end
	local trimmed = rawPassword:gsub("^%s+", ""):gsub("%s+$", "")
	if trimmed == "" then
		return nil
	end
	return trimmed:lower()
end

local function isValidPassword(password)
	return password ~= nil
		and #password >= GameConfig.PRIVATE_ROOM_PASSWORD_MIN_LENGTH
		and #password <= GameConfig.PRIVATE_ROOM_PASSWORD_MAX_LENGTH
end

-- Не более GameConfig.PRIVATE_ROOM_JOIN_ATTEMPT_LIMIT попыток "Присоединиться"
-- за скользящее окно времени с одного игрока - без этого читер мог бы за
-- секунды перебрать множество коротких паролей чужих комнат.
local function isRateLimited(player)
	local now = tick()
	local record = joinAttempts[player]

	if not record or now - record.windowStart > GameConfig.PRIVATE_ROOM_JOIN_ATTEMPT_WINDOW_SECONDS then
		record = { count = 0, windowStart = now }
		joinAttempts[player] = record
	end

	record.count += 1
	return record.count > GameConfig.PRIVATE_ROOM_JOIN_ATTEMPT_LIMIT
end

local function teleportToReservedServer(player, accessCode)
	local teleportOptions = Instance.new("TeleportOptions")
	teleportOptions.ReservedServerAccessCode = accessCode

	-- TeleportAsync - актуальный метод (TeleportToPrivateServer помечен Roblox
	-- как deprecated для нового кода, см. DECISIONS.md, п.20).
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(game.PlaceId, { player }, teleportOptions)
	end)

	return ok, err
end

local function onCreatePrivateRoom(player, rawPassword)
	-- Тот же лимит, что и у входа по паролю - без него читер мог бы спамить
	-- реальные ReserveServerAsync/MemoryStoreService-запросы без ограничений
	-- (создание комнаты - как минимум не более дешёвая операция, чем вход).
	if isRateLimited(player) then
		sendError(player, "Слишком много попыток - подожди немного и попробуй снова")
		return
	end

	local password = normalizePassword(rawPassword)

	if not isValidPassword(password) then
		sendError(player, string.format(
			"Пароль должен быть от %d до %d символов",
			GameConfig.PRIVATE_ROOM_PASSWORD_MIN_LENGTH,
			GameConfig.PRIVATE_ROOM_PASSWORD_MAX_LENGTH
		))
		return
	end

	-- Проверяем, не занят ли уже этот пароль другой активной комнатой - иначе
	-- новая запись в MemoryStore перезаписала бы старую, и друзья, уже
	-- играющие в первой комнате, стали бы недостижимы по этому паролю.
	-- Важно не спутать "запрос не удался" с "пароль свободен" - иначе
	-- временный сбой MemoryStoreService тихо перезаписал бы чужую активную
	-- комнату вместо явной ошибки создателю.
	local existingOk, existingCode = pcall(function()
		return passwordMap:GetAsync(password)
	end)

	if not existingOk then
		sendError(player, "Не удалось создать комнату, попробуй ещё раз")
		warn("[MecchaChameleon] MemoryStore GetAsync (create-check) failed: " .. tostring(existingCode))
		return
	end

	if existingCode then
		sendError(player, "Этот пароль уже занят - выбери другой")
		return
	end

	local reserveOk, accessCode = pcall(function()
		return TeleportService:ReserveServerAsync(game.PlaceId)
	end)

	if not reserveOk or not accessCode then
		sendError(player, "Не удалось создать комнату, попробуй ещё раз")
		warn("[MecchaChameleon] ReserveServerAsync failed: " .. tostring(accessCode))
		return
	end

	local saveOk, saveErr = pcall(function()
		return passwordMap:SetAsync(password, accessCode, GameConfig.PRIVATE_ROOM_PASSWORD_TTL_SECONDS)
	end)

	if not saveOk then
		sendError(player, "Не удалось создать комнату, попробуй ещё раз")
		warn("[MecchaChameleon] MemoryStore SetAsync failed: " .. tostring(saveErr))
		return
	end

	local teleportOk, teleportErr = teleportToReservedServer(player, accessCode)
	if not teleportOk then
		sendError(player, "Комната создана, но телепорт не удался - попробуй ещё раз")
		warn("[MecchaChameleon] TeleportAsync (create) failed: " .. tostring(teleportErr))
	end
end

local function onJoinPrivateRoom(player, rawPassword)
	if isRateLimited(player) then
		sendError(player, "Слишком много попыток - подожди немного и попробуй снова")
		return
	end

	local password = normalizePassword(rawPassword)

	if not isValidPassword(password) then
		sendError(player, "Введи пароль комнаты")
		return
	end

	local getOk, accessCode = pcall(function()
		return passwordMap:GetAsync(password)
	end)

	if not getOk then
		sendError(player, "Не удалось найти комнату, попробуй ещё раз")
		warn("[MecchaChameleon] MemoryStore GetAsync failed: " .. tostring(accessCode))
		return
	end

	if not accessCode then
		sendError(player, "Комната с таким паролем не найдена")
		return
	end

	local teleportOk, teleportErr = teleportToReservedServer(player, accessCode)
	if not teleportOk then
		sendError(player, "Комната недоступна (возможно, истёк срок действия) - попроси создать новую")
		warn("[MecchaChameleon] TeleportAsync (join) failed: " .. tostring(teleportErr))
	end
end

function PrivateRoomService.Init(remotes)
	remotesRef = remotes
	remotes.CreatePrivateRoom.OnServerEvent:Connect(onCreatePrivateRoom)
	remotes.JoinPrivateRoom.OnServerEvent:Connect(onJoinPrivateRoom)

	Players.PlayerRemoving:Connect(function(player)
		joinAttempts[player] = nil
	end)
end

return PrivateRoomService
