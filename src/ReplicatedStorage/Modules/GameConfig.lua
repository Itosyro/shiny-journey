-- GameConfig.lua
-- Общие настройки игры. Меняй значения тут, чтобы настроить баланс, не трогая
-- логику в других скриптах. Этот модуль используется и сервером, и клиентом.

local GameConfig = {}

-- === Карта (см. MAPS.md, DECISIONS.md, п.23) ===
-- true - MapBuilder.lua строит процедурную карту кодом при старте сервера.
-- Поставь false, если вручную вставишь свою карту в Workspace (например,
-- через Studio Toolbox) и процедурная генерация не нужна / будет мешать.
GameConfig.USE_PROCEDURAL_MAP = true

-- === Игроки и лобби ===
GameConfig.MIN_PLAYERS_TO_START = 2
-- MAX_PLAYERS здесь - только справочное значение для внутренних расчётов
-- (например, чтобы формула Seekers ниже проверялась и на верхней границе).
-- Реальный лимит игроков на сервер задаётся НЕ кодом, а в Creator Dashboard
-- (Experience Settings -> Basic Settings -> Max Players) - см. README.md.
-- См. DECISIONS.md, п.19 - диапазон уточнён на 2-24 по факту устройства
-- публичных лобби оригинала (раньше ошибочно считали, что 2-10).
GameConfig.MAX_PLAYERS = 24
GameConfig.LOBBY_COUNTDOWN_SECONDS = 15 -- отсчёт перед стартом раунда после набора минимума игроков

-- === Роли (см. DECISIONS.md, п.19) ===
-- Сколько игроков приходится на одного Seeker. Два отдельных значения, а не
-- одно - в Infection специально стартуем с МЕНЬШИМ числом Seekers, чем в
-- Classic, потому что оно всё равно вырастет по ходу раунда (пойманные Hiders
-- становятся Seekers) - см. PlayerRoleService.calculateSeekersCount.
GameConfig.SEEKERS_PER_PLAYERS_CLASSIC = 5   -- Classic: число Seekers не меняется в раунде
GameConfig.SEEKERS_PER_PLAYERS_INFECTION = 8 -- Infection: старт меньше, дальше растёт само
GameConfig.MIN_SEEKERS = 1
GameConfig.MAX_SEEKERS = 5

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
GameConfig.MAX_ACTIVE_STAMPS_PER_PLAYER = 150

-- === Обнаружение (поимка) ===
GameConfig.CATCH_MAX_DISTANCE = 8          -- на каком расстоянии искатель может поймать (в стадах)
GameConfig.CATCH_DISTANCE_TOLERANCE = 4    -- запас на задержку сети/движение при серверной проверке дистанции
GameConfig.CATCH_HOLD_DURATION = 0.6       -- сколько держать кнопку "Поймать" (мешает случайным тапам)

-- === Очки: базовые + Missed Point Ranking (см. DECISIONS.md, п.22) ===
-- Как часто проверять, не видит ли какой-нибудь Seeker текущего Hider -
-- не чаще раза в 1-2 секунды (не за каждый кадр), чтобы не грузить сервер
-- лишними raycast-проверками на каждую пару Seeker-Hider (см. CLAUDE.md).
GameConfig.MISSED_POINT_CHECK_INTERVAL_SECONDS = 1.5
-- Дистанция "в зоне видимости" для Missed Point Ranking - заметно больше
-- дистанции поимки (CATCH_MAX_DISTANCE), т.к. тут речь не о "можно схватить",
-- а о "теоретически мог бы заметить, но не заметил".
GameConfig.MISSED_POINT_MAX_DISTANCE = 50
GameConfig.MISSED_POINT_PER_TICK = 3 -- очков за каждый тик "замечен, но не пойман"
-- Отдельный флат-бонус за то, что дожил до конца раунда - помимо очков за
-- каждую прожитую секунду (POINTS_PER_SECOND_HIDDEN в ScoreService.lua).
GameConfig.SURVIVAL_BONUS_POINTS = 50

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

-- Заморозка / поза: см. ReplicatedStorage/Modules/PosePresets.lua - у каждого
-- из 4 пресетов свой animationId, поэтому единой GameConfig.POSE_ANIMATION_ID
-- больше нет (см. DECISIONS.md, п.17).

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

-- === Приватные комнаты (Custom Game с паролем) - см. DECISIONS.md, п.20 ===
GameConfig.PRIVATE_ROOM_PASSWORD_MIN_LENGTH = 4
GameConfig.PRIVATE_ROOM_PASSWORD_MAX_LENGTH = 20
-- Сколько живёт связка "пароль -> код сервера" в MemoryStoreService, пока
-- никто не зашёл. 6 часов - с запасом на "друзья собираются поиграть вечером",
-- но не 45-дневный максимум MemoryStore, чтобы не копить пароли навсегда.
GameConfig.PRIVATE_ROOM_PASSWORD_TTL_SECONDS = 6 * 60 * 60
-- Защита от подбора пароля: не больше стольки попыток "Присоединиться" за
-- окно времени с одного игрока.
GameConfig.PRIVATE_ROOM_JOIN_ATTEMPT_LIMIT = 5
GameConfig.PRIVATE_ROOM_JOIN_ATTEMPT_WINDOW_SECONDS = 60

-- === Зритель (Spectator) для зашедших посреди раунда - см. DECISIONS.md, п.21 ===
GameConfig.SPECTATOR_FLY_SPEED = 40 -- стадов в секунду

return GameConfig
