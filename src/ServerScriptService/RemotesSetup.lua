-- RemotesSetup.lua
-- Создаёт папку Remotes в ReplicatedStorage со всеми RemoteEvent, которые нужны
-- для связи клиент <-> сервер. Вызывается один раз при старте сервера (см. Main.server.lua).
-- Клиентские скрипты потом просто делают ReplicatedStorage.Remotes:WaitForChild("ИмяСобытия").
-- См. DECISIONS.md, п.7 — почему Remote создаются кодом, а не заранее в Studio.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemotesSetup = {}

-- Список всех RemoteEvent, которые использует игра.
local REMOTE_EVENT_NAMES = {
	"PaintStroke",        -- клиент -> сервер: пакет точек мазка кисти (см. DECISIONS.md, п.14)
	"RequestFreeze",      -- клиент -> сервер: включить/выключить позу (заморозку); при включении несёт id пресета позы (см. PosePresets.lua, DECISIONS.md п.17)
	"RoundStateChanged",  -- сервер -> клиент: началась новая фаза раунда
	"RoundTimerTick",     -- сервер -> клиент: обновление таймера каждую секунду
	"PlayerCaught",       -- сервер -> клиент: игрока поймали
	-- Итоги раунда едут внутри extra.results события RoundStateChanged -
	-- отдельного RemoteEvent для этого не заводим (было "RoundResults",
	-- убрано как дублирующий путь доставки, см. AUDIT_FABLE5.md, S3).
	"InkUpdate",          -- сервер -> клиент: обновление количества "чернил" кисти
	"HideCatchPromptsFromHiders", -- сервер -> клиент (только Hiders): локально скрыть подсказки "Поймать" (режим Proximity)
	"RequestTag",         -- клиент -> сервер (только Seekers): unit-вектор направления камеры - метка с дистанции (см. DECISIONS.md, п.29)
	"RequestWhistle",         -- клиент -> сервер: свистнуть добровольно прямо сейчас (см. DECISIONS.md, п.27)
	"WhistleCountdownUpdate", -- сервер -> клиент (только свистнувшему): длительность перезарядки (см. п.27)
	"CreatePrivateRoom",  -- клиент -> сервер: создать приватную комнату с паролем (см. DECISIONS.md, п.20)
	"JoinPrivateRoom",    -- клиент -> сервер: зайти в приватную комнату по паролю
	"PrivateRoomError",   -- сервер -> клиент: не удалось создать/зайти (текст причины)
	"SpectatorModeChanged", -- сервер -> клиент: включить/выключить режим зрителя (см. DECISIONS.md, п.21)
	"MissedPointRankingUpdate", -- сервер -> клиент (только сам Hider): личный счётчик Missed Point Ranking (см. DECISIONS.md, п.22)
	"RequestGameMode", -- клиент -> сервер: сменить режим (Classic/Infection) на следующий раунд (см. DECISIONS.md, п.30)
}

function RemotesSetup.Init()
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end

	local remotes = {}
	for _, remoteName in ipairs(REMOTE_EVENT_NAMES) do
		local existing = folder:FindFirstChild(remoteName)
		if not existing then
			existing = Instance.new("RemoteEvent")
			existing.Name = remoteName
			existing.Parent = folder
		end
		remotes[remoteName] = existing
	end

	return remotes
end

return RemotesSetup
