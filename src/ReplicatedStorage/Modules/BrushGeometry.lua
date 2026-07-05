-- BrushGeometry.lua
-- Общая математика для "мазков" кисти. Используется и клиентом (чтобы понять,
-- в какую грань детали и в какую точку этой грани попал palец/курсор при
-- рисовании), и сервером (чтобы по присланным (face, u, v) вычислить реальные
-- OffsetStudsU/V для размещения мазка-Texture на конкретной детали персонажа -
-- сервер не доверяет студовым координатам от клиента напрямую, только
-- нормализованным 0..1, см. PaintService.lua).

local BrushGeometry = {}

-- Для каждой грани детали - какая локальная ось соответствует горизонтали (U)
-- и какая вертикали (V) текстуры на этой грани.
local FACE_AXES = {
	[Enum.NormalId.Front] = { u = "X", v = "Y" },
	[Enum.NormalId.Back] = { u = "X", v = "Y" },
	[Enum.NormalId.Left] = { u = "Z", v = "Y" },
	[Enum.NormalId.Right] = { u = "Z", v = "Y" },
	[Enum.NormalId.Top] = { u = "X", v = "Z" },
	[Enum.NormalId.Bottom] = { u = "X", v = "Z" },
}

local function axisValue(vector, axisName)
	if axisName == "X" then
		return vector.X
	elseif axisName == "Y" then
		return vector.Y
	else
		return vector.Z
	end
end

-- Список граней, которые вообще поддерживаются (для серверной валидации входных
-- данных - клиент не должен присылать ничего, кроме этих 6 значений).
BrushGeometry.ValidFaces = {
	Enum.NormalId.Front,
	Enum.NormalId.Back,
	Enum.NormalId.Left,
	Enum.NormalId.Right,
	Enum.NormalId.Top,
	Enum.NormalId.Bottom,
}

-- Определяет, в какую грань детали смотрит нормаль. Нормаль должна быть уже
-- переведена в локальные координаты детали через `part.CFrame:VectorToObjectSpace(normal)`.
function BrushGeometry.DetectFace(localNormal)
	local absX, absY, absZ = math.abs(localNormal.X), math.abs(localNormal.Y), math.abs(localNormal.Z)

	if absX >= absY and absX >= absZ then
		return localNormal.X > 0 and Enum.NormalId.Right or Enum.NormalId.Left
	elseif absY >= absX and absY >= absZ then
		return localNormal.Y > 0 and Enum.NormalId.Top or Enum.NormalId.Bottom
	else
		return localNormal.Z > 0 and Enum.NormalId.Back or Enum.NormalId.Front
	end
end

-- Переводит точку попадания (в локальных координатах детали, центр детали = 0,0,0,
-- через `part.CFrame:PointToObjectSpace(worldPosition)`) в нормализованные (u, v)
-- в диапазоне [0, 1] для данной грани.
function BrushGeometry.PositionToUV(part, localPosition, face)
	local axes = FACE_AXES[face]
	if not axes then
		return 0.5, 0.5
	end

	local sizeU = axisValue(part.Size, axes.u)
	local sizeV = axisValue(part.Size, axes.v)
	local posU = axisValue(localPosition, axes.u)
	local posV = axisValue(localPosition, axes.v)

	local u = sizeU > 0 and (posU / sizeU + 0.5) or 0.5
	local v = sizeV > 0 and (posV / sizeV + 0.5) or 0.5

	return math.clamp(u, 0, 1), math.clamp(v, 0, 1)
end

-- Обратное преобразование: из нормализованных (u, v) и размера мазка (в стадах)
-- получаем OffsetStudsU/V так, чтобы центр мазка совпал с точкой (u, v) на грани.
function BrushGeometry.UVToOffset(part, face, u, v, stampSize)
	local axes = FACE_AXES[face]
	if not axes then
		return 0, 0
	end

	local sizeU = axisValue(part.Size, axes.u)
	local sizeV = axisValue(part.Size, axes.v)

	local offsetU = u * sizeU - stampSize / 2
	local offsetV = v * sizeV - stampSize / 2

	return offsetU, offsetV
end

return BrushGeometry
