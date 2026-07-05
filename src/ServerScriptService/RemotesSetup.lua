-- RemotesSetup.lua
-- Создаёт папку Remotes в ReplicatedStorage со всеми RemoteEvent, которые нужны
-- для связи клиент <-> сервер. Вызывается один раз при старте сервера (см. Main.server.lua).
-- Клиентские скрипты потом просто делают ReplicatedStorage.Remotes:WaitForChild("ИмяСобытия").
-- См. DECISIONS.md, п.7 — почему Remote создаются кодом, а не заранее в Studio.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemotesSetup = {}

-- Список всех RemoteEvent, которые использует игра.
local REMOTE_EVENT_NAMES = {
	"PaintCharacter",     -- клиент -> сервер: покрасить часть тела в цвет
	"RequestFreeze",      -- клиент -> сервер: включить/выключить позу (заморозку)
	"RoundStateChanged",  -- сервер -> клиент: началась новая фаза раунда
	"RoundTimerTick",     -- сервер -> клиент: обновление таймера каждую секунду
	"PlayerCaught",       -- сервер -> клиент: игрока поймали
	"RoundResults",       -- сервер -> клиент: итоги раунда (очки)
	"BrushChargesUpdate", -- сервер -> клиент: обновление количества зарядов краски
	"HideCatchPromptsFromHiders", -- сервер -> клиент (только Hiders): локально скрыть подсказки "Поймать"
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
