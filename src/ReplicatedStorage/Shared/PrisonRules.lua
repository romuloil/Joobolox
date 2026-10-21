-- Regras puras da prisão: sem serviços Roblox, dinheiro ou efeitos colaterais.
-- São usadas pelo servidor; publicá-las no Shared não concede autoridade ao cliente.
local PrisonRules = {}

function PrisonRules.isFinite(value)
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function PrisonRules.isFinitePoint(point)
	local kind = type(point)
	if kind ~= "table" and kind ~= "userdata" and kind ~= "vector" then
		return false
	end
	return PrisonRules.isFinite(point.X)
		and PrisonRules.isFinite(point.Y) and PrisonRules.isFinite(point.Z)
end

function PrisonRules.deadline(now, duration)
	if not PrisonRules.isFinite(now) or not PrisonRules.isFinite(duration) or duration <= 0 then
		return nil
	end
	local result = now + duration
	return PrisonRules.isFinite(result) and result or nil
end

function PrisonRules.remaining(endsAt, now)
	if not PrisonRules.isFinite(endsAt) or not PrisonRules.isFinite(now) then
		return 0
	end
	return math.max(0, endsAt - now)
end

-- expected/index são índices do PRÓXIMO ponto (1..N). O tempo de percurso
-- desconta o alcance do prompt e tolera uma pequena diferença de replicação.
function PrisonRules.canAdvance(expected, index, distance, elapsed, pathDistance, walkSpeed, alive)
	if not alive then
		return false, "character"
	end
	if not PrisonRules.isFinite(expected) or expected < 1 or expected % 1 ~= 0
		or not PrisonRules.isFinite(index) or expected ~= index then
		return false, "sequence"
	end
	if not PrisonRules.isFinite(distance) or distance < 0 or distance > 10 then
		return false, "distance"
	end
	if not PrisonRules.isFinite(elapsed) or elapsed < 0
		or not PrisonRules.isFinite(pathDistance) or pathDistance < 0
		or not PrisonRules.isFinite(walkSpeed) or walkSpeed <= 0 then
		return false, "travel"
	end
	local minimumTime = math.max(0, (pathDistance - 10) / (walkSpeed * 1.35) - 0.5)
	if elapsed < minimumTime then
		return false, "travel"
	end
	return true
end

-- Uma margem pequena absorve atualizações de posição agrupadas pela rede.
-- O tempo entre checkpoints também é conferido, independentemente desta amostra.
function PrisonRules.movementAllowed(distance, elapsed, walkSpeed)
	return PrisonRules.isFinite(distance) and distance >= 0
		and PrisonRules.isFinite(elapsed) and elapsed >= 0
		and PrisonRules.isFinite(walkSpeed) and walkSpeed > 0
		and distance <= 6 + elapsed * walkSpeed * 1.65
end

return PrisonRules
