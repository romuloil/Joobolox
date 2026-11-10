-- MoradiaBuilder (ModuleScript)
-- Caminho: ServerScriptService > Services > MoradiaBuilder
-- Marco 10.2 (pedido do Luís): apartamento, cobertura e mansão "de verdade". Antes o interior era
-- um cômodo montado longe da cidade, com a vista pintada na janela. Agora a moradia fica NO LUGAR:
--   * apartamento = um andar inteiro do prédio, com vidro em volta (dá para ver a cidade), sacada,
--     cozinha, banheiro e o elevador;
--   * cobertura = o último andar, com escada para o terraço (piscina, hidro, pergolado, heliponto);
--   * mansão = casa grande de 3 andares no estilo das fotos dele: vidro do chão ao teto, andar de
--     cima em balanço, sacada, deck com piscina de vidro, cinema, terraço no telhado.
-- Quem chama é o HorizonteBuilder (prédios e mansões do Bairro Horizonte).
-- O HomeService lê estas peças no modelo da moradia (Map.Houses):
--   Door = porta de fora (entrar/comprar); SaidaPorta = porta de dentro ("Sair");
--   Entrada = onde a pessoa aparece ao entrar; Origem = centro do chão onde ficam os móveis do
--   dono (tamanho do cômodo = HomeConfig.Tiers[nível].Room); Limite = caixas invisíveis da casa
--   (quem sai delas, por exemplo pulando da sacada, deixa de estar "dentro").
-- Coisas para mexer: peças com o atributo Toggle (TV, Luz, Fogo, Agua), ligadas pelo PropService.
-- Coordenadas: at(x, y, z) = do lote ou do prédio, frente (rua) em -Z.

local MoradiaBuilder = {}

local K -- ferramentas do MapBuilder
local palmFn -- palmeira do HorizonteBuilder

local WHITE = Color3.fromRGB(246, 245, 241)
local DARK = Color3.fromRGB(40, 42, 48)
local STONE = Color3.fromRGB(150, 146, 140)
local STONE_LIGHT = Color3.fromRGB(205, 200, 192)
local MARBLE = Color3.fromRGB(236, 233, 228)
local GLASS = Color3.fromRGB(185, 215, 232) -- vidro transparente (dá para ver através)
local GLASS_DARK = Color3.fromRGB(45, 60, 78)
local POOL_GLASS = Color3.fromRGB(110, 190, 230)
local WATER = Color3.fromRGB(70, 175, 230)
local POOL_TILE = Color3.fromRGB(120, 200, 235)
local LAWN = Color3.fromRGB(112, 178, 82)
local HEDGE = Color3.fromRGB(70, 140, 60)
local STEEL = Color3.fromRGB(190, 195, 200)
local CABINET = Color3.fromRGB(60, 62, 68)
local WOOD = Color3.fromRGB(150, 100, 60)
local WOOD_LIGHT = Color3.fromRGB(190, 145, 95)
local FABRIC = Color3.fromRGB(225, 220, 208)
local GOLD = Color3.fromRGB(215, 175, 80)
local NEON_WARM = Color3.fromRGB(255, 240, 215)
local M = Enum.Material

local RAIL_H = 4.4 -- guarda-corpo de vidro
local BARRIER_H = 9 -- parede invisível em cima do guarda-corpo (o pulo do Roblox passa de 7 studs)

---------------------------------------------------------------------------
-- Peças
---------------------------------------------------------------------------

-- extra: shape, transparency, reflectance, collide, class, shadow
local function P(parent, name, size, cf, color, material, extra)
	extra = extra or {}
	local p = K.makePart(parent, {
		ClassName = extra.class,
		Name = name,
		Size = size,
		CFrame = cf,
		Color = color,
		Material = material,
		Shape = extra.shape,
		Transparency = extra.transparency,
		Reflectance = extra.reflectance,
		CanCollide = extra.collide,
		CastShadow = extra.shadow,
	})
	return p
end

