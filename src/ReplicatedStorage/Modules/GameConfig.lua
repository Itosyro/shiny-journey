-- GameConfig.lua
-- Общие настройки игры. Меняй значения тут, чтобы настроить баланс, не трогая
-- логику в других скриптах. Этот модуль используется и сервером, и клиентом.

local GameConfig = {}

-- === Игроки и лобби ===
GameConfig.MIN_PLAYERS_TO_START = 2
GameConfig.MAX_PLAYERS = 10
GameConfig.LOBBY_COUNTDOWN_SECONDS = 15 -- отсчёт перед стартом раунда после набора минимума игроков
-- Целевой баланс (не жёсткое ограничение): формулы Seekers/тайминги в первую
-- очередь настроены и проверяются на серверах с 6-8 игроками одновременно -
-- см. DECISIONS.md, п.16. 2-10 остаётся диапазоном, который сервер допускает.
GameConfig.TARGET_PLAYERS_FOR_BALANCE = 7

-- === Роли ===
-- Сколько искателей (Seekers) назначаем в зависимости от числа игроков в раунде.
-- Формула: 1 искатель на каждые 4 игрока, минимум 1, максимум 3 (см. DECISIONS.md, п.6).
GameConfig.SEEKERS_PER_PLAYERS = 4
GameConfig.MIN_SEEKERS = 1
GameConfig.MAX_SEEKERS = 3

-- === Тайминги фаз раунда (в секундах) ===
GameConfig.HIDING_PHASE_DURATION = 30    -- время на покраску и прятки, искатели ждут в комнате
GameConfig.SEEKING_PHASE_DURATION = 120  -- время на поиск
GameConfig.ROUND_END_DISPLAY_DURATION = 12 -- сколько показываем экран результатов

-- === Покраска (кисть, см. DECISIONS.md, п.14) ===
GameConfig.EYEDROPPER_MAX_DISTANCE = 60  -- максимальная дальность пипетки (в стадах)

-- "Чернила" - расходуемый ресурс кисти (аналог полоски стамины), а не дискретные
-- "заряды": тратятся пропорционально числу мазков, медленно восстанавливаются.
GameConfig.MAX_INK = 100
GameConfig.INK_COST_PER_STAMP = 1        -- сколько чернил стоит один мазок минимального размера
GameConfig.INK_REGEN_PER_SECOND = 4      -- скорость восстановления чернил в секунду

-- Размер кисти (радиус мазка в стадах) - регулируется слайдером в UI
GameConfig.MIN_BRUSH_SIZE = 0.4
GameConfig.MAX_BRUSH_SIZE = 2.0
GameConfig.DEFAULT_BRUSH_SIZE = 0.8

-- Изображение одного мазка кисти (белый мягкий кружок, тонируется через Color3 -
-- см. DECISIONS.md, п.14, почему через Decal.Color3, а не EditableImage).
-- ЗАГЛУШКА! Замени на реальный ассет мазка, когда загрузишь его в Studio.
GameConfig.BRUSH_STAMP_IMAGE_ID = "rbxassetid://0"

-- Защита от накрутки: сколько точек мазка сервер примет за один пакет от клиента,
-- и сколько мазков может одновременно висеть на одном игроке (старые вытесняются).
GameConfig.MAX_STROKE_POINTS_PER_BATCH = 24
GameConfig.MAX_ACTIVE_STAMPS_PER_PLAYER = 400

-- === Обнаружение (поимка) ===
GameConfig.CATCH_MAX_DISTANCE = 8          -- на каком расстоянии искатель может поймать (в стадах)
GameConfig.CATCH_DISTANCE_TOLERANCE = 4    -- запас на задержку сети/движение при серверной проверке дистанции
GameConfig.CATCH_HOLD_DURATION = 0.6       -- сколько держать кнопку "Поймать" (мешает случайным тапам)

-- Части тела, которые разрешено красить (имена BasePart в модели персонажа).
-- Список покрывает и R15, и R6 риги (см. DECISIONS.md, п.8).
GameConfig.PAINTABLE_PART_NAMES = {
	"Head",
	"UpperTorso", "LowerTorso", "Torso",
	"LeftUpperArm", "LeftLowerArm", "LeftHand", "Left Arm",
	"RightUpperArm", "RightLowerArm", "RightHand", "Right Arm",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "Left Leg",
	"RightUpperLeg", "RightLowerLeg", "RightFoot", "Right Leg",
}

-- === Заморозка / поза ===
-- ЗАГЛУШКА! Замени на реальный Animation ID позы, когда анимация будет загружена в Studio.
GameConfig.POSE_ANIMATION_ID = "rbxassetid://0"

-- === Свисток (Whistle) - см. DECISIONS.md, п.15 ===
GameConfig.WHISTLE_AUTO_INTERVAL_SECONDS = 45 -- через сколько секунд молчания срабатывает автосвисток
-- ЗАГЛУШКА! Замени на реальный звук свистка, когда загрузишь его в Studio.
GameConfig.WHISTLE_SOUND_ID = "rbxassetid://0"
GameConfig.WHISTLE_VOLUME = 1
GameConfig.WHISTLE_ROLLOFF_MIN_DISTANCE = 5   -- ближе этого расстояния звук на полной громкости
GameConfig.WHISTLE_ROLLOFF_MAX_DISTANCE = 60  -- дальше этого расстояния звук не слышен

-- === Команды ===
GameConfig.TEAM_HIDERS_NAME = "Hiders"
GameConfig.TEAM_SEEKERS_NAME = "Seekers"
GameConfig.TEAM_SPECTATORS_NAME = "Spectators"

return GameConfig
