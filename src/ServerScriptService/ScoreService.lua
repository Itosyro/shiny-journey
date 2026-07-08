-- ScoreService.lua
-- Считает очки за раунд: Hiders получают очки за время, что продержались
-- непойманными, флат-бонус за то, что дожили до конца раунда, и очки Missed
-- Point Ranking - за то, что оставались в зоне видимости Seeker'а и всё
-- равно не были замечены (см. DECISIONS.md, п.22). Seekers получают очки за
-- каждого найденного игрока.

local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local LineOfSightUtil = require(script.Parent.LineOfSightUtil)

-- Только для проверки, не пойман ли уже Hider (пойманным Missed Point Ranking
-- не начисляем) - require сиблинг-сервиса напрямую, без цикла зависимостей,
-- т.к. CatchService получает ScoreService через Init-инъекцию, а не через
-- require (тот же паттерн, что уже используется в WhistleService.lua).
local CatchService = require(script.Parent.CatchService)

local ScoreService = {}

local totalScores = {}       -- [Player] = очки за всю игровую сессию сервера
local roundStartTimes = {}   -- [Player] = tick(), когда началась фаза поиска (для Hiders)
local roundScores = {}       -- [Player] = очки конкретно за текущий раунд
local missedPointScores = {} -- [Player] = очки Missed Point Ranking конкретно за этот раунд

local POINTS_PER_CATCH = 20
local POINTS_PER_SECOND_HIDDEN = 1

local remotesRef

-- Увеличивается на каждый Start/EndMissedPointTracking, чтобы предыдущий
-- фоновый цикл сам понял, что раунд закончился, и не работал поверх нового -
-- тот же паттерн "токена раунда", что уже используется в WhistleService.watchLoop.
local missedPointRoundToken = 0

function ScoreService.Init(remotes)
	remotesRef = remotes

	-- Как и все остальные сервисы (см. ARCHITECTURE.md, "Состояние на сервере"),
	-- чистим состояние вышедшего игрока - иначе таблицы копят записи по мёртвым
	-- объектам Player весь срок жизни сервера (найдено аудитом Fable 5).
	Players.PlayerRemoving:Connect(function(player)
		totalScores[player] = nil
		roundScores[player] = nil
		roundStartTimes[player] = nil
		missedPointScores[player] = nil
	end)
end

function ScoreService.GetTotal(player)
	return totalScores[player] or 0
end

function ScoreService.GetMissedPoints(player)
	return missedPointScores[player] or 0
end

-- Вызывается в начале фазы поиска - готовим таблицы очков заново
function ScoreService.StartRoundTracking(hiders, seekers)
	roundScores = {}
	roundStartTimes = {}
	missedPointScores = {}

	local now = tick()
	for _, player in ipairs(hiders) do
		roundStartTimes[player] = now
		roundScores[player] = 0
		missedPointScores[player] = 0
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
-- очки за полное время выживания в фазе поиска, ПЛЮС отдельный флат-бонус
-- SURVIVAL_BONUS_POINTS за то, что дожили буквально до конца - это разные
-- вещи: первое награждает за каждую прожитую секунду одинаково для всех, а
-- бонус специально награждает именно за "дотянул до финиша", даже если сам
-- раунд был коротким.
function ScoreService.OnHiderSurvived(player)
	local startedAt = roundStartTimes[player]
	if startedAt then
		local survivedSeconds = tick() - startedAt
		roundScores[player] = (roundScores[player] or 0) + math.floor(survivedSeconds * POINTS_PER_SECOND_HIDDEN)
	end

	roundScores[player] = (roundScores[player] or 0) + GameConfig.SURVIVAL_BONUS_POINTS
end

-- === Missed Point Ranking (см. DECISIONS.md, п.22) ===

local function sendMissedPointUpdate(player, total)
	if remotesRef then
		remotesRef.MissedPointRankingUpdate:FireClient(player, total)
	end
end

-- Раз в MISSED_POINT_CHECK_INTERVAL_SECONDS проверяет каждого текущего Hider
-- против каждого текущего Seeker: если хотя бы один Seeker видит Hider
-- (дистанция + прямой взгляд - та же математика, что и у поимки, но на
-- большей дистанции) и Hider ещё не пойман - начисляет очки. Роль читается
-- напрямую из живого player.Team, а не из списка на старте раунда - это
-- само по себе останавливает рост личного счётчика, как только Hider
-- становится Seeker в Infection, без необходимости знать о мутациях
-- currentHiders/currentSeekers внутри RoundManager.
local function missedPointWatchLoop(myToken)
	while myToken == missedPointRoundToken do
		local hidersTeam = Teams:FindFirstChild(GameConfig.TEAM_HIDERS_NAME)
		local seekersTeam = Teams:FindFirstChild(GameConfig.TEAM_SEEKERS_NAME)

		if hidersTeam and seekersTeam then
			local seekers = {}
			for _, player in ipairs(Players:GetPlayers()) do
				if player.Team == seekersTeam then
					table.insert(seekers, player)
				end
			end

			-- Один набор параметров raycast на весь тик (все пары Hider×Seeker),
			-- а не пересборка Players:GetPlayers() на каждую отдельную пару.
			local raycastParams = LineOfSightUtil.BuildAllCharactersRaycastParams()

			for _, hider in ipairs(Players:GetPlayers()) do
				if hider.Team == hidersTeam and not CatchService.IsFound(hider) then
					local spotted = false
					for _, seeker in ipairs(seekers) do
						if LineOfSightUtil.IsWithinDistance(seeker, hider, GameConfig.MISSED_POINT_MAX_DISTANCE)
							and LineOfSightUtil.HasLineOfSight(seeker, hider, raycastParams) then
							spotted = true
							break
						end
					end

					if spotted then
						missedPointScores[hider] = (missedPointScores[hider] or 0) + GameConfig.MISSED_POINT_PER_TICK
						roundScores[hider] = (roundScores[hider] or 0) + GameConfig.MISSED_POINT_PER_TICK
						sendMissedPointUpdate(hider, missedPointScores[hider])
					end
				end
			end
		end

		task.wait(GameConfig.MISSED_POINT_CHECK_INTERVAL_SECONDS)
	end
end

-- Запускается в начале фазы поиска вместе с остальными таймерами раунда.
function ScoreService.StartMissedPointTracking()
	missedPointRoundToken += 1
	task.spawn(missedPointWatchLoop, missedPointRoundToken)
end

-- Останавливает фоновый цикл (тот же паттерн, что WhistleService.EndRound/
-- CatchService.EndRound) - вызывается и в обычном конце раунда, и в
-- аварийном pcall-восстановлении RoundManager.
function ScoreService.EndMissedPointTracking()
	missedPointRoundToken += 1
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
			missedPoints = missedPointScores[player] or 0,
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
			missedPoints = missedPointScores[player] or 0,
		})
	end

	return results
end

return ScoreService
