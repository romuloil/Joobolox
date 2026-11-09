-- HorizonteBuilder (ModuleScript)
-- Caminho: ServerScriptService > Services > HorizonteBuilder
-- Marco 10: Bairro Horizonte, o bairro de luxo depois da Rodovia LK-101 (Trevo Norte, ~4 km ao
-- norte da cidade). As ruas vêm do CityRoads e o asfalto é do ExpansionBuilder; aqui ficam as
-- construções, em duas etapas (chamadas pelo MapBuilder):
--   1. plan(): ANTES de encher as ruas da cidade de casas. Só reserva os lotes (sem sorteio).
--   2. build(): no fim, DEPOIS das casas. Monta tudo nos lotes reservados. Assim o número das
--      casas antigas (HouseNumber) não muda. O bairro tem sorteio próprio (Horizonte.Seed).
--
-- O que tem:
--   * Boulevard do Horizonte (pista dupla com palmeiras): portal de entrada e 12 prédios. Térreo =
--     saguão com ELEVADORES: cada elevador é a "porta" de um apartamento (tier "apartamento") e o
--     da lateral é o da cobertura ("cobertura"). Elevadores em Map.Houses, prédio em Map.Buildings;
--   * Ruas das Orquídeas, Magnólias e Hortênsias: casas modernas (tier "casamoderna"), Praça do
--     Horizonte, bosque, o lote "em breve" do shopping e a joalheria (Marco 10.8, no lote "novidade");
--   * condomínio Jardins do Horizonte: portaria no boulevard, Alameda dos Jardins em volta do
--     Parque dos Jardins (lago, clube, quadra) e 13 mansões (tier "mansao") do lado de fora.
-- Todas as casas do bairro têm o atributo Remote (entregas e incêndios ficam só na cidade).
-- Coordenadas de cada lote: (0, 0, 0) = centro; -Z = frente (virada para a rua).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local CityRoads = require(Shared:WaitForChild("CityRoads"))
local MoradiaBuilder = require(script.Parent:WaitForChild("MoradiaBuilder"))
local JewelryBuilder = require(script.Parent:WaitForChild("JewelryBuilder")) -- Marco 10.8: joalheria no lote "novidade"

local HorizonteBuilder = {}

local H = GameConfig.Horizonte
local M = GameConfig.Map

local TOWER_W, TOWER_D = 64, 66 -- lote do prédio
-- Marco 10.2: prédio mais largo e andar mais alto (o apartamento é um andar inteiro de verdade)
local BODY_W, BODY_D = 58, 50 -- corpo do prédio
local LOBBY_H = 14 -- pé-direito do saguão
local FLOOR_H = 10
local PENTHOUSE_H = 13.6 -- andar da cobertura (laje + pé-direito)
local MANSION_W, MANSION_D = MoradiaBuilder.MANSION_W, MoradiaBuilder.MANSION_D
local MODERN_W, MODERN_D = 56, 60 -- casa moderna
local GUARD_W, GUARD_D = 14, 16
local D = CityRoads.District
local STREET_HALF = M.RoadWidth / 2 + M.SidewalkWidth -- rua: asfalto + calçada (de cada lado)
local BOULEVARD_HALF = CityRoads.Kinds.boulevard.Width / 2 + M.SidewalkWidth
local G = 0.7 -- altura do piso dos lotes

local WHITE = Color3.fromRGB(246, 245, 241)
local STONE = Color3.fromRGB(150, 146, 140)
local DARK = Color3.fromRGB(45, 48, 54)
local GLASS_DARK = Color3.fromRGB(45, 60, 78)
local LOBBY_GLASS = Color3.fromRGB(170, 205, 225)
local PAVING = Color3.fromRGB(214, 208, 198)
local LAWN = Color3.fromRGB(112, 178, 82)
local WATER = Color3.fromRGB(70, 175, 230)
local NEON_WARM = Color3.fromRGB(255, 240, 215)
local GOLD = Color3.fromRGB(215, 175, 80)
local WOODS = { Color3.fromRGB(150, 100, 60), Color3.fromRGB(120, 80, 50), Color3.fromRGB(175, 130, 85) }
local MANSION_WALLS = { Color3.fromRGB(246, 245, 241), Color3.fromRGB(236, 226, 208), Color3.fromRGB(214, 216, 218) }
local BALL = Enum.PartType.Ball

local K -- ferramentas do MapBuilder (ver MapBuilder.build)
local rng = Random.new(H.Seed)

-- Peça simples. extra: shape, transparency, reflectance, collide
local function P(parent, name, size, cf, color, material, extra)
	extra = extra or {}
	return K.makePart(parent, {
		Name = name,
		Size = size,
		CFrame = cf,
		Color = color,
		Material = material,
		Shape = extra.shape,
		Transparency = extra.transparency,
		Reflectance = extra.reflectance,
		CanCollide = extra.collide,
	})
end

local function glow(part, range, brightness, color)
	local light = Instance.new("PointLight")
	light.Range = range
	light.Brightness = brightness
	light.Color = color or Color3.fromRGB(255, 235, 200)
	light.Parent = part
end

-- Palmeira (tronco em gomos levemente inclinado e 7 folhas caídas)
local function palm(parent, pos, scale)
	scale = scale or 1
	local tree = K.model("Palmeira", parent)
	local h = 14 * scale
	local lean = rng:NextNumber(-0.12, 0.12)
	local segs = 4
	for i = 0, segs - 1 do
		local y = h * (i + 0.5) / segs
		local thick = (1.1 - i * 0.08) * scale
		P(tree, "Trunk", Vector3.new(thick, h / segs + 0.3, thick), CFrame.new(pos + Vector3.new(lean * y, y, 0)) * CFrame.Angles(0, 0, -lean), Color3.fromRGB(150, 115, 75), Enum.Material.Wood)
	end
	local top = pos + Vector3.new(lean * h, h, 0)
	P(tree, "Coco", Vector3.new(1.4, 1.4, 1.4) * scale, CFrame.new(top), Color3.fromRGB(110, 85, 50), Enum.Material.Wood, { shape = BALL, collide = false })
	local turn = rng:NextNumber(0, math.pi)
	for k = 0, 6 do
		local a = turn + k * math.pi * 2 / 7
		local frond = CFrame.new(top) * CFrame.Angles(0, a, 0) * CFrame.Angles(math.rad(-25), 0, 0) * CFrame.new(0, 0, -3.2 * scale)
		P(tree, "Folha", Vector3.new(1.6 * scale, 0.2, 6.5 * scale), frond, Color3.fromRGB(60, 150 + (k % 2) * 15, 60), Enum.Material.Grass, { collide = false })
	end
	return tree
end

local function bench(parent, cf)
	P(parent, "Banco", Vector3.new(5, 0.4, 1.6), cf * CFrame.new(0, 1.6, 0), Color3.fromRGB(150, 105, 65), Enum.Material.WoodPlanks)
	P(parent, "Encosto", Vector3.new(5, 1.4, 0.3), cf * CFrame.new(0, 2.5, 0.7), Color3.fromRGB(150, 105, 65), Enum.Material.WoodPlanks)
	for _, x in ipairs({ -2, 2 }) do
		P(parent, "Pe", Vector3.new(0.4, 1.4, 1.4), cf * CFrame.new(x, 0.7 + 0.1, 0), DARK, Enum.Material.Metal)
	end
end

---------------------------------------------------------------------------
-- Prédio: saguão com elevadores (apartamentos e cobertura), torre e terraço
---------------------------------------------------------------------------

local function unitDoor(parent, doorCf, info)
	local id = K.nextHouseId()
	local unit = K.model("Casa " .. id, parent)
	P(unit, "DoorFrame", Vector3.new(5.6, 8.8, 0.3), doorCf * CFrame.new(0, 0.4, 0.15), info.gold and GOLD or DARK, Enum.Material.Metal)
	P(unit, "Door", Vector3.new(4, 7.6, 0.4), doorCf, Color3.fromRGB(190, 195, 200), Enum.Material.Metal)
	P(unit, "Seam", Vector3.new(0.08, 7.6, 0.05), doorCf * CFrame.new(0, 0, -0.22), Color3.fromRGB(110, 112, 118), nil, { collide = false })
	local plate = P(unit, "FloorPlate", Vector3.new(3.4, 0.9, 0.1), doorCf * CFrame.new(0, 6.4, -0.1), DARK, nil, { collide = false })
	K.addSurfaceText(plate, info.label, info.accent, DARK)
	unit:SetAttribute("HouseNumber", id)
	unit:SetAttribute("Street", info.street)
	unit:SetAttribute("StreetNumber", info.number)
	unit:SetAttribute("Address", ("%s, %d - %s"):format(info.street, info.number, info.label))
	unit:SetAttribute("Tier", info.tier)
	unit:SetAttribute("Building", info.building)
	unit:SetAttribute("Remote", true)
	return unit
