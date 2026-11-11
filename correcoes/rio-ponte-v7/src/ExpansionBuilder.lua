-- ExpansionBuilder (ModuleScript)
-- Caminho: ServerScriptService > Services > ExpansionBuilder
-- Marco 10: monta as estradas da expansão da cidade a partir do CityRoads (Shared):
--   * Rodovia LK-101 (pista dupla com canteiro, mureta com tela verde, guard-rail, postes no meio,
--     faixas, placas em pórtico e marcos de km) da Avenida das Palmeiras até o Trevo Norte;
--   * Rodoanel LK-100: o trecho norte do anel que um dia vai dar a volta no mapa inteiro;
--   * saídas para áreas futuras (Estrada do Vale, da Serra; Avenida do Progresso e a rotatória
--     com as estradas Leste, Oeste e Sul), cada uma terminando numa barreira "em breve";
--   * as ruas do Bairro Horizonte (o HorizonteBuilder monta as construções);
--   * no campo: Posto Estrela, plantações, árvores e torres eólicas.
-- Duas etapas, como o HorizonteBuilder: plan() antes das casas da cidade (asfalto e áreas
-- ocupadas, sem sorteio) e build() no fim (enfeites, com sorteio próprio).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local CityRoads = require(Shared:WaitForChild("CityRoads"))

local RiverLayout = require(Shared:WaitForChild("RiverLayout"))
local ExpansionBuilder = {}

local M = GameConfig.Map
local R = GameConfig.Rodovia
local C = GameConfig.Colors

local CW = R.CarriageWidth
local MEDIAN = R.Median
local DASH_GAP, DASH_LEN = 30, 10 -- faixa tracejada da rodovia (mais espaçada que na cidade)

local CONCRETE = Color3.fromRGB(190, 188, 182)
local SCREEN = Color3.fromRGB(45, 125, 70) -- tela verde em cima da mureta (como na foto)
local RAIL = Color3.fromRGB(175, 180, 186)
local SIGN_GREEN = Color3.fromRGB(20, 105, 60)
local YELLOW = Color3.fromRGB(240, 200, 40)
local WHITE = Color3.fromRGB(246, 245, 241)
local DARK = Color3.fromRGB(45, 48, 54)
local GRASS = Color3.fromRGB(100, 165, 70)

local K -- ferramentas do MapBuilder
local rng = Random.new(GameConfig.Horizonte.Seed + 7)

local function P(parent, name, size, cf, color, material, extra)
	extra = extra or {}
	local part = K.makePart(parent, {
		Name = name,
		Size = size,
		CFrame = cf,
		Color = color,
		Material = material,
		Shape = extra.shape,
		Transparency = extra.transparency,
		CanCollide = extra.collide,
		CastShadow = extra.shadow,
	})
	return part
end

local function perpOf(d)
	return Vector3.new(-d.Z, 0, d.X)
end

-- Faixa comprida ao longo de a -> b (corta em pedaços: peça do Roblox tem no máximo 2048)
local function strip(parent, name, a, b, width, height, y, color, material, extra)
	local len = (b - a).Magnitude
	if len < 0.5 then
		return
	end
	local n = math.ceil(len / 1800)
	for i = 0, n - 1 do
		local p0 = a + (b - a) * (i / n)
		local p1 = a + (b - a) * ((i + 1) / n)
		local mid = (p0 + p1) / 2
		P(parent, name, Vector3.new(width, height, (p1 - p0).Magnitude), CFrame.lookAt(mid, p1) + Vector3.new(0, y, 0), color, material, extra)
	end
end

-- Pedaços de [t0, t1] que não caem em nenhuma faixa proibida (gaps = { {de, até} })
local function pieces(t0, t1, gaps)
	local out = { { t0, t1 } }
	for _, g in ipairs(gaps) do
		local nextOut = {}
		for _, p in ipairs(out) do
			if g[2] <= p[1] or g[1] >= p[2] then
				table.insert(nextOut, p)
			else
				if g[1] > p[1] then
					table.insert(nextOut, { p[1], g[1] })
				end
				if g[2] < p[2] then
					table.insert(nextOut, { g[2], p[2] })
				end
			end
		end
		out = nextOut
	end
	local clean = {}
	for _, p in ipairs(out) do
		if p[2] - p[1] > 1 then
			table.insert(clean, p)
		end
	end
	return clean
end

local function blocked(t, gaps)
	for _, g in ipairs(gaps) do
		if t > g[1] and t < g[2] then
			return true
		end
	end
	return false
end

---------------------------------------------------------------------------
-- Peças da beira da estrada
---------------------------------------------------------------------------

