-- ScoreService.lua
-- Считает очки за раунд: Hiders получают очки за время, что продержались
-- непойманными, Seekers получают очки за каждого найденного игрока.

local ScoreService = {}

local totalScores = {}     -- [Player] = очки за всю игровую сессию сервера
local roundStartTimes = {} -- [Player] = tick(), когда началась фаза поиска (для Hiders)
local roundScores = {}     -- [Player] = очки конкретно за текущий раунд

local POINTS_PER_CATCH = 20
local POINTS_PER_SECOND_HIDDEN = 1

function ScoreService.Init()
end

function ScoreService.GetTotal(player)
	return totalScores[player] or 0
end

-- Вызывается в начале фазы поиска - готовим таблицы очков заново
function ScoreService.StartRoundTracking(hiders, seekers)
	roundScores = {}
	roundStartTimes = {}

	local now = tick()
	for _, player in ipairs(hiders) do
		roundStartTimes[player] = now
		roundScores[player] = 0
	end
	for _, player in ipairs(seekers) do
		roundScores[player] = 0
	end
end

-- Вызывается CatchService, когда прячущегося поймали
function ScoreService.OnHiderCaught(hiderPlayer, seekerPlayer)
	-- Прячущийся получает очки за то время, что продержался до поимки
	local startedAt = roundStartTimes[hiderPlayer]
	if startedAt then
		local survivedSeconds = tick() - startedAt
		roundScores[hiderPlayer] = (roundScores[hiderPlayer] or 0) + math.floor(survivedSeconds * POINTS_PER_SECOND_HIDDEN)
	end

	-- Искатель получает очки за поимку
	roundScores[seekerPlayer] = (roundScores[seekerPlayer] or 0) + POINTS_PER_CATCH
end

-- Вызывается в конце раунда для тех Hiders, кого не поймали - они получают
-- очки за полное время выживания в фазе поиска
function ScoreService.OnHiderSurvived(player)
	local startedAt = roundStartTimes[player]
	if startedAt then
		local survivedSeconds = tick() - startedAt
		roundScores[player] = (roundScores[player] or 0) + math.floor(survivedSeconds * POINTS_PER_SECOND_HIDDEN)
	end
end

-- Собрать финальные результаты раунда и прибавить их к общему счёту за сессию
function ScoreService.BuildRoundResults(hiders, seekers)
	local results = {}

	for _, player in ipairs(hiders) do
		local gained = roundScores[player] or 0
		totalScores[player] = (totalScores[player] or 0) + gained
		table.insert(results, {
			name = player.Name,
			role = "Hider",
			roundScore = gained,
			totalScore = totalScores[player],
		})
	end

	for _, player in ipairs(seekers) do
		local gained = roundScores[player] or 0
		totalScores[player] = (totalScores[player] or 0) + gained
		table.insert(results, {
			name = player.Name,
			role = "Seeker",
			roundScore = gained,
			totalScore = totalScores[player],
		})
	end

	return results
end

return ScoreService