end

local function buildTower(groups, plan, item, streetName)
	local cfg = item.cfg
	local lot = item.lot
	local floors = cfg.Floors
	local w, d = BODY_W, BODY_D
	local accent = cfg.Accent or GOLD
	local b = K.model(cfg.Name, groups.buildings)
	local cf = lot * CFrame.new(0, 0, 3)
	local function at(x, y, z)
		return cf * CFrame.new(x, y, z)
	end
	local front = -d / 2
	local y0 = G + LOBBY_H
	local bodyH = floors * FLOOR_H
	local top = y0 + bodyH

	-- Lote: piso, caminho da entrada, canteiros com palmeira, banco e letreiro de pedra
	P(b, "Plaza", Vector3.new(TOWER_W, 0.3, TOWER_D), lot * CFrame.new(0, 0.55, 0), PAVING, Enum.Material.Concrete)
	P(b, "Entrada", Vector3.new(10, 0.05, 18), lot * CFrame.new(0, 0.72, -TOWER_D / 2 + 9), Color3.fromRGB(120, 118, 115), Enum.Material.Slate, { collide = false })
	for _, x in ipairs({ -26, 26 }) do
		P(b, "Canteiro", Vector3.new(7, 1.2, 6), lot * CFrame.new(x, 1.2, -28.5), Color3.fromRGB(120, 115, 110), Enum.Material.Concrete)
		P(b, "Terra", Vector3.new(6.2, 0.2, 5.2), lot * CFrame.new(x, 1.85, -28.5), Color3.fromRGB(90, 140, 60), Enum.Material.Grass, { collide = false })
		palm(b, (lot * CFrame.new(x, 1.8, -28.5)).Position, 0.9)
	end
	local stone = P(b, "Letreiro", Vector3.new(12, 3.2, 1.4), lot * CFrame.new(-13, G + 1.6, -30), STONE, Enum.Material.Slate)
	local stoneText = P(b, "LetreiroNome", Vector3.new(11, 1.8, 0.1), stone.CFrame * CFrame.new(0, 0.2, -0.75), STONE, Enum.Material.Slate, { collide = false })
	K.addSurfaceText(stoneText, cfg.Name, Color3.fromRGB(35, 35, 40), STONE)
	bench(b, lot * CFrame.new(14, G - 0.7, -29) * CFrame.Angles(0, math.pi, 0))

	-- Saguão (térreo): piso de mármore, paredes, vidro na frente com vão de entrada
	P(b, "LobbyFloor", Vector3.new(w - 1, 0.2, d - 1), at(0, G + 0.1, 0), Color3.fromRGB(232, 228, 222), Enum.Material.Marble)
	P(b, "LobbyBack", Vector3.new(w, LOBBY_H, 1), at(0, G + LOBBY_H / 2, d / 2 - 0.5), Color3.fromRGB(120, 85, 55), Enum.Material.WoodPlanks)
	for _, s in ipairs({ -1, 1 }) do
		P(b, "LobbySide", Vector3.new(1, LOBBY_H, d), at(s * (w / 2 - 0.5), G + LOBBY_H / 2, 0), WHITE)
		P(b, "LobbyGlass", Vector3.new(w / 2 - 5, 10, 0.4), at(s * (5 + (w / 2 - 5) / 2), G + 5, front + 0.2), LOBBY_GLASS, nil, { transparency = 0.5, reflectance = 0.1 })
		for _, x in ipairs({ 5, 13, w / 2 - 0.5 }) do
			P(b, "Mullion", Vector3.new(0.5, 10, 0.6), at(s * x, G + 5, front + 0.2), DARK, Enum.Material.Metal)
		end
	end
	P(b, "LobbyBand", Vector3.new(w, LOBBY_H - 10, 0.8), at(0, G + 10 + (LOBBY_H - 10) / 2, front + 0.4), DARK)
	local nameBoard = P(b, "LobbyName", Vector3.new(24, 2.4, 0.2), at(0, G + 12, front - 0.1), DARK, nil, { collide = false })
	K.addSurfaceText(nameBoard, cfg.Name, accent, DARK)
	P(b, "Marquise", Vector3.new(16, 0.5, 7), at(0, G + 10.6, front - 3.5), WHITE, nil, { collide = false })
	local numberPlate = P(b, "NumberPlate", Vector3.new(2, 1.1, 0.1), at(7.5, G + 8, front - 0.45), Color3.fromRGB(30, 60, 110), nil, { collide = false })
	K.addSurfaceText(numberPlate, tostring(item.number), Color3.new(1, 1, 1), Color3.fromRGB(30, 60, 110))
	for _, x in ipairs({ -9, 9 }) do
		local lamp = P(b, "LobbyLight", Vector3.new(8, 0.2, 2.4), at(x, G + LOBBY_H - 0.1, -2), Color3.fromRGB(255, 245, 225), Enum.Material.Neon, { collide = false })
		glow(lamp, 18, 0.6)
	end
	-- Portaria (balcão à esquerda), sofá à direita e vasos
	P(b, "Portaria", Vector3.new(3, 3.4, 9), at(-w / 2 + 4, G + 1.7, -4), Color3.fromRGB(70, 55, 45), Enum.Material.WoodPlanks)
	P(b, "PortariaTampo", Vector3.new(3.4, 0.25, 9.4), at(-w / 2 + 4, G + 3.5, -4), Color3.fromRGB(235, 232, 226), Enum.Material.Marble)
	local deskSign = P(b, "PortariaPlaca", Vector3.new(5, 1, 0.1), at(-w / 2 + 5.56, G + 2.3, -4) * CFrame.Angles(0, -math.pi / 2, 0), DARK, nil, { collide = false })
	K.addSurfaceText(deskSign, "PORTARIA", accent, DARK)
	P(b, "Sofa", Vector3.new(3, 1.6, 9), at(w / 2 - 3, G + 0.8, -9), Color3.fromRGB(80, 80, 88), Enum.Material.Fabric)
	P(b, "SofaBack", Vector3.new(0.8, 2.6, 9), at(w / 2 - 1.4, G + 1.3, -9), Color3.fromRGB(80, 80, 88), Enum.Material.Fabric)
	for _, p in ipairs({ { -w / 2 + 2.5, 4 }, { -w / 2 + 2.5, -15.5 }, { w / 2 - 2.5, -15.5 } }) do
		P(b, "Vaso", Vector3.new(1.6, 1.6, 1.6), at(p[1], G + 0.8, p[2]), Color3.fromRGB(60, 60, 65), Enum.Material.Slate)
		P(b, "Planta", Vector3.new(2.6, 2.6, 2.6), at(p[1], G + 2.6, p[2]), Color3.fromRGB(70, 150, 70), Enum.Material.Grass, { shape = BALL, collide = false })
	end

	-- Elevadores: apartamentos no fundo, cobertura (dourado) na parede da direita.
	-- Marco 10.2: cada elevador leva a um andar de verdade do prédio (MoradiaBuilder).
	local n = H.ApartmentsPerTower
	local aptAt = {} -- aptAt[andar] = unidade
	for i = 1, n do
		local floor = math.floor(2 + (i - 1) * (floors - 3) / math.max(n - 1, 1) + 0.5)
		local doorCf = at(-17.5 + 7 * (i - 1), G + 3.8, d / 2 - 1 - 0.2)
		aptAt[floor] = unitDoor(groups.houses, doorCf, { label = ("Apto %d"):format(floor * 100 + 1), tier = "apartamento", accent = accent, street = streetName, number = item.number, building = cfg.Name })
	end
	local penthouseUnit = unitDoor(groups.houses, at(w / 2 - 1 - 0.2, G + 3.8, 8) * CFrame.Angles(0, math.pi / 2, 0), { label = "Cobertura", tier = "cobertura", accent = GOLD, gold = true, street = streetName, number = item.number, building = cfg.Name })

	-- Torre: andares "fechados" (só fachada) agrupados em blocos e os andares de apartamento ocos
	local glassStyle = cfg.Style == "vidro"
	local trim = glassStyle and WHITE or (cfg.Wall or WHITE)
	local function solidFloors(k0, k1)
		local base = y0 + (k0 - 1) * FLOOR_H
		local hh = (k1 - k0 + 1) * FLOOR_H
		if glassStyle then
			P(b, "Body", Vector3.new(w, hh, d), at(0, base + hh / 2, 0), cfg.Glass or GLASS_DARK, nil, { reflectance = 0.25 })
			for k = k0, k1 do
				P(b, "Laje", Vector3.new(w + 0.8, 0.6, d + 0.8), at(0, y0 + (k - 1) * FLOOR_H + 0.3, 0), WHITE, nil, { collide = false })
			end
			for kk = 1, 5 do
				P(b, "Brise", Vector3.new(0.5, hh, 0.8), at(-w / 2 + kk * w / 6, base + hh / 2, d / 2 + 0.4), WHITE, nil, { collide = false })
			end
			for _, x in ipairs({ -1, 1 }) do
				for _, z in ipairs({ -1, 1 }) do
					P(b, "Quina", Vector3.new(1.4, hh, 1.4), at(x * w / 2, base + hh / 2, z * d / 2), WHITE)
				end
			end
		else
			P(b, "Body", Vector3.new(w, hh, d), at(0, base + hh / 2, 0), cfg.Wall or WHITE)
			for k = k0, k1 do
				local fb = y0 + (k - 1) * FLOOR_H
				local y = fb + FLOOR_H / 2 + 0.4
				P(b, "Windows", Vector3.new(w - 6, 5.6, 0.3), at(0, y, front - 0.1), Color3.fromRGB(120, 160, 190), nil, { reflectance = 0.15, collide = false })
				P(b, "Windows", Vector3.new(w - 6, 5.6, 0.3), at(0, y, d / 2 + 0.1), Color3.fromRGB(120, 160, 190), nil, { reflectance = 0.15, collide = false })
				for _, s in ipairs({ -1, 1 }) do
					P(b, "Windows", Vector3.new(0.3, 5.6, d - 8), at(s * (w / 2 + 0.1), y, 0), Color3.fromRGB(120, 160, 190), nil, { reflectance = 0.15, collide = false })
				end
				P(b, "Sacada", Vector3.new(w - 4, 0.5, 3.6), at(0, fb + 0.25, front - 1.8), WHITE, nil, { collide = false })
				P(b, "Guarda", Vector3.new(w - 4, 2.4, 0.2), at(0, fb + 1.7, front - 3.5), Color3.fromRGB(190, 225, 240), nil, { transparency = 0.55, collide = false })
			end
		end
	end
	local k = 1
	while k <= floors do
		if aptAt[k] then
			MoradiaBuilder.apartment(b, aptAt[k], at, y0 + (k - 1) * FLOOR_H, { w = w, d = d, h = FLOOR_H, trim = trim })
			k += 1
		else
			local k1 = k
			while k1 < floors and not aptAt[k1 + 1] do
				k1 += 1
			end
			solidFloors(k, k1)
			k = k1 + 1
		end
	end

	-- Cobertura (último andar) com o terraço no telhado
	MoradiaBuilder.penthouse(b, penthouseUnit, at, top, { w = w, d = d, h = PENTHOUSE_H, name = cfg.Name, accent = accent, helipad = cfg.Helipad })

	b:SetAttribute("Address", ("%s, %d"):format(streetName, item.number))
	b:SetAttribute("PlaceName", cfg.Name)
	b:SetAttribute("Curb", K.curbOf(lot, TOWER_D))
	b:SetAttribute("Remote", true)
	return b
