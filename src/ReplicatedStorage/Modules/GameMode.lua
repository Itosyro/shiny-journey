-- GameMode.lua
-- Определяет, что происходит с пойманным Hider - см. DECISIONS.md, п.18.
-- Общий модуль (ReplicatedStorage): и сервер (RoundManager решает, как обработать
-- поимку), и клиент (например, чтобы показать точную формулировку сообщения о
-- поимке) читают один и тот же режим.
--
-- Режим хранится как Attribute на ReplicatedStorage, а не в локальной
-- переменной модуля - см. DECISIONS.md, п.30 (MEGA_PLAN 3.4.1). Attribute
-- реплицируется платформой сама (встроенное вместо своего RemoteEvent на
-- каждое чтение - ponytail), поэтому и сервер, и клиент читают текущее
-- значение через GetCurrent() и получают одно и то же без дополнительного
-- кода. Клиент может подписаться на
-- `ReplicatedStorage:GetAttributeChangedSignal("GameMode")`, чтобы узнавать
-- о смене режима в реальном времени (см. LobbyUIClient.lua).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameMode = {}

GameMode.Classic = "Classic"     -- пойманный Hider выбывает в Spectators до конца раунда
GameMode.Infection = "Infection" -- пойманный Hider сразу же становится Seeker

local ATTRIBUTE_NAME = "GameMode"
local DEFAULT_MODE = GameMode.Infection

function GameMode.GetCurrent()
	return ReplicatedStorage:GetAttribute(ATTRIBUTE_NAME) or DEFAULT_MODE
end

-- Для клиентского UI, которому нужно узнавать о смене режима в реальном
-- времени (см. LobbyUIClient.lua) - инкапсулирует имя атрибута здесь же,
-- а не дублирует строку "GameMode" в клиентском коде.
function GameMode.GetChangedSignal()
	return ReplicatedStorage:GetAttributeChangedSignal(ATTRIBUTE_NAME)
end

-- Только сервер должен вызывать эту функцию - клиент выбирает режим через
-- RemoteEvent RequestGameMode, а его серверный обработчик (RoundManager)
-- сам валидирует значение и фазу перед вызовом.
function GameMode.SetCurrent(mode)
	ReplicatedStorage:SetAttribute(ATTRIBUTE_NAME, mode)
end

return GameMode