local function simpleTree(parent, pos, scale)
	local t = K.model("Arvore", parent)
	local h = 7 * scale
	P(t, "Tronco", Vector3.new(1.3, h, 1.3) * Vector3.new(scale, 1, scale), CFrame.new(pos + Vector3.new(0, h / 2, 0)), C.Trunk, Enum.Material.Wood)
	local leaf = C.Leaves[rng:NextInteger(1, #C.Leaves)]
	P(t, "Copa", Vector3.new(8, 8, 8) * scale, CFrame.new(pos + Vector3.new(0, h + 2.5 * scale, 0)), leaf, Enum.Material.Grass, { shape = Enum.PartType.Ball })
	return t
end

-- Poste duplo do canteiro da rodovia (braço para as duas pistas)
local function medianLamp(parent, pos, d, withLight)
	local lamp = K.model("PosteRodovia", parent)
	local n = perpOf(d)
	P(lamp, "Poste", Vector3.new(0.8, 18, 0.8), CFrame.new(pos + Vector3.new(0, 9.5, 0)), Color3.fromRGB(150, 155, 160), Enum.Material.Metal)
	for _, s in ipairs({ -1, 1 }) do
		local armMid = pos + n * s * 4 + Vector3.new(0, 18.2, 0)
		P(lamp, "Braco", Vector3.new(8, 0.4, 0.4), CFrame.lookAt(armMid, armMid + d) * CFrame.Angles(0, 0, 0), Color3.fromRGB(150, 155, 160), Enum.Material.Metal)
		local head = P(lamp, "Luz", Vector3.new(2.4, 0.5, 1.2), CFrame.lookAt(pos + n * s * 7.6 + Vector3.new(0, 17.9, 0), pos + n * s * 7.6 + Vector3.new(0, 17.9, 0) + d), Color3.fromRGB(255, 235, 190), Enum.Material.Neon, { collide = false })
		if withLight then
			local light = Instance.new("SpotLight")
			light.Face = Enum.NormalId.Bottom
			light.Range = 34
			light.Angle = 110
			light.Brightness = 1.2
			light.Color = Color3.fromRGB(255, 225, 175)
			light.Parent = head
		end
	end
end

-- Placa verde num pórtico sobre uma pista. pos = meio da pista; d = sentido do trânsito.
local function gantry(parent, pos, d, lines)
	local g = K.model("Portico", parent)
	local n = perpOf(d) -- para fora (o canteiro fica do lado -n)
	for _, lat in ipairs({ -(CW / 2 + 2), CW / 2 + 5 }) do
		local base = pos + n * lat
		P(g, "Coluna", Vector3.new(1.2, 22, 1.2), CFrame.new(base + Vector3.new(0, 11.4, 0)), Color3.fromRGB(150, 155, 160), Enum.Material.Metal)
	end
	local beamPos = pos + n * 1.5 + Vector3.new(0, 22.2, 0)
	P(g, "Viga", Vector3.new(CW + 9, 1, 1), CFrame.lookAt(beamPos, beamPos - d), Color3.fromRGB(150, 155, 160), Enum.Material.Metal, { collide = false })
	local face = CFrame.lookAt(pos + Vector3.new(0, 19, 0), pos + Vector3.new(0, 19, 0) - d) -- frente para quem vem
	P(g, "Borda", Vector3.new(CW - 1.4, 6.6, 0.25), face * CFrame.new(0, 0, 0.2), Color3.new(1, 1, 1), nil, { collide = false })
	local board = P(g, "Placa", Vector3.new(CW - 2, 6, 0.3), face, SIGN_GREEN, nil, { collide = false })
	K.addSurfaceText(board, lines, Color3.new(1, 1, 1), SIGN_GREEN)
end

local function postSign(parent, pos, facing, text, color, size)
	local s = K.model("Placa", parent)
	size = size or Vector3.new(3.4, 3.4, 0.2)
	P(s, "Poste", Vector3.new(0.3, 7, 0.3), CFrame.new(pos + Vector3.new(0, 3.5, 0)), Color3.fromRGB(120, 125, 130), Enum.Material.Metal)
	local board = P(s, "Placa", size, CFrame.lookAt(pos + Vector3.new(0, 6.6, 0), pos + Vector3.new(0, 6.6, 0) + facing), color, nil, { collide = false })
	return board
end

-- Barreira "em breve" no fim de uma estrada (Pos = fim, Dir = sentido de quem chega)
local function roadEnd(parent, e, width)
	local f = K.model("FimProvisorio", parent)
	local n = perpOf(e.Dir)
	local count = math.floor(width / 4)
	for i = 0, count - 1 do
		local x = -width / 2 + 2 + i * 4
		local p = e.Pos + n * x
		P(f, "Barreira", Vector3.new(3.8, 2.6, 1.4), CFrame.lookAt(p + Vector3.new(0, 1.8, 0), p + Vector3.new(0, 1.8, 0) + e.Dir), (i % 2 == 0) and Color3.fromRGB(230, 70, 50) or WHITE, Enum.Material.Concrete)
	end
	for _, x in ipairs({ -width / 4, width / 4 }) do
		local p = e.Pos - e.Dir * 14 + n * x
		P(f, "Cone", Vector3.new(1, 1.8, 1), CFrame.new(p + Vector3.new(0, 1.4, 0)), Color3.fromRGB(240, 120, 30))
	end
	local signPos = e.Pos + e.Dir * 6
	local cf = CFrame.lookAt(signPos + Vector3.new(0, 7, 0), signPos + Vector3.new(0, 7, 0) - e.Dir)
	for _, x in ipairs({ -7, 7 }) do
		P(f, "Poste", Vector3.new(0.6, 10, 0.6), cf * CFrame.new(x, -2, 0.3), Color3.fromRGB(70, 70, 75), Enum.Material.Metal)
	end
	local board = P(f, "Placa", Vector3.new(16, 5, 0.4), cf, Color3.fromRGB(240, 150, 30), nil, { collide = false })
	K.addSurfaceText(board, e.Text, Color3.fromRGB(30, 30, 30), Color3.fromRGB(240, 150, 30))
	K.occupy(K.rect(CFrame.lookAt(e.Pos + e.Dir * 10, e.Pos + e.Dir * 20), width + 12, 24))
end

---------------------------------------------------------------------------
-- Uma estrada inteira (asfalto, canteiro, faixas, calçadas, guard-rail e postes)
---------------------------------------------------------------------------

local function roadGaps(r, splitList, circles)
	local gaps = {}
	for _, s in ipairs(splitList) do
		local m = s.width / 2 + M.SidewalkWidth + 6
		table.insert(gaps, { s.t - m, s.t + m })
	end
	local _, total = CityRoads.segments(r)
	for _, c in ipairs(circles) do
		if (r.Points[1] - c.Center).Magnitude < 1 then
			table.insert(gaps, { -1, c.Radius + 8 })
		end
		if (r.Points[#r.Points] - c.Center).Magnitude < 1 then
			table.insert(gaps, { total - c.Radius - 8, total + 1 })
		end
	end
	return gaps, total
end

-- railGaps = vãos só no guard-rail do lado +1 (entrada do posto)
local function buildRoad(parent, props, r, splitList, circles, railGaps)
    if r.CustomBuild == "RiverBridge" then
        local segs, total = CityRoads.segments(r)
        for _, s in ipairs(segs) do
            K.occupy(K.rect(CFrame.lookAt((s.a+s.b)/2, s.b), 76, s.len+24))
        end
        return nil, total
    end
	local kind = CityRoads.Kinds[r.Kind]
	local f = K.folder(r.Name, parent)
	local segs = CityRoads.segments(r)
	local gaps, total = roadGaps(r, splitList, circles)
	local W = r.Width
	local lift = (r.Kind == "rodovia" or r.Kind == "boulevard") and 0.02 or 0.035
	local roadY = K.ROAD_TOP - 0.5 + lift
	local divided = r.Kind == "rodovia" or r.Kind == "boulevard"
	local median = r.Kind == "rodovia" and MEDIAN or (kind.Median or 0)
	local laneW = divided and (W - median) / 2 or W
	local lampEvery = r.Kind == "rodovia" and 180 or (r.Kind == "boulevard" and 60 or (r.Kind == "estrada" and 220 or 70))
	local nextLamp, lampCount = lampEvery / 2, 0
	local nextDash = 10
	local nextKm = 1000

	for i, s in ipairs(segs) do
		local d, n = s.dir, perpOf(s.dir)
		-- emenda com o trecho seguinte/anterior (curvas): estica um pouco o asfalto
		local extA, extB = 0, 0
		if segs[i - 1] then
			local ang = math.acos(math.clamp(segs[i - 1].dir:Dot(d), -1, 1))
			extA = W / 2 * math.tan(ang / 2) + 1
		end
		if segs[i + 1] then
			local ang = math.acos(math.clamp(segs[i + 1].dir:Dot(d), -1, 1))
			extB = W / 2 * math.tan(ang / 2) + 1
		end
		strip(f, "Asphalt", s.a - d * extA, s.b + d * extB, W, 1, roadY, C.Asphalt, Enum.Material.Asphalt)
		local margin = kind.Sidewalk and M.SidewalkWidth or (kind.Verge or 0)
		K.occupy(K.rect(CFrame.lookAt((s.a + s.b) / 2, s.b), W + 2 * margin + 1, s.len + M.RoadWidth))

		local function at(t, lateral)
			return s.a + d * (t - s.t0) + n * lateral
		end
		local free = pieces(s.t0, s.t0 + s.len, gaps)
		for _, p in ipairs(free) do
			local t0, t1 = p[1], p[2]
			-- nas curvas, estica até a emenda (senão abre uma fresta do lado de fora)
			if t0 <= s.t0 + 0.01 then
				t0 -= extA
			end
			if t1 >= s.t0 + s.len - 0.01 then
				t1 += extB
			end
			if divided then
				-- canteiro do meio
				strip(f, "Canteiro", at(t0, 0), at(t1, 0), median - 1, 0.6, K.ROAD_TOP + 0.05, GRASS, Enum.Material.Grass)
				if r.Kind == "rodovia" then
					strip(f, "Mureta", at(t0, 0), at(t1, 0), 1.2, 2.4, K.ROAD_TOP + 1.4, CONCRETE, Enum.Material.Concrete)
					strip(f, "Tela", at(t0, 0), at(t1, 0), 0.2, 1.8, K.ROAD_TOP + 3.5, SCREEN, Enum.Material.DiamondPlate, { collide = false, transparency = 0.15 })
				end
				-- faixas: amarela junto do canteiro, branca na beira, tracejada entre as 2 faixas
				for _, side in ipairs({ -1, 1 }) do
					local inner = side * (median / 2 + 0.6)
					local outer = side * (W / 2 - 1.2)
					strip(f, "LinhaAmarela", at(t0, inner), at(t1, inner), 0.4, 0.1, K.ROAD_TOP + lift + 0.06, YELLOW, nil, { collide = false, shadow = false })
					strip(f, "LinhaBorda", at(t0, outer), at(t1, outer), 0.4, 0.1, K.ROAD_TOP + lift + 0.06, C.RoadLine, nil, { collide = false, shadow = false })
				end
			elseif r.Kind == "estrada" then
				for _, side in ipairs({ -1, 1 }) do
					local outer = side * (W / 2 - 0.8)
					strip(f, "LinhaBorda", at(t0, outer), at(t1, outer), 0.35, 0.1, K.ROAD_TOP + lift + 0.06, C.RoadLine, nil, { collide = false, shadow = false })
				end
			end
			-- calçadas (cidade) ou guard-rail (rodovia)
			if kind.Sidewalk then
				for _, side in ipairs({ -1, 1 }) do
					local lat = side * (W / 2 + M.SidewalkWidth / 2)
					strip(f, "Sidewalk", at(t0, lat), at(t1, lat), M.SidewalkWidth, 1, K.SIDEWALK_TOP - 0.5, C.Sidewalk, Enum.Material.Concrete)
				end
			elseif r.Kind == "rodovia" then
				for _, side in ipairs({ -1, 1 }) do
					local lat = side * (W / 2 + 2)
					for _, q in ipairs(side == 1 and pieces(t0, t1, railGaps or {}) or { { t0, t1 } }) do
						strip(f, "GuardRail", at(q[1], lat), at(q[2], lat), 0.35, 1, K.ROAD_TOP + 2.3, RAIL, Enum.Material.Metal)
						strip(f, "GuardRailPostes", at(q[1], lat + side * 0.3), at(q[2], lat + side * 0.3), 0.25, 2, K.ROAD_TOP + 1, Color3.fromRGB(120, 125, 130), Enum.Material.Metal, { collide = false })
					end
				end
			end
		end

		-- tracejado no meio de cada pista (ou no meio da rua)
		local lanes = divided and { -(median / 2 + laneW / 2), median / 2 + laneW / 2 } or { 0 }
		local gap = r.Kind == "rodovia" and DASH_GAP or 14
		local len = r.Kind == "rodovia" and DASH_LEN or 6
		while nextDash < s.t0 + s.len do
			if not blocked(nextDash, gaps) then
				for _, lat in ipairs(lanes) do
					local p = at(nextDash, lat)
					P(f, "Line", Vector3.new(0.6, 0.1, len), CFrame.lookAt(p, p + d) + Vector3.new(0, K.ROAD_TOP + lift + 0.08, 0), C.RoadLine, nil, { collide = false, shadow = false })
				end
			end
			nextDash += gap
		end

		-- postes
		while nextLamp < s.t0 + s.len do
			if not blocked(nextLamp, gaps) then
				lampCount += 1
				if divided and r.Kind == "rodovia" then
					medianLamp(props, at(nextLamp, 0) + Vector3.new(0, K.ROAD_TOP, 0), d, lampCount % 2 == 0)
				elseif divided then
					-- boulevard: poste e palmeira alternados no canteiro
					if lampCount % 2 == 0 then
						K.buildLamp(props, CFrame.lookAt(at(nextLamp, 0), at(nextLamp, 0) + d) + Vector3.new(0, K.ROAD_TOP - K.SIDEWALK_TOP + 0.6, 0))
					else
						K.palm(f, at(nextLamp, 0) + Vector3.new(0, K.ROAD_TOP + 0.6, 0), 1.05)
					end
				else
					local side = (lampCount % 2 == 0) and 1 or -1
					local lat = side * (W / 2 + (kind.Sidewalk and M.SidewalkWidth / 2 + 1 or 2.5))
					local p = at(nextLamp, lat)
					K.buildLamp(props, CFrame.lookAt(p, p - n * side) + Vector3.new(0, kind.Sidewalk and 0 or -K.SIDEWALK_TOP, 0))
				end
			end
			nextLamp += lampEvery
		end

		-- marco de km (rodovia), na beira direita de quem vai
		if r.Kind == "rodovia" then
			while nextKm < s.t0 + s.len do
				if not blocked(nextKm, gaps) then
					local p = at(nextKm, W / 2 + 4)
					local board = postSign(props, p, -d, "", Color3.fromRGB(20, 105, 60), Vector3.new(2.6, 3.2, 0.2))
					K.addSurfaceText(board, ("%s\nkm %d"):format(r.Code or "", nextKm / 1000), Color3.new(1, 1, 1), SIGN_GREEN)
				end
				nextKm += 1000
			end
		end
	end
	return f, total
end

local function buildRoundabout(parent, c, roads)
	local f = K.model(c.Name, parent)
	local disc = K.flatCylinder(f, "Asfalto", c.Center + Vector3.new(0, K.ROAD_TOP - 0.5 + 0.05, 0), c.Radius, 1, C.Asphalt, Enum.Material.Asphalt)
	disc.CastShadow = false
	local islandR = c.Radius * 0.45
	K.flatCylinder(f, "Meio-fio", c.Center + Vector3.new(0, K.ROAD_TOP + 0.3, 0), islandR + 0.6, 0.6, WHITE, Enum.Material.Concrete)
	K.flatCylinder(f, "Ilha", c.Center + Vector3.new(0, K.ROAD_TOP + 0.4, 0), islandR, 0.7, GRASS, Enum.Material.Grass)
	local top = c.Center + Vector3.new(0, K.ROAD_TOP + 0.75, 0)
	if c.Kind == "rodovia" then
		-- monumento do Trevo Norte: 3 lâminas com luz e o nome
		for i = 0, 2 do
			local a = i * 2 * math.pi / 3
			local p = top + Vector3.new(math.cos(a) * 5, 0, math.sin(a) * 5)
			P(f, "Lamina", Vector3.new(2, 26 + i * 4, 6), CFrame.lookAt(p + Vector3.new(0, 13 + i * 2, 0), top + Vector3.new(0, 13 + i * 2, 0)), WHITE, Enum.Material.Marble)
			P(f, "LaminaLuz", Vector3.new(2.1, 26 + i * 4, 0.4), CFrame.lookAt(p + Vector3.new(0, 13 + i * 2, 0), top + Vector3.new(0, 13 + i * 2, 0)) * CFrame.new(0, 0, 3.1), Color3.fromRGB(255, 190, 110), Enum.Material.Neon, { collide = false })
		end
		for k = 0, 7 do
			local a = k * math.pi / 4
			K.palm(f, top + Vector3.new(math.cos(a) * islandR * 0.75, 0, math.sin(a) * islandR * 0.75), 1.1)
		end
	else
		for k = 0, 4 do
			local a = k * 2 * math.pi / 5
			K.palm(f, top + Vector3.new(math.cos(a) * islandR * 0.6, 0, math.sin(a) * islandR * 0.6), 1)
		end
	end
	-- placas de "dê a preferência" em cada estrada que chega
	for _, r in ipairs(roads) do
		local first, last = r.Points[1], r.Points[#r.Points]
		local from
		if (first - c.Center).Magnitude < 1 then
			from = r.Points[2]
		elseif (last - c.Center).Magnitude < 1 then
			from = r.Points[#r.Points - 1]
		end
		if from then
			local d = (c.Center - from).Unit
			local n = perpOf(d)
			local entryWidth = r.CustomBuild == "RiverBridge" and RiverLayout.roadWidth(c.Center.X) or r.Width
			local p = c.Center - d * (c.Radius + 10) + n * (entryWidth / 2 + 3)
			local board = postSign(parent, p, -d, "", WHITE, Vector3.new(3.2, 3.2, 0.2))
			K.addSurfaceText(board, "PARE", Color3.fromRGB(200, 30, 30), WHITE)
		end
	end
	K.occupy(K.rect(CFrame.new(c.Center), c.Radius * 2 + 12, c.Radius * 2 + 12))
end

---------------------------------------------------------------------------
-- Posto Estrela (enfeite na beira da rodovia, lado leste)
---------------------------------------------------------------------------

local POSTO_W, POSTO_D = 130, 80

local function postoLot()
	local half = CityRoads.Kinds.rodovia.Width / 2 + CityRoads.Kinds.rodovia.Verge + 1
	local center = Vector3.new(half + POSTO_D / 2, 0, R.PostoZ)
	return CFrame.lookAt(center, center - Vector3.new(1, 0, 0)) -- frente (-Z) virada para a rodovia
end

local function buildPosto(parent, lot)
	local f = K.model("PostoEstrela", parent)
	local red = Color3.fromRGB(200, 40, 45)
	local function at(x, y, z)
		return lot * CFrame.new(x, y, z)
	end
	P(f, "Piso", Vector3.new(POSTO_W, 0.4, POSTO_D + 8), at(0, 0.5, -4), Color3.fromRGB(150, 150, 152), Enum.Material.Concrete)
	-- cobertura das bombas
	P(f, "Cobertura", Vector3.new(56, 2, 30), at(-10, 14, -10), WHITE)
	P(f, "CoberturaFaixa", Vector3.new(56.4, 1.2, 30.4), at(-10, 13.2, -10), red, Enum.Material.Neon, { collide = false })
	for _, x in ipairs({ -32, -10, 12 }) do
		for _, z in ipairs({ -20, 0 }) do
			P(f, "Pilar", Vector3.new(1.4, 13, 1.4), at(x, 7, z), WHITE)
		end
	end
	for _, x in ipairs({ -26, -4 }) do
		for _, z in ipairs({ -14, -6 }) do
			P(f, "Ilha", Vector3.new(10, 0.6, 2.6), at(x + 5, 1, z), CONCRETE, Enum.Material.Concrete)
			local pump = P(f, "Bomba", Vector3.new(2, 5, 1.6), at(x + 5, 3.8, z), WHITE)
			P(f, "BombaVisor", Vector3.new(1.4, 1, 0.1), pump.CFrame * CFrame.new(0, 1, -0.85), Color3.fromRGB(20, 30, 40), nil, { collide = false })
			P(f, "BombaFaixa", Vector3.new(2.05, 0.6, 1.65), pump.CFrame * CFrame.new(0, -1.6, 0), red, nil, { collide = false })
		end
	end
	for _, x in ipairs({ -30, -10, 10 }) do
		local lamp = P(f, "LuzCobertura", Vector3.new(6, 0.2, 2), at(x, 12.9, -10), Color3.fromRGB(255, 250, 235), Enum.Material.Neon, { collide = false })
		if x == -10 then
			local light = Instance.new("PointLight")
			light.Range = 30
			light.Brightness = 0.8
			light.Parent = lamp
		end
	end
	-- loja de conveniência
	P(f, "Loja", Vector3.new(40, 11, 22), at(36, 6.2, 22), WHITE)
	P(f, "LojaVidro", Vector3.new(30, 7, 0.3), at(36, 4.6, 10.9), Color3.fromRGB(150, 195, 220), nil, { transparency = 0.35 })
	P(f, "LojaTeto", Vector3.new(42, 0.8, 24), at(36, 12.1, 22), red)
	local signLoja = P(f, "LojaPlaca", Vector3.new(26, 2.4, 0.3), at(36, 9.6, 10.8), red, nil, { collide = false })
	K.addSurfaceText(signLoja, "Conveniência Estrela", Color3.new(1, 1, 1), red)
	-- vagas e totem de preços
	for k = 0, 4 do
		P(f, "Vaga", Vector3.new(0.4, 0.1, 14), at(20 + k * 7, 0.75, -2), WHITE, nil, { collide = false, shadow = false })
	end
	P(f, "Totem", Vector3.new(6, 26, 1.6), at(-56, 13, -36), red)
	local logo = P(f, "TotemNome", Vector3.new(5.4, 4, 0.2), at(-56, 22, -36.9), red, nil, { collide = false })
	K.addSurfaceText(logo, "★ " .. R.PostoName, Color3.new(1, 1, 1), red)
	local prices = P(f, "TotemPrecos", Vector3.new(5.4, 8, 0.2), at(-56, 12, -36.9), DARK, nil, { collide = false })
	K.addSurfaceText(prices, "Gasolina\n5,49\nEtanol\n3,79", YELLOW, DARK)
	f:SetAttribute("PlaceName", R.PostoName)
	return f
end

---------------------------------------------------------------------------
-- Campo: plantações, árvores e torres eólicas (ocupam só onde estiver livre)
---------------------------------------------------------------------------

local CROPS = {
	{ Color3.fromRGB(130, 170, 60), Color3.fromRGB(105, 145, 50) }, -- soja
	{ Color3.fromRGB(205, 180, 90), Color3.fromRGB(180, 155, 70) }, -- trigo
	{ Color3.fromRGB(150, 110, 70), Color3.fromRGB(120, 90, 60) }, -- terra arada
	{ Color3.fromRGB(95, 160, 70), Color3.fromRGB(80, 140, 60) }, -- milho novo
}

local function field(parent, cf, w, d)
	local f = K.model("Plantacao", parent)
	local crop = CROPS[rng:NextInteger(1, #CROPS)]
	P(f, "Terra", Vector3.new(w, 0.3, d), cf * CFrame.new(0, 0.15, 0), crop[1], Enum.Material.Grass)
	local rows = math.floor(w / 14)
	for i = 1, rows do
		P(f, "Fileira", Vector3.new(4, 0.35, d - 6), cf * CFrame.new(-w / 2 + i * w / (rows + 1), 0.2, 0), crop[2], Enum.Material.Grass, { collide = false, shadow = false })
	end
end

local function windTurbine(parent, pos)
	local f = K.model("Eolica", parent)
	P(f, "Torre", Vector3.new(4, 90, 4), CFrame.new(pos + Vector3.new(0, 45, 0)), WHITE, Enum.Material.SmoothPlastic)
	local hub = pos + Vector3.new(0, 91, 0)
	P(f, "Nacele", Vector3.new(5, 5, 10), CFrame.new(hub), WHITE)
	local turn = rng:NextNumber(0, math.pi)
	for k = 0, 2 do
		local a = turn + k * 2 * math.pi / 3
		P(f, "Pa", Vector3.new(2.4, 40, 0.6), CFrame.new(hub + Vector3.new(0, 0, -5.4)) * CFrame.Angles(0, 0, a) * CFrame.new(0, 20, 0), WHITE, nil, { collide = false })
	end
end

local function countryside(parent, data)
	-- plantações alinhadas com as estradas (fazendas na beira da rodovia e das estradas)
	local placed = 0
	local city = CityRoads.RADIAL_END + 300
	local roads = {}
	for _, r in ipairs(data.roads) do
		if r.Kind == "rodovia" or r.Kind == "estrada" then
			table.insert(roads, r)
		end
	end
	for _ = 1, 1200 do
		if placed >= 80 then
			break
		end
		local r = roads[rng:NextInteger(1, #roads)]
		local segs, total = CityRoads.segments(r)
		local t = rng:NextNumber(0, total)
		local s = segs[#segs]
		for _, seg in ipairs(segs) do
			if t <= seg.t0 + seg.len then
				s = seg
				break
			end
		end
		local side = rng:NextInteger(0, 1) == 0 and -1 or 1
		local w, d = rng:NextNumber(150, 300), rng:NextNumber(110, 220)
		local off = r.Width / 2 + 30 + d / 2 + rng:NextNumber(0, 1) ^ 2 * 700
		local p = s.a + s.dir * (t - s.t0) + perpOf(s.dir) * side * off
		if p.Magnitude > city then
			local cf = CFrame.lookAt(p, p + s.dir) * CFrame.Angles(0, math.pi / 2, 0) -- lado comprido ao longo da estrada
			local area = K.rect(cf, w + 30, d + 30)
			if K.isFree(area) then
				K.occupy(area)
				field(parent, cf, w, d)
				-- fileira de árvores no fundo (longe da estrada)
				for x = -w / 2, w / 2, 22 do
					local tp = (cf * CFrame.new(x, 0, d / 2 + 10)).Position
					if (tp - p):Dot(perpOf(s.dir) * side) > 0 then
						simpleTree(parent, tp, rng:NextNumber(0.9, 1.3))
					else
						simpleTree(parent, (cf * CFrame.new(x, 0, -d / 2 - 10)).Position, rng:NextNumber(0.9, 1.3))
					end
				end
				placed += 1
			end
		end
	end
	-- torres eólicas num morro a oeste da rodovia
	for i = 0, 5 do
		local p = Vector3.new(-1700 - (i % 2) * 140, 0, -2000 - i * 220)
		local area = K.rect(CFrame.new(p), 50, 50)
		if K.isFree(area) then
			K.occupy(area)
			windTurbine(parent, p)
		end
	end
end

---------------------------------------------------------------------------
-- Etapas
---------------------------------------------------------------------------

-- Etapa 1 (antes das casas da cidade): asfalto de todas as estradas e áreas ocupadas.
-- helpers = ferramentas do MapBuilder (+ palm, do HorizonteBuilder)
function ExpansionBuilder.plan(map, props, helpers)
	K = helpers
	local data = CityRoads.get()
	local splits = CityRoads.splits()
	local root = K.folder("Expansao", map)
	local roadsFolder = K.folder("Estradas", root)
	local plan = { root = root, data = data, splits = splits, lengths = {} }
	-- o posto abre um vão no guard-rail da rodovia (lado leste, pista de quem vai para o norte)
	for i, r in ipairs(data.roads) do
		local extra = nil
		if i == 1 then
			local tPosto = math.abs(R.PostoZ) - CityRoads.RADIAL_END
			extra = { { tPosto - POSTO_W / 2 + 6, tPosto + POSTO_W / 2 - 6 } }
		end
		local ok, err = pcall(function()
			local _, total = buildRoad(roadsFolder, props, r, splits[i], data.circles, extra)
			plan.lengths[i] = total
		end)
		if not ok then
			warn(("[Expansao] Erro ao montar %s: %s"):format(r.Name, tostring(err)))
		end
	end
	for _, c in ipairs(data.circles) do
		local ok, err = pcall(buildRoundabout, roadsFolder, c, data.roads)
		if not ok then
			warn(("[Expansao] Erro ao montar %s: %s"):format(c.Name, tostring(err)))
		end
	end
	for _, e in ipairs(data.ends) do
		local width = CityRoads.Kinds.estrada.Width
		for _, r in ipairs(data.roads) do
			if (r.Points[#r.Points] - e.Pos).Magnitude < 1 then
				width = r.Width
			end
		end
		roadEnd(roadsFolder, e, width)
	end
	-- lote do posto
	local lot = postoLot()
	local area = K.rect(lot, POSTO_W, POSTO_D)
	if K.isFree(area) then
		K.occupy(area)
		plan.posto = lot
	else
		warn("[Expansao] Sem espaço livre para o posto")
	end
	return plan
end

-- Etapa 2 (depois das casas da cidade): placas, posto e o campo
function ExpansionBuilder.build(plan)
	local root = plan.root
	local signs = K.folder("Placas", root)
	local north, south = Vector3.new(0, 0, -1), Vector3.new(0, 0, 1)
	local laneOffset = MEDIAN / 2 + CW / 2
	local startZ = -CityRoads.RADIAL_END
	local trevoZ = -R.RingRadius
	local km = (R.RingRadius - CityRoads.RADIAL_END) / 1000
	local function northbound(z)
		return Vector3.new(laneOffset, 0, z) -- pista da direita de quem vai para o norte (+X)
	end
	local function southbound(z)
		return Vector3.new(-laneOffset, 0, z)
	end
	gantry(signs, northbound(startZ - 150), north, (("%s  ↑ Bairro Horizonte %.1f km\nVale · Serra 500 m"):format(R.Code, km):gsub("%.", ",")))
	gantry(signs, northbound(R.ExitZ + 90), north, ("→ %s    ← %s"):format(R.ValeName, R.SerraName))
	gantry(signs, northbound(R.PostoZ + 300), north, ("⛽ %s 300 m"):format(R.PostoName))
	gantry(signs, northbound(trevoZ + 420), north, ("%s: ↑ %s   ← → %s"):format(R.TrevoName, GameConfig.Horizonte.Name, R.RingName))
	gantry(signs, southbound(trevoZ + 250), south, (("%s  ↓ Centro %.1f km"):format(R.Code, km):gsub("%.", ",")))
	gantry(signs, southbound(R.ExitZ - 90), south, ("← %s    → %s"):format(R.ValeName, R.SerraName))
	-- limite de velocidade no começo
	local speed = postSign(signs, northbound(startZ - 80) + Vector3.new(CW / 2 + 6, 0, 0), south, "", WHITE, Vector3.new(3.4, 3.4, 0.2))
	K.addSurfaceText(speed, "80", Color3.fromRGB(20, 20, 20), WHITE)
	if plan.posto then
		local ok, err = pcall(buildPosto, root, plan.posto)
		if not ok then
			warn("[Expansao] Erro ao montar o posto: " .. tostring(err))
		end
	end
	local ok, err = pcall(countryside, K.folder("Campo", root), plan.data)
	if not ok then
		warn("[Expansao] Erro ao montar o campo: " .. tostring(err))
	end
end

return ExpansionBuilder