end

---------------------------------------------------------------------------
-- Mansão: Marco 10.2, refeita no MoradiaBuilder (3 andares de verdade, dá para andar dentro)
---------------------------------------------------------------------------

local function buildMansion(groups, plan, item, streetName)
	local lot = item.lot
	local mx = item.mirror and -1 or 1
	local function at(x, y, z)
		return lot * CFrame.new(x * mx, y, z)
	end
	local id = K.nextHouseId()
	local house = K.model("Casa " .. id, groups.houses)
	local map = groups.houses.Parent
	MoradiaBuilder.mansion(house, at, {
		id = id,
		garages = map and (map:FindFirstChild("Garages") or K.folder("Garages", map)), -- Marco 10.6: garagem do dono
		wall = MANSION_WALLS[rng:NextInteger(1, #MANSION_WALLS)],
		wood = WOODS[rng:NextInteger(1, #WOODS)],
		number = item.number,
		helipad = item.helipad,
	})
	house:SetAttribute("HouseNumber", id)
	house:SetAttribute("Street", streetName)
	house:SetAttribute("StreetNumber", item.number)
	house:SetAttribute("Address", ("%s, %d"):format(streetName, item.number))
	house:SetAttribute("Tier", "mansao")
	house:SetAttribute("Remote", true)
	house:SetAttribute("Curb", K.curbOf(lot, MANSION_D))
	return house
end


---------------------------------------------------------------------------
-- Casa moderna: Marco 10.6, refeita no MoradiaBuilder (2 andares, varanda, piscina; dá para andar dentro)
---------------------------------------------------------------------------

local MODERN_WALLS = { Color3.fromRGB(246, 245, 241), Color3.fromRGB(222, 222, 220), Color3.fromRGB(232, 222, 205), Color3.fromRGB(70, 72, 78) }

local function buildModernHouse(groups, item, streetName)
	local lot = item.lot
	local mx = item.mirror and -1 or 1
	local function at(x, y, z)
		return lot * CFrame.new(x * mx, y, z)
	end
	local id = K.nextHouseId()
	local house = K.model("Casa " .. id, groups.houses)
	local wall = MODERN_WALLS[rng:NextInteger(1, #MODERN_WALLS)]
	local trim = wall == MODERN_WALLS[4] and WHITE or DARK
	local wood = WOODS[rng:NextInteger(1, #WOODS)]
	local number = item.number

	-- Marco 10.6: casa de verdade de 2 andares (MoradiaBuilder.modern), dá para entrar e andar dentro
	MoradiaBuilder.modern(house, at, { wall = wall, trim = trim, wood = wood, number = number })

	house:SetAttribute("HouseNumber", id)
	house:SetAttribute("Street", streetName)
	house:SetAttribute("StreetNumber", number)
	house:SetAttribute("Address", ("%s, %d"):format(streetName, number))
	house:SetAttribute("Tier", "casamoderna")
	house:SetAttribute("Remote", true)
	house:SetAttribute("Curb", K.curbOf(lot, MODERN_D))
	return house
end

---------------------------------------------------------------------------
-- Praça, bosque, lotes "em breve", parque do condomínio e portais
---------------------------------------------------------------------------

local function roundTree(parent, pos, scale)
	local t = K.model("Arvore", parent)
	local h = 7 * scale
	P(t, "Tronco", Vector3.new(1.3 * scale, h, 1.3 * scale), CFrame.new(pos + Vector3.new(0, h / 2, 0)), GameConfig.Colors.Trunk, Enum.Material.Wood)
	local leaves = GameConfig.Colors.Leaves
	P(t, "Copa", Vector3.new(8, 8, 8) * scale, CFrame.new(pos + Vector3.new(0, h + 2.5 * scale, 0)), leaves[rng:NextInteger(1, #leaves)], Enum.Material.Grass, { shape = BALL, collide = false })
end

local function fountain(f, c, size)
	K.flatCylinder(f, "Bacia", c + Vector3.new(0, G + 0.7, 0), 9 * size, 1.4, STONE, Enum.Material.Slate)
	local water = K.flatCylinder(f, "Agua", c + Vector3.new(0, G + 1.45, 0), 8.2 * size, 0.2, WATER, Enum.Material.SmoothPlastic)
	water.Transparency = 0.2
	water.CanCollide = false
	K.flatCylinder(f, "Coluna", c + Vector3.new(0, G + 3.2, 0), 1.2, 5, WHITE, Enum.Material.Marble)
	K.flatCylinder(f, "Prato", c + Vector3.new(0, G + 5.8, 0), 3.2, 0.6, WHITE, Enum.Material.Marble)
	local fall = K.flatCylinder(f, "Cascata", c + Vector3.new(0, G + 3.6, 0), 2.9, 4.2, WATER, Enum.Material.SmoothPlastic)
	fall.Transparency = 0.6
	fall.CanCollide = false
	local ring = K.flatCylinder(f, "AnelLuz", c + Vector3.new(0, G + 1.42, 0), 8.6 * size, 0.12, Color3.fromRGB(120, 210, 255), Enum.Material.Neon)
	ring.CanCollide = false
end

local function stoneSign(f, cf, text, width)
	local sign = P(f, "Letreiro", Vector3.new(width, 2.6, 1.2), cf * CFrame.new(0, 1.3, 0), STONE, Enum.Material.Slate)
	local label = P(f, "LetreiroNome", Vector3.new(width - 1, 1.8, 0.1), sign.CFrame * CFrame.new(0, 0.2, -0.65), STONE, Enum.Material.Slate, { collide = false })
	K.addSurfaceText(label, text, Color3.fromRGB(35, 35, 40), STONE)
end

local function buildPlaza(parent, item)
	local lot, w, d = item.lot, item.w, item.d
	local f = K.model("PracaHorizonte", parent)
	local function at(x, y, z)
		return lot * CFrame.new(x, y, z)
	end
	P(f, "Piso", Vector3.new(w, 0.3, d), at(0, 0.55, 0), PAVING, Enum.Material.Concrete)
	for _, x in ipairs({ -130, -80, 80, 130 }) do
		for _, z in ipairs({ -12, 14 }) do
			P(f, "Gramado", Vector3.new(36, 0.35, 14), at(x, 0.72, z), LAWN, Enum.Material.Grass)
			palm(f, at(x, 0.9, z).Position, rng:NextNumber(0.95, 1.2))
		end
	end
	local c = at(0, 0, 2).Position
	fountain(f, c, 1.3)
	for i = 0, 3 do
		local a = i * math.pi / 2 + math.pi / 4
		local p = c + Vector3.new(math.cos(a) * 17, G - 0.7, math.sin(a) * 17)
		bench(f, CFrame.lookAt(p, Vector3.new(c.X, p.Y, c.Z)))
	end
	for _, x in ipairs({ -105, -45, 45, 105 }) do
		bench(f, at(x, G - 0.7, 1))
	end
	for _, x in ipairs({ -150, -90, -30, 30, 90, 150 }) do
		K.buildLamp(f, at(x, G - 0.8, -d / 2 + 3))
	end
	-- quiosque de café
	P(f, "Quiosque", Vector3.new(10, 6, 7), at(-150, G + 3, 18), WHITE)
	P(f, "QuiosqueToldo", Vector3.new(12, 0.4, 3), at(-150, G + 6.2, 13.6) * CFrame.Angles(math.rad(-12), 0, 0), Color3.fromRGB(40, 110, 80), Enum.Material.Fabric, { collide = false })
	local cafe = P(f, "QuiosquePlaca", Vector3.new(8, 1.4, 0.1), at(-150, G + 4.8, 14.45), Color3.fromRGB(40, 110, 80), nil, { collide = false })
	K.addSurfaceText(cafe, "Café Horizonte", Color3.new(1, 1, 1), Color3.fromRGB(40, 110, 80))
	stoneSign(f, at(0, G, -d / 2 + 4), H.PlazaName, 18)
end

local function buildBosque(parent, item)
	local lot, w, d = item.lot, item.w, item.d
	local f = K.model("BosqueHorizonte", parent)
	P(f, "Gramado", Vector3.new(w, 0.3, d), lot * CFrame.new(0, 0.55, 0), LAWN, Enum.Material.Grass)
	P(f, "Caminho", Vector3.new(w - 10, 0.12, 5), lot * CFrame.new(0, 0.76, 0), Color3.fromRGB(196, 170, 125), Enum.Material.Ground, { collide = false })
	for x = -w / 2 + 14, w / 2 - 14, 22 do
		for _, z in ipairs({ -17, 17 }) do
			roundTree(f, (lot * CFrame.new(x + rng:NextNumber(-4, 4), G, z + rng:NextNumber(-4, 4))).Position, rng:NextNumber(0.9, 1.3))
		end
	end
	for x = -w / 2 + 40, w / 2 - 40, 80 do
		bench(f, lot * CFrame.new(x, G - 0.7, -4))
	end
	stoneSign(f, lot * CFrame.new(0, G, -d / 2 + 3), "Bosque das Hortênsias", 18)
end

local function buildSpareLot(parent, item)
	local lot, w, d = item.lot, item.w, item.d
	local f = K.model("LoteHorizonte", parent)
	P(f, "Terreno", Vector3.new(w, 0.2, d), lot * CFrame.new(0, 0.5, 0), Color3.fromRGB(165, 145, 115), Enum.Material.Ground)
	-- tapume na frente (com o vão da placa)
	for _, s in ipairs({ -1, 1 }) do
		local len = w / 2 - 12
		P(f, "Tapume", Vector3.new(len, 6, 0.4), lot * CFrame.new(s * (12 + len / 2), G + 3, -d / 2 + 1), Color3.fromRGB(235, 235, 230), Enum.Material.WoodPlanks)
		P(f, "TapumeFaixa", Vector3.new(len, 0.8, 0.45), lot * CFrame.new(s * (12 + len / 2), G + 5.2, -d / 2 + 1), Color3.fromRGB(30, 60, 110), nil, { collide = false })
	end
	K.buildComingSoon(f, lot * CFrame.new(0, 0.6, -d / 2 + 4), item.text)
	for _, x in ipairs({ -9, -5, 5, 9 }) do
		P(f, "Cone", Vector3.new(1, 1.6, 1), lot * CFrame.new(x, 1.4, -d / 2 + 2), Color3.fromRGB(240, 120, 30))
	end
end

-- Parque dos Jardins (dentro da Alameda): lago com ilha, clube com piscina, quadra e árvores
local function buildPark(parent, item)
	local lot, w, d = item.lot, item.w, item.d
	local f = K.model("ParqueDosJardins", parent)
	local function at(x, y, z)
		return lot * CFrame.new(x, y, z)
	end
	P(f, "Gramado", Vector3.new(w, 0.3, d), at(0, 0.55, 0), LAWN, Enum.Material.Grass)
	-- Marco 10.6: mureta com cerca viva em volta do parque (carro não entra no gramado). Na entrada
	-- (frente, no meio) ficam balizadores: gente passa entre eles, carro não.
	do
		local stone = Color3.fromRGB(205, 200, 192)
		local GAP = 6
		local function wall(cx, cz, sx, sz)
			P(f, "Mureta", Vector3.new(sx, 3.2, sz), at(cx, G + 1.6, cz), stone, Enum.Material.Concrete)
			P(f, "CercaVivaMureta", Vector3.new(math.max(sx - 0.4, 1), 1.6, math.max(sz - 0.4, 1)), at(cx, G + 4, cz), Color3.fromRGB(70, 140, 60), Enum.Material.Grass, { collide = false })
		end
		local hw, hd = w / 2 - 0.6, d / 2 - 0.6
		wall(0, hd, w, 1.2)
		wall(-hw, 0, 1.2, d)
		wall(hw, 0, 1.2, d)
		local len = hw - GAP
		wall(-(GAP + len / 2), -hd, len, 1.2)
		wall(GAP + len / 2, -hd, len, 1.2)
		for x = -GAP + 0.3, GAP - 0.3, 2.85 do
			P(f, "Balizador", Vector3.new(0.6, 3.4, 0.6), at(x, G + 1.7, -hd), DARK, Enum.Material.Metal)
		end
	end
	local pathColor = Color3.fromRGB(214, 200, 170)
	P(f, "Caminho", Vector3.new(8, 0.12, d / 2 - 80), at(0, 0.76, -d / 2 + (d / 2 - 80) / 2), pathColor, Enum.Material.Pavement, { collide = false })
	-- lago com caminho em volta
	local lakeC = at(0, 0, 0).Position
	K.flatCylinder(f, "LagoBorda", lakeC + Vector3.new(0, 0.75, 0), 72, 0.5, STONE, Enum.Material.Slate)
	local lake = K.flatCylinder(f, "Lago", lakeC + Vector3.new(0, 0.82, 0), 70, 0.5, WATER, Enum.Material.SmoothPlastic)
	lake.Transparency = 0.15
	K.flatCylinder(f, "Ilha", lakeC + Vector3.new(0, 1, 0), 10, 0.6, LAWN, Enum.Material.Grass)
	palm(f, lakeC + Vector3.new(0, 1.3, 0), 1.3)
	local segs = 20
	local chord = 2 * 80 * math.tan(math.pi / segs) + 0.5
	for i = 0, segs - 1 do
		local a = (i + 0.5) * 2 * math.pi / segs
		local p = lakeC + Vector3.new(math.cos(a) * 80, 0.76, math.sin(a) * 80)
		P(f, "CaminhoLago", Vector3.new(chord, 0.12, 6), CFrame.lookAt(p, Vector3.new(lakeC.X, p.Y, lakeC.Z)), pathColor, Enum.Material.Pavement, { collide = false })
		if i % 4 == 1 then
			local b = lakeC + Vector3.new(math.cos(a) * 87, G - 0.7, math.sin(a) * 87)
			bench(f, CFrame.lookAt(b, Vector3.new(lakeC.X, b.Y, lakeC.Z)))
		end
	end
	for _, z in ipairs({ -170, -130 }) do
		for _, x in ipairs({ -7, 7 }) do
			K.buildLamp(f, at(x, G - 0.8, z))
		end
	end
	-- Marco 10.4: parque e clube mais caprichados (pedido do Luís)
	local function B(name, x0, x1, y0, y1, z0, z1, color, material, extra)
		local sx, sy, sz = math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0)
		return P(f, name, Vector3.new(sx, sy, sz), at((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, material, extra)
	end
	local function seatAt(cf, size, color, text, material)
		local s = K.makePart(f, { ClassName = "Seat", Name = "Assento", Size = size, CFrame = cf, Color = color, Material = material or Enum.Material.Fabric })
		s:SetAttribute("SeatText", text)
		return s
	end
	local function face(x, z, dx, dz)
		return lot * CFrame.lookAt(Vector3.new(x, 0, z), Vector3.new(x + dx, 0, z + dz))
	end
	local function stool(x, z)
		local cf = face(x, z, 0, -1)
		seatAt(cf * CFrame.new(0, G + 2.6, 0), Vector3.new(1.6, 0.3, 1.6), Color3.fromRGB(60, 60, 66), "Banqueta", Enum.Material.SmoothPlastic)
		P(f, "BanquetaPe", Vector3.new(0.3, 2.4, 0.3), cf * CFrame.new(0, G + 1.2, 0), DARK, Enum.Material.Metal)
	end
	local function chair(x, z, dx, dz, color)
		local cf = face(x, z, dx, dz)
		seatAt(cf * CFrame.new(0, G + 1.7, 0), Vector3.new(2, 0.3, 2), color, "Cadeira")
		P(f, "Encosto", Vector3.new(2, 2, 0.3), cf * CFrame.new(0, G + 2.8, 0.9), color, Enum.Material.Fabric)
		P(f, "Pe", Vector3.new(0.3, 1.6, 0.3), cf * CFrame.new(0, G + 0.8, 0), DARK, Enum.Material.Metal)
	end
	local function lounger(x, z)
		local cf = face(x, z, 0, -1)
		seatAt(cf * CFrame.new(0, G + 1, 0.5), Vector3.new(2.4, 0.4, 5), WHITE, "Espreguiçadeira", Enum.Material.SmoothPlastic)
		P(f, "EspreguicadeiraEncosto", Vector3.new(2.4, 0.3, 2.6), cf * CFrame.new(0, G + 1.9, 3.6) * CFrame.Angles(math.rad(50), 0, 0), WHITE)
		P(f, "EspreguicadeiraBase", Vector3.new(2.2, 0.8, 4.6), cf * CFrame.new(0, G + 0.4, 0.5), Color3.fromRGB(200, 200, 205), Enum.Material.Metal)
	end
	local function umbrella(x, z, color)
		B("GuardaSolHaste", x - 0.15, x + 0.15, G, G + 7, z - 0.15, z + 0.15, DARK, Enum.Material.Metal)
		K.flatCylinder(f, "GuardaSol", at(x, G + 7, z).Position, 4, 0.3, color, Enum.Material.Fabric)
	end

	-- Clube Jardins: dá para entrar (bar com banquetas, mesas, sofás, TV) e o telhado tem deck
	local CX0, CX1, CZ0, CZ1, CH = 122, 178, 116, 144, 12
	local clubWall = Color3.fromRGB(248, 246, 240)
	B("ClubePiso", CX0, CX1, G, G + 0.2, CZ0, CZ1, Color3.fromRGB(176, 132, 92), Enum.Material.WoodPlanks)
	B("ClubeParede", CX0, CX1, G, G + CH, CZ1 - 1, CZ1, clubWall)
	B("ClubeParede", CX0, CX0 + 1, G, G + CH, CZ0, CZ1, clubWall)
	B("ClubeParede", CX1 - 1, CX1, G, G + CH, CZ0, CZ1, clubWall)
	B("ClubePedra", CX0 - 0.3, CX0 + 12, G, G + CH, CZ1 - 0.6, CZ1 + 0.3, STONE, Enum.Material.Slate)
	for _, seg in ipairs({ { CX0 + 1, 145 }, { 155, CX1 - 1 } }) do -- vidro da frente (virado para a piscina)
		B("ClubeVidro", seg[1], seg[2], G, G + 9.5, CZ0 + 0.3, CZ0 + 0.7, Color3.fromRGB(150, 195, 220), nil, { transparency = 0.45, reflectance = 0.15 })
		for x = seg[1], seg[2], (seg[2] - seg[1]) / 4 do
			B("Caixilho", x - 0.2, x + 0.2, G, G + 9.5, CZ0 + 0.2, CZ0 + 0.8, DARK, Enum.Material.Metal, { collide = false })
		end
	end
	B("ClubeVerga", CX0, CX1, G + 9.5, G + CH, CZ0, CZ0 + 1, clubWall)
	B("ClubeTeto", CX0 - 3, CX1 + 3, G + CH, G + CH + 0.8, CZ0 - 6, CZ1 + 1, DARK)
	B("ClubeLuz", CX0 - 2.8, CX1 + 2.8, G + CH - 0.15, G + CH, CZ0 - 5.8, CZ0 - 5.5, Color3.fromRGB(255, 225, 170), Enum.Material.Neon, { collide = false, shadow = false })
	local club = P(f, "ClubePlaca", Vector3.new(20, 2, 0.2), at(150, G + 10.8, CZ0 - 0.1), DARK, nil, { collide = false })
	K.addSurfaceText(club, "Clube Jardins", Color3.fromRGB(240, 220, 160), DARK)
	-- bar no fundo com 6 banquetas
	B("Bar", 135, 165, G, G + 3.6, 136, 138, Color3.fromRGB(70, 55, 45), Enum.Material.WoodPlanks)
	B("BarTampo", 134.6, 165.4, G + 3.6, G + 3.85, 135.6, 138.4, Color3.fromRGB(235, 232, 226), Enum.Material.Marble)
	B("BarPrateleira", 135, 165, G + 5, G + 5.3, 141.6, 143, Color3.fromRGB(70, 55, 45), Enum.Material.Wood)
	for x = 137, 163, 2.4 do
		B("Garrafa", x - 0.25, x + 0.25, G + 5.3, G + 6.5, 142.1, 142.6, ({ Color3.fromRGB(60, 140, 80), Color3.fromRGB(150, 70, 40), Color3.fromRGB(220, 200, 120) })[(math.floor(x) % 3) + 1], nil, { transparency = 0.2, collide = false })
	end
	for x = 138, 162, 4.8 do
		stool(x, 133.6)
	end
	-- mesas com cadeiras
	for _, p in ipairs({ { 130, 124 }, { 144, 124 }, { 158, 124 }, { 170, 130 } }) do
		B("Mesa", p[1] - 1.8, p[1] + 1.8, G + 2.6, G + 2.9, p[2] - 1.8, p[2] + 1.8, WHITE, Enum.Material.Marble)
		B("MesaPe", p[1] - 0.3, p[1] + 0.3, G, G + 2.6, p[2] - 0.3, p[2] + 0.3, DARK, Enum.Material.Metal)
		chair(p[1] - 3.2, p[2], 1, 0, Color3.fromRGB(70, 110, 150))
		chair(p[1] + 3.2, p[2], -1, 0, Color3.fromRGB(70, 110, 150))
	end
	-- sofá e TV na lateral
	seatAt(face(CX0 + 3, 130, 1, 0) * CFrame.new(0, G + 1.3, 0), Vector3.new(8, 1.2, 3), Color3.fromRGB(200, 195, 185), "Sofá")
	B("SofaEncosto", CX0 + 1, CX0 + 2, G, G + 4, 126, 134, Color3.fromRGB(200, 195, 185), Enum.Material.Fabric)
	local tv = B("TV", CX1 - 1.4, CX1 - 1.1, G + 4.5, G + 8.5, 126, 134, Color3.fromRGB(20, 20, 24))
	tv:SetAttribute("Toggle", "TV")
	tv:SetAttribute("Label", "TV")
	for _, x in ipairs({ 136, 164 }) do
		local lamp = B("ClubeLampada", x - 2, x + 2, G + CH - 0.25, G + CH, 128, 132, NEON_WARM, Enum.Material.Neon, { collide = false, shadow = false })
		glow(lamp, 24, 0.5)
	end
	-- deck da piscina, piscina grande, piscina infantil, espreguiçadeiras, guarda-sóis e duchas
	P(f, "ClubeDeck", Vector3.new(76, 0.3, 44), at(152, G + 0.15, 92), Color3.fromRGB(170, 130, 95), Enum.Material.WoodPlanks)
	P(f, "PiscinaBorda", Vector3.new(40, 0.8, 18), at(146, G + 0.55, 90), WHITE, Enum.Material.Marble)
	P(f, "Piscina", Vector3.new(38, 0.2, 16), at(146, G + 1, 90), WATER, nil, { transparency = 0.2, collide = false })
	B("PiscinaRaia", 127, 165, G + 1.12, G + 1.14, 89.8, 90.2, Color3.fromRGB(30, 80, 160), nil, { collide = false })
	K.flatCylinder(f, "PiscinaInfantilBorda", at(180, G + 0.5, 90).Position, 6.5, 1, WHITE, Enum.Material.Marble)
	local kids = K.flatCylinder(f, "PiscinaInfantil", at(180, G + 1.02, 90).Position, 5.8, 0.15, Color3.fromRGB(110, 205, 240), Enum.Material.SmoothPlastic)
	kids.Transparency = 0.2
	kids.CanCollide = false
	for k = 0, 5 do
		lounger(126 + k * 7, 105)
	end
	for _, x in ipairs({ 129.5, 143.5, 157.5 }) do
		umbrella(x, 108, Color3.fromRGB(240, 235, 220))
	end
	for _, x in ipairs({ 120, 172 }) do
		B("Ducha", x - 0.2, x + 0.2, G, G + 8, 78, 78.4, Color3.fromRGB(200, 200, 205), Enum.Material.Metal)
		B("DuchaCabeca", x - 0.6, x + 0.6, G + 7.8, G + 8.1, 77.6, 78.8, Color3.fromRGB(200, 200, 205), Enum.Material.Metal)
	end
	for _, p in ipairs({ { 116, 72 }, { 188, 72 }, { 116, 112 }, { 190, 110 } }) do
		palm(f, at(p[1], G, p[2]).Position, rng:NextNumber(1, 1.25))
	end

	-- quadra de tênis com alambrado e bancos
	P(f, "Quadra", Vector3.new(40, 0.2, 22), at(-150, G + 0.1, 120), Color3.fromRGB(60, 120, 95), Enum.Material.Concrete)
	P(f, "QuadraMeio", Vector3.new(34, 0.05, 15), at(-150, G + 0.22, 120), Color3.fromRGB(70, 110, 170), nil, { collide = false })
	for _, z in ipairs({ 112.5, 127.5 }) do
		B("QuadraLinha", -167, -133, G + 0.25, G + 0.27, z - 0.15, z + 0.15, WHITE, nil, { collide = false })
	end
	for _, x in ipairs({ -167, -133 }) do
		B("QuadraLinha", x - 0.15, x + 0.15, G + 0.25, G + 0.27, 112.5, 127.5, WHITE, nil, { collide = false })
	end
	P(f, "Rede", Vector3.new(0.2, 2.4, 16), at(-150, G + 1.3, 120), Color3.fromRGB(240, 240, 240), nil, { transparency = 0.3 })
	for _, z in ipairs({ 107, 133 }) do
		B("Alambrado", -172, -128, G, G + 9, z - 0.1, z + 0.1, Color3.fromRGB(40, 90, 60), Enum.Material.Metal, { transparency = 0.6 })
	end
	B("Alambrado", -172.1, -171.9, G, G + 9, 107, 133, Color3.fromRGB(40, 90, 60), Enum.Material.Metal, { transparency = 0.6 })
	B("Alambrado", -128.1, -127.9, G, G + 9, 107, 124, Color3.fromRGB(40, 90, 60), Enum.Material.Metal, { transparency = 0.6 })
	for _, x in ipairs({ -160, -140 }) do
		bench(f, lot * CFrame.new(x, G - 0.7, 136) * CFrame.Angles(0, math.pi, 0))
	end

	-- píer no lago com pedalinhos (dá para sentar)
	B("Pier", 40, 76.5, G + 0.6, G + 0.9, -3, 3, Color3.fromRGB(150, 110, 75), Enum.Material.WoodPlanks)
	for x = 44, 74, 6 do
		for _, z in ipairs({ -3, 3 }) do
			B("PierPoste", x - 0.3, x + 0.3, 0, G + 2.2, z - 0.3, z + 0.3, Color3.fromRGB(110, 80, 55), Enum.Material.Wood)
		end
	end
	for k, z in ipairs({ -8, 8 }) do
		local cf = face(42, z, -1, 0)
		P(f, "Pedalinho", Vector3.new(4, 1.6, 6), cf * CFrame.new(0, 1.6, 0), k == 1 and WHITE or Color3.fromRGB(250, 210, 60))
		P(f, "PedalinhoPescoco", Vector3.new(0.9, 3.4, 0.9), cf * CFrame.new(0, 3.2, -2.6), k == 1 and WHITE or Color3.fromRGB(250, 210, 60))
		P(f, "PedalinhoBico", Vector3.new(0.6, 0.5, 1.2), cf * CFrame.new(0, 4.6, -3.4), Color3.fromRGB(240, 140, 40))
		seatAt(cf * CFrame.new(0, 2.55, 0.8), Vector3.new(3, 0.3, 2), Color3.fromRGB(70, 110, 170), "Pedalinho", Enum.Material.SmoothPlastic)
	end

	-- parquinho e academia ao ar livre (frente, à esquerda)
	B("Areia", -230, -110, G, G + 0.12, -170, -110, Color3.fromRGB(225, 205, 150), Enum.Material.Sand)
	for _, x in ipairs({ -205, -195 }) do -- balanço
		for _, z in ipairs({ -151.4, -148.6 }) do
			B("BalancoPoste", x - 0.2, x + 0.2, G, G + 9, z - 0.2, z + 0.2, Color3.fromRGB(230, 70, 60), Enum.Material.Metal)
		end
	end
	B("BalancoTrave", -205.4, -194.6, G + 8.7, G + 9.2, -150.25, -149.75, Color3.fromRGB(230, 70, 60), Enum.Material.Metal)
	for _, x in ipairs({ -202.2, -197.8 }) do
		B("Corrente", x - 0.06, x + 0.06, G + 2.8, G + 8.7, -150.06, -149.94, Color3.fromRGB(150, 150, 155), Enum.Material.Metal, { collide = false })
		seatAt(face(x, -150, 0, -1) * CFrame.new(0, G + 2.7, 0), Vector3.new(2.2, 0.3, 1.2), Color3.fromRGB(40, 110, 200), "Balanço", Enum.Material.SmoothPlastic)
	end
	B("EscorregaTorre", -172, -168, G + 5.8, G + 6.3, -142, -138, Color3.fromRGB(250, 200, 50))
	for _, x in ipairs({ -171.8, -168.2 }) do
		for _, z in ipairs({ -141.8, -138.2 }) do
			B("EscorregaPoste", x - 0.2, x + 0.2, G, G + 9, z - 0.2, z + 0.2, Color3.fromRGB(40, 110, 200), Enum.Material.Metal)
		end
	end
	for k = 0, 4 do
		B("Degrau", -171.3, -168.7, G + 0.9 + k * 1.2, G + 1.2 + k * 1.2, -135.8 - (4 - k) * 0.7, -135 - (4 - k) * 0.7, Color3.fromRGB(40, 110, 200), Enum.Material.Metal)
	end
	P(f, "Rampa", Vector3.new(2.6, 0.3, 9.6), at(-170, G + 3.1, -146.4) * CFrame.Angles(math.rad(-34), 0, 0), Color3.fromRGB(60, 190, 110))
	for k, x in ipairs({ -145, -135, -125 }) do -- academia
		B("BarraPoste", x - 2.2, x - 1.8, G, G + 7, -125, -124.6, Color3.fromRGB(240, 170, 40), Enum.Material.Metal)
		B("BarraPoste", x + 1.8, x + 2.2, G, G + 7, -125, -124.6, Color3.fromRGB(240, 170, 40), Enum.Material.Metal)
		B("Barra", x - 2, x + 2, G + 6.5 - k * 1.2, G + 6.8 - k * 1.2, -124.95, -124.65, Color3.fromRGB(200, 200, 205), Enum.Material.Metal)
	end
	-- piquenique e jardim de flores (frente, à direita)
	for _, p in ipairs({ { 130, -150 }, { 160, -150 }, { 190, -150 }, { 145, -125 }, { 175, -125 } }) do
		B("MesaPiquenique", p[1] - 3, p[1] + 3, G + 2.6, G + 2.9, p[2] - 1.6, p[2] + 1.6, Color3.fromRGB(160, 115, 70), Enum.Material.WoodPlanks)
		B("MesaPiqueniquePe", p[1] - 0.3, p[1] + 0.3, G, G + 2.6, p[2] - 0.3, p[2] + 0.3, Color3.fromRGB(110, 80, 55), Enum.Material.Wood)
		for _, s in ipairs({ -1, 1 }) do
			seatAt(face(p[1], p[2] + s * 2.8, 0, -s) * CFrame.new(0, G + 1.6, 0), Vector3.new(6, 0.3, 1.2), Color3.fromRGB(160, 115, 70), "Banco", Enum.Material.WoodPlanks)
		end
	end
	local flowerColors = { Color3.fromRGB(240, 90, 120), Color3.fromRGB(250, 210, 60), Color3.fromRGB(170, 100, 230), Color3.fromRGB(255, 140, 60), WHITE }
	for k = 0, 9 do
		local x, z = 110 + (k % 5) * 22, -100 - math.floor(k / 5) * 14
		P(f, "Flores", Vector3.new(8, 1.6, 6), at(x, G + 0.6, z), flowerColors[(k % #flowerColors) + 1], Enum.Material.Grass, { shape = BALL, collide = false })
	end
	-- mais postes em volta do lago
	for i = 0, 7 do
		local a = i * math.pi / 4 + math.pi / 8
		local pos = lakeC + Vector3.new(math.cos(a) * 86, 0, math.sin(a) * 86)
		K.buildLamp(f, CFrame.lookAt(Vector3.new(pos.X, G - 0.8, pos.Z), Vector3.new(lakeC.X, G - 0.8, lakeC.Z)))
	end
	-- árvores em volta (deixa a entrada aberta)
	for x = -w / 2 + 16, w / 2 - 16, 40 do
		for _, z in ipairs({ -d / 2 + 14, d / 2 - 14 }) do
			if not (z < 0 and math.abs(x) < 30) then
				roundTree(f, at(x + rng:NextNumber(-3, 3), G, z).Position, rng:NextNumber(1, 1.4))
			end
		end
	end
	for z = -d / 2 + 54, d / 2 - 54, 40 do
		for _, x in ipairs({ -w / 2 + 14, w / 2 - 14 }) do
			roundTree(f, at(x, G, z + rng:NextNumber(-3, 3)).Position, rng:NextNumber(1, 1.4))
		end
	end
	stoneSign(f, at(0, G, -d / 2 + 6) * CFrame.new(-14, 0, 0), H.ParkName, 16)
end

-- Portal sobre o boulevard (dois pilares nas calçadas e a viga com o nome dos dois lados)
local function buildPortal(parent, name, t, text, glowColor)
	local f = K.model(name, parent)
	local p = CityRoads.districtPoint(0, t)
	local north = Vector3.new(0, 0, -1)
	local half = BOULEVARD_HALF - M.SidewalkWidth / 2
	for _, x in ipairs({ -half, half }) do
		P(f, "Pilar", Vector3.new(3, 22, 3), CFrame.new(p + Vector3.new(x, 11.8, 0)), STONE, Enum.Material.Slate)
	end
	local beam = CFrame.lookAt(p + Vector3.new(0, 21.4, 0), p + Vector3.new(0, 21.4, 0) + north)
	P(f, "Viga", Vector3.new(2 * half + 4, 3.4, 2.4), beam, DARK, nil, { collide = false })
	for _, turn in ipairs({ 0, math.pi }) do
		local board = P(f, "Placa", Vector3.new(34, 2.6, 0.2), beam * CFrame.Angles(0, turn, 0) * CFrame.new(0, 0, -1.3), DARK, nil, { collide = false })
		K.addSurfaceText(board, text, Color3.fromRGB(240, 220, 160), DARK)
	end
	local strip = P(f, "Luz", Vector3.new(2 * half + 3, 0.3, 0.3), beam * CFrame.new(0, -1.85, 0), glowColor, Enum.Material.Neon, { collide = false })
	strip.CastShadow = false
	return f
end

local function buildGuard(parent, item)
	local lot = item.lot
	local g = K.model("Guarita", parent)
	P(g, "Piso", Vector3.new(GUARD_W, 0.3, GUARD_D), lot * CFrame.new(0, 0.55, 0), PAVING, Enum.Material.Concrete)
	P(g, "Corpo", Vector3.new(10, 9, 8), lot * CFrame.new(0, G + 4.5, -1), WHITE)
	P(g, "Vidro", Vector3.new(8.4, 3.6, 0.3), lot * CFrame.new(0, G + 5.4, -5.1), GLASS_DARK, nil, { reflectance = 0.3 })
	P(g, "VidroLado", Vector3.new(0.3, 3.6, 6), lot * CFrame.new(-5.1, G + 5.4, -1), GLASS_DARK, nil, { reflectance = 0.3 })
	P(g, "Teto", Vector3.new(12, 0.6, 10), lot * CFrame.new(0, G + 9.3, -1.5), DARK)
	local sign = P(g, "Placa", Vector3.new(6, 1.2, 0.2), lot * CFrame.new(0, G + 8, -5.15), DARK, nil, { collide = false })
	K.addSurfaceText(sign, "PORTARIA", Color3.fromRGB(240, 220, 160), DARK)
	local lamp = P(g, "Luz", Vector3.new(2, 0.2, 2), lot * CFrame.new(0, G + 8.9, -1), Color3.fromRGB(255, 240, 210), Enum.Material.Neon, { collide = false })
	glow(lamp, 12, 0.5)
end

---------------------------------------------------------------------------
-- Etapa 1: reserva dos lotes (antes das casas da cidade)
---------------------------------------------------------------------------

-- Lote ao lado de um trecho a -> b. half = meia largura da rua com a calçada.
local function lotAlong(a, b, t, side, half, depth)
	local dir = (b - a).Unit
	local perp = Vector3.new(-dir.Z, 0, dir.X)
	local center = a + dir * t + perp * side * (half + 0.6 + depth / 2)
	return CFrame.lookAt(center, center - perp * side)
end

-- O ExpansionBuilder usa a palmeira do bairro no canteiro do boulevard e nas rotatórias
function HorizonteBuilder.init(helpers)
	K = helpers
end

function HorizonteBuilder.palm(parent, pos, scale)
	return palm(parent, pos, scale)
end

-- O que fica em cada lado de cada rua (lado -1 = norte, +1 = sul, metade oeste/leste)
local STREET_PLAN = {
	{ north = { "casas", "casas" }, south = { "praca", "shopping" } }, -- Orquídeas
	{ north = { "novidade", "casas" }, south = { "casas", "casas" } }, -- Magnólias
	{ north = {}, south = { "bosque", "casas" } }, -- Hortênsias
}
local HOUSE_X = { 140, 206, 272, 338, 404, 470 }
local SPECIAL_W, SPECIAL_D = 330, 60

function HorizonteBuilder.plan(map, helpers)
	K = helpers
	local at = CityRoads.districtPoint
	local f = K.folder("Horizonte", map)
	local plan = { folder = f, items = {} }

	local function reserve(kind, lot, w, d, extra)
		local area = K.rect(lot, w, d)
		if not K.isFree(area) then
			local p = lot.Position
			warn(("[Horizonte] Sem espaço livre para %s em (%d, %d)"):format(kind, p.X, p.Z))
			return nil
		end
		K.occupy(area)
		local item = { kind = kind, lot = lot, w = w, d = d }
		for key, v in pairs(extra or {}) do
			item[key] = v
		end
		table.insert(plan.items, item)
		return item
	end

	-- Boulevard: 12 prédios, 6 de cada lado (lado +1 = leste)
	local ba, bb = at(0, 0), at(0, D.Loop.T0)
	local k = 0
	for _, t in ipairs(D.TowerT) do
		for _, side in ipairs({ -1, 1 }) do
			k += 1
			local cfg = H.Towers[k]
			if cfg then
				reserve("torre", lotAlong(ba, bb, t, side, BOULEVARD_HALF, TOWER_D), TOWER_W, TOWER_D, { cfg = cfg, street = H.BoulevardName, t = t, side = side })
			end
		end
	end
	plan.guard = reserve("guarita", lotAlong(ba, bb, D.GateT - 18, 1, BOULEVARD_HALF, GUARD_D), GUARD_W, GUARD_D)

	-- Ruas do bairro (de oeste para leste: t = x + Half)
	for i, name in ipairs(H.Streets) do
		local sa, sb = at(-D.Half, D.StreetT[i]), at(D.Half, D.StreetT[i])
		for _, sideName in ipairs({ "north", "south" }) do
			local side = sideName == "north" and -1 or 1
			for h, what in ipairs(STREET_PLAN[i][sideName]) do
				local sign = h == 1 and -1 or 1
				if what == "casas" then
					for j, x in ipairs(HOUSE_X) do
						local t = sign * x + D.Half
						reserve("casa", lotAlong(sa, sb, t, side, STREET_HALF, MODERN_D), MODERN_W, MODERN_D, { street = name, t = t, side = side, mirror = j % 2 == 0 })
					end
				else
					local t = sign * (HOUSE_X[1] + HOUSE_X[#HOUSE_X]) / 2 + D.Half
					local text = what == "shopping" and "Em breve: Shopping Horizonte" or "Em breve: novidade no Horizonte"
					reserve(what, lotAlong(sa, sb, t, side, STREET_HALF, SPECIAL_D), SPECIAL_W, SPECIAL_D, { text = text })
				end
			end
		end
	end

	-- Condomínio: mansões do lado de fora da Alameda dos Jardins
	local L = D.Loop
	local center = at(0, (L.T0 + L.T1) / 2)
	local loopSides = {
		{ a = at(L.X, L.T0), b = at(L.X, L.T1), offset = 2 * L.X, ts = { 40, 150, 260, 370 } }, -- leste
		{ a = at(L.X, L.T1), b = at(-L.X, L.T1), offset = 2 * L.X + (L.T1 - L.T0), ts = { 70, 185, 300, 415, 530 } }, -- norte
		{ a = at(-L.X, L.T1), b = at(-L.X, L.T0), offset = 4 * L.X + (L.T1 - L.T0), ts = { 70, 180, 290, 400 } }, -- oeste
	}
	local n = 0
	for _, seg in ipairs(loopSides) do
		local dir = (seg.b - seg.a).Unit
		local perp = Vector3.new(-dir.Z, 0, dir.X)
		for _, t in ipairs(seg.ts) do
			local mid = seg.a + dir * t
			local side = perp:Dot(mid - center) > 0 and 1 or -1
			n += 1
			reserve("mansao", lotAlong(seg.a, seg.b, t, side, STREET_HALF, MANSION_D), MANSION_W, MANSION_D, { street = H.LoopName, t = seg.offset + t, side = side, mirror = n % 2 == 0, helipad = n % 3 == 1 })
		end
	end
	-- Parque dos Jardins (dentro da Alameda)
	local parkW = 2 * (L.X - STREET_HALF) - 4
	local parkD = (L.T1 - L.T0) - 2 * STREET_HALF - 4
	reserve("parque", CFrame.lookAt(center, center + Vector3.new(0, 0, 1)), parkW, parkD)
	return plan
end

---------------------------------------------------------------------------
-- Etapa 2: construções (depois das casas da cidade)
---------------------------------------------------------------------------

-- Devolve quantos prédios, casas modernas e mansões foram montados
function HorizonteBuilder.build(plan, groups, props)
	MoradiaBuilder.init(K, palm)
	local streets = {}
	local function streetOf(name)
		streets[name] = streets[name] or K.newStreet(name)
		return streets[name]
	end
	local numbered = {}
	for _, item in ipairs(plan.items) do
		if item.street then
			table.insert(numbered, item)
		end
	end
	table.sort(numbered, function(x, y)
		if x.street ~= y.street then
			return x.street < y.street
		end
		return x.t < y.t
	end)
	for _, item in ipairs(numbered) do
		item.number = K.takeNumber(streetOf(item.street), item.side)
	end

	local counts = { torre = 0, casa = 0, mansao = 0 }
	local builders = {
		torre = function(item)
			buildTower(groups, plan, item, item.street)
		end,
		casa = function(item)
			buildModernHouse(groups, item, item.street)
		end,
		mansao = function(item)
			buildMansion(groups, plan, item, item.street)
		end,
		praca = function(item)
			buildPlaza(plan.folder, item)
		end,
		bosque = function(item)
			buildBosque(plan.folder, item)
		end,
		shopping = function(item)
			buildSpareLot(plan.folder, item)
		end,
		novidade = function(item)
			-- Marco 10.8: o lote "em breve: novidade" virou a joalheria (GameConfig.Jewelry)
			JewelryBuilder.build(plan.folder, item, K)
		end,
		parque = function(item)
			buildPark(plan.folder, item)
		end,
		guarita = function(item)
			buildGuard(plan.folder, item)
		end,
	}
	for _, item in ipairs(plan.items) do
		local ok, err = pcall(builders[item.kind], item)
		if ok then
			if counts[item.kind] then
				counts[item.kind] += 1
			end
		else
			warn(("[Horizonte] Erro ao montar %s: %s"):format(item.kind, tostring(err)))
		end
	end
	local ok, err = pcall(function()
		buildPortal(plan.folder, "PortalHorizonte", 76, "Bem-vindo ao " .. H.Name, Color3.fromRGB(255, 180, 90))
		buildPortal(plan.folder, "PortariaCondominio", D.GateT, H.CondoName, Color3.fromRGB(255, 200, 120))
	end)
	if not ok then
		warn("[Horizonte] Erro ao montar os portais: " .. tostring(err))
	end

	-- Placas com o nome das ruas
	local at = CityRoads.districtPoint
	local function streetSign(a, b, t, lateral, name)
		local dir = (b - a).Unit
		local perp = Vector3.new(-dir.Z, 0, dir.X)
		local p = a + dir * t + perp * lateral
		K.buildStreetSign(props, CFrame.lookAt(p, p - perp), name)
	end
	streetSign(at(0, 0), at(0, D.Loop.T0), 100, BOULEVARD_HALF - 1, H.BoulevardName)
	for i, name in ipairs(H.Streets) do
		streetSign(at(-D.Half, D.StreetT[i]), at(D.Half, D.StreetT[i]), 34, STREET_HALF - 1, name)
		streetSign(at(D.Half, D.StreetT[i]), at(-D.Half, D.StreetT[i]), D.Half - 46, STREET_HALF - 1, name)
	end
	streetSign(at(-D.Half, D.StreetT[1]), at(-D.Half, D.StreetT[3]), 40, STREET_HALF - 1, H.WestName)
	streetSign(at(D.Half, D.StreetT[3]), at(D.Half, D.StreetT[1]), 40, STREET_HALF - 1, H.EastName)
	streetSign(at(-D.Loop.X, D.Loop.T0), at(D.Loop.X, D.Loop.T0), 40, -(STREET_HALF - 1), H.LoopName)
	return counts.torre, counts.casa, counts.mansao
end

-- Marco 10.4: o Jardim Progresso (ProgressoBuilder) usa os mesmos prédios e casas modernas
HorizonteBuilder.TOWER_W, HorizonteBuilder.TOWER_D = TOWER_W, TOWER_D
HorizonteBuilder.MODERN_W, HorizonteBuilder.MODERN_D = MODERN_W, MODERN_D
function HorizonteBuilder.buildTower(groups, item, streetName)
	return buildTower(groups, nil, item, streetName)
end
function HorizonteBuilder.buildModernHouse(groups, item, streetName)
	return buildModernHouse(groups, item, streetName)
end

return HorizonteBuilder
