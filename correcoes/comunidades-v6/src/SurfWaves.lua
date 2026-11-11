-- SurfWaves (ModuleScript)
-- Caminho: ReplicatedStorage > Shared > SurfWaves
-- Marco 10.32: as ondas da área de surfe, iguais em todos os aparelhos e no servidor (contadas
-- pelo relógio do servidor: Workspace:GetServerTimeNow()). Cada onda é uma crista em linha reta
-- (de X0 a X1) que nasce no fundo (ZOut), anda até a areia, cresce até ZPeak e quebra em ZBreak.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local S = GameConfig.Surf
local L = GameConfig.Litoral

local SurfWaves = {}

SurfWaves.FRONT = 9 -- largura da frente da onda (lado da areia, íngreme)
SurfWaves.BACK = 22 -- largura das costas (lado do mar, suave)

local function smooth(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- tempo que uma onda leva do fundo até quebrar
function SurfWaves.life()
	return (S.ZOut - S.ZBreak) / S.WaveSpeed
end

-- altura da crista quando ela está em z
function SurfWaves.amplitude(z)
	if z >= S.ZPeak then
		return S.WaveHeight * (0.18 + 0.82 * smooth((S.ZOut - z) / (S.ZOut - S.ZPeak)))
	end
	return S.WaveHeight * smooth((z - S.ZBreak) / (S.ZPeak - S.ZBreak)) ^ 0.6
end

-- ondas vivas agora: lista de { id, z (crista), a (altura), breaking (0 a 1) }
function SurfWaves.active(t)
	local out = {}
	local life = SurfWaves.life()
	local first = math.floor((t - life) / S.WavePeriod)
	for k = first, math.floor(t / S.WavePeriod) do
		local age = t - k * S.WavePeriod
		if age >= 0 and age <= life then
			local z = S.ZOut - S.WaveSpeed * age
			table.insert(out, {
				id = k,
				z = z,
				a = SurfWaves.amplitude(z),
				breaking = z < S.ZPeak and (S.ZPeak - z) / (S.ZPeak - S.ZBreak) or 0,
			})
		end
	end
	return out
end

-- altura da água (y) em (x, z) somando as ondas
function SurfWaves.height(x, z, t, waves)
	local y = L.SeaLevel
	if x < S.X0 - 10 or x > S.X1 + 10 then
		return y
	end
	local best = 0
	for _, w in ipairs(waves or SurfWaves.active(t)) do
		local d = z - w.z
		local k = d < 0 and 1 + d / SurfWaves.FRONT or 1 - d / SurfWaves.BACK
		if k > 0 then
			best = math.max(best, w.a * k)
		end
	end
	return y + best
end

function SurfWaves.inZone(pos, pad)
	pad = pad or 0
	return pos.X > S.X0 - pad and pos.X < S.X1 + pad and pos.Z > S.ZShore - 40 - pad and pos.Z < S.ZOut + pad
end

return SurfWaves
