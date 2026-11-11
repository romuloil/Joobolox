-- CityRoads (ModuleScript)
-- Caminho: ReplicatedStorage > Shared > CityRoads
-- Marco 10: desenho das estradas da expansão da cidade, só com contas (sem peças).
-- O MapBuilder (ExpansionBuilder e HorizonteBuilder) monta o asfalto a partir daqui; o mapa (M)
-- desenha e o GPS (RouteGraph) anda pelas mesmas linhas. Assim os três nunca discordam.
--
-- Cada estrada: { Name, Kind, Points = { Vector3 (Y = 0) }, Width, Code }
--   Kind "rodovia"   = pista dupla com canteiro, mureta e guard-rail (Rodovia LK-101, Rodoanel)
--   Kind "boulevard" = pista dupla com canteiro de palmeiras e calçadas (bairro de luxo)
--   Kind "avenida" / "rua" = mão dupla com calçadas
--   Kind "estrada"   = mão dupla sem calçada (estradas para áreas futuras)
-- Rotatórias: { Name, Center, Radius, Kind }. As estradas que chegam nelas começam ou terminam
-- no centro (o asfalto redondo cobre o resto).
-- Fins provisórios: { Pos, Dir, Text } (placa "em breve" e barreira no fim da estrada).

local GameConfig = require(script.Parent:WaitForChild("GameConfig"))

local CityRoads = {}

local M = GameConfig.Map
local R = GameConfig.Rodovia
local P = GameConfig.Progresso
local H = GameConfig.Horizonte
local RADIAL_END = 50 + M.RoadLength

CityRoads.RADIAL_END = RADIAL_END

-- Largura total (asfalto) de cada tipo; calçada = Map.SidewalkWidth de cada lado quando Sidewalk
CityRoads.Kinds = {
	rodovia = { Width = 2 * R.CarriageWidth + R.Median, Sidewalk = false, Verge = 8 },
	boulevard = { Width = 2 * 24 + 12, Sidewalk = true, Median = 12 },
	avenida = { Width = M.RoadWidth, Sidewalk = true },
	rua = { Width = M.RoadWidth, Sidewalk = true },
	estrada = { Width = M.RoadWidth, Sidewalk = false, Verge = 3 },
}

-- Medidas do Bairro Horizonte (distâncias para o norte a partir do Trevo Norte)
CityRoads.District = {
	StreetT = { 300, 560, 820 }, -- ruas atravessadas (Orquídeas, Magnólias, Hortênsias)
	Half = 520, -- ruas do Poente e do Nascente (x = -520 e +520)
	TowerT = { 110, 210, 390, 480, 650, 740 }, -- prédios dos dois lados do boulevard
	GateT = 885, -- portaria do condomínio
	Loop = { X = 300, T0 = 920, T1 = 1360 }, -- Alameda dos Jardins (retângulo)
}

-- Distrito financeiro: compartilhado pelo construtor, mapa e GPS.
CityRoads.FinancialDistrict = {
 Name = "Centro Financeiro do Vale",
 Streets = {
  { Name = "Avenida dos Negócios", A = Vector3.new(180, 0, -1360), B = Vector3.new(1040, 0, -1360) },
  { Name = "Alameda das Empresas", A = Vector3.new(180, 0, -1580), B = Vector3.new(1040, 0, -1580) },
  { Name = "Rua da Praça Financeira", A = Vector3.new(180, 0, -1150), B = Vector3.new(180, 0, -2020) },
  { Name = "Rua dos Investidores", A = Vector3.new(610, 0, -1150), B = Vector3.new(610, 0, -2020) },
  { Name = "Rua das Conexões", A = Vector3.new(1040, 0, -1150), B = Vector3.new(1040, 0, -2020) },
  { Name = "Boulevard Metropolitano", A = Vector3.new(180, 0, -1800), B = Vector3.new(1040, 0, -1800), Kind = "boulevard" },
  { Name = "Avenida das Torres", A = Vector3.new(180, 0, -2020), B = Vector3.new(1040, 0, -2020) },
  { Name = "Rua do Banco Oeste", A = Vector3.new(180, 0, -1150), B = Vector3.new(180, 0, -820) },
  { Name = "Rua do Jardim do Banco", A = Vector3.new(180, 0, -820), B = Vector3.new(430, 0, -820) },
  { Name = "Rua do Banco Leste", A = Vector3.new(670, 0, -1150), B = Vector3.new(670, 0, -1000) },
  { Name = "Avenida da Capital", A = Vector3.new(180, 0, -2240), B = Vector3.new(1040, 0, -2240) },
  { Name = "Rua da Praça Norte", A = Vector3.new(180, 0, -2020), B = Vector3.new(180, 0, -2240) },
  { Name = "Rua dos Investidores Norte", A = Vector3.new(610, 0, -2020), B = Vector3.new(610, 0, -2240) },
  { Name = "Rua das Conexões Norte", A = Vector3.new(1040, 0, -2020), B = Vector3.new(1040, 0, -2240) },
 },
}

