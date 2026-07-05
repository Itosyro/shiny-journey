-- GameConfig.lua
-- Общие настройки игры. Меняй значения тут, чтобы настроить баланс, не трогая
-- логику в других скриптах. Этот модуль используется и сервером, и клиентом.

local GameConfig = {}

-- === Игроки и лобби ===
GameConfig.MIN_PLAYERS_TO_START = 2
GameConfig.MAX_PLAYERS = 10
GameConfig.LOBBY_COUNTDOWN_SECONDS = 15 -- отсчёт перед стартом раунда после набора минимума игроков

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

-- === Покраска ===
GameConfig.MAX_BRUSH_CHARGES = 20        -- сколько "мазков" краски есть у игрока за раунд
GameConfig.BRUSH_RECHARGE_SECONDS = 3    -- через сколько секунд восстанавливается 1 заряд
GameConfig.EYEDROPPER_MAX_DISTANCE = 60  -- максимальная дальность пипетки (в стадах)

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

-- === Команды ===
GameConfig.TEAM_HIDERS_NAME = "Hiders"
GameConfig.TEAM_SEEKERS_NAME = "Seekers"
GameConfig.TEAM_SPECTATORS_NAME = "Spectators"

return GameConfig
