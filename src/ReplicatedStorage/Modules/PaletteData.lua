-- PaletteData.lua
-- Список готовых цветов для UI-палитры игрока. Чтобы добавить/убрать цвет —
-- просто добавь или удали строку Color3.fromRGB(...) в списке ниже.

local PaletteData = {}

PaletteData.Colors = {
	Color3.fromRGB(255, 255, 255), -- белый (стартовый цвет Hiders)
	Color3.fromRGB(20, 20, 20),    -- чёрный
	Color3.fromRGB(120, 120, 120), -- серый
	Color3.fromRGB(160, 130, 98),  -- бежевый / светлое дерево
	Color3.fromRGB(102, 68, 44),   -- коричневый / тёмное дерево
	Color3.fromRGB(237, 28, 36),   -- красный
	Color3.fromRGB(255, 127, 39),  -- оранжевый
	Color3.fromRGB(255, 242, 0),   -- жёлтый
	Color3.fromRGB(34, 177, 76),   -- зелёный
	Color3.fromRGB(0, 100, 0),     -- тёмно-зелёный (трава/кусты)
	Color3.fromRGB(0, 162, 232),   -- голубой
	Color3.fromRGB(63, 72, 204),   -- синий
	Color3.fromRGB(163, 73, 164),  -- фиолетовый
	Color3.fromRGB(255, 174, 201), -- розовый
	Color3.fromRGB(185, 122, 87),  -- терракот
	Color3.fromRGB(200, 191, 231), -- лавандовый
}

return PaletteData
