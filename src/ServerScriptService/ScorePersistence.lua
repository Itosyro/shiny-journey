-- ScorePersistence.lua
-- Сохраняет общий счёт игрока (totalScore) между игровыми сессиями через
-- DataStore. Изолирует все pcall/retry от чистой логики очков в
-- ScoreService.lua - см. MEGA_PLAN.md 3.4.3, DECISIONS.md, п.32.
--
-- Один DataStore, значение - просто число (никаких таблиц-схем, YAGNI).
-- UpdateAsync не нужен: одно значение, и всегда пишет ровно один сервер -
-- владелец конкретного игрока, гонки между серверами тут в принципе нет
-- (в отличие от общего пароля приватных комнат, см. DECISIONS.md, п.20).

local DataStoreService = game:GetService("DataStoreService")

local ScorePersistence = {}

local store = DataStoreService:GetDataStore("PlayerTotals")

-- Одна попытка + один ретрай через 2с (временный сбой сети/DataStore) -
-- если оба раза неудача, вызывающая сторона ДОЛЖНА играть с 0 и НЕ
-- сохранять при выходе, чтобы не затереть реальное сохранённое значение
-- нулём (важное правило - см. DECISIONS.md, п.32).
function ScorePersistence.Load(player)
	local key = tostring(player.UserId)

	local ok, value = pcall(function()
		return store:GetAsync(key)
	end)
	if ok then
		return value, true
	end

	task.wait(2)

	local ok2, value2 = pcall(function()
		return store:GetAsync(key)
	end)
	if ok2 then
		return value2, true
	end

	warn("[MecchaChameleon] Не удалось загрузить очки для " .. player.Name)
	return nil, false
end

function ScorePersistence.Save(player, totalScore)
	local key = tostring(player.UserId)

	local ok, err = pcall(function()
		store:SetAsync(key, totalScore)
	end)
	if not ok then
		warn("[MecchaChameleon] Не удалось сохранить очки для " .. player.Name .. ": " .. tostring(err))
	end
end

return ScorePersistence
