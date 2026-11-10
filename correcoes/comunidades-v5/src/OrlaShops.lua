-- OrlaShops (ModuleScript)
-- Caminho: ServerScriptService > Services > OrlaShops
-- Marco 10.32: as lojas da primeira fila da orla (LitoralBuilder.buildFrontRow) viraram lojas de
-- verdade: dá para entrar, cada uma tem o interior do seu tema (lanchonete, moda praia, surf shop,
-- vitrine, tatuagem, bicicletas), vitrine de vidro com caixilho, luz no teto e acabamento.
--   * Algumas são "vazadas": vitrine e porta dos dois lados (rua da Beira-Mar e calçadão da praia).
--   * As outras ganham um fundo elegante virado para a Beira-Mar: rodapé de pedra, pilastras,
--     janelas foscas, arandelas, floreiras, porta de serviço com marquise e placa.
--   * Lojas de comida têm balcão com atributo LitoralSnack: o LitoralService põe o "Comprar".
-- Usa um sorteio próprio (não mexe no sorteio do resto da orla).

local OrlaShops = {}

local WHITE = Color3.fromRGB(248, 248, 244)
local GLASS = Color3.fromRGB(185, 222, 235)
local FRAME = Color3.fromRGB(45, 48, 54)
local WOOD = Color3.fromRGB(158, 122, 82)
local WOOD_DARK = Color3.fromRGB(105, 78, 52)
local STONE = Color3.fromRGB(196, 188, 172)
local LAMP = Color3.fromRGB(255, 244, 222)
local METAL = Color3.fromRGB(150, 155, 162)

-- tema de cada nome de loja (LitoralBuilder.SHOPS) e o lanche que o balcão vende
OrlaShops.THEMES = {
	["Surf Shop"] = { kind = "pranchas" },
	["Pranchas Sol"] = { kind = "pranchas" },
	["Skate Shop"] = { kind = "pranchas", skate = true },
	["Sorveteria"] = { kind = "comida", snack = "Sorvete", floor = Color3.fromRGB(250, 236, 240), vitrine = true },
	["Açaí da Orla"] = { kind = "comida", snack = "Acai", floor = Color3.fromRGB(236, 226, 240), vitrine = true },
	["Bar do Zé"] = { kind = "comida", snack = "Refri", floor = Color3.fromRGB(200, 180, 150), bar = true },
	["Pastelaria"] = { kind = "comida", snack = "Churros", floor = Color3.fromRGB(245, 235, 210) },
	["Sucos Naturais"] = { kind = "comida", snack = "Coco", floor = Color3.fromRGB(225, 240, 215), vitrine = true },
	["Peixaria"] = { kind = "comida", floor = Color3.fromRGB(220, 232, 240), peixe = true },
	["Café Brisa"] = { kind = "comida", snack = "Churros", floor = Color3.fromRGB(190, 160, 125) },
	["Pizza na Areia"] = { kind = "comida", snack = "Refri", floor = Color3.fromRGB(235, 220, 200), forno = true },
	["Lanchonete Maré"] = { kind = "comida", snack = "CachorroQuente", floor = Color3.fromRGB(240, 240, 235) },
	["Moda Praia"] = { kind = "roupas" },
	["Biquínis"] = { kind = "roupas" },
	["Chapéus"] = { kind = "roupas", chapeus = true },
	["Óculos & Cia"] = { kind = "vitrines" },
	["Souvenirs"] = { kind = "vitrines" },
	["Artesanato"] = { kind = "vitrines" },
	["Tatuagem"] = { kind = "tatuagem" },
	["Bike Aluguel"] = { kind = "bikes" },
}

local BRIGHT = {
	Color3.fromRGB(230, 70, 80), Color3.fromRGB(40, 140, 220), Color3.fromRGB(250, 200, 40), Color3.fromRGB(40, 180, 120),
	Color3.fromRGB(240, 120, 40), Color3.fromRGB(150, 80, 200), Color3.fromRGB(250, 250, 250), Color3.fromRGB(30, 30, 35),
	Color3.fromRGB(255, 140, 180), Color3.fromRGB(90, 200, 220),
}

