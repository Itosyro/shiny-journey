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
	"RoundResults",       -- сервер -> клиент: итоги раунда (очки)
	"InkUpdate",          -- сервер -> клиент: обновление количества "чернил" кисти
	"HideCatchPromptsFromHiders", -- сервер -> клиент (только Hiders): локально скрыть подсказки "Поймать"
	"RequestWhistle",         -- клиент -> сервер: свистнуть прямо сейчас (см. DECISIONS.md, п.15)
	"WhistleCountdownUpdate", -- сервер -> клиент (только Hiders): секунд до следующего свистка
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
