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
local ScorePersistence = require(script.Parent.ScorePersistence)

local ScoreService = {}

local totalScores = {}       -- [Player] = очки за всю игровую сессию сервера (+ сохранённые прошлых сессий)
local roundStartTimes = {}   -- [Player] = tick(), когда началась фаза поиска (для Hiders)
local roundScores = {}       -- [Player] = очки конкретно за текущий раунд
local missedPointScores = {} -- [Player] = очки Missed Point Ranking конкретно за этот раунд
-- [Player] = true, если загрузка сохранённых очков при входе прошла
-- успешно - сохраняем при выходе ТОЛЬКО в этом случае (см. DECISIONS.md,
-- п.32): если DataStore был недоступен при загрузке, играть с 0 можно, но
-- сохранять этот 0 обратно нельзя - затрёт реальное значение игрока.
local loadSucceeded = {}

local POINTS_PER_CATCH = 20
local POINTS_PER_SECOND_HIDDEN = 1

local remotesRef

-- Увеличивается на каждый Start/EndMissedPointTracking, чтобы предыдущий
-- фоновый цикл сам понял, что раунд закончился, и не работал поверх нового -
-- тот же паттерн "токена раунда", что уже используется в WhistleService.watchLoop.
local missedPointRoundToken = 0

-- Сохранённые прошлой сессией очки - подставляются ОДИН раз при входе
-- (см. ScoreService.Init), до этого игрок числится с 0 (GetTotal). Не
-- используется для очков конкретно этого раунда (roundScores) - только
-- для totalScores.
function ScoreService.SeedTotal(player, value)
	totalScores[player] = value
end

-- Сохраняет очки одного игрока, только если загрузка при входе прошла
-- успешно (см. loadSucceeded выше) - общая функция для PlayerRemoving и
-- BindToClose, чтобы не дублировать эту проверку в двух местах.
local function persistIfLoaded(player)
	if loadSucceeded[player] then
		ScorePersistence.Save(player, totalScores[player] or 0)
	end
end

function ScoreService.Init(remotes)
	remotesRef = remotes

	-- Загружаем сохранённый счёт при входе - ScorePersistence сама делает
	-- ретрай и решает, успешна ли загрузка (см. DECISIONS.md, п.32).
	Players.PlayerAdded:Connect(function(player)
		local value, ok = ScorePersistence.Load(player)
		loadSucceeded[player] = ok
		if ok and value then
			ScoreService.SeedTotal(player, value)
		end
	end)

	-- Как и все остальные сервисы (см. ARCHITECTURE.md, "Состояние на сервере"),
	-- чистим состояние вышедшего игрока - иначе таблицы копят записи по мёртвым
	-- объектам Player весь срок жизни сервера (найдено аудитом Fable 5).
	-- Сохранение - ДО очистки totalScores, иначе нечего будет сохранять.
	Players.PlayerRemoving:Connect(function(player)
		persistIfLoaded(player)

		totalScores[player] = nil
		roundScores[player] = nil
		roundStartTimes[player] = nil
		missedPointScores[player] = nil
		loadSucceeded[player] = nil
	end)

	-- Обязательно - иначе очки игроков, всё ещё на сервере в момент его
	-- выключения (обновление/деплой), теряются: PlayerRemoving в этом
	-- случае не успевает сработать для всех.
	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			persistIfLoaded(player)
		end
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

-- Универсальная точечная прибавка/штраф очков за раунд - используется там,
-- где начисление не привязано к "поймали"/"дожил" (например, очки за
-- смелость при добровольном свистке, см. WhistleService.lua,
-- DECISIONS.md, п.27). Клэмп снизу нулём - штраф не может увести очки в
-- минус.
function ScoreService.AddRoundPoints(player, delta)
	roundScores[player] = math.max(0, (roundScores[player] or 0) + delta)
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