-- kit: { P, sign, column, nocollide, snacks = L.Snacks }
-- lot: { x0, x1 (paredes de fora), z0 (fundo, lado da Beira-Mar), z1 (frente, lado da praia),
--        h (altura total), name, wall, awning, vazada, index }
function OrlaShops.build(b, kit, lot, rng)
	local P, sign, column, nocollide = kit.P, kit.sign, kit.column, kit.nocollide
	local theme = OrlaShops.THEMES[lot.name] or { kind = "vitrines" }
	local x0, x1, z0, z1 = lot.x0, lot.x1, lot.z0, lot.z1
	local cx, zc = (x0 + x1) / 2, (z0 + z1) / 2
	local W, D = x1 - x0, z1 - z0
	local Y0 = 0.8 -- piso do calçadão
	local FLOOR_H = 10 -- térreo
	local T = 0.8 -- espessura das paredes
	local iw, id = W - 2 * T, D - 2 * T
	local accent = lot.awning

	local function at(x, y, z)
		return CFrame.new(cx + x, Y0 + y, zc + z)
	end
	local function lp(name, size, x, y, z, color, material, extra)
		return P(b, name, size, at(x, y, z), color, material, extra)
	end
	local function deco(name, size, x, y, z, color, material, extra)
		local e = nocollide(extra)
		return P(b, name, size, at(x, y, z), color, material, e)
	end

	-- estrutura: piso, paredes dos lados, laje do térreo e andares de cima (maciços)
	lp("Piso", Vector3.new(iw, 0.2, id), 0, 0.1, 0, theme.floor or Color3.fromRGB(226, 214, 196), theme.kind == "roupas" and Enum.Material.WoodPlanks or Enum.Material.Marble)
	for _, sx in ipairs({ -1, 1 }) do
		lp("Parede", Vector3.new(T, lot.h, D), sx * (W - T) / 2, lot.h / 2, 0, lot.wall, Enum.Material.Plaster)
	end
	lp("Laje", Vector3.new(iw, 0.6, id), 0, FLOOR_H - 0.3, 0, WHITE, Enum.Material.SmoothPlastic)
	if lot.h > FLOOR_H + 0.5 then
		lp("Corpo", Vector3.new(iw, lot.h - FLOOR_H, D), 0, FLOOR_H + (lot.h - FLOOR_H) / 2, 0, lot.wall, Enum.Material.Plaster)
	end
	-- luz do teto (painéis neon, sem PointLight para não pesar no celular)
	for k = -1, 1, 2 do
		deco("Luminaria", Vector3.new(math.min(iw - 6, 14), 0.12, 2.4), 0, FLOOR_H - 0.66, k * id * 0.22, LAMP, Enum.Material.Neon, { Transparency = 0.15 })
	end

	-- fachada de vidro (frente = +1, fundo = -1). A porta fica do lado "doorSide" (-1 / 1).
	local function storefront(side, doorSide)
		local z = side * (D / 2 - T / 2)
		local doorW = 5.5
		local doorX = doorSide * (iw / 2 - doorW / 2 - 1.2)
		-- viga em cima (onde vai o letreiro) e soleira
		lp("Viga", Vector3.new(iw, 1.6, T), 0, FLOOR_H - 0.8, z, lot.wall, Enum.Material.Plaster)
		deco("Soleira", Vector3.new(iw, 0.25, T + 0.2), 0, 0.12, z, STONE, Enum.Material.Slate)
		-- vidros com caixilho, menos onde é a porta
		local left, right = -iw / 2, iw / 2
		local spans = {}
		if doorX - doorW / 2 > left + 0.5 then
			table.insert(spans, { left, doorX - doorW / 2 })
		end
		if doorX + doorW / 2 < right - 0.5 then
			table.insert(spans, { doorX + doorW / 2, right })
		end
		local glassTop = FLOOR_H - 1.6
		for _, s in ipairs(spans) do
			local a, c = s[1], s[2]
			local n = math.max(1, math.floor((c - a) / 6 + 0.5))
			local pw = (c - a) / n
			for i = 0, n - 1 do
				local px = a + pw * (i + 0.5)
				lp("Vidro", Vector3.new(pw - 0.3, glassTop - 0.6, 0.2), px, 0.3 + (glassTop - 0.6) / 2, z, GLASS, Enum.Material.Glass, { Transparency = 0.62, CastShadow = false, Reflectance = 0.08 })
			end
			for i = 0, n do
				deco("Caixilho", Vector3.new(0.3, glassTop - 0.3, 0.35), a + pw * i, 0.15 + (glassTop - 0.3) / 2, z, FRAME, Enum.Material.Metal)
			end
			deco("Caixilho", Vector3.new(c - a, 0.3, 0.35), (a + c) / 2, 0.3, z, FRAME, Enum.Material.Metal)
			deco("Caixilho", Vector3.new(c - a, 0.3, 0.35), (a + c) / 2, glassTop - 0.15, z, FRAME, Enum.Material.Metal)
		end
		-- porta: batente de metal e uma folha de vidro aberta para dentro
		for _, k in ipairs({ -1, 1 }) do
			deco("Batente", Vector3.new(0.35, glassTop, 0.45), doorX + k * doorW / 2, glassTop / 2, z, FRAME, Enum.Material.Metal)
		end
		deco("Batente", Vector3.new(doorW, 0.35, 0.45), doorX, glassTop, z, FRAME, Enum.Material.Metal)
		local hinge = doorX - doorSide * doorW / 2
		local leaf = P(b, "PortaVidro", Vector3.new(doorW - 0.6, glassTop - 0.6, 0.15), at(hinge, 0.3 + (glassTop - 0.6) / 2, z) * CFrame.Angles(0, doorSide * side * math.rad(75), 0) * CFrame.new(doorSide * (doorW - 0.6) / 2, 0, 0), GLASS, Enum.Material.Glass, nocollide({ Transparency = 0.55, CastShadow = false }))
		leaf.CanQuery = false
		deco("Capacho", Vector3.new(doorW - 1, 0.06, 2.6), doorX, 0.22, z - side * 1.8, Color3.fromRGB(70, 60, 55), Enum.Material.Fabric)
		return doorX
	end

	local frontDoor = storefront(1, (lot.index % 2 == 0) and 1 or -1)
	if lot.vazada then
		storefront(-1, frontDoor > 0 and 1 or -1)
		-- marquise e letreiro do lado da rua
		local ac = accent
		P(b, "Marquise", Vector3.new(W - 1, 0.35, 3.6), CFrame.new(cx, Y0 + FLOOR_H - 0.5, z0 - 1.6), WHITE, Enum.Material.SmoothPlastic, nocollide())
		deco("FaixaMarquise", Vector3.new(W - 1, 0.5, 0.2), 0, FLOOR_H - 0.5, -D / 2 - 3.4, ac, Enum.Material.SmoothPlastic)
		local plate = sign(b, CFrame.new(cx, Y0 + FLOOR_H + 0.9, z0 - 0.2), Vector3.new(math.min(W - 6, 20), 1.6, 0.2), lot.name, ac, WHITE)
		plate.Name = "SignRua"
	else
		-- fundo elegante (virado para a Beira-Mar)
		local z = -D / 2 + T / 2
		lp("Fundo", Vector3.new(iw, FLOOR_H, T), 0, FLOOR_H / 2, z, lot.wall, Enum.Material.Plaster)
		local zf = -D / 2 - 0.15
		deco("Rodape", Vector3.new(W + 0.2, 1.4, 0.4), 0, 0.7, zf, STONE, Enum.Material.Slate)
		deco("Cornija", Vector3.new(W + 0.4, 0.7, 0.8), 0, FLOOR_H + 0.1, zf - 0.1, WHITE, Enum.Material.Concrete)
		local nPil = math.max(2, math.floor(W / 9))
		for i = 0, nPil do
			local px = -W / 2 + 0.6 + (W - 1.2) * i / nPil
			deco("Pilastra", Vector3.new(0.9, FLOOR_H - 1.4, 0.35), px, 1.4 + (FLOOR_H - 1.4) / 2, zf, WHITE, Enum.Material.Concrete)
		end
		-- porta de serviço com marquise, janelas foscas entre as pilastras e arandelas
		local doorX = -frontDoor * 0.6
		deco("PortaServico", Vector3.new(3.6, 7, 0.3), doorX, 3.5, zf - 0.1, WOOD_DARK, Enum.Material.Wood)
		deco("Macaneta", Vector3.new(0.2, 0.2, 0.3), doorX + 1.3, 3.5, zf - 0.3, METAL, Enum.Material.Metal)
		deco("MarquisePorta", Vector3.new(5.4, 0.25, 2), doorX, 7.6, zf - 1, FRAME, Enum.Material.Metal)
		for i = 0, nPil - 1 do
			local px = -W / 2 + 0.6 + (W - 1.2) * (i + 0.5) / nPil
			if math.abs(px - doorX) > 3.2 then
				deco("JanelaFosca", Vector3.new(math.min(4.2, (W - 1.2) / nPil - 2), 4.4, 0.2), px, 5.2, zf - 0.05, Color3.fromRGB(220, 232, 236), Enum.Material.Glass, { Transparency = 0.25 })
				deco("Peitoril", Vector3.new(math.min(4.8, (W - 1.2) / nPil - 1.4), 0.3, 0.6), px, 2.85, zf - 0.25, WHITE, Enum.Material.Concrete)
				-- floreira embaixo da janela
				deco("Floreira", Vector3.new(math.min(4.2, (W - 1.2) / nPil - 2), 1, 1.2), px, 1.9, zf - 0.75, WOOD_DARK, Enum.Material.Wood)
				for k = -1, 1 do
					deco("Folhagem", Vector3.new(1.4, 1.1, 1.1), px + k * 1.2, 2.6, zf - 0.75, Color3.fromRGB(70 + rng:NextInteger(0, 40), 150, 70), Enum.Material.Grass, { Shape = Enum.PartType.Ball })
				end
			end
		end
		for _, k in ipairs({ -1, 1 }) do
			deco("Arandela", Vector3.new(0.5, 0.9, 0.4), doorX + k * 2.6, 6.2, zf - 0.3, LAMP, Enum.Material.Neon)
		end
		local plate = sign(b, CFrame.new(cx + doorX, Y0 + 8.6, z0 - 0.45), Vector3.new(math.min(W - 8, 12), 1.1, 0.15), lot.name, WHITE, accent)
		plate.Name = "PlacaFundo"
		-- ar-condicionado em cima
		deco("ArCondicionado", Vector3.new(2.4, 1.6, 1), W / 2 - 3, FLOOR_H - 2.4, zf - 0.6, Color3.fromRGB(235, 235, 235), Enum.Material.SmoothPlastic)
	end
	-- janelas do fundo nos andares de cima
	local floors = math.floor((lot.h - FLOOR_H) / 8 + 0.5)
	for fl = 1, floors do
		local y = FLOOR_H + (fl - 1) * 8 + 4
		deco("JanelasFundo", Vector3.new(W - 8, 3.6, 0.3), 0, y, -D / 2 - 0.1, Color3.fromRGB(120, 170, 200), Enum.Material.SmoothPlastic, { Transparency = 0.15 })
		deco("SacadaFundo", Vector3.new(W - 6, 0.5, 1.2), 0, y - 2, -D / 2 - 0.6, WHITE, Enum.Material.Concrete)
	end

	-- interior por tema --------------------------------------------------
	local backZ = lot.vazada and -id / 2 + 7 or -id / 2 + 1.6 -- fundo útil (se vazada, deixa passagem)
	local frontZ = id / 2 - 6 -- não tampa a vitrine
	local wallL, wallR = -iw / 2, iw / 2
	local function counter(x, z, len, along, color)
		-- along = "z": balcão ao longo da parede do lado; "x": atravessado no fundo
		local size = along == "z" and Vector3.new(2.2, 3.4, len) or Vector3.new(len, 3.4, 2.2)
		local c = lp("Balcao", size, x, 1.9, z, color or WOOD, Enum.Material.WoodPlanks)
		local top = along == "z" and Vector3.new(2.6, 0.25, len + 0.3) or Vector3.new(len + 0.3, 0.25, 2.6)
		deco("TampoBalcao", top, x, 3.72, z, Color3.fromRGB(236, 232, 226), Enum.Material.Marble)
		deco("Caixa", Vector3.new(1.2, 0.9, 1), x, 4.3, z + (along == "z" and len / 2 - 1.2 or 0), FRAME, Enum.Material.SmoothPlastic)
		return c
	end
	local function shelfWall(x, z0w, z1w, levels, facing)
		-- prateleira encostada na parede (x), de z0w a z1w, com coisinhas coloridas
		local len = z1w - z0w
		deco("Estante", Vector3.new(0.6, levels * 1.8 + 0.6, len), x - facing * 0.3, (levels * 1.8 + 0.6) / 2 + 0.2, (z0w + z1w) / 2, WOOD_DARK, Enum.Material.Wood)
		for lv = 1, levels do
			local y = 0.2 + lv * 1.8
			deco("Tabua", Vector3.new(1.4, 0.15, len), x + facing * 0.4, y - 0.95, (z0w + z1w) / 2, WOOD, Enum.Material.Wood)
			local zz = z0w + 0.6
			while zz < z1w - 0.6 do
				local s = rng:NextNumber(0.6, 1.1)
				deco("Item", Vector3.new(0.8, s, 0.7), x + facing * 0.5, y - 0.875 + s / 2, zz, BRIGHT[rng:NextInteger(1, #BRIGHT)], Enum.Material.SmoothPlastic)
				zz += 1.1
			end
		end
	end
	local function table4(x, z, color)
		column(b, "PeMesa", Vector3.new(cx + x, Y0 + 0.2, zc + z), 2.6, 0.2, METAL, Enum.Material.Metal)
		P(b, "Mesa", Vector3.new(0.2, 3.2, 3.2), at(x, 2.9, z) * CFrame.Angles(0, 0, math.rad(90)), color or WHITE, Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
		for k = 0, 3 do
			local a = k * math.pi / 2
			local sx, sz = math.cos(a) * 2.6, math.sin(a) * 2.6
			local seat = P(b, "Cadeira", Vector3.new(1.4, 0.3, 1.4), at(x + sx, 1.9, z + sz), accent, Enum.Material.SmoothPlastic, { ClassName = "Seat" })
			seat:SetAttribute("SeatText", "Sentar")
			column(b, "PeCadeira", Vector3.new(cx + x + sx, Y0 + 0.2, zc + z + sz), 1.5, 0.12, METAL, Enum.Material.Metal)
		end
	end

	local kind = theme.kind
	if kind == "comida" then
		local cxCounter = wallL + 4
		local len = math.min(16, id - 18)
		local c = counter(cxCounter, backZ + len / 2 + 2, len, "z", accent)
		if theme.snack and kit.snacks and kit.snacks[theme.snack] then
			c:SetAttribute("LitoralSnack", theme.snack)
			local s = kit.snacks[theme.snack]
			local menu = sign(b, CFrame.new(cx + wallL + 0.5, Y0 + 7, zc + backZ + len / 2 + 2) * CFrame.Angles(0, -math.pi / 2, 0), Vector3.new(len - 2, 2.2, 0.15), ("CARDÁPIO • %s $%d"):format(s.Name, s.Price), WHITE, Color3.fromRGB(35, 38, 44))
			menu.Name = "Cardapio"
		end
		shelfWall(wallL + 0.8, backZ + 2, backZ + 2 + len, 2, 1)
		if theme.vitrine then
			deco("VitrineGelada", Vector3.new(2, 1.4, len * 0.6), cxCounter, 4.5, backZ + len / 2 + 2, GLASS, Enum.Material.Glass, { Transparency = 0.5 })
			for i = 0, 4 do
				deco("Pote", Vector3.new(1.2, 0.6, 1), cxCounter, 4.1, backZ + 4 + i * len * 0.1, BRIGHT[(i + lot.index) % #BRIGHT + 1], Enum.Material.SmoothPlastic)
			end
		end
		if theme.peixe then
			deco("Gelo", Vector3.new(2.2, 0.4, len - 2), cxCounter, 3.95, backZ + len / 2 + 2, Color3.fromRGB(235, 245, 250), Enum.Material.Ice)
			for i = 0, math.floor(len / 2) - 2 do
				deco("Peixe", Vector3.new(0.6, 0.35, 1.8), cxCounter, 4.3, backZ + 3 + i * 2, Color3.fromRGB(150, 165, 175), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Ball })
			end
		end
		if theme.forno then
			lp("Forno", Vector3.new(6, 3, 5), wallR - 3.6, 1.5, backZ + 3, Color3.fromRGB(150, 70, 50), Enum.Material.Brick)
			deco("Cupula", Vector3.new(5.6, 4, 4.6), wallR - 3.6, 3.2, backZ + 3, Color3.fromRGB(160, 80, 55), Enum.Material.Brick, { Shape = Enum.PartType.Ball })
			deco("Brasa", Vector3.new(2, 1, 0.3), wallR - 3.6, 3.4, backZ + 5.4, Color3.fromRGB(255, 120, 30), Enum.Material.Neon)
		end
		if theme.bar then
			for i = 0, 3 do
				local seat = P(b, "Banqueta", Vector3.new(1.3, 0.3, 1.3), at(cxCounter + 2.4, 2.6, backZ + 4 + i * 3.2), accent, Enum.Material.SmoothPlastic, { ClassName = "Seat" })
				seat:SetAttribute("SeatText", "Sentar")
				column(b, "PeBanqueta", Vector3.new(cx + cxCounter + 2.4, Y0 + 0.2, zc + backZ + 4 + i * 3.2), 2.2, 0.12, METAL, Enum.Material.Metal)
			end
		end
		-- mesas no salão
		local tx0, tx1 = wallL + 9, wallR - 3.5
		local placed = 0
		for z = backZ + 4, frontZ - 1, 8 do
			for x = tx0, tx1, 8 do
				if placed < 6 then
					table4(x, z, WHITE)
					placed += 1
				end
			end
		end
		-- vaso de planta no canto
		deco("Vaso", Vector3.new(1.6, 1.6, 1.6), wallR - 1.4, 0.9, frontZ + 3, Color3.fromRGB(230, 225, 215), Enum.Material.Concrete)
		deco("Planta", Vector3.new(2.4, 3, 2.4), wallR - 1.4, 3, frontZ + 3, Color3.fromRGB(60, 140, 70), Enum.Material.Grass, { Shape = Enum.PartType.Ball })
	elseif kind == "roupas" then
		counter(wallR - 3, backZ + 4, 7, "z", WHITE)
		-- araras com roupas penduradas
		local racks = math.max(2, math.floor((id - 14) / 9))
		for r = 0, racks - 1 do
			local z = backZ + 8 + r * 8.5
			if z < frontZ then
				local x = -iw * 0.15
				for _, k in ipairs({ -1, 1 }) do
					deco("PosteArara", Vector3.new(0.2, 5, 0.2), x + k * 3.4, 2.5, z, METAL, Enum.Material.Metal)
				end
				deco("Arara", Vector3.new(7, 0.15, 0.15), x, 5, z, METAL, Enum.Material.Metal)
				for i = 0, 8 do
					if theme.chapeus then
						local hc = BRIGHT[rng:NextInteger(1, #BRIGHT)]
						deco("Aba", Vector3.new(0.7, 0.12, 1.3), x - 3 + i * 0.75, 4.3, z, hc, Enum.Material.Fabric)
						deco("Copa", Vector3.new(0.45, 0.5, 0.75), x - 3 + i * 0.75, 4.6, z, hc, Enum.Material.Fabric)
					else
						deco("Roupa", Vector3.new(0.15, 2.4, 1.4), x - 3 + i * 0.75, 3.7, z, BRIGHT[rng:NextInteger(1, #BRIGHT)], Enum.Material.Fabric)
					end
				end
			end
		end
		shelfWall(wallL + 0.8, backZ + 3, frontZ, 3, 1)
		-- manequins perto da vitrine
		for _, k in ipairs({ -1, 1 }) do
			local mx = k * iw * 0.25
			local color = BRIGHT[rng:NextInteger(1, #BRIGHT)]
			deco("BaseManequim", Vector3.new(1.6, 0.3, 1.6), mx, 0.35, id / 2 - 3.5, FRAME, Enum.Material.Metal)
			deco("Manequim", Vector3.new(1.6, 2.6, 0.8), mx, 3.3, id / 2 - 3.5, color, Enum.Material.Fabric)
			deco("PernaManequim", Vector3.new(1.2, 2.2, 0.6), mx, 1.5, id / 2 - 3.5, Color3.fromRGB(235, 225, 215), Enum.Material.SmoothPlastic)
			deco("CabecaManequim", Vector3.new(1, 1.1, 1), mx, 5.2, id / 2 - 3.5, Color3.fromRGB(235, 225, 215), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Ball })
		end
		-- provador e espelho
		deco("Espelho", Vector3.new(0.15, 6, 3), wallR - 0.5, 4, frontZ - 3, Color3.fromRGB(210, 225, 235), Enum.Material.Glass, { Reflectance = 0.5 })
		deco("Provador", Vector3.new(4, 7, 0.2), wallR - 2.4, 4, backZ + 9.5, accent, Enum.Material.Fabric)
	elseif kind == "pranchas" then
		counter(wallL + 4, backZ + 4, 8, "z", WOOD)
		-- pranchas (ou shapes de skate) em pé na parede da direita
		local n = math.floor((frontZ - backZ - 4) / 2.6)
		for i = 0, n - 1 do
			local z = backZ + 3 + i * 2.6
			local c1 = BRIGHT[rng:NextInteger(1, #BRIGHT)]
			if theme.skate then
				deco("Shape", Vector3.new(0.3, 3.2, 1), wallR - 0.6, 4.6, z, c1, Enum.Material.Wood)
				deco("Lixa", Vector3.new(0.05, 3.1, 0.95), wallR - 0.78, 4.6, z, Color3.fromRGB(30, 30, 30), Enum.Material.Sand)
			else
				local len = rng:NextNumber(6, 8.4)
				deco("Prancha", Vector3.new(0.35, len, 1.9), wallR - 0.8, 0.4 + len / 2, z, c1, Enum.Material.SmoothPlastic)
				deco("Longarina", Vector3.new(0.4, len - 0.4, 0.08), wallR - 0.8, 0.4 + len / 2, z, WHITE, Enum.Material.SmoothPlastic)
				deco("Bico", Vector3.new(0.35, 1.9, 1.9), wallR - 0.8, 0.4 + len, z, c1, Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
			end
		end
		-- mesa central com parafina, óculos e bonés
		lp("MesaCentral", Vector3.new(6, 3, 4), -1, 1.5, (backZ + frontZ) / 2, WOOD, Enum.Material.WoodPlanks)
		for i = 0, 5 do
			deco("Produto", Vector3.new(0.8, 0.5, 0.8), -3 + i * 0.8, 3.25, (backZ + frontZ) / 2 + (i % 2) * 0.9 - 0.4, BRIGHT[rng:NextInteger(1, #BRIGHT)], Enum.Material.SmoothPlastic)
		end
		shelfWall(wallL + 0.8, backZ + 10, frontZ, 3, 1)
		-- roupa de borracha (wetsuit) pendurada
		deco("Arara", Vector3.new(0.15, 0.15, 6), -iw * 0.15, 6, frontZ - 4, METAL, Enum.Material.Metal)
		for i = 0, 3 do
			deco("Wetsuit", Vector3.new(1.4, 4, 0.2), -iw * 0.15, 3.9, frontZ - 6.4 + i * 1.6, Color3.fromRGB(25, 25, 30), Enum.Material.Fabric)
		end
	elseif kind == "vitrines" then
		counter(0, backZ + 2.5, math.min(10, iw - 6), "x", WOOD_DARK)
		for i = 0, 2 do
			local z = backZ + 9 + i * 8
			if z < frontZ then
				lp("BaseVitrine", Vector3.new(6, 3, 2.4), 0, 1.5, z, WOOD_DARK, Enum.Material.Wood)
				deco("CaixaVidro", Vector3.new(6, 2, 2.4), 0, 4, z, GLASS, Enum.Material.Glass, { Transparency = 0.6 })
				for k = 0, 4 do
					deco("Peca", Vector3.new(0.6, 0.6, 0.6), -2.4 + k * 1.2, 3.35, z, BRIGHT[rng:NextInteger(1, #BRIGHT)], Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Ball })
				end
			end
		end
		shelfWall(wallL + 0.8, backZ + 5, frontZ, 3, 1)
		shelfWall(wallR - 0.8, backZ + 5, frontZ, 3, -1)
	elseif kind == "tatuagem" then
		counter(wallR - 3, frontZ - 4, 6, "z", FRAME)
		lp("Maca", Vector3.new(2.4, 2.6, 6.4), -iw * 0.2, 1.3, backZ + 6, Color3.fromRGB(30, 30, 35), Enum.Material.Fabric)
		deco("Encosto", Vector3.new(2.4, 2.4, 0.6), -iw * 0.2, 3.2, backZ + 3.2, Color3.fromRGB(30, 30, 35), Enum.Material.Fabric)
		deco("Luminaria", Vector3.new(0.3, 7, 0.3), -iw * 0.2 + 2.6, 3.5, backZ + 9, METAL, Enum.Material.Metal)
		deco("Lampada", Vector3.new(1.4, 0.6, 1.4), -iw * 0.2 + 1.6, 7, backZ + 8, LAMP, Enum.Material.Neon)
		for i = 0, 4 do
			deco("Quadro", Vector3.new(0.15, 2.6, 2.2), wallL + 0.5, 5.5, backZ + 4 + i * 4, BRIGHT[rng:NextInteger(1, #BRIGHT)], Enum.Material.SmoothPlastic)
		end
		lp("Sofa", Vector3.new(2.4, 1.6, 7), wallR - 2, 0.8, (backZ + frontZ) / 2, Color3.fromRGB(150, 30, 40), Enum.Material.Fabric)
	elseif kind == "bikes" then
		counter(wallL + 4, backZ + 4, 7, "z", WOOD)
		local n = math.floor((frontZ - backZ - 6) / 4)
		for i = 0, n - 1 do
			local z = backZ + 6 + i * 4
			local c1 = BRIGHT[rng:NextInteger(1, #BRIGHT)]
			local x = iw * 0.15
			for _, k in ipairs({ -1, 1 }) do
				deco("Roda", Vector3.new(0.25, 2.6, 2.6), x + k * 1.9, 1.5, z, Color3.fromRGB(25, 25, 28), Enum.Material.Rubber, { Shape = Enum.PartType.Cylinder, CFrame = at(x + k * 1.9, 1.5, z) * CFrame.Angles(0, math.pi / 2, 0) })
			end
			deco("Quadro", Vector3.new(3.8, 0.25, 0.25), x, 2.4, z, c1, Enum.Material.Metal)
			deco("Selim", Vector3.new(0.9, 0.25, 0.5), x - 1, 3.3, z, Color3.fromRGB(30, 30, 30), Enum.Material.Fabric)
			deco("Guidao", Vector3.new(0.2, 0.2, 1.6), x + 1.6, 3.4, z, METAL, Enum.Material.Metal)
		end
		shelfWall(wallR - 0.8, backZ + 3, frontZ, 2, -1)
	end
end

return OrlaShops
