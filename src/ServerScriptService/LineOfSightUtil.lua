-- LineOfSightUtil.lua
-- Общая серверная проверка дистанции и прямой видимости (line of sight) между
-- двумя игроками. Раньше эта математика была продублирована только внутри
-- CatchService (для поимки) - вынесена сюда, т.к. теперь её же использует
-- ScoreService для Missed Point Ranking (см. DECISIONS.md, п.22), и дублировать
-- одну и ту же логику raycast в двух сервисах не стоило.

local Workspace = game:GetService("Workspace")

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

-- Прямой взгляд от головы fromPlayer до HumanoidRootPart toPlayer - луч не
-- должен ни во что упереться по пути (иначе между ними стена/препятствие).
function LineOfSightUtil.HasLineOfSight(fromPlayer, toPlayer)
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

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { fromChar, toChar }

	local result = Workspace:Raycast(origin, toTarget, raycastParams)
	-- Если луч долетел до цели, ничего не задев по пути - обзор чист
	return result == nil
end

return LineOfSightUtil
