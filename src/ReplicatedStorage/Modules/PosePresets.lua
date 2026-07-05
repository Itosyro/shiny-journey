-- PosePresets.lua
-- Список конкретных пресетов позы ("замереть как..."), общий для клиента (UI
-- выбора) и сервера (валидация + анимация). Раньше "заморозка" была одна
-- произвольная поза без выбора; после дополнительного изучения референса
-- заменено на выбор из конкретных пресетов с разным силуэтом, как в оригинале
-- (присесть/лечь/прислониться/замереть стоя) - см. DECISIONS.md, п.17.

local PosePresets = {}

-- Каждый пресет:
--   id                        - уникальный строковый ключ (передаётся по сети в RequestFreeze)
--   label                     - подпись на кнопке UI (крупный текст, иконок-картинок пока нет)
--   animationId               - ЗАГЛУШКА rbxassetid://0 до появления реальных анимаций для
--                               каждой позы (тот же паттерн, что раньше был для одной общей
--                               позы, см. DECISIONS.md п.10) - требует финальных ассетов.
--   hipHeightMultiplier       - "hitbox-профиль": во сколько раз изменить Humanoid.HipHeight
--                               игрока в этой позе относительно его исходного значения -
--                               грубая имитация физического силуэта объекта (низкий/компактный/
--                               высокий). Работает и на R6, и на R15 (HipHeight - свойство
--                               базового класса Humanoid, не привязано к ригу).
--   maskingBonus              - АРХИТЕКТУРНЫЙ ЗАДЕЛ, пока НЕ используется нигде в логике
--                               обнаружения (см. DECISIONS.md, п.17) - вес "сложности заметить"
--                               эту позу, зарезервирован для будущей балансировки CatchService.
--   poseChangeCooldownSeconds - АРХИТЕКТУРНЫЙ ЗАДЕЛ, пока НЕ используется - в будущем можно
--                               ограничить, как часто разрешено переключать именно эту позу
--                               (например, Lie Down "тяжелее" перестроить на ходу).
PosePresets.List = {
	{
		id = "Crouch",
		label = "Присесть",
		animationId = "rbxassetid://0",
		hipHeightMultiplier = 0.55,
		maskingBonus = 1.0,
		poseChangeCooldownSeconds = 0,
	},
	{
		id = "LieDown",
		label = "Лечь",
		animationId = "rbxassetid://0",
		hipHeightMultiplier = 0.2,
		maskingBonus = 1.0,
		poseChangeCooldownSeconds = 0,
	},
	{
		id = "Lean",
		label = "Прислониться",
		animationId = "rbxassetid://0",
		hipHeightMultiplier = 0.9,
		maskingBonus = 1.0,
		poseChangeCooldownSeconds = 0,
	},
	{
		id = "StandStill",
		label = "Замереть стоя",
		animationId = "rbxassetid://0",
		hipHeightMultiplier = 1.0,
		maskingBonus = 1.0,
		poseChangeCooldownSeconds = 0,
	},
}

-- Быстрый поиск пресета по id - используется и клиентом (подсветка кнопки),
-- и сервером (валидация присланного poseId перед тем как встать в позу).
PosePresets.ById = {}
for _, preset in ipairs(PosePresets.List) do
	PosePresets.ById[preset.id] = preset
end

return PosePresets