-- Extensão ao norte/leste do distrito, em direção à Solaris e ao Rodoanel.
-- Ruas antigas conservam suas posições e nomes.
CityRoads.FinancialExtension = {
 {Name="Avenida da Capital Leste",A=Vector3.new(1040,0,-2240),B=Vector3.new(2020,0,-2240)},
 {Name="Rua das Conexões Alta",A=Vector3.new(1040,0,-2240),B=Vector3.new(1040,0,-3220)},
 {Name="Avenida da Integração",A=Vector3.new(1430,0,-2240),B=Vector3.new(1430,0,-3220)},
 {Name="Rua dos Negócios Leste",A=Vector3.new(1900,0,-2240),B=Vector3.new(1900,0,-3220)},
 {Name="Alameda da Vista",A=Vector3.new(610,0,-2480),B=Vector3.new(2020,0,-2480)},
 {Name="Rua do Panorama",A=Vector3.new(1040,0,-2740),B=Vector3.new(2020,0,-2740)},
 {Name="Alameda dos Escritórios",A=Vector3.new(1040,0,-3000),B=Vector3.new(2020,0,-3000)},
 {Name="Avenida do Rodoanel",A=Vector3.new(1040,0,-3220),B=Vector3.new(2020,0,-3220)},
}

local cache

-- Ponto do bairro: x = leste (+) / oeste (-), t = distância para o norte a partir do trevo
function CityRoads.districtPoint(x, t)
	return Vector3.new(x, 0, -R.RingRadius - t)
end

function CityRoads.ringPoint(deg)
	local a = math.rad(deg)
	return Vector3.new(R.RingRadius * math.sin(a), 0, -R.RingRadius * math.cos(a))
end

