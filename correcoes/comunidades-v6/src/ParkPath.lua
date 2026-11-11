-- ParkPath (ModuleScript)
-- Caminho: ReplicatedStorage > Shared > ParkPath
-- Trilho da montanha-russa da MigueLândia (Marco 7.2). O servidor usa para montar o trilho
-- e o cliente usa para andar com o trenzinho exatamente em cima dele.
-- Medidas em studs, em relação ao ponto "Origin" da montanha-russa (no chão, no meio da volta).

local ParkPath = {}

ParkPath.Samples = 180 -- pontos ao longo da volta (mais pontos = trilho mais redondo)
ParkPath.Gauge = 1.4 -- metade da distância entre os dois trilhos

-- t de 0 a 1 dá uma volta inteira
function ParkPath.point(t)
	local a = t * math.pi * 2
	local x = 80 * math.cos(a)
	local z = 52 * math.sin(a) + 10 * math.sin(2 * a)
	local y = 22 + 10 * math.sin(3 * a) + 6 * math.sin(2 * a + 1)
	return Vector3.new(x, y, z)
end

-- Lista com todos os pontos (o último liga no primeiro)
function ParkPath.points()
	local list = {}
	for i = 0, ParkPath.Samples - 1 do
		table.insert(list, ParkPath.point(i / ParkPath.Samples))
	end
	return list
end

return ParkPath
