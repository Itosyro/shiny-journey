-- LineOfSightUtil.lua
-- Общая серверная проверка дистанции и прямой видимости (line of sight) между
-- двумя игроками. Раньше эта математика была продублирована только внутри
-- CatchService (для поимки) - вынесена сюда, т.к. теперь её же использует
-- ScoreService для Missed Point Ranking (см. DECISIONS.md, п.22), и дублировать
-- одну и ту же логику raycast в двух сервисах не стоило.

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local LineOfSightUtil = {}

function LineOfSightUtil.IsWithinDistance(fromPlayer, toPlayer, maxDistance)
	local fromChar = fromPlayer.Character
	local toChar = toPlayer.Character
	if not fromChar or not toChar then
		return false
	end

	local fromRoot = fromChar:FindFirstChild("HumanoidRootPart")
	local toRoot = toChar:FindFirstChild("HumanoidRootPart")
	if not fromRoot or not toRoot then
		return false
	end

	return (fromRoot.Position - toRoot.Position).Magnitude <= maxDistance
end

-- Исключает из raycast персонажи ВСЕХ игроков на сервере, а не только двух
-- проверяемых - иначе третий игрок, случайно оказавшийся на пути луча,
-- "загораживал" бы обзор и ломал честную поимку/Missed Point Ranking (см.
-- AUDIT_FABLE5.md, S4). Для цикла, проверяющего много пар за один тик
-- (Missed Point Ranking), собрать один раз и передать в HasLineOfSight
-- третьим аргументом - иначе Players:GetPlayers() дублировался бы на
-- каждую отдельную пару.
function LineOfSightUtil.BuildAllCharactersRaycastParams()
	local characters = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(characters, player.Character)
		end
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = characters
	return raycastParams
end

-- Прямой взгляд от головы fromPlayer до HumanoidRootPart toPlayer - луч не
-- должен ни во что упереться по пути (иначе между ними стена/препятствие).
-- precomputedParams - опционально, см. BuildAllCharactersRaycastParams выше.
function LineOfSightUtil.HasLineOfSight(fromPlayer, toPlayer, precomputedParams)
	local fromChar = fromPlayer.Character
	local toChar = toPlayer.Character
	if not fromChar or not toChar then
		return false
	end

	local fromHead = fromChar:FindFirstChild("Head")
	local toRoot = toChar:FindFirstChild("HumanoidRootPart")
	if not fromHead or not toRoot then
		return false
	end

	local origin = fromHead.Position
	local toTarget = toRoot.Position - origin

	local raycastParams = precomputedParams or LineOfSightUtil.BuildAllCharactersRaycastParams()

	local result = Workspace:Raycast(origin, toTarget, raycastParams)
	-- Если луч долетел до цели, ничего не задев по пути - обзор чист
	return result == nil
end

return LineOfSightUtil