function CityRoads.get()
	if cache then
		return cache
	end
	local roads, circles, ends = {}, {}, {}
	local function road(name, kind, points, extra)
		local r = { Name = name, Kind = kind, Points = points, Width = CityRoads.Kinds[kind].Width }
		for k, v in pairs(extra or {}) do
			r[k] = v
		end
		table.insert(roads, r)
		return r
	end
	local function soon(points, text)
		local n = #points
		table.insert(ends, { Pos = points[n], Dir = (points[n] - points[n - 1]).Unit, Text = text })
	end

	-- Rodovia LK-101: continua a Avenida das Palmeiras (rua 1, norte) até o Trevo Norte
	local trevo = Vector3.new(0, 0, -R.RingRadius)
	road(R.Name, "rodovia", { Vector3.new(0, 0, -RADIAL_END), trevo }, { Code = R.Code })
	table.insert(circles, { Name = R.TrevoName, Center = trevo, Radius = R.TrevoRadius, Kind = "rodovia" })

	-- Rodoanel LK-100: por enquanto o trecho norte, dos dois lados do trevo
	local delta = math.deg((R.TrevoRadius + 4) / R.RingRadius)
	for _, side in ipairs({ -1, 1 }) do
		local pts = { trevo }
		local steps = math.ceil((R.RingArc - delta) / 4)
		for i = 0, steps do
			table.insert(pts, CityRoads.ringPoint(side * (delta + (R.RingArc - delta) * i / steps)))
		end
		road(R.RingName, "rodovia", pts, { Code = R.RingCode })
		soon(pts, R.RingName .. ": continua em breve")
	end

	-- Saídas da rodovia (cruzamento com retorno): Estrada do Vale (leste) e da Serra (oeste)
	local exit = Vector3.new(0, 0, R.ExitZ)
	local vale = road(R.ValeName, "estrada", { exit, exit + Vector3.new(R.ExitLength, 0, 0) })
	soon(vale.Points, R.ValeSoon)
	local serra = road(R.SerraName, "estrada", { exit, exit - Vector3.new(R.ExitLength, 0, 0) })
	soon(serra.Points, R.SerraSoon)

	for _, st in ipairs(CityRoads.FinancialDistrict.Streets) do
		road(st.Name, st.Kind or "rua", { st.A, st.B }, { FinancialDistrict = true })
	end

 for _,st in ipairs(CityRoads.FinancialExtension)do
  road(st.Name,"rua",{st.A,st.B},{FinancialExtension=true})
 end
 -- Une a pista a um vértice real da rodovia, sem um fim solto ao lado do asfalto.
 local join,best
 local target=CityRoads.ringPoint(30)
 for _,r in ipairs(roads)do
  if r.Code==R.RingCode then
   for _,p in ipairs(r.Points)do
    local distance=(p-target).Magnitude
    if p.X>1000 and (not best or distance<best)then join,best=p,distance end
   end
  end
 end
 if join then road("Acesso Financeiro ao Rodoanel","avenida",{Vector3.new(1900,0,-3220),Vector3.new(1900,0,-3450),join},{FinancialExtension=true})end

	-- Avenida do Progresso (rua 5, sul) e a rotatória com 3 estradas
	local rc = Vector3.new(0, 0, P.EndZ + P.RoundaboutRadius)
	road(P.Name, "avenida", { Vector3.new(0, 0, RADIAL_END), rc })
	table.insert(circles, { Name = P.RoundaboutName, Center = rc, Radius = P.RoundaboutRadius, Kind = "avenida" })
	for _, b in ipairs(P.Branches) do
		local r = road(b.Name, "estrada", { rc, rc + b.Dir * P.BranchLength })
		if b.Soon then
			soon(r.Points, b.Soon)
		end
	end

	-- Marco 10.31: Costa do Sol (litoral), no fim da Estrada Sul
	local LT = GameConfig.Litoral
	if LT then
		local entry = Vector3.new(0, 0, LT.EntryZ)
		table.insert(circles, { Name = LT.RoundaboutName, Center = entry, Radius = LT.RoundaboutRadius, Kind = "avenida" })
		road(LT.AvenueName, "boulevard", { entry, Vector3.new(0, 0, LT.BeiraMarZ) }, { Litoral = true })
		road(LT.BeiraMarName, "boulevard", { Vector3.new(-LT.BeiraMarHalf, 0, LT.BeiraMarZ), Vector3.new(LT.BeiraMarHalf, 0, LT.BeiraMarZ) }, { Litoral = true })
		road(LT.TownName, "rua", { Vector3.new(-LT.TownHalf, 0, LT.TownZ), Vector3.new(LT.TownHalf, 0, LT.TownZ) }, { Litoral = true })
		for _, st in ipairs(LT.CrossStreets) do
			road(st.Name, "rua", { Vector3.new(st.X, 0, LT.TownZ), Vector3.new(st.X, 0, LT.BeiraMarZ) }, { Litoral = true })
		end
		for _, side in ipairs({ -1, 1 }) do
			table.insert(circles, { Name = "Retorno da Orla", Center = Vector3.new(side * LT.BeiraMarHalf, 0, LT.BeiraMarZ), Radius = 34, Kind = "avenida" })
		end
	end

	-- Marco 10.4: ruas do Jardim Progresso (dos dois lados da Avenida do Progresso)
	for _, st in ipairs(P.District.Streets) do
		road(st.Name, "rua", { st.From, st.To })
	end

	-- Bairro Horizonte (depois do Trevo Norte)
	local D = CityRoads.District
	local at = CityRoads.districtPoint
	road(H.BoulevardName, "boulevard", { trevo, at(0, D.Loop.T0) })
	for i, name in ipairs(H.Streets) do
		local t = D.StreetT[i]
		road(name, "rua", { at(-D.Half, t), at(D.Half, t) })
	end
	road(H.WestName, "rua", { at(-D.Half, D.StreetT[1]), at(-D.Half, D.StreetT[3]) })
	road(H.EastName, "rua", { at(D.Half, D.StreetT[1]), at(D.Half, D.StreetT[3]) })
	-- duas estradas saem do bairro para os próximos bairros
	local west = road(H.Streets[1], "estrada", { at(-D.Half, D.StreetT[1]), at(-D.Half - 800, D.StreetT[1]) })
	soon(west.Points, "Novo bairro: em breve")
	local east = road(H.Streets[2], "estrada", { at(D.Half, D.StreetT[2]), at(D.Half + 800, D.StreetT[2]) })
	soon(east.Points, "Novo bairro: em breve")
	local L = D.Loop
	road(H.LoopName, "rua", { at(-L.X, L.T0), at(L.X, L.T0), at(L.X, L.T1), at(-L.X, L.T1), at(-L.X, L.T0) }, { Loop = true })

	-- Marco 10.1: estradas de acesso às 3 favelas (comunidades das gangues). Terminam na entrada
	-- de cada favela; as vielas de dentro são do FavelaBuilder (a pé, fora do GPS).
	local G = GameConfig.Gangs
	for _, id in ipairs(G.Order) do
		local g = G.List[id]
		road(g.Road.Name, "estrada", g.Road.Points, { Favela = id })
	end

	cache = { roads = roads, circles = circles, ends = ends, trevo = trevo }
	return cache
