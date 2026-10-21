-- Regras puras da autoridade de empregos e retirada de uniforme.
local WorkRoleRules = {}
local roles = { Policial = true, Taxista = true, Pizzaiolo = true, Atendente = true, Entregador = true }

function WorkRoleRules.finite(value)
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function WorkRoleRules.finitePoint(point)
	local kind = type(point)
	if kind ~= "table" and kind ~= "userdata" and kind ~= "vector" then return false end
	return WorkRoleRules.finite(point.X) and WorkRoleRules.finite(point.Y) and WorkRoleRules.finite(point.Z)
end

function WorkRoleRules.validRole(role)
	return type(role) == "string" and roles[role] == true
end

function WorkRoleRules.canAssign(currentRole, requestedRole, alive, detained)
	if not WorkRoleRules.validRole(requestedRole) then return false, "role" end
	if not alive or detained then return false, "character" end
	if currentRole ~= nil and currentRole ~= requestedRole then return false, "employed" end
	return true
end

function WorkRoleRules.canEquip(currentRole, requestedRole, distance, alive, detained, stunned)
	if not WorkRoleRules.validRole(requestedRole) or currentRole ~= requestedRole then return false, "role" end
	if not alive or detained or stunned then return false, "character" end
	if not WorkRoleRules.finite(distance) or distance < 0 or distance > 11 then return false, "distance" end
	return true
end

return WorkRoleRules