-- Caixa pelos limites (x0..x1, y0..y1, z0..z1) nas coordenadas de at()
local function box(parent, name, at, x0, x1, y0, y1, z0, z1, color, material, extra)
	local sx, sy, sz = math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0)
	return P(parent, name, Vector3.new(sx, sy, sz), at((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, material, extra)
end

-- Peça invisível de controle (não colide, não atrapalha clique nem câmera)
local function marker(parent, name, cf, size)
	local p = P(parent, name, size or Vector3.new(1, 0.2, 1), cf, WHITE, nil, { transparency = 1, collide = false, shadow = false })
	p.CanQuery = false
	p.CanTouch = false
	return p
end

local function glass(parent, at, x0, x1, y0, y1, z0, z1, name)
	return box(parent, name or "Vidro", at, x0, x1, y0, y1, z0, z1, GLASS, M.SmoothPlastic, { transparency = 0.62, reflectance = 0.05 })
end

local function barrier(parent, at, x0, x1, y0, y1, z0, z1)
	local p = box(parent, "Barreira", at, x0, x1, y0, y1, z0, z1, WHITE, nil, { transparency = 1, shadow = false })
	p.CanQuery = false
	return p
end

-- Guarda-corpo de vidro ao longo de X (em z) ou de Z (em x), com corrimão e barreira invisível
local function railX(parent, at, x0, x1, z, y)
	box(parent, "GuardaCorpo", at, x0, x1, y, y + RAIL_H, z - 0.12, z + 0.12, GLASS, M.SmoothPlastic, { transparency = 0.5, reflectance = 0.05 })
	box(parent, "Corrimao", at, x0, x1, y + RAIL_H, y + RAIL_H + 0.25, z - 0.2, z + 0.2, DARK, M.Metal, { collide = false })
	barrier(parent, at, x0, x1, y + RAIL_H, y + BARRIER_H, z - 0.1, z + 0.1)
end

local function railZ(parent, at, z0, z1, x, y)
	box(parent, "GuardaCorpo", at, x - 0.12, x + 0.12, y, y + RAIL_H, z0, z1, GLASS, M.SmoothPlastic, { transparency = 0.5, reflectance = 0.05 })
	box(parent, "Corrimao", at, x - 0.2, x + 0.2, y + RAIL_H, y + RAIL_H + 0.25, z0, z1, DARK, M.Metal, { collide = false })
	barrier(parent, at, x - 0.1, x + 0.1, y + RAIL_H, y + BARRIER_H, z0, z1)
end

-- Laje com um furo (escada, piscina): até 4 peças em volta do furo
local function slab(parent, name, at, x0, x1, z0, z1, y0, y1, color, material, hole, extra)
	if not hole then
		return box(parent, name, at, x0, x1, y0, y1, z0, z1, color, material, extra)
	end
	local hx0, hx1, hz0, hz1 = hole[1], hole[2], hole[3], hole[4]
	if hz0 > z0 then
		box(parent, name, at, x0, x1, y0, y1, z0, hz0, color, material, extra)
	end
	if hz1 < z1 then
		box(parent, name, at, x0, x1, y0, y1, hz1, z1, color, material, extra)
	end
	if hx0 > x0 then
		box(parent, name, at, x0, hx0, y0, y1, hz0, hz1, color, material, extra)
	end
	if hx1 < x1 then
		box(parent, name, at, hx1, x1, y0, y1, hz0, hz1, color, material, extra)
	end
end

-- Lance de escada ao longo de X: começa em x0 (embaixo) e anda para dir (+1/-1); faixa z0..z1;
-- y = chão de baixo. Degraus maciços (solid) ou soltos, e uma rampa invisível por cima das
-- quinas para subir sem engasgar.
local function flight(parent, at, x0, dir, z0, z1, y, n, rise, run, color, solid)
	for i = 1, n do
		local xa, xb = x0 + dir * (i - 1) * run, x0 + dir * i * run
		local top = y + i * rise
		box(parent, "Degrau", at, xa, xb, solid and y or top - 0.6, top, z0, z1, color, M.WoodPlanks)
	end
	local zc = (z0 + z1) / 2
	local a = at(x0, y + rise, zc).Position
	local b = at(x0 + dir * (n - 1) * run, y + n * rise, zc).Position
	local ramp = P(parent, "Rampa", Vector3.new(math.abs(z1 - z0), 0.4, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b) * CFrame.new(0, -0.2, 0), WHITE, nil, { transparency = 1, shadow = false })
	return ramp
end

-- Assento (Seat): o SeatService põe o "Sentar" com E
local function seat(parent, cf, size, color, text)
	local s = P(parent, "Assento", size or Vector3.new(2, 0.5, 2), cf, color or FABRIC, M.Fabric, { class = "Seat" })
	s:SetAttribute("SeatText", text or "Sofá")
	return s
end

local function toggle(part, kind, label, extra)
	part:SetAttribute("Toggle", kind)
	part:SetAttribute("Label", label)
	for k, v in pairs(extra or {}) do
		part:SetAttribute(k, v)
	end
	return part
end

local function glow(part, range, brightness)
	local light = Instance.new("PointLight")
	light.Range = range
	light.Brightness = brightness
	light.Color = Color3.fromRGB(255, 235, 205)
	light.Parent = part
	return light
end

-- Água que liga e desliga (chuveiro, hidro): bolhas/gotas desligadas no começo
local function water(part, kind)
	local e = Instance.new("ParticleEmitter")
	e.Name = "Agua"
	e.Enabled = false
	if kind == "chuveiro" then
		e.Rate = 60
		e.Lifetime = NumberRange.new(0.5, 0.7)
		e.Speed = NumberRange.new(10, 12)
		e.EmissionDirection = Enum.NormalId.Bottom
		e.Size = NumberSequence.new(0.12)
		e.Color = ColorSequence.new(Color3.fromRGB(200, 230, 255))
		e.Transparency = NumberSequence.new(0.3)
	else
		e.Rate = 25
		e.Lifetime = NumberRange.new(0.6, 1)
		e.Speed = NumberRange.new(1, 2)
		e.EmissionDirection = Enum.NormalId.Top
		e.Size = NumberSequence.new(0.35)
		e.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
		e.Transparency = NumberSequence.new(0.4)
	end
	e.Parent = part
	return e
end

local function fire(part)
	local f = Instance.new("Fire")
	f.Name = "Fogo"
	f.Enabled = false
	f.Size = 4
	f.Heat = 6
	f.Parent = part
	return f
end

local function plant(parent, at, x, y, z, size)
	size = size or 1
	box(parent, "Vaso", at, x - 0.9 * size, x + 0.9 * size, y, y + 1.8 * size, z - 0.9 * size, z + 0.9 * size, DARK, M.Slate)
	P(parent, "Planta", Vector3.new(2.8, 3.2, 2.8) * size, at(x, y + 3.2 * size, z), Color3.fromRGB(70, 150, 70), M.Grass, { shape = Enum.PartType.Ball, collide = false })
end

-- Quadro na parede (normal = lado para onde ele olha: "-z", "+z", "-x", "+x")
local function painting(parent, at, x, y, z, normal, w, h, color)
	local thin = 0.15
	if normal == "-z" or normal == "+z" then
		local s = normal == "-z" and -1 or 1
		box(parent, "Moldura", at, x - w / 2 - 0.2, x + w / 2 + 0.2, y - h / 2 - 0.2, y + h / 2 + 0.2, z, z + s * thin, DARK, nil, { collide = false })
		box(parent, "Quadro", at, x - w / 2, x + w / 2, y - h / 2, y + h / 2, z + s * thin, z + s * (thin + 0.05), color, nil, { collide = false })
	else
		local s = normal == "-x" and -1 or 1
		box(parent, "Moldura", at, x, x + s * thin, y - h / 2 - 0.2, y + h / 2 + 0.2, z - w / 2 - 0.2, z + w / 2 + 0.2, DARK, nil, { collide = false })
		box(parent, "Quadro", at, x + s * thin, x + s * (thin + 0.05), y - h / 2, y + h / 2, z - w / 2, z + w / 2, color, nil, { collide = false })
	end
end

local ART = { Color3.fromRGB(230, 120, 80), Color3.fromRGB(80, 140, 210), Color3.fromRGB(240, 200, 90), Color3.fromRGB(120, 190, 150), Color3.fromRGB(200, 110, 170) }

-- Cama de casal fixa: cabeceira em z1 (fundo), pé virado para -Z. x0..x1 de largura.
local function bedFixed(parent, at, x0, x1, z0, z1, y, blanket)
	box(parent, "Cama", at, x0, x1, y, y + 1.6, z0, z1, WOOD)
	box(parent, "Colchao", at, x0 + 0.3, x1 - 0.3, y + 1.6, y + 2.5, z0 + 0.3, z1 - 0.3, Color3.new(1, 1, 1), M.Fabric)
	box(parent, "Edredom", at, x0 + 0.2, x1 - 0.2, y + 1.6, y + 2.6, z0 + 0.2, z0 + (z1 - z0) * 0.6, blanket, M.Fabric)
	local mid = (x0 + x1) / 2
	box(parent, "Travesseiro", at, x0 + 0.8, mid - 0.3, y + 2.5, y + 3.1, z1 - 1.8, z1 - 0.6, Color3.new(1, 1, 1), M.Fabric, { collide = false })
	box(parent, "Travesseiro", at, mid + 0.3, x1 - 0.8, y + 2.5, y + 3.1, z1 - 1.8, z1 - 0.6, Color3.new(1, 1, 1), M.Fabric, { collide = false })
	box(parent, "Cabeceira", at, x0 - 0.5, x1 + 0.5, y, y + 5, z1, z1 + 0.5, WOOD_LIGHT, M.Fabric)
end

-- Sofá fixo de frente para -Z (encosto em z1). Põe assentos a cada 3 studs.
local function sofaFixed(parent, at, x0, x1, z0, z1, y, color)
	box(parent, "Sofa", at, x0, x1, y, y + 1.4, z0, z1, color, M.Fabric)
	box(parent, "SofaEncosto", at, x0, x1, y + 1.4, y + 3.6, z1 - 0.9, z1, color, M.Fabric)
	local n = math.max(1, math.floor((x1 - x0) / 3))
	local step = (x1 - x0) / n
	for i = 1, n do
		seat(parent, at(x0 + (i - 0.5) * step, y + 1.65, (z0 + z1 - 0.9) / 2), Vector3.new(step - 0.3, 0.5, z1 - z0 - 1.1), color, "Sofá")
	end
end

-- O mesmo virado para -X (encosto em x1) ou +X (encosto em x0)
local function sofaFixedX(parent, at, x0, x1, z0, z1, y, color, facing)
	box(parent, "Sofa", at, x0, x1, y, y + 1.4, z0, z1, color, M.Fabric)
	local bx0, bx1 = facing < 0 and x1 - 0.9 or x0, facing < 0 and x1 or x0 + 0.9
	box(parent, "SofaEncosto", at, bx0, bx1, y + 1.4, y + 3.6, z0, z1, color, M.Fabric)
	local n = math.max(1, math.floor((z1 - z0) / 3))
	local step = (z1 - z0) / n
	local cx = facing < 0 and (x0 + x1 - 0.9) / 2 or (x0 + x1 + 0.9) / 2
	for i = 1, n do
		seat(parent, at(cx, y + 1.65, z0 + (i - 0.5) * step), Vector3.new(x1 - x0 - 1.1, 0.5, step - 0.3), color, "Sofá")
	end
end

local function stool(parent, at, x, y, z, color)
	box(parent, "PeBanqueta", at, x - 0.2, x + 0.2, y, y + 2.4, z - 0.2, z + 0.2, DARK, M.Metal)
	seat(parent, at(x, y + 2.6, z), Vector3.new(1.6, 0.4, 1.6), color or DARK, "Banqueta")
end

local function chair(parent, at, x, y, z, color, backAt)
	seat(parent, at(x, y + 1.8, z), Vector3.new(2, 0.4, 2), color or WOOD, "Cadeira")
	box(parent, "PeCadeira", at, x - 0.25, x + 0.25, y, y + 1.6, z - 0.25, z + 0.25, DARK, M.Metal, { collide = false })
	if backAt == "+z" then
		box(parent, "EncostoCadeira", at, x - 1, x + 1, y + 2, y + 4.2, z + 0.8, z + 1, color or WOOD, nil, { collide = false })
	elseif backAt == "-z" then
		box(parent, "EncostoCadeira", at, x - 1, x + 1, y + 2, y + 4.2, z - 1, z - 0.8, color or WOOD, nil, { collide = false })
	end
end

local function lounger(parent, at, x, y, z0, z1)
	box(parent, "Espreguicadeira", at, x - 1.3, x + 1.3, y, y + 1, z0, z1, WHITE)
	seat(parent, at(x, y + 1.2, (z0 + z1) / 2 - 0.6), Vector3.new(2.4, 0.4, z1 - z0 - 1.6), Color3.fromRGB(240, 238, 230), "Espreguiçadeira")
	box(parent, "EncostoEsp", at, x - 1.3, x + 1.3, y + 1, y + 2.6, z1 - 1.2, z1, WHITE, nil, { collide = false })
end

-- Luz pendente de neon (sem PointLight) e luz de teto com PointLight
local function pendant(parent, at, x, y, z)
	box(parent, "Fio", at, x - 0.05, x + 0.05, y - 2, y, z - 0.05, z + 0.05, DARK, nil, { collide = false })
	P(parent, "Pendente", Vector3.new(1.2, 1.2, 1.2), at(x, y - 2.4, z), NEON_WARM, M.Neon, { shape = Enum.PartType.Ball, collide = false, shadow = false })
end

local function ceilingLight(parent, at, x, y, z, lit, range)
	local p = box(parent, "Lampada", at, x - 1.5, x + 1.5, y - 0.15, y, z - 1.5, z + 1.5, NEON_WARM, M.Neon, { collide = false, shadow = false })
	if lit then
		glow(p, range or 22, 0.5)
	end
	return p
end

---------------------------------------------------------------------------
-- Andar de apartamento (e o andar de baixo da cobertura)
---------------------------------------------------------------------------

-- tower = modelo do prédio (vidro, lajes, sacada); unit = modelo da unidade em Map.Houses (o que é
-- da moradia: núcleo do elevador, cozinha, banheiro, marcas do HomeService).
-- base = altura de baixo da laje; o = { w, d, h, stairs (cobertura), extraTop, trim }
-- Devolve: fy (altura do piso), zb0 (frente da faixa do fundo)
local function apartmentFloor(tower, unit, at, base, o)
	local w, d, h = o.w, o.d, o.h
	local hw, hd = w / 2, d / 2
	local fy = base + 0.8
	local top = base + h
	local trim = o.trim or WHITE

	-- Laje, piso e as 4 paredes de vidro (com a porta da sacada na frente)
	box(tower, "Laje", at, -hw, hw, base, fy, -hd, hd, WHITE)
	box(unit, "Piso", at, -hw + 0.4, hw - 0.4, fy, fy + 0.05, -hd + 0.4, hd - 0.4, o.floor or Color3.fromRGB(205, 175, 135), o.floorMaterial or M.WoodPlanks, { collide = false })
	glass(tower, at, -hw, -3, fy, top, -hd, -hd + 0.4)
	glass(tower, at, 3, hw, fy, top, -hd, -hd + 0.4)
	glass(tower, at, -3, 3, fy + 8.4, top, -hd, -hd + 0.4)
	box(tower, "PortaSacada", at, -3.2, 3.2, fy + 8.2, fy + 8.4, -hd - 0.1, -hd + 0.5, DARK, M.Metal, { collide = false })
	glass(tower, at, -hw, hw, fy, top, hd - 0.4, hd)
	glass(tower, at, -hw, -hw + 0.4, fy, top, -hd + 0.4, hd - 0.4)
	glass(tower, at, hw - 0.4, hw, fy, top, -hd + 0.4, hd - 0.4)
	-- montantes por fora (poucos: não tapam a vista) e quinas
	for _, x in ipairs({ -hw / 2, hw / 2 }) do
		box(tower, "Montante", at, x - 0.2, x + 0.2, fy, top, -hd - 0.35, -hd, DARK, M.Metal, { collide = false })
		box(tower, "Montante", at, x - 0.2, x + 0.2, fy, top, hd, hd + 0.35, DARK, M.Metal, { collide = false })
	end
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			box(tower, "Quina", at, sx * hw - 0.7, sx * hw + 0.7, fy, top, sz * hd - 0.7, sz * hd + 0.7, trim)
		end
	end

	-- Sacada na frente (laje, guarda-corpo, 2 cadeiras e mesinha)
	box(tower, "Sacada", at, -hw + 3, hw - 3, fy - 0.6, fy, -hd - 5, -hd, WHITE)
	box(tower, "PisoSacada", at, -hw + 3.2, hw - 3.2, fy, fy + 0.05, -hd - 4.8, -hd, WOOD_LIGHT, M.WoodPlanks, { collide = false })
	railX(tower, at, -hw + 3, hw - 3, -hd - 4.85, fy)
	railZ(tower, at, -hd - 5, -hd, -hw + 3.15, fy)
	railZ(tower, at, -hd - 5, -hd, hw - 3.15, fy)
	for _, x in ipairs({ -9, -4 }) do
		chair(unit, at, x, fy, -hd - 2.4, WHITE)
	end
	box(unit, "MesinhaSacada", at, -7.3, -5.7, fy, fy + 2.4, -hd - 3, -hd - 1.6, WHITE)
	plant(unit, at, hw - 5.5, fy, -hd - 2.5, 0.8)

	-- Faixa do fundo: elevador no meio, cozinha à esquerda, banheiro (ou escada) à direita
	local zb1 = hd - 0.4
	local zb0 = zb1 - 9
	box(unit, "Wall", at, -5, 5, fy, top, zb0, zb1, Color3.fromRGB(235, 228, 215), M.SmoothPlastic)
	box(unit, "Moldura", at, -2.8, 2.8, fy, fy + 8.4, zb0 - 0.15, zb0, DARK, M.Metal)
	local exit = box(unit, "SaidaPorta", at, -2.2, 2.2, fy, fy + 7.8, zb0 - 0.4, zb0 - 0.15, STEEL, M.Metal)
	box(unit, "Fresta", at, -0.04, 0.04, fy, fy + 7.8, zb0 - 0.45, zb0 - 0.4, Color3.fromRGB(110, 112, 118), nil, { collide = false })
	box(unit, "PainelElevador", at, 3.2, 4, fy + 3.6, fy + 5.2, zb0 - 0.1, zb0, DARK, nil, { collide = false })
	box(unit, "BotaoElevador", at, 3.45, 3.75, fy + 4.6, fy + 4.9, zb0 - 0.2, zb0 - 0.1, Color3.fromRGB(255, 190, 60), M.Neon, { collide = false })

	-- Cozinha: geladeira, bancada com cooktop e pia, armários em cima e ilha com banquetas
	local kx0, kx1 = -hw + 0.4, -5
	box(unit, "Geladeira", at, kx0 + 0.2, kx0 + 3.8, fy, fy + 7.4, zb1 - 3, zb1, STEEL, M.Metal)
	box(unit, "Puxador", at, kx0 + 3.8, kx0 + 3.95, fy + 3, fy + 6, zb1 - 2.6, zb1 - 2.4, DARK, M.Metal, { collide = false })
	box(unit, "Bancada", at, kx0 + 4, kx1 - 0.2, fy, fy + 3, zb1 - 2.6, zb1, CABINET)
	box(unit, "Tampo", at, kx0 + 4, kx1 - 0.2, fy + 3, fy + 3.25, zb1 - 2.8, zb1, MARBLE, M.Marble)
	box(unit, "Cooktop", at, -15, -12, fy + 3.25, fy + 3.3, zb1 - 2.3, zb1 - 0.5, Color3.fromRGB(20, 20, 24), nil, { collide = false })
	box(unit, "Pia", at, -10, -7.5, fy + 3.2, fy + 3.3, zb1 - 2.3, zb1 - 0.6, STEEL, M.Metal, { collide = false })
	box(unit, "Torneira", at, -8.9, -8.6, fy + 3.3, fy + 4.6, zb1 - 0.6, zb1 - 0.3, STEEL, M.Metal, { collide = false })
	box(unit, "Armarios", at, kx0 + 4, kx1 - 0.2, fy + 5.8, fy + 8.4, zb1 - 1.4, zb1, Color3.fromRGB(235, 232, 226))
	box(unit, "Coifa", at, -15, -12, fy + 5.2, fy + 5.8, zb1 - 2.2, zb1 - 1.4, STEEL, M.Metal, { collide = false })
	box(unit, "Ilha", at, -22, -9, fy, fy + 3, zb0 + 0.8, zb0 + 3.2, CABINET)
	box(unit, "TampoIlha", at, -22.3, -8.7, fy + 3, fy + 3.25, zb0 + 0.2, zb0 + 3.4, MARBLE, M.Marble)
	for _, x in ipairs({ -20, -15.5, -11 }) do
		stool(unit, at, x, fy, zb0 - 0.9, Color3.fromRGB(70, 70, 76))
	end
	pendant(unit, at, -18.5, top, zb0 + 2)
	pendant(unit, at, -12.5, top, zb0 + 2)

	if o.stairs then
		-- cobertura: escada para o terraço no lugar do banheiro (sobe de x = hw para o elevador)
		local n = 17
		flight(unit, at, hw - 0.6, -1, zb0 + 1.5, zb0 + 6.5, fy, n, (top + 0.8 - fy) / n, 1.25, WOOD_LIGHT, true)
	else
		-- Banheiro: parede com vão, vidro fosco no fundo, box com chuveiro, vaso e pia com espelho
		box(unit, "Wall", at, 5, 8, fy, top, zb0, zb0 + 0.4, Color3.fromRGB(235, 228, 215))
		box(unit, "Wall", at, 11.5, hw - 0.4, fy, top, zb0, zb0 + 0.4, Color3.fromRGB(235, 228, 215))
		box(unit, "Wall", at, 8, 11.5, fy + 8, top, zb0, zb0 + 0.4, Color3.fromRGB(235, 228, 215))
		box(unit, "VidroFosco", at, 5, hw - 0.4, fy, top, zb1 - 0.15, zb1, Color3.new(1, 1, 1), nil, { transparency = 0.2 })
		box(unit, "VidroFosco", at, hw - 0.55, hw - 0.4, fy, top, zb0 + 0.4, zb1, Color3.new(1, 1, 1), nil, { transparency = 0.2 })
		box(unit, "PisoBanheiro", at, 5, hw - 0.4, fy + 0.05, fy + 0.1, zb0 + 0.4, zb1, Color3.fromRGB(225, 225, 228), M.Slate, { collide = false })
		box(unit, "Pia", at, 5, 7.4, fy, fy + 3.2, zb0 + 1.5, zb0 + 6.5, CABINET)
		box(unit, "TampoPia", at, 5, 7.6, fy + 3.2, fy + 3.45, zb0 + 1.4, zb0 + 6.6, MARBLE, M.Marble)
		box(unit, "Espelho", at, 5, 5.15, fy + 4.2, fy + 7.6, zb0 + 1.8, zb0 + 6.2, Color3.fromRGB(215, 230, 240), nil, { reflectance = 0.5, collide = false })
		box(unit, "Vaso", at, 14.5, 16.7, fy, fy + 1.7, zb1 - 3.2, zb1 - 0.8, Color3.new(1, 1, 1))
		box(unit, "Caixa", at, 14.6, 16.6, fy + 1.7, fy + 3.6, zb1 - 1.4, zb1 - 0.4, Color3.new(1, 1, 1))
		box(unit, "Ralo", at, hw - 6, hw - 0.6, fy, fy + 0.3, zb1 - 5, zb1 - 0.2, Color3.new(1, 1, 1))
		box(unit, "VidroBox", at, hw - 6.2, hw - 6, fy + 0.3, fy + 8, zb1 - 5, zb1 - 0.2, GLASS, nil, { transparency = 0.5 })
		box(unit, "VidroBox", at, hw - 6, hw - 3.4, fy + 0.3, fy + 8, zb1 - 5.2, zb1 - 5, GLASS, nil, { transparency = 0.5 })
		local shower = box(unit, "Chuveiro", at, hw - 3.8, hw - 2.2, fy + 8, fy + 8.25, zb1 - 3.2, zb1 - 1.6, STEEL, M.Metal, { collide = false })
		water(shower, "chuveiro")
		toggle(shower, "Agua", "Chuveiro")
		ceilingLight(unit, at, 12, top, zb0 + 4.5, false)
		painting(unit, at, 19, fy + 5.2, zb0, "-z", 5, 3.2, ART[(math.floor(base) % #ART) + 1])
	end

	-- Cortinas nos cantos da frente e plafons no teto da sala
	for _, s in ipairs({ -1, 1 }) do
		box(unit, "Cortina", at, s * (hw - 0.6) - 1.5, s * (hw - 0.6) + 1.5, fy + 0.2, top - 0.3, -hd + 0.5, -hd + 0.9, FABRIC, M.Fabric, { collide = false })
	end
	box(unit, "Trilho", at, -hw + 0.4, hw - 0.4, top - 0.3, top, -hd + 0.4, -hd + 1, DARK, nil, { collide = false })
	local zr0, zr1 = -hd + 0.4, zb0 - 2.5 -- área dos móveis do dono
	local zc = (zr0 + zr1) / 2
	for _, x in ipairs({ -hw / 2, hw / 2 }) do
		for _, z in ipairs({ zc - (zr1 - zr0) / 4, zc + (zr1 - zr0) / 4 }) do
			ceilingLight(unit, at, x, top, z, false)
		end
	end

	-- Marcas do HomeService
	marker(unit, "Origem", at(0, fy, zc) * CFrame.Angles(0, math.pi, 0)) -- -Z dos móveis = elevador
	local e = at(0, fy, zb0 - 4).Position
	marker(unit, "Entrada", CFrame.lookAt(e, at(0, fy, -hd).Position))
	local lim = box(unit, "Limite", at, -hw - 0.5, hw + 0.5, base, top + (o.extraTop or 0), -hd - 5.5, hd + 0.5, WHITE, nil, { transparency = 1, collide = false, shadow = false })
	lim.CanQuery = false
	lim.CanTouch = false
	unit:SetAttribute("InPlace", true)
	unit:SetAttribute("ExitText", "Elevador")
	exit.CanCollide = true
	return fy, zb0
end

function MoradiaBuilder.init(helpers, palm)
	K = helpers
	palmFn = palm
end

-- Apartamento: um andar do prédio. base = altura de baixo da laje.
function MoradiaBuilder.apartment(tower, unit, at, base, o)
	apartmentFloor(tower, unit, at, base, o)
end

---------------------------------------------------------------------------
-- Cobertura: o último andar (como o apartamento, com escada) e o terraço no telhado
---------------------------------------------------------------------------

-- base = topo do prédio. o = { w, d, h, name, accent, helipad }. Devolve a altura do terraço.
function MoradiaBuilder.penthouse(tower, unit, at, base, o)
	local w, d, h = o.w, o.d, o.h
	local hw, hd = w / 2, d / 2
	local _, zb0 = apartmentFloor(tower, unit, at, base, { w = w, d = d, h = h, stairs = true, extraTop = 14, floor = MARBLE, floorMaterial = M.Marble })
	local roof = base + h + 0.8
	local hole = { 6.8, hw - 0.4, zb0 + 1.3, zb0 + 6.7 }
	slab(tower, "Telhado", at, -hw, hw, -hd, hd, base + h, roof, WHITE, nil, hole)
	-- Marco 10.4: faixa de luz só na borda (antes era uma placa inteira de neon embaixo do
	-- telhado e aparecia no vão da escada)
	for _, e in ipairs({
		{ -hw - 0.6, hw + 0.6, -hd - 0.6, -hd + 0.4 },
		{ -hw - 0.6, hw + 0.6, hd - 0.4, hd + 0.6 },
		{ -hw - 0.6, -hw + 0.4, -hd + 0.4, hd - 0.4 },
		{ hw - 0.4, hw + 0.6, -hd + 0.4, hd - 0.4 },
	}) do
		box(tower, "FaixaLuz", at, e[1], e[2], roof - 0.55, roof - 0.2, e[3], e[4], o.accent or GOLD, M.Neon, { collide = false, shadow = false })
	end

	-- Piso do terraço: deck de madeira na frente, pedra clara no resto
	box(unit, "Deck", at, -hw + 0.4, hw - 0.4, roof, roof + 0.05, -hd + 0.4, -hd + 18, WOOD_LIGHT, M.WoodPlanks, { collide = false })
	-- Guarda-corpo em volta do telhado e do vão da escada
	railX(unit, at, -hw, hw, -hd + 0.2, roof)
	railX(unit, at, -hw, hw, hd - 0.2, roof)
	railZ(unit, at, -hd, hd, -hw + 0.2, roof)
	railZ(unit, at, -hd, hd, hw - 0.2, roof)
	railX(unit, at, hole[1], hole[2], hole[3] - 0.15, roof)
	railX(unit, at, hole[1], hole[2], hole[4] + 0.15, roof)

	-- Piscina (borda de mármore, água rasa)
	local px0, px1, pz0, pz1 = -hw + 3, -hw + 25, -hd + 3, -hd + 15
	box(unit, "PiscinaFundo", at, px0, px1, roof, roof + 0.2, pz0, pz1, POOL_TILE)
	for _, b in ipairs({ { px0 - 0.8, px1 + 0.8, pz0 - 0.8, pz0 }, { px0 - 0.8, px1 + 0.8, pz1, pz1 + 0.8 }, { px0 - 0.8, px0, pz0, pz1 }, { px1, px1 + 0.8, pz0, pz1 } }) do
		box(unit, "PiscinaBorda", at, b[1], b[2], roof, roof + 1.6, b[3], b[4], WHITE, M.Marble)
	end
	box(unit, "Piscina", at, px0, px1, roof + 0.2, roof + 1.3, pz0, pz1, WATER, nil, { transparency = 0.3, collide = false })
	-- Espreguiçadeiras e guarda-sol
	for _, x in ipairs({ 2, 6, 10, 14 }) do
		lounger(unit, at, x, roof, -hd + 3, -hd + 9)
	end
	box(unit, "GuardaSolHaste", at, 17.8, 18.2, roof, roof + 7, -hd + 5.8, -hd + 6.2, DARK, M.Metal)
	K.flatCylinder(unit, "GuardaSol", at(18, roof + 7, -hd + 6).Position, 4, 0.4, Color3.fromRGB(240, 235, 220), M.Fabric)
	-- Hidromassagem redonda (liga as bolhas)
	local jx, jz = hw - 7, -hd + 13
	K.flatCylinder(unit, "HidroBorda", at(jx, roof + 0.8, jz).Position, 3.6, 1.6, WHITE, M.Marble)
	local jw = K.flatCylinder(unit, "HidroAgua", at(jx, roof + 1.65, jz).Position, 3.1, 0.15, WATER, M.SmoothPlastic)
	jw.Transparency = 0.25
	water(jw, "hidro")
	toggle(jw, "Agua", "Hidromassagem")
	-- Pergolado com sofá em L e mesinha
	local gx0, gx1, gz0, gz1 = -hw + 2, -hw + 18, 2, 16
	for _, x in ipairs({ gx0, gx1 }) do
		for _, z in ipairs({ gz0, gz1 }) do
			box(unit, "PostePergolado", at, x - 0.3, x + 0.3, roof, roof + 9, z - 0.3, z + 0.3, WOOD, M.Wood)
		end
	end
	for k = 0, 7 do
		local z = gz0 + k * (gz1 - gz0) / 7
		box(unit, "Ripa", at, gx0 - 0.5, gx1 + 0.5, roof + 9, roof + 9.4, z - 0.2, z + 0.2, WOOD, M.Wood, { collide = false })
	end
	sofaFixed(unit, at, gx0 + 1, gx1 - 1, gz1 - 4, gz1 - 0.6, roof, Color3.fromRGB(225, 220, 205))
	sofaFixedX(unit, at, gx0 + 0.6, gx0 + 4, gz0 + 1, gz1 - 4, roof, Color3.fromRGB(225, 220, 205), 1)
	box(unit, "MesaCentro", at, gx0 + 7, gx1 - 4, roof, roof + 1.4, gz0 + 4, gz1 - 7, WOOD_LIGHT, M.Wood)
	local lamp = box(unit, "LuzPergolado", at, (gx0 + gx1) / 2 - 1, (gx0 + gx1) / 2 + 1, roof + 8.4, roof + 8.9, (gz0 + gz1) / 2 - 1, (gz0 + gz1) / 2 + 1, NEON_WARM, M.Neon, { collide = false })
	glow(lamp, 18, 0.5)
	-- Vasos
	for _, p in ipairs({ { -hw + 2.5, hd - 2.5 }, { 3, hd - 2.5 }, { hw - 2.5, 2 } }) do
		plant(unit, at, p[1], roof, p[2], 1.1)
	end
	-- Heliponto (só nos prédios que têm)
	if o.helipad then
		local pad = at(14, roof, 2).Position
		K.flatCylinder(unit, "Heliponto", pad + Vector3.new(0, 0.15, 0), 8, 0.3, DARK, M.Concrete)
		K.flatCylinder(unit, "HelipontoAnel", pad + Vector3.new(0, 0.32, 0), 7.2, 0.05, Color3.fromRGB(240, 200, 40), M.SmoothPlastic)
		K.flatCylinder(unit, "HelipontoMeio", pad + Vector3.new(0, 0.36, 0), 6.4, 0.05, DARK, M.Concrete)
		for _, x in ipairs({ 12.4, 15.6 }) do
			box(unit, "LetraH", at, x - 0.35, x + 0.35, roof + 0.39, roof + 0.42, -0.5, 4.5, WHITE, nil, { collide = false })
		end
		box(unit, "LetraH", at, 12.4, 15.6, roof + 0.39, roof + 0.42, 1.65, 2.35, WHITE, nil, { collide = false })
	end
	-- Letreiro com o nome do prédio no fundo do terraço
	for _, x in ipairs({ -hw + 4, 2 }) do
		box(tower, "PosteNome", at, x - 0.3, x + 0.3, roof, roof + 7, hd - 1.6, hd - 1.0, DARK, M.Metal)
	end
	local sign = box(tower, "NomeTopo", at, -hw + 3, 3, roof + 4, roof + 7, hd - 1.6, hd - 1.3, DARK, nil, { collide = false })
	if o.name then
		K.addSurfaceText(sign, o.name, o.accent or GOLD, DARK)
	end
	return roof
end

---------------------------------------------------------------------------
-- Mansão (3 andares, vidro, balanço, deck com piscina de vidro e terraço)
---------------------------------------------------------------------------

-- Tamanho do lote: 100 x 120 (x = largura na rua, z = fundo). Volumes (x, z):
--   térreo     x -34..18, z -22..14 (sala dos móveis do dono, cozinha, jantar, escada)
--   garagem    x  20..44, z -18..10
--   1º andar   x -40..26, z -30..12 (suíte master, banheiro com hidro, sala de TV, suíte 2)
--              + sacada na frente e deck com piscina de vidro atrás (z 12..40)
--   2º andar   x -30..20, z -20..12 (cinema, bar, sinuca) + terraço no teto do 1º andar
-- o = { wall, wood, number, helipad }
MoradiaBuilder.MANSION_W = 100
MoradiaBuilder.MANSION_D = 120

function MoradiaBuilder.mansion(house, at, o)
	local G = 0.7
	local Y0 = G + 0.8
	local Y1 = Y0 + 13.8
	local Y2 = Y1 + 12.8
	local Y3 = Y2 + 11.8
	local wall = o.wall or WHITE
	local wood = o.wood or WOOD
	local function B(name, x0, x1, y0, y1, z0, z1, color, material, extra)
		return box(house, name, at, x0, x1, y0, y1, z0, z1, color, material, extra)
	end
	local function GL(x0, x1, y0, y1, z0, z1)
		return glass(house, at, x0, x1, y0, y1, z0, z1)
	end
	local luzes = {
		K.model("LuzesTerreo", house),
		K.model("LuzesAndar1", house),
		K.model("LuzesAndar2", house),
	}

	-- Terreno: gramado, muro com portão e entrada de carro, caminho até a porta
	B("Gramado", -50, 50, 0.4, G, -60, 60, LAWN, M.Grass)
	-- Marco 10.4: muro e cerca viva mais altos (o pulo do Roblox passa de 7 studs)
	for _, seg in ipairs({ { -50, -12 }, { -4, 22 }, { 42, 50 } }) do
		B("Muro", seg[1], seg[2], G, G + 8, -60, -59, wall, M.Plaster)
		B("MuroTopo", seg[1] - 0.1, seg[2] + 0.1, G + 8, G + 8.3, -60.15, -58.85, DARK)
	end
	for _, x in ipairs({ -12, -4 }) do
		B("PilarPortao", x - 0.8, x + 0.8, G, G + 9.4, -60.3, -58.7, STONE, M.Slate)
		local l = B("LuzPortao", x - 0.5, x + 0.5, G + 9.4, G + 10, -60, -59, NEON_WARM, M.Neon, { collide = false })
		glow(l, 10, 0.4)
	end
	local plate = B("NumeroMuro", -18, -15, G + 1.6, G + 2.8, -60.1, -60.05, DARK, nil, { collide = false })
	K.addSurfaceText(plate, tostring(o.number or ""), Color3.new(1, 1, 1), DARK)
	B("EntradaCarro", 23, 41, G, G + 0.2, -59, -18, Color3.fromRGB(178, 175, 170), M.Concrete)
	for z = -57, -29, 3.5 do
		B("Pisante", -10, -6, G, G + 0.15, z, z + 2, Color3.fromRGB(200, 196, 188), M.Slate, { collide = false })
	end
	for _, x in ipairs({ -12.5, -3.5 }) do
		for z = -54, -30, 8 do
			B("Balizador", x - 0.3, x + 0.3, G, G + 1.6, z - 0.3, z + 0.3, DARK, M.Metal)
			B("BalizadorLuz", x - 0.32, x + 0.32, G + 1.3, G + 1.6, z - 0.32, z + 0.32, NEON_WARM, M.Neon, { collide = false })
		end
	end
	-- Cercas vivas e palmeiras
	B("CercaViva", -50, -48.4, G, G + 10, -59, 60, HEDGE, M.Grass)
	B("CercaViva", 48.4, 50, G, G + 10, -59, 60, HEDGE, M.Grass)
	B("CercaViva", -48.4, 48.4, G, G + 10, 58.4, 60, HEDGE, M.Grass)
	for _, p in ipairs({ { -46, -54 }, { -28, -54 }, { 8, -54 }, { 46, -54 }, { -46, -30 }, { 46, -6 }, { -46, 50 }, { -10, 54 }, { 30, 54 }, { 46, 30 } }) do
		palmFn(house, at(p[1], G, p[2]).Position, 1.05 + (p[1] % 3) * 0.08)
	end
	for _, x in ipairs({ -30, -24, 4, 10 }) do
		P(house, "Arbusto", Vector3.new(3, 2.4, 3), at(x, G + 1, -25), Color3.fromRGB(80, 155, 65), M.Grass, { shape = Enum.PartType.Ball, collide = false })
	end

	-- Base de pedra e degraus da entrada
	B("Base", -35, 19, G, Y0, -23, 15, STONE_LIGHT, M.Concrete)
	B("Degrau", -13, -3, G, G + 0.4, -26, -23, STONE_LIGHT, M.Concrete)

	-- TÉRREO --------------------------------------------------------------
	local h0 = Y1 - 0.8
	B("PisoTerreo", -33.6, 17.6, Y0, Y0 + 0.05, -21.6, 13.6, MARBLE, M.Marble, { collide = false })
	-- frente: pedra, vidro, porta e vidro
	B("Pedra", -34.6, -28, Y0, Y1, -22.8, -21.6, STONE, M.Slate)
	GL(-28, -11, Y0, h0, -22, -21.6)
	GL(-5, 18, Y0, h0, -22, -21.6)
	GL(-11, -5, Y0 + 10, h0, -22, -21.6)
	B("PortaMoldura", -11.3, -4.7, Y0, Y0 + 10.3, -22.1, -21.7, DARK, M.Metal)
	B("Door", -11, -5, Y0, Y0 + 10, -22.3, -21.9, Color3.fromRGB(70, 48, 32), M.Wood)
	B("Puxador", -6.4, -6.1, Y0 + 3.5, Y0 + 7, -22.6, -22.3, GOLD, M.Metal, { collide = false })
	local doorPlate = B("NumberPlate", -3.8, -1.8, Y0 + 7.4, Y0 + 8.4, -22.15, -22.05, DARK, nil, { collide = false })
	K.addSurfaceText(doorPlate, tostring(o.number or ""), Color3.new(1, 1, 1), DARK)
	B("Marquise", -15, -1, Y0 + 11.2, Y0 + 11.7, -28, -22, DARK, nil, { collide = false })
	for _, x in ipairs({ -12.4, -3.6 }) do
		local l = B("Arandela", x - 0.3, x + 0.3, Y0 + 6.5, Y0 + 7.7, -22.3, -22, NEON_WARM, M.Neon, { collide = false })
		glow(l, 10, 0.4)
	end
	local exit = B("SaidaPorta", -10.6, -5.4, Y0, Y0 + 9.6, -21.6, -21.45, Color3.fromRGB(70, 48, 32), M.Wood, { collide = false })
	-- fundo e lado esquerdo de vidro, direito de parede (garagem)
	-- Marco 10.6 (pedido do Luís): porta de vidro de correr no fundo do hall (x -8..-2), para a
	-- área de lazer (quintal embaixo do deck, jacuzzi, pingue-pongue)
	GL(-34, -8, Y0, h0, 13.6, 14)
	GL(-2, 18, Y0, h0, 13.6, 14)
	GL(-8, -2, Y0 + 9.6, h0, 13.6, 14)
	B("PortaFundoMoldura", -8.3, -1.7, Y0 + 9.4, Y0 + 9.7, 13.5, 14.1, DARK, M.Metal, { collide = false })
	for _, x in ipairs({ -8.15, -1.85 }) do
		B("PortaFundoMoldura", x - 0.15, x + 0.15, Y0, Y0 + 9.6, 13.5, 14.1, DARK, M.Metal, { collide = false })
	end
	box(house, "PortaFundoAberta", at, -13.8, -8.2, Y0, Y0 + 9.4, 13.2, 13.5, GLASS, M.SmoothPlastic, { transparency = 0.55, reflectance = 0.05, collide = false })
	B("DegrauFundo", -9, -1, G, G + 0.4, 14, 16.5, STONE_LIGHT, M.Concrete)
	local lazer = B("PlacaLazer", -7, -3, Y0 + 10, Y0 + 11, 13.35, 13.45, DARK, nil, { collide = false }) -- em cima da porta, por dentro
	K.addSurfaceText(lazer, "Área de lazer", Color3.fromRGB(240, 220, 160), DARK)
	GL(-34, -33.6, Y0, h0, -21.6, 13.6)
	B("ParedeGaragem", 17.6, 18.2, Y0, h0, -22, 14, wall, M.Plaster)
	for _, x in ipairs({ -22, -16, 2, 8, 14 }) do
		B("Montante", x - 0.2, x + 0.2, Y0, h0, -22.35, -22, DARK, M.Metal, { collide = false })
	end
	for x = -28, 12, 8 do
		if x < -8 or x > -2 then -- o vão da porta do fundo fica livre
			B("Montante", x - 0.2, x + 0.2, Y0, h0, 14, 14.35, DARK, M.Metal, { collide = false })
		end
	end
	-- cozinha: bancada na parede da direita, geladeira, ilha com banquetas, jantar perto do vidro
	B("Bancada", 15, 17.6, Y0, Y0 + 3, -20, -5, CABINET)
	B("Tampo", 14.8, 17.6, Y0 + 3, Y0 + 3.25, -20.2, -5, MARBLE, M.Marble)
	B("Cooktop", 15.2, 17.2, Y0 + 3.25, Y0 + 3.3, -15, -12, Color3.fromRGB(20, 20, 24), nil, { collide = false })
	B("Pia", 15.3, 17.2, Y0 + 3.2, Y0 + 3.3, -9.5, -7, STEEL, M.Metal, { collide = false })
	B("Armarios", 16.2, 17.6, Y0 + 6.4, Y0 + 9.6, -20, -5, Color3.fromRGB(235, 232, 226))
	B("Geladeira", 14.2, 17.6, Y0, Y0 + 8.4, -4.6, -1, STEEL, M.Metal)
	B("Ilha", 3, 12, Y0, Y0 + 3, -12, -8.6, CABINET)
	B("TampoIlha", 2.6, 12.4, Y0 + 3, Y0 + 3.25, -12.2, -8.2, MARBLE, M.Marble)
	for _, x in ipairs({ 4.5, 7.5, 10.5 }) do
		stool(house, at, x, Y0, -6.9)
	end
	pendant(house, at, 5, h0, -10.4)
	pendant(house, at, 10, h0, -10.4)
	B("MesaJantar", 1, 13, Y0 + 2.6, Y0 + 2.9, -19.2, -15.6, wood, M.Wood)
	B("PeMesa", 6.6, 7.4, Y0, Y0 + 2.6, -17.8, -17, DARK, M.Metal)
	for _, x in ipairs({ 3, 7, 11 }) do
		chair(house, at, x, Y0, -20.3, WHITE, "-z")
		chair(house, at, x, Y0, -14.4, WHITE, "+z")
	end
	-- hall de entrada: tapete, aparador, lustre
	B("TapeteEntrada", -11, -5, Y0 + 0.05, Y0 + 0.1, -20.5, -13, Color3.fromRGB(150, 120, 90), M.Fabric, { collide = false })
	B("Aparador", -5.2, -2.4, Y0, Y0 + 3, -9, -4, wood, M.Wood)
	plant(house, at, -3.8, Y0 + 3, -6.5, 0.6)
	local core = P(house, "Lustre", Vector3.new(2.4, 2.4, 2.4), at(-8, h0 - 4, -15), Color3.fromRGB(255, 245, 220), M.Neon, { shape = Enum.PartType.Ball, collide = false })
	core.Parent = luzes[1]
	glow(core, 26, 0.55)
	B("LustreHaste", -8.15, -7.85, h0 - 3, h0, -15.15, -14.85, GOLD, M.Metal, { collide = false })
	-- piano no fundo do hall
	-- (Marco 10.6: o piano chegou para frente, o fundo do hall virou a passagem para o quintal)
	B("Piano", -9, -3.5, Y0, Y0 + 3.4, 0, 6, Color3.fromRGB(20, 20, 22))
	B("TampaPiano", -9, -3.5, Y0 + 3.4, Y0 + 3.6, 0, 6, Color3.fromRGB(20, 20, 22), nil, { collide = false })
	B("Teclado", -9, -3.5, Y0 + 2.6, Y0 + 2.9, -0.8, 0, Color3.new(1, 1, 1), nil, { collide = false })
	seat(house, at(-6.25, Y0 + 1.8, -2.2), Vector3.new(3, 0.5, 1.4), Color3.fromRGB(20, 20, 22), "Banco do piano")
	local sw0 = toggle(B("Interruptor", -4.6, -4, Y0 + 4.2, Y0 + 5.2, -21.6, -21.4, Color3.new(1, 1, 1)), "Luz", "Luzes do térreo", { Target = "LuzesTerreo", On = true })
	sw0.CanCollide = false
	for _, z in ipairs({ -10, 4 }) do
		local l = ceilingLight(house, at, 8, h0, z, true)
		l.Parent = luzes[1]
	end

	-- ESCADA (U, do térreo ao 2º andar): poço x 0..17, z 0..11
	local run = 1.25
	box(house, "ParedeEscada", at, 0, 11.25, Y0, Y2 + 9, 5.25, 5.75, WHITE, M.Plaster)
	flight(house, at, 0, 1, 0, 5.25, Y0, 9, (Y1 - Y0) / 18, run, WOOD_LIGHT, true)
	B("Patamar", 11.25, 17, Y0, Y0 + (Y1 - Y0) / 2, 0, 11, WOOD_LIGHT, M.WoodPlanks)
	flight(house, at, 11.25, -1, 5.75, 11, Y0 + (Y1 - Y0) / 2, 9, (Y1 - Y0) / 18, run, WOOD_LIGHT, false)
	flight(house, at, 0, 1, 0, 5.25, Y1, 9, (Y2 - Y1) / 18, run, WOOD_LIGHT, false)
	B("Patamar", 11.25, 17, Y1 + (Y2 - Y1) / 2 - 0.6, Y1 + (Y2 - Y1) / 2, 0, 11, WOOD_LIGHT, M.WoodPlanks)
	flight(house, at, 11.25, -1, 5.75, 11, Y1 + (Y2 - Y1) / 2, 9, (Y2 - Y1) / 18, run, WOOD_LIGHT, false)
	local stairHole = { 0, 17, 0, 11 }

	-- GARAGEM -------------------------------------------------------------
	-- Marco 10.6 (pedido do Luís): garagem de verdade, só do dono da mansão. Portão aberto (o
	-- carro sai pela entrada de carro), 2 vagas e o painel "Abrir garagem" na parede do fundo.
	-- O painel e as vagas ficam num modelo em Map.Garages (VehicleService) com o atributo
	-- Private: o HomeService marca OwnerId = quem mora aqui, e só essa pessoa tira carro.
	B("PisoGaragem", 20.6, 43.4, G, G + 0.2, -18, 9.4, Color3.fromRGB(150, 150, 155), M.Concrete)
	B("Garagem", 20, 44, G, G + 12, 9.4, 10, wall, M.Plaster) -- fundo
	B("Garagem", 43.4, 44, G, G + 12, -18, 9.4, wall, M.Plaster) -- lado de fora
	B("Garagem", 20, 20.6, G, G + 12, -18, 9.4, wall, M.Plaster) -- lado da casa
	B("TetoGaragem", 19.5, 44.5, G + 12, G + 12.6, -18.5, 10.5, DARK)
	B("PortaoGaragem", 22, 42, G + 9.8, G + 12, -18.35, -18, GLASS_DARK, nil, { reflectance = 0.3 }) -- portão enrolado lá em cima
	B("MadeiraGaragem", 42, 44, G, G + 12, -18.3, -18, wood, M.WoodPlanks)
	B("MadeiraGaragem", 20, 22, G, G + 12, -18.3, -18, wood, M.WoodPlanks)
	for _, x in ipairs({ 26, 32, 38 }) do
		local l = B("LuzGaragem", x - 0.6, x + 0.6, G + 10, G + 10.4, -18.6, -18.3, NEON_WARM, M.Neon, { collide = false })
		l.CastShadow = false
	end
	for _, x in ipairs({ 26.5, 37.5 }) do
		local l = B("LuzGaragem", x - 2, x + 2, G + 11.75, G + 12, -6, -4, NEON_WARM, M.Neon, { collide = false })
		l.CastShadow = false
		B("FaixaVaga", x - 4.7, x - 4.4, G + 0.2, G + 0.23, -16, 8, Color3.fromRGB(245, 200, 40), nil, { collide = false })
	end
	if o.garages then
		local g = K.model("GaragemMansao" .. tostring(o.id or ""), o.garages)
		g:SetAttribute("Private", true)
		g:SetAttribute("HouseNumber", o.id)
		local panel = box(g, "Balcao", at, 30.5, 33.5, Y0 + 2.4, Y0 + 4.6, 9, 9.4, Color3.fromRGB(30, 60, 120))
		panel.CanCollide = false
		K.addSurfaceText(panel, "GARAGEM", Color3.new(1, 1, 1), Color3.fromRGB(30, 60, 120))
		for k, x in ipairs({ 26.5, 37.5 }) do
			local vaga = marker(g, "Vaga" .. k, at(x, G + 0.7, -5))
			vaga.Size = Vector3.new(1, 1, 1)
		end
		house:SetAttribute("Garagem", g.Name)
	end

	-- 1º ANDAR ------------------------------------------------------------
	local h1 = Y2 - 0.8
	slab(house, "Laje1", at, -40, 26, -30, 12, Y1 - 0.8, Y1, WHITE, nil, stairHole)
	slab(house, "Piso1", at, -39.6, 25.6, -29.6, 11.6, Y1, Y1 + 0.05, Color3.fromRGB(205, 175, 135), M.WoodPlanks, stairHole, { collide = false })
	B("Sacada", -38, 14, Y1 - 0.8, Y1, -36, -30, WHITE)
	B("PisoSacada", -37.8, 13.8, Y1, Y1 + 0.05, -35.8, -30, WOOD_LIGHT, M.WoodPlanks, { collide = false })
	railX(house, at, -38, 14, -35.85, Y1)
	railZ(house, at, -36, -30, -37.85, Y1)
	railZ(house, at, -36, -30, 13.85, Y1)
	-- deck com a piscina de vidro (a piscina fica pendurada, dá para ver a água de baixo)
	local poolHole = { -30, 6, 18, 34 }
	slab(house, "Deck", at, -40, 26, 12, 40, Y1 - 0.8, Y1, WHITE, nil, poolHole)
	slab(house, "PisoDeck", at, -40, 26, 12, 40, Y1, Y1 + 0.05, WOOD_LIGHT, M.WoodPlanks, poolHole, { collide = false })
	B("FundoPiscina", -30, 6, Y1 - 4.6, Y1 - 4, 18, 34, POOL_TILE)
	box(house, "VidroPiscina", at, -30, -29.6, Y1 - 4, Y1, 18, 34, POOL_GLASS, nil, { transparency = 0.35 })
	box(house, "VidroPiscina", at, 5.6, 6, Y1 - 4, Y1, 18, 34, POOL_GLASS, nil, { transparency = 0.35 })
	box(house, "VidroPiscina", at, -29.6, 5.6, Y1 - 4, Y1, 18, 18.4, POOL_GLASS, nil, { transparency = 0.35 })
	box(house, "VidroPiscina", at, -29.6, 5.6, Y1 - 4, Y1, 33.6, 34, POOL_GLASS, nil, { transparency = 0.35 })
	B("Agua", -29.6, 5.6, Y1 - 4, Y1 - 0.4, 18.4, 33.6, WATER, nil, { transparency = 0.45, collide = false })
	for _, b in ipairs({ { -31, 7, 17, 18 }, { -31, 7, 34, 35 }, { -31, -30, 18, 34 }, { 6, 7, 18, 34 } }) do
		B("BordaPiscina", b[1], b[2], Y1, Y1 + 0.3, b[3], b[4], WHITE, M.Marble)
	end
	B("DegrauPiscina", 3.6, 5.6, Y1 - 2.4, Y1 - 2, 24, 28, WHITE, M.Marble)
	railX(house, at, -40, 26, 39.85, Y1)
	railZ(house, at, 12, 40, -39.85, Y1)
	railZ(house, at, 12, 40, 25.85, Y1)
	for _, x in ipairs({ 11, 15, 19, 23 }) do
		lounger(house, at, x, Y1, 22, 28)
	end
	B("GuardaSolHaste", 16.8, 17.2, Y1, Y1 + 7, 31.8, 32.2, DARK, M.Metal)
	K.flatCylinder(house, "GuardaSol", at(17, Y1 + 7, 32).Position, 4.5, 0.4, Color3.fromRGB(240, 235, 220), M.Fabric)
	B("MesaDeck", -38, -33, Y1 + 2.6, Y1 + 2.9, 22, 30, wood, M.Wood)
	for _, z in ipairs({ 23.5, 26, 28.5 }) do
		chair(house, at, -38.8, Y1, z, WHITE)
		chair(house, at, -32.2, Y1, z, WHITE)
	end
	plant(house, at, -37, Y1, 37, 1)
	plant(house, at, 23, Y1, 37, 1)
	-- pilares embaixo do deck
	for _, p in ipairs({ { -40, 40 }, { -12, 40 }, { 10, 40 }, { 26, 40 }, { -40, 26 }, { 26, 26 } }) do
		B("Pilar", p[1] - 0.6, p[1] + 0.6, G, Y1 - 0.8, p[2] - 0.6, p[2] + 0.6, WHITE)
	end
	-- paredes do 1º andar: vidro na frente (vão para a sacada), atrás (vão para o deck) e na esquerda
	GL(-40, -23, Y1, h1, -30, -29.6)
	GL(-17, 26, Y1, h1, -30, -29.6)
	GL(-23, -17, Y1 + 8.6, h1, -30, -29.6)
	GL(-40, -12, Y1, h1, 11.6, 12)
	GL(-4, 26, Y1, h1, 11.6, 12)
	GL(-12, -4, Y1 + 8.6, h1, 11.6, 12)
	GL(-40, -39.6, Y1, h1, -29.6, 11.6)
	B("MadeiraLateral", 25.6, 26.3, Y1, h1, -30, 12, wood, M.WoodPlanks)
	for _, x in ipairs({ -34, -28, -10, -4, 2, 8, 14, 20 }) do
		B("Montante", x - 0.2, x + 0.2, Y1, h1, -30.35, -30, DARK, M.Metal, { collide = false })
	end
	-- divisórias (pintáveis): suíte master | banheiro, suíte | sala, sala | suíte 2, suíte 2 | escada
	local WALL_IN = Color3.fromRGB(240, 236, 228)
	B("Wall", -39.6, -20, Y1, h1, -2.2, -1.8, WALL_IN)
	B("Wall", -16, -14, Y1, h1, -2.2, -1.8, WALL_IN)
	B("Wall", -20, -16, Y1 + 8.6, h1, -2.2, -1.8, WALL_IN)
	B("Wall", -14.2, -13.8, Y1, h1, -29.6, -8, WALL_IN)
	B("Wall", -14.2, -13.8, Y1, h1, -4, 11.6, WALL_IN)
	B("Wall", -14.2, -13.8, Y1 + 8.6, h1, -8, -4, WALL_IN)
	B("Wall", -0.2, 0.2, Y1, h1, -29.6, -10, WALL_IN)
	B("Wall", -0.2, 0.2, Y1, h1, -6, -1.2, WALL_IN)
	B("Wall", -0.2, 0.2, Y1 + 8.6, h1, -10, -6, WALL_IN)
	B("Wall", 0, 25.6, Y1, h1, -1.2, -0.8, WALL_IN)
	railZ(house, at, 0, 11, 17.15, Y1)
	-- suíte master: cama king virada para a sacada, criados-mudos, guarda-roupa, poltrona
	bedFixed(house, at, -31, -22, -12, -2.6, Y1, Color3.fromRGB(70, 90, 140))
	for _, x in ipairs({ -33.4, -19.6 }) do
		B("CriadoMudo", x - 1.2, x + 1.2, Y1, Y1 + 2.2, -4.6, -2.4, wood, M.Wood)
		local l = B("Abajur", x - 0.5, x + 0.5, Y1 + 2.2, Y1 + 3.8, -4, -3, NEON_WARM, M.Neon, { collide = false })
		l.Parent = luzes[2]
	end
	B("GuardaRoupa", -16.6, -14.2, Y1, Y1 + 9.4, -27, -12, wood, M.Wood)
	B("TapeteSuite", -33, -20, Y1 + 0.05, Y1 + 0.1, -18, -8, Color3.fromRGB(200, 190, 175), M.Fabric, { collide = false })
	seat(house, at(-35, Y1 + 1.6, -24), Vector3.new(3, 0.6, 3), Color3.fromRGB(190, 110, 70), "Poltrona")
	box(house, "PoltronaBase", at, -36.5, -33.5, Y1, Y1 + 1.3, -25.5, -22.5, Color3.fromRGB(190, 110, 70), M.Fabric)
	-- banheiro da suíte: hidro, bancada dupla, box, vaso, vidro fosco
	B("VidroFosco", -39.6, -14.2, Y1, h1, 11.2, 11.6, Color3.new(1, 1, 1), nil, { transparency = 0.2 })
	B("VidroFosco", -39.6, -39.2, Y1, h1, -1.8, 11.6, Color3.new(1, 1, 1), nil, { transparency = 0.2 })
	B("PisoBanheiro", -39.6, -14.2, Y1 + 0.05, Y1 + 0.1, -1.8, 11.6, Color3.fromRGB(225, 225, 228), M.Slate, { collide = false })
	B("Hidromassagem", -37, -28, Y1, Y1 + 2.6, 2, 10, WHITE, M.Marble)
	local hidro = B("AguaHidro", -36.4, -28.6, Y1 + 1.8, Y1 + 2.4, 2.6, 9.4, WATER, nil, { transparency = 0.3, collide = false })
	water(hidro, "hidro")
	toggle(hidro, "Agua", "Hidromassagem")
	B("BancadaBanheiro", -16.6, -14.2, Y1, Y1 + 3.2, 0, 9, CABINET)
	B("TampoBanheiro", -16.8, -14.2, Y1 + 3.2, Y1 + 3.45, -0.2, 9.2, MARBLE, M.Marble)
	B("Espelho", -14.4, -14.2, Y1 + 4.2, Y1 + 8.4, 0.5, 8.5, Color3.fromRGB(215, 230, 240), nil, { reflectance = 0.5, collide = false })
	B("Ralo", -24, -18, Y1, Y1 + 0.3, 6, 11.2, WHITE)
	B("VidroBox", -24.2, -24, Y1 + 0.3, Y1 + 8.6, 6, 11.2, GLASS, nil, { transparency = 0.5 })
	local shower = B("Chuveiro", -21.8, -20.2, Y1 + 8.6, Y1 + 8.85, 7.8, 9.4, STEEL, M.Metal, { collide = false })
	water(shower, "chuveiro")
	toggle(shower, "Agua", "Chuveiro")
	B("Vaso", -26.5, -24.5, Y1, Y1 + 1.7, -1.6, 0.8, Color3.new(1, 1, 1))
	-- sala de TV (entre as suítes): TV na parede, sofá, lareira, tapete
	local tv = B("TVSala", -13.8, -13.5, Y1 + 3, Y1 + 8.4, -21, -11, Color3.fromRGB(20, 20, 24))
	toggle(tv, "TV", "TV")
	sofaFixedX(house, at, -5.6, -2.2, -21, -11, Y1, Color3.fromRGB(80, 80, 88), -1)
	B("TapeteSala", -12, -6.4, Y1 + 0.05, Y1 + 0.1, -20, -12, Color3.fromRGB(150, 60, 50), M.Fabric, { collide = false })
	B("MesaCentro", -10.5, -7.5, Y1, Y1 + 1.4, -18, -14, wood, M.Wood)
	B("Lareira", -1.6, -0.2, Y1, Y1 + 4, -27, -21, STONE, M.Slate)
	local fireBox = B("Fornalha", -1.7, -1.5, Y1 + 0.6, Y1 + 2.8, -26, -22, Color3.fromRGB(15, 15, 15))
	fire(fireBox)
	toggle(fireBox, "Fogo", "Lareira")
	plant(house, at, -12, Y1, 9.5, 1)
	plant(house, at, -2.2, Y1, -28, 0.9)
	painting(house, at, -0.2, Y1 + 6, -16, "-x", 6, 4, ART[2])
	local sw1 = toggle(B("Interruptor", -0.6, -0.2, Y1 + 4.2, Y1 + 5.2, -3.8, -3.2, Color3.new(1, 1, 1)), "Luz", "Luzes do 1º andar", { Target = "LuzesAndar1", On = true })
	sw1.CanCollide = false
	-- suíte 2: cama, escrivaninha perto do vidro, guarda-roupa
	bedFixed(house, at, 14, 21, -12, -1.6, Y1, Color3.fromRGB(200, 120, 90))
	B("GuardaRoupa2", 23.2, 25.6, Y1, Y1 + 9.4, -26, -16, wood, M.Wood)
	B("Escrivaninha", 2, 9, Y1 + 2.8, Y1 + 3.1, -28.6, -25.8, Color3.new(1, 1, 1))
	B("PeEscrivaninha", 2, 2.4, Y1, Y1 + 2.8, -28.6, -25.8, Color3.new(1, 1, 1))
	B("PeEscrivaninha", 8.6, 9, Y1, Y1 + 2.8, -28.6, -25.8, Color3.new(1, 1, 1))
	chair(house, at, 5.5, Y1, -24.4, DARK, "+z")
	B("Monitor", 4, 7, Y1 + 3.1, Y1 + 5.2, -28.4, -28.1, Color3.fromRGB(20, 20, 24))
	for _, p in ipairs({ { -26, -18 }, { -7, -6 }, { 17, -20 }, { -26, 5 } }) do
		local l = ceilingLight(house, at, p[1], h1, p[2], true, 20)
		l.Parent = luzes[2]
	end

	-- 2º ANDAR (cinema) E TERRAÇO ----------------------------------------
	local h2 = Y3 - 0.8
	slab(house, "Laje2", at, -40, 26, -30, 12, Y2 - 0.8, Y2, WHITE, nil, stairHole)
	slab(house, "Piso2", at, -29.6, 19.6, -19.6, 11.6, Y2, Y2 + 0.05, Color3.fromRGB(60, 50, 45), M.WoodPlanks, stairHole, { collide = false })
	B("PisoTerraco", -39.8, 25.8, Y2, Y2 + 0.05, -29.8, -20, WOOD_LIGHT, M.WoodPlanks, { collide = false })
	B("PisoTerraco", -39.8, -30, Y2, Y2 + 0.05, -20, 11.8, WOOD_LIGHT, M.WoodPlanks, { collide = false })
	B("PisoTerraco", 20, 25.8, Y2, Y2 + 0.05, -20, 11.8, WOOD_LIGHT, M.WoodPlanks, { collide = false })
	railX(house, at, -40, 26, -29.85, Y2)
	railZ(house, at, -30, 12, -39.85, Y2)
	railZ(house, at, -30, 12, 25.85, Y2)
	railX(house, at, -40, -30, 11.85, Y2)
	railX(house, at, 20, 26, 11.85, Y2)
	-- paredes do 2º andar
	GL(-30, -14, Y2, h2, -20, -19.6)
	GL(-6, 20, Y2, h2, -20, -19.6)
	GL(-14, -6, Y2 + 8.6, h2, -20, -19.6)
	GL(-30, 20, Y2, h2, 11.6, 12)
	GL(19.6, 20, Y2, h2, -19.6, 11.6)
	B("MadeiraCinema", -30.4, -29.6, Y2, h2, -20, 12, Color3.fromRGB(90, 60, 40), M.WoodPlanks)
	B("Teto", -31, 21, Y3 - 0.8, Y3, -21, 13, DARK)
	railZ(house, at, 0, 5.25, -0.15, Y2)
	railX(house, at, 0, 17, -0.15, Y2)
	railZ(house, at, 0, 11, 17.15, Y2)
	-- cinema: telão, 2 fileiras de sofá, bar com banquetas, sinuca
	local screen = B("Telao", -29.6, -29.3, Y2 + 2, Y2 + 8.6, -15, -1, Color3.fromRGB(20, 20, 24))
	toggle(screen, "TV", "Telão")
	sofaFixedX(house, at, -22, -18.6, -14, -2, Y2, Color3.fromRGB(150, 40, 45), -1)
	B("Degrau", -16.6, -10, Y2, Y2 + 1, -15, -1, Color3.fromRGB(60, 50, 45), M.WoodPlanks)
	sofaFixedX(house, at, -15, -11.6, -14, -2, Y2 + 1, Color3.fromRGB(150, 40, 45), -1)
	B("Bar", -28, -16, Y2, Y2 + 3.6, 9, 11.4, Color3.fromRGB(40, 30, 25), M.Wood)
	B("TampoBar", -28.2, -15.8, Y2 + 3.6, Y2 + 3.85, 8.6, 11.4, MARBLE, M.Marble)
	for _, x in ipairs({ -26, -23, -20, -17 }) do
		stool(house, at, x, Y2, 7.4, Color3.fromRGB(150, 40, 45))
	end
	for i, x in ipairs({ -27, -24.5, -22, -19.5, -17 }) do
		box(house, "Garrafa", at, x - 0.2, x + 0.2, Y2 + 3.85, Y2 + 5.2, 10.6, 11, ART[i], nil, { collide = false })
	end
	B("Sinuca", 4, 13, Y2, Y2 + 3, -15, -9.5, Color3.fromRGB(70, 45, 30), M.Wood)
	B("Feltro", 4.4, 12.6, Y2 + 3, Y2 + 3.1, -14.6, -9.9, Color3.fromRGB(40, 120, 60), M.Fabric)
	for _, p in ipairs({ { -20, 4 }, { 8, -2 }, { -8, -12 } }) do
		local l = ceilingLight(house, at, p[1], h2, p[2], true, 20)
		l.Parent = luzes[3]
	end
	local sw2 = toggle(B("Interruptor", 1, 1.6, Y2 + 4.2, Y2 + 5.2, 5.05, 5.25, Color3.new(1, 1, 1)), "Luz", "Luzes do 2º andar", { Target = "LuzesAndar2", On = true })
	sw2.CanCollide = false
	-- terraço: pergolado com sofá, lareira externa com banquinhos, espreguiçadeiras, vasos
	for _, x in ipairs({ -38.5, -25.5 }) do
		for _, z in ipairs({ -28.5, -21.5 }) do
			B("PostePergolado", x - 0.3, x + 0.3, Y2, Y2 + 9, z - 0.3, z + 0.3, wood, M.Wood)
		end
	end
	for x = -39, -25, 2 do
		B("Ripa", x - 0.2, x + 0.2, Y2 + 9, Y2 + 9.4, -29, -21, wood, M.Wood, { collide = false })
	end
	sofaFixed(house, at, -37.5, -26.5, -25, -21.6, Y2, Color3.fromRGB(225, 220, 205))
	local pit = at(-8, Y2, -25).Position
	K.flatCylinder(house, "FogueiraBorda", pit + Vector3.new(0, 0.7, 0), 2.6, 1.4, STONE, M.Slate)
	local pitFire = K.flatCylinder(house, "Fogueira", pit + Vector3.new(0, 1.45, 0), 2, 0.1, Color3.fromRGB(20, 20, 20), M.Slate)
	fire(pitFire)
	toggle(pitFire, "Fogo", "Fogueira")
	for _, d in ipairs({ { -4.5, 0 }, { 4.5, 0 }, { 0, -3.4 } }) do
		stool(house, at, -8 + d[1], Y2, -25 + d[2], wood)
	end
	for _, x in ipairs({ 8, 12, 16 }) do
		lounger(house, at, x, Y2, -28.6, -22.6)
	end
	plant(house, at, 23.5, Y2, -27.5, 1.1)
	plant(house, at, -37.5, Y2, 9.5, 1.1)
	plant(house, at, 23, Y2, 9.5, 1.1)
	if o.helipad then
		local pad = at(-5, Y3, -4).Position
		K.flatCylinder(house, "Heliponto", pad + Vector3.new(0, 0.15, 0), 9, 0.3, Color3.fromRGB(60, 62, 68), M.Concrete)
		K.flatCylinder(house, "HelipontoAnel", pad + Vector3.new(0, 0.32, 0), 8.2, 0.05, Color3.fromRGB(240, 200, 40), M.SmoothPlastic)
		K.flatCylinder(house, "HelipontoMeio", pad + Vector3.new(0, 0.36, 0), 7.4, 0.05, Color3.fromRGB(60, 62, 68), M.Concrete)
		for _, x in ipairs({ -6.8, -3.2 }) do
			B("LetraH", x - 0.4, x + 0.4, Y3 + 0.39, Y3 + 0.42, -6.8, -1.2, WHITE, nil, { collide = false })
		end
		B("LetraH", -6.8, -3.2, Y3 + 0.39, Y3 + 0.42, -4.4, -3.6, WHITE, nil, { collide = false })
	end

	-- EMBAIXO DO DECK E QUINTAL (área aberta do lote)
	sofaFixed(house, at, -37, -25, 26, 29.5, G, Color3.fromRGB(225, 220, 205))
	sofaFixedX(house, at, -38.5, -35, 16, 26, G, Color3.fromRGB(225, 220, 205), 1)
	B("MesaCentroPatio", -32, -28, G, G + 1.4, 19, 24, wood, M.Wood)
	B("PingPong", 11, 20, G + 2.6, G + 2.9, 21, 26, Color3.fromRGB(30, 90, 160))
	B("RedePingPong", 15.4, 15.6, G + 2.9, G + 3.6, 21, 26, Color3.new(1, 1, 1), nil, { collide = false })
	B("PePingPong", 15, 16, G, G + 2.6, 23, 24, DARK, M.Metal)
	B("Churrasqueira", 20, 24, G, G + 3.4, 34, 36.5, Color3.fromRGB(70, 70, 76), M.Metal)
	for _, x in ipairs({ -20, 0 }) do
		local l = B("LuzDeck", x - 1.2, x + 1.2, Y1 - 1.1, Y1 - 0.8, 37, 39.4, NEON_WARM, M.Neon, { collide = false })
		glow(l, 20, 0.45)
	end
	local jac = at(-20, G, 50).Position
	K.flatCylinder(house, "JacuzziBorda", jac + Vector3.new(0, 0.9, 0), 4.2, 1.8, WHITE, M.Marble)
	local jacW = K.flatCylinder(house, "JacuzziAgua", jac + Vector3.new(0, 1.85, 0), 3.7, 0.15, WATER, M.SmoothPlastic)
	jacW.Transparency = 0.25
	water(jacW, "hidro")
	toggle(jacW, "Agua", "Jacuzzi")
	for _, x in ipairs({ -32, -8 }) do
		lounger(house, at, x, G, 46, 52)
	end

	-- Marcas do HomeService
	marker(house, "Origem", at(-21.75, Y0, -4.5)) -- sala do térreo (x -33.25..-10.25, z -21.5..12.5)
	local e = at(-8, Y0, -17).Position
	marker(house, "Entrada", CFrame.lookAt(e, at(-8, Y0, 0).Position))
	for _, l in ipairs({
		{ -34, 18, Y0 - 0.5, Y1, -22, 14 },
		{ -41, 27, Y1 - 4.8, Y2, -37, 41 },
		{ -41, 27, Y2 - 0.5, Y3 + 1, -31, 13 },
		{ -48.4, 48.4, G - 0.5, Y1 - 0.8, 14, 58.4 }, -- Marco 10.6: quintal (área de lazer)
	}) do
		local lim = box(house, "Limite", at, l[1], l[2], l[3], l[4], l[5], l[6], WHITE, nil, { transparency = 1, collide = false, shadow = false })
		lim.CanQuery = false
		lim.CanTouch = false
	end
	house:SetAttribute("InPlace", true)
	house:SetAttribute("ExitText", "Porta")
	exit.CanCollide = false
end

---------------------------------------------------------------------------
-- Casa moderna (Marco 10.6, pedido do Luís): casa de verdade de 2 andares, igual à mansão (a
-- pessoa entra e anda nela). Térreo com sala (móveis do dono), cozinha americana com ilha e jantar,
-- escada; andar de cima com suíte, sala de TV, banheiro e porta para a varanda em cima da
-- garagem; fundo com deck, piscina e churrasqueira. Vidro de verdade (dá para ver a rua).
-- Lote 56 x 60 (x = largura na rua, z = fundo), frente em -Z. Volumes (x, z):
--   térreo   x -24..12, z -12..8     andar de cima  x -24..12, z -14..8 (balanço na frente)
--   garagem  x  12..25, z -14..6 (varanda em cima)   piscina e deck  z 8..26
-- o = { wall, trim, wood, number, mx }
---------------------------------------------------------------------------

-- Lance de escada ao longo de Z: começa em z0 (embaixo) e anda para dir (+1/-1); faixa x0..x1
local function flightZ(parent, at, z0, dir, x0, x1, y, n, rise, run, color)
	for i = 1, n do
		local za, zb = z0 + dir * (i - 1) * run, z0 + dir * i * run
		box(parent, "Degrau", at, x0, x1, y, y + i * rise, za, zb, color, M.WoodPlanks)
	end
	local xc = (x0 + x1) / 2
	local a = at(xc, y + rise, z0).Position
	local b = at(xc, y + n * rise, z0 + dir * (n - 1) * run).Position
	P(parent, "Rampa", Vector3.new(math.abs(x1 - x0), 0.4, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b) * CFrame.new(0, -0.2, 0), WHITE, nil, { transparency = 1, shadow = false })
end

MoradiaBuilder.MODERN_DOOR_X = -14.8 -- meio da sala (a frente da porta fica livre de móveis)

function MoradiaBuilder.modern(house, at, o)
	local G = 0.7
	local Y0 = G + 0.6 -- piso do térreo
	local Y1 = Y0 + 11.8 -- piso do andar de cima
	local h0 = Y1 - 0.8 -- teto do térreo
	local h1 = Y1 + 10 -- teto do andar de cima
	local wall = o.wall or WHITE
	local trim = o.trim or DARK
	local wood = o.wood or WOOD
	local slate = Color3.fromRGB(128, 122, 114)
	local WALL_IN = Color3.fromRGB(240, 236, 228)
	local DX = MoradiaBuilder.MODERN_DOOR_X
	local function B(name, x0, x1, y0, y1, z0, z1, color, material, extra)
		return box(house, name, at, x0, x1, y0, y1, z0, z1, color, material, extra)
	end
	local function GL(x0, x1, y0, y1, z0, z1)
		return glass(house, at, x0, x1, y0, y1, z0, z1)
	end
	-- montantes escuros por fora do vidro (frente/fundo)
	local function mullions(x0, x1, y0, y1, z, out)
		local n = math.max(1, math.floor((x1 - x0) / 5 + 0.5))
		for k = 0, n do
			local x = x0 + k * (x1 - x0) / n
			B("Montante", x - 0.15, x + 0.15, y0, y1, z, z + out * 0.3, DARK, M.Metal, { collide = false })
		end
	end
	local luzes = { K.model("LuzesTerreo", house), K.model("LuzesAndar1", house) }

	-- Terreno, muro com ripas, portões, caminho de pisantes e canteiro --------------
	B("Gramado", -28, 28, 0.4, G, -30, 30, Color3.fromRGB(112, 178, 82), M.Grass)
	local muro = wall == Color3.fromRGB(70, 72, 78) and STONE or wall
	for _, seg in ipairs({ { -28, -17.5 }, { -12, 12 }, { 26, 28 } }) do
		B("Muro", seg[1], seg[2], G, G + 3.2, -29.8, -29, muro, M.Plaster)
		B("MuroTopo", seg[1] - 0.1, seg[2] + 0.1, G + 3.2, G + 3.45, -29.9, -28.9, trim)
	end
	for x = -11.5, 11.5, 1.5 do
		B("Ripa", x - 0.3, x + 0.3, G + 3.45, G + 5.6, -29.5, -29.2, wood, M.Wood, { collide = false })
	end
	B("RipaTrave", -12, 12, G + 5.6, G + 5.8, -29.6, -29.1, trim, nil, { collide = false })
	local plate = B("NumeroMuro", -16.9, -15.1, G + 1.4, G + 2.6, -29.9, -29.85, DARK, nil, { collide = false })
	K.addSurfaceText(plate, tostring(o.number or ""), Color3.new(1, 1, 1), DARK)
	B("EntradaCarro", 13, 25, G, G + 0.2, -29, -14, Color3.fromRGB(178, 175, 170), M.Concrete)
	for z = -28, -15.5, 3.2 do
		B("Pisante", DX - 1.6, DX + 1.6, G, G + 0.15, z, z + 2, Color3.fromRGB(200, 196, 188), M.Slate, { collide = false })
	end
	for _, z in ipairs({ -26, -20 }) do
		for _, x in ipairs({ DX - 2.8, DX + 2.8 }) do
			B("Balizador", x - 0.25, x + 0.25, G, G + 1.4, z - 0.25, z + 0.25, DARK, M.Metal)
			B("BalizadorLuz", x - 0.27, x + 0.27, G + 1.1, G + 1.4, z - 0.27, z + 0.27, NEON_WARM, M.Neon, { collide = false })
		end
	end
	B("Canteiro", -9, 9, G, G + 1.4, -17.5, -15, slate, M.Slate)
	B("CanteiroTerra", -8.7, 8.7, G + 1.4, G + 1.5, -17.2, -15.3, Color3.fromRGB(90, 140, 60), M.Grass, { collide = false })
	for _, x in ipairs({ -6, 0, 6 }) do
		P(house, "Arbusto", Vector3.new(2.6, 2.2, 2.2), at(x, G + 2.4, -16.2), Color3.fromRGB(80, 155, 65), M.Grass, { shape = Enum.PartType.Ball, collide = false })
	end
	-- cerca viva alta (não dá para pular) e muros fechando os lados: o fundo só se alcança por dentro
	for _, s in ipairs({ -1, 1 }) do
		B("CercaViva", s > 0 and 27 or -28, s > 0 and 28 or -27, G, G + 8, -29, 30, HEDGE, M.Grass)
	end
	B("CercaViva", -27, 27, G, G + 8, 29, 30, HEDGE, M.Grass)
	B("MuroLateral", -27, -24.4, G, G + 8, -12.8, -12.4, muro, M.Plaster)
	B("MuroLateral", 25, 27, G, G + 8, 5.6, 6.2, muro, M.Plaster)
	palmFn(house, at(-24, G, -24).Position, 0.95)
	palmFn(house, at(23, G, 26).Position, 1)
	palmFn(house, at(-24, G, 27).Position, 0.9)

	-- TÉRREO --------------------------------------------------------------
	B("Base", -24.4, 12.4, G, Y0, -12.4, 8.4, STONE_LIGHT, M.Concrete)
	B("Degrau", DX - 3, DX + 3, G, G + 0.3, -15, -12.4, STONE_LIGHT, M.Concrete)
	B("PisoTerreo", -23.6, 11.6, Y0, Y0 + 0.05, -11.6, 7.6, Color3.fromRGB(205, 175, 135), M.WoodPlanks, { collide = false })
	-- frente: pedra (à esquerda), porta de madeira, vidro do chão ao teto até a escada
	B("Pedra", -24.4, DX - 2.4, Y0, h0, -12.4, -11.6, slate, M.Slate)
	B("PortaMoldura", DX - 2.5, DX + 2.5, Y0, Y0 + 9, -12.3, -11.7, DARK, M.Metal)
	B("Door", DX - 2.2, DX + 2.2, Y0, Y0 + 8.6, -12.45, -12.05, wood, M.Wood)
	B("Puxador", DX + 1.4, DX + 1.6, Y0 + 3, Y0 + 6.5, -12.7, -12.45, Color3.fromRGB(200, 200, 205), M.Metal, { collide = false })
	B("Pedra", DX - 2.5, DX + 2.5, Y0 + 9, h0, -12.4, -11.6, slate, M.Slate)
	local exit = B("SaidaPorta", DX - 2, DX + 2, Y0, Y0 + 8.4, -11.6, -11.45, wood, M.Wood, { collide = false })
	local np = B("NumberPlate", DX + 3, DX + 4.8, Y0 + 6.2, Y0 + 7.2, -12.5, -12.45, DARK, nil, { collide = false })
	K.addSurfaceText(np, tostring(o.number or ""), Color3.new(1, 1, 1), DARK)
	local sconce = B("Arandela", DX - 3.4, DX - 2.8, Y0 + 5.6, Y0 + 6.8, -12.7, -12.4, NEON_WARM, M.Neon, { collide = false })
	glow(sconce, 10, 0.4)
	GL(DX + 2.5, 12, Y0, h0, -12, -11.6)
	mullions(DX + 2.5, 12, Y0, h0, -12, -1)
	-- fundo: vidro com a porta de correr aberta (x -5..1) para o deck da piscina
	GL(-24, -5, Y0, h0, 7.6, 8)
	GL(1, 12, Y0, h0, 7.6, 8)
	GL(-5, 1, Y0 + 9.2, h0, 7.6, 8)
	box(house, "PortaCorrer", at, -10.6, -5.2, Y0, Y0 + 9.2, 7.25, 7.55, GLASS, M.SmoothPlastic, { transparency = 0.55, reflectance = 0.05, collide = false })
	mullions(-24, 12, Y0, h0, 8, 1)
	-- laterais de parede (vizinho e garagem)
	B("ParedeLateral", -24.4, -23.6, Y0, h0, -11.6, 7.6, wall, M.Plaster)
	B("ParedeLateral", 11.6, 12.4, Y0, h0, -11.6, 7.6, wall, M.Plaster)
	-- cozinha americana: bancada na frente (de cara para o vidro), geladeira, ilha com banquetas e
	-- mesa de jantar perto da porta do fundo. Fica um corredor (z 4.4..7.6) até o pé da escada.
	B("Bancada", 0, 7.6, Y0, Y0 + 3, -11.4, -9, CABINET)
	B("Tampo", 0, 7.6, Y0 + 3, Y0 + 3.25, -11.5, -8.8, MARBLE, M.Marble)
	B("Cooktop", 4, 6.5, Y0 + 3.25, Y0 + 3.3, -10.9, -9.3, Color3.fromRGB(20, 20, 24), nil, { collide = false })
	B("Pia", 1, 3, Y0 + 3.2, Y0 + 3.3, -10.9, -9.3, STEEL, M.Metal, { collide = false })
	B("Geladeira", -3.8, -0.4, Y0, Y0 + 8, -11.4, -8.4, STEEL, M.Metal)
	B("Ilha", -2, 4, Y0, Y0 + 3, -5, -3, CABINET)
	B("TampoIlha", -2.3, 4.3, Y0 + 3, Y0 + 3.25, -5.2, -2.8, MARBLE, M.Marble)
	for _, x in ipairs({ -0.6, 1.8 }) do
		stool(house, at, x, Y0, -1.6, Color3.fromRGB(70, 70, 76))
	end
	pendant(house, at, -0.2, h0, -4)
	pendant(house, at, 2.2, h0, -4)
	B("MesaJantar", -4, 3, Y0 + 2.6, Y0 + 2.9, 2, 4.4, wood, M.Wood)
	B("PeMesa", -0.9, -0.1, Y0, Y0 + 2.6, 2.8, 3.6, DARK, M.Metal)
	for _, x in ipairs({ -2.6, -0.5, 1.6 }) do
		chair(house, at, x, Y0, 0.8, WHITE, "-z")
	end
	-- escada (junto da parede da garagem): o pé fica no fundo (entra pelo corredor) e sobe para a frente
	local n = 18
	flightZ(house, at, 7.4, -1, 8.2, 11.6, Y0, n, (Y1 - Y0) / n, 1, WOOD_LIGHT)
	local sw0 = toggle(B("Interruptor", DX - 3.4, DX - 2.8, Y0 + 4.2, Y0 + 5.2, -11.6, -11.4, Color3.new(1, 1, 1)), "Luz", "Luzes do térreo", { Target = "LuzesTerreo", On = true })
	sw0.CanCollide = false
	for _, p in ipairs({ { -14.8, -6 }, { -14.8, 3 }, { 1, -7 } }) do
		local l = ceilingLight(house, at, p[1], h0, p[2], p[1] ~= -14.8 or p[2] > 0, 22)
		l.Parent = luzes[1]
	end

	-- ANDAR DE CIMA -------------------------------------------------------
	local hole = { 8, 11.6, -10.6, 7.6 }
	slab(house, "Laje1", at, -24.4, 12.4, -14.4, 8.4, Y1 - 0.8, Y1, WHITE, nil, hole)
	slab(house, "Piso1", at, -23.6, 11.6, -13.6, 7.6, Y1, Y1 + 0.05, Color3.fromRGB(190, 160, 120), M.WoodPlanks, hole, { collide = false })
	railZ(house, at, -10.6, 7.6, 7.85, Y1)
	-- frente toda de vidro (com ripado de madeira por fora na esquerda), fundo de vidro
	GL(-24, 12, Y1, h1, -14, -13.6)
	mullions(-24, 12, Y1, h1, -14, -1)
	B("RipadoFundo", -24, -16, Y1 + 0.5, h1 - 0.5, -14.5, -14.3, Color3.fromRGB(40, 40, 44), nil, { collide = false })
	for x = -23.6, -16.4, 0.8 do
		B("Ripado", x - 0.2, x + 0.2, Y1 + 0.5, h1 - 0.5, -14.8, -14.5, wood, M.Wood, { collide = false })
	end
	GL(-24, 12, Y1, h1, 7.6, 8)
	mullions(-24, 12, Y1, h1, 8, 1)
	B("ParedeLateral", -24.4, -23.6, Y1, h1, -13.6, 7.6, wall, M.Plaster)
	-- parede da garagem com a porta de vidro para a varanda
	B("ParedeLateral", 11.6, 12.4, Y1, h1, -10.8, 7.6, wall, M.Plaster)
	B("ParedeLateral", 11.6, 12.4, Y1 + 8.6, h1, -13.6, -10.8, wall, M.Plaster)
	B("PortaVarandaMoldura", 11.5, 12.5, Y1 + 8.4, Y1 + 8.6, -13.6, -10.8, DARK, M.Metal, { collide = false })
	-- divisórias (pintáveis): sala de TV na frente | suíte e banheiro no fundo (portas em x -10..-7 e -1..2)
	B("Wall", -23.6, -10, Y1, h1, -1.2, -0.8, WALL_IN)
	B("Wall", -7, -1, Y1, h1, -1.2, -0.8, WALL_IN)
	B("Wall", 2, 7.6, Y1, h1, -1.2, -0.8, WALL_IN)
	B("Wall", -10, -7, Y1 + 8.4, h1, -1.2, -0.8, WALL_IN)
	B("Wall", -1, 2, Y1 + 8.4, h1, -1.2, -0.8, WALL_IN)
	B("Wall", -6.2, -5.8, Y1, h1, -0.8, 7.6, WALL_IN)
	B("Wall", 7.6, 8, Y1, h1, -0.8, 7.6, WALL_IN)
	-- suíte (fundo, esquerda): cama de casal virada para a frente, criados-mudos, guarda-roupa
	bedFixed(house, at, -19, -12, -0.4, 6.6, Y1, Color3.fromRGB(70, 90, 140))
	for _, x in ipairs({ -20.8, -10.2 }) do
		B("CriadoMudo", x - 1, x + 1, Y1, Y1 + 2.2, 5, 7, wood, M.Wood)
		local l = B("Abajur", x - 0.45, x + 0.45, Y1 + 2.2, Y1 + 3.6, 5.5, 6.5, NEON_WARM, M.Neon, { collide = false })
		l.Parent = luzes[2]
	end
	B("GuardaRoupa", -23.6, -21.4, Y1, Y1 + 9, -0.4, 4, wood, M.Wood)
	B("TapeteSuite", -20, -11, Y1 + 0.05, Y1 + 0.1, -0.6, 2, Color3.fromRGB(200, 190, 175), M.Fabric, { collide = false })
	-- banheiro (fundo, meio): box com chuveiro, vaso, bancada com espelho, vidro fosco
	B("VidroFosco", -5.8, 7.6, Y1, h1, 7.2, 7.6, Color3.new(1, 1, 1), nil, { transparency = 0.2 })
	B("PisoBanheiro", -5.8, 7.6, Y1 + 0.05, Y1 + 0.1, -0.8, 7.2, Color3.fromRGB(225, 225, 228), M.Slate, { collide = false })
	B("Ralo", 2.6, 7.4, Y1, Y1 + 0.3, 3.2, 7.2, Color3.new(1, 1, 1))
	B("VidroBox", 2.4, 2.6, Y1 + 0.3, Y1 + 8, 3.2, 7.2, GLASS, nil, { transparency = 0.5 })
	local shower = B("Chuveiro", 4.2, 5.8, Y1 + 8, Y1 + 8.25, 4.6, 6.2, STEEL, M.Metal, { collide = false })
	water(shower, "chuveiro")
	toggle(shower, "Agua", "Chuveiro")
	B("Vaso", -5.6, -3.6, Y1, Y1 + 1.7, 4.6, 6.8, Color3.new(1, 1, 1))
	B("BancadaBanheiro", -5.8, -3.4, Y1, Y1 + 3.2, 1.4, 4.2, CABINET)
	B("TampoBanheiro", -5.8, -3.2, Y1 + 3.2, Y1 + 3.45, 1.3, 4.3, MARBLE, M.Marble)
	B("Espelho", -5.8, -5.65, Y1 + 4.2, Y1 + 7.6, 1.6, 4, Color3.fromRGB(215, 230, 240), nil, { reflectance = 0.5, collide = false })
	ceilingLight(house, at, 0, h1, 4, false)
	-- sala de TV (frente): TV na parede do vizinho, sofá virado para ela, cantinho do computador
	local tv = B("TVSala", -23.6, -23.2, Y1 + 3, Y1 + 7.4, -9.5, -3.5, Color3.fromRGB(20, 20, 24))
	toggle(tv, "TV", "TV")
	sofaFixedX(house, at, -16, -13, -10.5, -2.5, Y1, Color3.fromRGB(80, 80, 88), -1)
	B("TapeteSala", -22, -13, Y1 + 0.05, Y1 + 0.1, -10.5, -2.5, Color3.fromRGB(150, 60, 50), M.Fabric, { collide = false })
	B("MesaCentro", -20.5, -18, Y1, Y1 + 1.4, -8, -5, wood, M.Wood)
	plant(house, at, -22.4, Y1, -12.4, 0.9)
	plant(house, at, -9, Y1, -12.4, 0.9)
	B("Escrivaninha", 2.4, 7.4, Y1 + 2.8, Y1 + 3.1, -4, -1.4, Color3.new(1, 1, 1))
	B("PeEscrivaninha", 2.4, 2.8, Y1, Y1 + 2.8, -4, -1.4, Color3.new(1, 1, 1))
	B("PeEscrivaninha", 7, 7.4, Y1, Y1 + 2.8, -4, -1.4, Color3.new(1, 1, 1))
	chair(house, at, 4.9, Y1, -5.4, DARK, "-z")
	B("Monitor", 3.4, 6.4, Y1 + 3.1, Y1 + 5.2, -1.6, -1.3, Color3.fromRGB(20, 20, 24))
	painting(house, at, -4, Y1 + 5.6, -1.2, "-z", 4, 3, ART[3])
	local sw1 = toggle(B("Interruptor", -12.6, -12, Y1 + 4.2, Y1 + 5.2, -1.4, -1.2, Color3.new(1, 1, 1)), "Luz", "Luzes de cima", { Target = "LuzesAndar1", On = true })
	sw1.CanCollide = false
	for _, p in ipairs({ { -15, -7 }, { -15, 3 }, { 0, -8 } }) do
		local l = ceilingLight(house, at, p[1], h1, p[2], p[2] ~= 3, 20)
		l.Parent = luzes[2]
	end
	-- telhado com beiral e fita de luz na frente
	B("Telhado", -25, 13, h1, h1 + 0.8, -15, 9, trim)
	B("LuzBeiral", -24.6, 12.6, h1 - 0.15, h1, -14.9, -14.6, Color3.fromRGB(255, 225, 170), M.Neon, { collide = false, shadow = false })

	-- GARAGEM (coberta) E VARANDA EM CIMA ------------------------------------
	B("TetoGaragem", 12.4, 25.4, Y1 - 0.8, Y1, -14.4, 6.4, trim)
	B("PisoVaranda", 12.4, 25.2, Y1, Y1 + 0.05, -14.2, 6.2, WOOD_LIGHT, M.WoodPlanks, { collide = false })
	for _, z in ipairs({ -13.8, 5.8 }) do
		B("Pilar", 24.4, 25, G, Y1 - 0.8, z - 0.3, z + 0.3, trim, M.Metal)
	end
	B("GaragemFundo", 12.4, 25, G, Y1 - 0.8, 5.6, 6.2, wall, M.Plaster)
	for _, z in ipairs({ -9, -1 }) do
		B("LuzGaragem", 17, 20, Y1 - 0.95, Y1 - 0.8, z - 0.4, z + 0.4, NEON_WARM, M.Neon, { collide = false, shadow = false })
	end
	railX(house, at, 12.4, 25.4, -14.25, Y1)
	railZ(house, at, -14.4, 6.4, 25.25, Y1)
	railX(house, at, 12.4, 25.4, 6.25, Y1)
	for _, x in ipairs({ 17, 21 }) do
		lounger(house, at, x, Y1, -6, 0)
	end
	B("MesinhaVaranda", 14, 16, Y1, Y1 + 2.2, -12, -10, WHITE)
	chair(house, at, 15, Y1, -8.6, WHITE, "+z")
	plant(house, at, 23.6, Y1, -12.4, 0.9)
	plant(house, at, 23.6, Y1, 4.4, 0.9)

	-- FUNDO: deck, piscina, espreguiçadeiras, guarda-sol e churrasqueira ----------
	B("Deck", -24, 12, G, G + 0.5, 8.4, 14, wood, M.WoodPlanks)
	B("PiscinaBorda", -18, 2, G, G + 0.8, 15, 26, WHITE, M.Marble)
	B("Piscina", -17, 1, G + 0.8, G + 0.95, 16, 25, WATER, nil, { transparency = 0.2, collide = false })
	B("PiscinaLuz", -17, 1, G + 0.6, G + 0.72, 15.95, 16.05, Color3.fromRGB(120, 210, 255), M.Neon, { collide = false })
	for _, x in ipairs({ 7, 10.5 }) do
		lounger(house, at, x, G, 17, 23)
	end
	B("GuardaSolHaste", 14.6, 14.9, G, G + 7, 22, 22.3, DARK, M.Metal)
	K.flatCylinder(house, "GuardaSol", at(14.75, G + 7, 22.15).Position, 3.6, 0.3, Color3.fromRGB(240, 235, 220), M.Fabric)
	B("Churrasqueira", -26, -22, G, G + 3.4, 17, 23, slate, M.Slate)
	B("ChurrasqueiraTampo", -26.2, -21.8, G + 3.4, G + 3.6, 16.8, 23.2, DARK, M.Marble)
	B("Chamine", -25.5, -23.5, G + 3.6, G + 9, 21, 22.6, slate, M.Slate)
	local deckLight = B("LuzDeck", -6, -2, h0 - 0.2, h0 + 0.2, 8.6, 9.2, NEON_WARM, M.Neon, { collide = false })
	glow(deckLight, 18, 0.4)

	-- Marcas do HomeService
	marker(house, "Origem", at(DX, Y0, -2)) -- sala do térreo (x -23.3..-6.3, z -11.5..7.5)
	local e = at(DX, Y0, -8).Position
	marker(house, "Entrada", CFrame.lookAt(e, at(DX, Y0, 0).Position))
	for _, l in ipairs({
		{ -24.4, 12.4, Y0 - 0.5, Y1, -12.4, 8.4 },
		{ -24.4, 25.6, Y1 - 0.8, h1 + 1, -14.6, 8.4 },
		{ -27, 27, G - 0.5, Y1 - 1, 8.4, 29 },
	}) do
		local lim = box(house, "Limite", at, l[1], l[2], l[3], l[4], l[5], l[6], WHITE, nil, { transparency = 1, collide = false, shadow = false })
		lim.CanQuery = false
		lim.CanTouch = false
	end
	house:SetAttribute("InPlace", true)
	house:SetAttribute("ExitText", "Porta")
	exit.CanCollide = false
end

return MoradiaBuilder