end

---------------------------------------------------------------------------
-- Cruzamentos: onde cada estrada encontra outra (para abrir a calçada e o canteiro, e para o GPS)
---------------------------------------------------------------------------

local function flat(v)
	return Vector2.new(v.X, v.Z)
end

-- Trechos de uma estrada com a distância acumulada (t0) desde o começo
function CityRoads.segments(r)
	local list, t = {}, 0
	for i = 1, #r.Points - 1 do
		local a, b = r.Points[i], r.Points[i + 1]
		local len = (b - a).Magnitude
		table.insert(list, { a = a, b = b, len = len, t0 = t, dir = (b - a).Unit })
		t += len
	end
	return list, t
end

local function crossing(a, b, c, d)
	local p, r = flat(a), flat(b) - flat(a)
	local q, s = flat(c), flat(d) - flat(c)
	local den = r.X * s.Y - r.Y * s.X
	if math.abs(den) < 1e-6 then
		return nil
	end
	local qp = q - p
	local u = (qp.X * s.Y - qp.Y * s.X) / den
	local v = (qp.X * r.Y - qp.Y * r.X) / den
	if u >= -1e-4 and u <= 1 + 1e-4 and v >= -1e-4 and v <= 1 + 1e-4 then
		return u, v
	end
	return nil
end

-- splits[i] = { { t, pos, width } } em ordem de t: lugares onde a estrada i encontra outra
-- (inclusive a cidade antiga, no começo das estradas que saem do anel externo)
function CityRoads.splits()
	local data = CityRoads.get()
	local roads = data.roads
	local out = {}
	local segs = {}
	for i, r in ipairs(roads) do
		out[i] = {}
		segs[i] = CityRoads.segments(r)
	end
	local function add(i, t, pos, width)
		for _, s in ipairs(out[i]) do
			if math.abs(s.t - t) < 2 then
				s.width = math.max(s.width, width)
				return
			end
		end
		table.insert(out[i], { t = t, pos = pos, width = width })
	end
	for i, ri in ipairs(roads) do
		for j, rj in ipairs(roads) do
			if i < j then
				for _, si in ipairs(segs[i]) do
					for _, sj in ipairs(segs[j]) do
						local u, v = crossing(si.a, si.b, sj.a, sj.b)
						if u then
							local pos = si.a + (si.b - si.a) * u
							add(i, si.t0 + si.len * u, pos, rj.Width)
							add(j, sj.t0 + sj.len * v, pos, ri.Width)
						end
					end
				end
			end
		end
		-- começa no anel externo da cidade antiga
		local first = ri.Points[1]
		if math.abs(first.Magnitude - RADIAL_END) < 1 then
			add(i, 0, first, M.RoadWidth)
		end
	end
	for i in ipairs(roads) do
		table.sort(out[i], function(a, b)
			return a.t < b.t
		end)
	end
	return out
end

return CityRoads
