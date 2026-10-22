-- Regras puras: compartilhá-las não dá autoridade ao cliente.
local Rules = {}
function Rules.finite(value)
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
function Rules.point(point)
	local kind = type(point)
	return (kind == "table" or kind == "userdata" or kind == "vector")
		and Rules.finite(point.X) and Rules.finite(point.Y) and Rules.finite(point.Z)
end
function Rules.canJoin(alive, detained, count, slots)
	return alive == true and not detained and Rules.finite(count) and Rules.finite(slots)
		and count >= 0 and slots > 0 and count < slots
end
function Rules.canCapture(onDuty, equipped, distance, now, stunnedUntil, wanted, detained, protected, prisonOffense)
	return onDuty == true and equipped == true and wanted == true and (not detained or prisonOffense == true) and not protected
		and Rules.finite(distance) and distance >= 0 and distance <= 8
		and Rules.finite(now) and Rules.finite(stunnedUntil) and now < stunnedUntil
end
function Rules.validDirection(point)
	if not Rules.point(point) then return false end
	local lengthSquared = point.X * point.X + point.Y * point.Y + point.Z * point.Z
	return Rules.finite(lengthSquared) and lengthSquared > 0.0001 and lengthSquared < 100000000
end
function Rules.validReport(category)
	return category == "Seguranca" or category == "Patrulha" or category == "Manutencao"
end
return Rules
