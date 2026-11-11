-- CondoBuilder (ModuleScript)
-- Caminho: ServerScriptService > Services > CondoBuilder
-- Marco 10.32: condomínios fechados no miolo das quadras do litoral (atrás da Beira-Mar e da
-- Rua das Gaivotas). Cada um tem muro com portaria (guarita, cancela e letreiro), prédios baixos
-- de 3 a 4 andares, área de lazer com piscina, deque e espreguiçadeiras, quadra de tênis com
-- alambrado e rede, parquinho, estacionamento, caminhos, palmeiras e bancos.
-- A frente (portão) fica no -Z do lote. Tudo é peça simples (sem script), feito pelo LitoralBuilder.

local CondoBuilder = {}

local WHITE = Color3.fromRGB(248, 248, 244)
local STONE = Color3.fromRGB(190, 182, 166)
local PATH = Color3.fromRGB(225, 218, 205)
local GRASS = Color3.fromRGB(100, 172, 84)
local ASPHALT = Color3.fromRGB(62, 64, 70)
local GLASS = Color3.fromRGB(140, 190, 215)
local METAL = Color3.fromRGB(70, 76, 84)
local WOOD = Color3.fromRGB(158, 122, 82)
local WATER = Color3.fromRGB(70, 185, 225)

CondoBuilder.NAMES = {
	"Condomínio Brisa do Mar", "Condomínio Jardim Atlântico", "Residencial Recanto das Ondas",
	"Condomínio Vila Coral", "Residencial Porto Belo", "Condomínio Mirante da Costa",
}

-- kit: { P, sign, column, nocollide, palm, bench }
-- lot: CFrame do centro (frente = -Z), W (largura, X), D (fundo, Z), name, wall, accent
function CondoBuilder.build(f, kit, lot, rng)
	local P, sign, column, nocollide = kit.P, kit.sign, kit.column, kit.nocollide
	local W, D = lot.W, lot.D
	local cf = lot.cf
	local G = 0.8 -- chão do lote
	local accent = lot.accent
	local function at(x, y, z)
		return cf * CFrame.new(x, y, z)
	end
	local function lp(name, size, x, y, z, color, material, extra)
		return P(f, name, size, at(x, y, z), color, material, extra)
	end
	local function deco(name, size, x, y, z, color, material, extra)
		return P(f, name, size, at(x, y, z), color, material, nocollide(extra))
	end
	local function pos(x, y, z)
		return at(x, y, z).Position
	end

	-- chão: grama com caminhos
	lp("Gramado", Vector3.new(W, 0.4, D), 0, G - 0.2, 0, GRASS, Enum.Material.Grass)
	deco("CaminhoCentral", Vector3.new(10, 0.06, D - 20), 0, G + 0.03, 4, PATH, Enum.Material.Pavement)
	deco("CaminhoTravessa", Vector3.new(W - 24, 0.06, 8), 0, G + 0.03, -D * 0.12, PATH, Enum.Material.Pavement)

	-- muro com portaria na frente (vão de 26 no meio)
	local WALL_H, T = 7, 1
	local GATE = 26
	local function wallRun(x0, z0, x1, z1)
		local len = math.max(math.abs(x1 - x0), math.abs(z1 - z0))
		if len < 1 then
			return
		end
		local horizontal = math.abs(x1 - x0) >= math.abs(z1 - z0)
		local size = horizontal and Vector3.new(len, WALL_H, T) or Vector3.new(T, WALL_H, len)
		lp("Muro", size, (x0 + x1) / 2, G + WALL_H / 2, (z0 + z1) / 2, lot.wall, Enum.Material.Plaster)
		local cap = horizontal and Vector3.new(len + 0.4, 0.4, T + 0.5) or Vector3.new(T + 0.5, 0.4, len + 0.4)
		deco("Capa", cap, (x0 + x1) / 2, G + WALL_H + 0.2, (z0 + z1) / 2, WHITE, Enum.Material.Concrete)
	end
	local hx, hz = W / 2, D / 2
	wallRun(-hx, -hz, -GATE / 2, -hz)
	wallRun(GATE / 2, -hz, hx, -hz)
	wallRun(-hx, hz, hx, hz)
	wallRun(-hx, -hz, -hx, hz)
	wallRun(hx, -hz, hx, hz)
	-- pilares do muro (a cada ~24) com luminária
	for _, side in ipairs({ -1, 1 }) do
		for z = -hz, hz, 24 do
			deco("Pilar", Vector3.new(1.8, WALL_H + 1, 1.8), side * hx, G + (WALL_H + 1) / 2, z, STONE, Enum.Material.Slate)
		end
	end
	-- portaria: guarita de vidro, cancela, letreiro de pedra e portão de pedestre
	local gz = -hz
	lp("PisoEntrada", Vector3.new(GATE, 0.1, 20), 0, G + 0.05, gz + 6, ASPHALT, Enum.Material.Asphalt)
	lp("Guarita", Vector3.new(8, 8, 8), GATE / 2 + 5, G + 4, gz + 5, WHITE, Enum.Material.Plaster)
	deco("VidroGuarita", Vector3.new(8.2, 3, 8.2), GATE / 2 + 5, G + 5, gz + 5, GLASS, Enum.Material.Glass, { Transparency = 0.45 })
	deco("TetoGuarita", Vector3.new(10, 0.6, 10), GATE / 2 + 5, G + 8.3, gz + 5, accent, Enum.Material.SmoothPlastic)
	for _, k in ipairs({ -1, 1 }) do
		deco("PosteCancela", Vector3.new(0.8, 3.4, 0.8), k * (GATE / 2 - 2), G + 1.7, gz + 1.5, Color3.fromRGB(240, 200, 40), Enum.Material.Metal)
		deco("Cancela", Vector3.new(GATE / 2 - 3, 0.35, 0.35), k * (GATE / 4 - 0.5), G + 3.2, gz + 1.5, k > 0 and WHITE or Color3.fromRGB(220, 50, 40), Enum.Material.SmoothPlastic)
	end
	local panel = lp("PainelEntrada", Vector3.new(16, 6, 1.6), -GATE / 2 - 9, G + 3, gz - 1.6, STONE, Enum.Material.Slate)
	local plate = sign(f, at(-GATE / 2 - 9, G + 3.8, gz - 2.5) * CFrame.Angles(0, math.pi, 0), Vector3.new(14, 2.2, 0.2), lot.name, WHITE, accent)
	plate.Name = "LetreiroCondominio"
	panel:SetAttribute("Condominio", lot.name)
	deco("FloreiraEntrada", Vector3.new(16, 1.2, 2), -GATE / 2 - 9, G + 0.6, gz - 3.4, Color3.fromRGB(80, 70, 60), Enum.Material.Wood)
	for k = -2, 2 do
		deco("Flor", Vector3.new(1.6, 1.4, 1.4), -GATE / 2 - 9 + k * 3, G + 1.6, gz - 3.4, Color3.fromRGB(230, 90 + k * 20, 120), Enum.Material.Grass, { Shape = Enum.PartType.Ball })
	end

	-- estacionamento logo depois da portaria (lado esquerdo)
	local parkX0, parkX1 = -hx + 6, -GATE / 2 - 4
	if parkX1 - parkX0 > 24 then
		lp("Estacionamento", Vector3.new(parkX1 - parkX0, 0.1, 22), (parkX0 + parkX1) / 2, G + 0.05, gz + 14, ASPHALT, Enum.Material.Asphalt)
		for x = parkX0 + 2, parkX1 - 2, 11 do
			deco("Vaga", Vector3.new(0.3, 0.05, 18), x, G + 0.12, gz + 14, WHITE, Enum.Material.SmoothPlastic)
		end
	end

	-- prédios baixos (blocos A, B, C, D) no fundo e nas laterais
	local function block(name, x, z, bw, bd, floors, yaw)
		local bcf = at(x, G, z) * CFrame.Angles(0, yaw or 0, 0)
		local h = floors * 8
		local m = Instance.new("Model")
		m.Name = name
		m.Parent = f
		local function bp(n, size, ox, oy, oz, color, material, extra)
			return P(m, n, size, bcf * CFrame.new(ox, oy, oz), color, material, extra)
		end
		bp("Corpo", Vector3.new(bw, h, bd), 0, h / 2, 0, lot.wall, Enum.Material.Plaster)
		bp("Base", Vector3.new(bw + 0.6, 1.4, bd + 0.6), 0, 0.7, 0, STONE, Enum.Material.Slate)
		for fl = 0, floors - 1 do
			local y = fl * 8 + 4.6
			for _, side in ipairs({ -1, 1 }) do
				bp("Janelas", Vector3.new(bw - 6, 3.4, 0.3), 0, y, side * (bd / 2 + 0.1), GLASS, Enum.Material.Glass, nocollide({ Transparency = 0.2 }))
				if fl > 0 then
					bp("Sacada", Vector3.new(bw - 4, 0.5, 2.4), 0, y - 2.2, side * (bd / 2 + 1.2), WHITE, Enum.Material.Concrete)
					bp("Guarda", Vector3.new(bw - 4, 1.6, 0.2), 0, y - 1.2, side * (bd / 2 + 2.4), GLASS, Enum.Material.Glass, nocollide({ Transparency = 0.5 }))
				end
			end
			bp("FaixaAndar", Vector3.new(bw + 0.3, 0.5, bd + 0.3), 0, fl * 8 + 8, 0, WHITE, Enum.Material.Concrete, nocollide())
		end
		bp("Platibanda", Vector3.new(bw + 1, 1.2, bd + 1), 0, h + 0.6, 0, WHITE, Enum.Material.Concrete)
		bp("CaixaDagua", Vector3.new(8, 4, 6), bw / 4, h + 2, 0, Color3.fromRGB(225, 225, 225), Enum.Material.Concrete)
		-- entrada com marquise
		bp("Porta", Vector3.new(5, 7, 0.3), 0, 3.5, -bd / 2 - 0.2, Color3.fromRGB(90, 70, 55), Enum.Material.Wood)
		bp("Marquise", Vector3.new(10, 0.4, 5), 0, 8, -bd / 2 - 2.5, accent, Enum.Material.SmoothPlastic, nocollide())
		local s = P(m, "Bloco", Vector3.new(4, 1.4, 0.2), bcf * CFrame.new(0, 9.2, -bd / 2 - 0.2) * CFrame.Angles(0, math.pi, 0), WHITE, Enum.Material.SmoothPlastic, nocollide())
		kit.text(s, name, accent, WHITE)
		return m
	end
	local floorsA = rng:NextInteger(3, 4)
	local BW, BD = math.min(48, W * 0.3), 22
	block("Bloco A", -W * 0.3, hz - BD / 2 - 8, BW, BD, floorsA, math.pi)
	block("Bloco B", W * 0.3, hz - BD / 2 - 8, BW, BD, floorsA, math.pi)
	if W >= 200 and D > 140 then
		block("Bloco C", -hx + BD / 2 + 8, hz * 0.12, math.min(40, D * 0.25), BD, rng:NextInteger(3, 4), -math.pi / 2)
		block("Bloco D", hx - BD / 2 - 8, hz * 0.12, math.min(40, D * 0.25), BD, rng:NextInteger(3, 4), math.pi / 2)
	end

	-- área da piscina (centro)
	local px, pz = -W * 0.14, -D * 0.02
	lp("Deque", Vector3.new(58, 0.5, 34), px, G + 0.25, pz, Color3.fromRGB(236, 226, 205), Enum.Material.Pavement)
	lp("BordaPiscina", Vector3.new(40, 0.9, 18), px, G + 0.45, pz, WHITE, Enum.Material.Marble)
	deco("Piscina", Vector3.new(38, 0.2, 16), px, G + 0.92, pz, WATER, Enum.Material.Glass, { Transparency = 0.25 })
	deco("Raia", Vector3.new(36, 0.05, 0.3), px, G + 1.04, pz, Color3.fromRGB(30, 80, 160), Enum.Material.SmoothPlastic)
	deco("PiscinaKids", Vector3.new(8, 0.2, 8), px + 25, G + 0.62, pz - 10, Color3.fromRGB(120, 210, 240), Enum.Material.Glass, { Transparency = 0.2 })
	for i = 0, 5 do
		local lx = px - 20 + i * 8
		local seat = P(f, "Espreguicadeira", Vector3.new(2.4, 0.5, 6), at(lx, G + 1.2, pz + 13.5) * CFrame.Angles(math.rad(-8), 0, 0), WHITE, Enum.Material.SmoothPlastic, { ClassName = "Seat" })
		seat:SetAttribute("SeatText", "Deitar")
		if i % 2 == 0 then
			column(f, "PosteGuardaSol", pos(lx + 4, G + 0.5, pz + 14), 7, 0.15, WOOD, Enum.Material.Wood)
			deco("GuardaSol", Vector3.new(0.4, 8, 8), lx + 4, G + 7.6, pz + 14, i % 4 == 0 and accent or WHITE, Enum.Material.Fabric, { Shape = Enum.PartType.Cylinder, CFrame = at(lx + 4, G + 7.6, pz + 14) * CFrame.Angles(0, 0, math.rad(90)) })
		end
	end
	-- quiosque / salão de festas ao lado da piscina
	lp("Quiosque", Vector3.new(16, 0.5, 12), px - 37, G + 0.25, pz, WOOD, Enum.Material.WoodPlanks)
	for _, ox in ipairs({ -7, 7 }) do
		for _, oz in ipairs({ -5, 5 }) do
			column(f, "PosteQuiosque", pos(px - 37 + ox, G + 0.5, pz + oz), 8, 0.35, WOOD, Enum.Material.Wood)
		end
	end
	deco("TelhadoQuiosque", Vector3.new(18, 0.8, 14), px - 37, G + 8.8, pz, Color3.fromRGB(150, 85, 55), Enum.Material.WoodPlanks)
	lp("Churrasqueira", Vector3.new(4, 3.6, 2.4), px - 37, G + 2.3, pz - 4.5, Color3.fromRGB(160, 80, 55), Enum.Material.Brick)
	lp("MesaQuiosque", Vector3.new(8, 0.4, 3), px - 37, G + 3, pz + 1.5, WOOD, Enum.Material.WoodPlanks)

	-- quadra de tênis (do outro lado do caminho)
	local tx, tz = W * 0.27, -D * 0.06
	local CW, CL = 26, 54
	local court = lp("QuadraTenis", Vector3.new(CW + 10, 0.3, CL + 12), tx, G + 0.15, tz, Color3.fromRGB(70, 140, 90), Enum.Material.Concrete)
	court:SetAttribute("Esporte", "tenis")
	deco("Piso", Vector3.new(CW, 0.05, CL), tx, G + 0.33, tz, Color3.fromRGB(45, 105, 165), Enum.Material.SmoothPlastic)
	local function line(sx, sz, ox, oz)
		deco("Linha", Vector3.new(sx, 0.05, sz), tx + ox, G + 0.37, tz + oz, WHITE, Enum.Material.SmoothPlastic)
	end
	line(CW, 0.3, 0, -CL / 2)
	line(CW, 0.3, 0, CL / 2)
	line(0.3, CL, -CW / 2, 0)
	line(0.3, CL, CW / 2, 0)
	line(0.3, CL, -CW / 2 + 3, 0)
	line(0.3, CL, CW / 2 - 3, 0)
	line(CW - 6, 0.3, 0, -CL / 4)
	line(CW - 6, 0.3, 0, CL / 4)
	line(0.3, CL / 2, 0, 0)
	lp("Rede", Vector3.new(CW + 2, 3, 0.15), tx, G + 1.8, tz, Color3.fromRGB(240, 240, 240), Enum.Material.Fabric, { Transparency = 0.35 })
	for _, k in ipairs({ -1, 1 }) do
		column(f, "PosteRede", pos(tx + k * (CW / 2 + 1), G + 0.3, tz), 3.6, 0.2, METAL, Enum.Material.Metal)
	end
	-- alambrado (tela verde) em volta, com 4 postes de luz
	local fw, fl = CW + 10, CL + 12
	for _, k in ipairs({ -1, 1 }) do
		lp("Alambrado", Vector3.new(fw, 9, 0.2), tx, G + 4.8, tz + k * fl / 2, Color3.fromRGB(30, 90, 50), Enum.Material.Fabric, { Transparency = 0.7 })
		lp("Alambrado", Vector3.new(0.2, 9, fl), tx + k * fw / 2, G + 4.8, tz, Color3.fromRGB(30, 90, 50), Enum.Material.Fabric, { Transparency = 0.7 })
		for _, j in ipairs({ -1, 1 }) do
			column(f, "PosteLuz", pos(tx + k * fw / 2, G + 0.3, tz + j * fl / 2), 14, 0.25, METAL, Enum.Material.Metal)
			deco("Refletor", Vector3.new(2, 1, 1), tx + k * fw / 2, G + 14.5, tz + j * fl / 2, Color3.fromRGB(255, 250, 225), Enum.Material.Neon)
		end
	end
	local bancoQuadra = pos(tx - fw / 2 - 4, G, tz)
	kit.bench(f, bancoQuadra, math.pi / 2)

	-- parquinho (escorregador e balanço)
	local kx, kz = W * 0.27, hz - 46
	if kz > tz + fl / 2 + 10 then
		lp("AreiaParquinho", Vector3.new(22, 0.3, 16), kx, G + 0.15, kz, Color3.fromRGB(232, 211, 160), Enum.Material.Sand)
		deco("TorreEscorregador", Vector3.new(4, 5, 4), kx - 6, G + 2.8, kz, Color3.fromRGB(240, 120, 40), Enum.Material.SmoothPlastic)
		P(f, "Escorregador", Vector3.new(2.6, 5, 8), at(kx - 6, G + 2.8, kz + 6) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(250, 210, 40), Enum.Material.SmoothPlastic, { ClassName = "WedgePart" })
		for _, ox in ipairs({ 2, 10 }) do
			column(f, "PosteBalanco", pos(kx + ox, G + 0.3, kz - 3), 7, 0.2, METAL, Enum.Material.Metal)
			column(f, "PosteBalanco", pos(kx + ox, G + 0.3, kz + 3), 7, 0.2, METAL, Enum.Material.Metal)
		end
		deco("TravessaBalanco", Vector3.new(0.3, 0.3, 6.4), kx + 2, G + 7.2, kz, METAL, Enum.Material.Metal)
		deco("TravessaBalanco", Vector3.new(0.3, 0.3, 6.4), kx + 10, G + 7.2, kz, METAL, Enum.Material.Metal)
		for _, ox in ipairs({ 2, 10 }) do
			local seat = P(f, "Balanco", Vector3.new(1.6, 0.25, 1.2), at(kx + ox, G + 2, kz), Color3.fromRGB(40, 140, 220), Enum.Material.SmoothPlastic, { ClassName = "Seat" })
			seat:SetAttribute("SeatText", "Balançar")
		end
	end

	-- palmeiras e bancos nos caminhos
	for z = -hz + 30, hz - 40, 26 do
		for _, sx in ipairs({ -8, 8 }) do
			kit.palm(f, pos(sx, G, z), 1.1 + rng:NextNumber(0, 0.4))
		end
	end
	for _, z in ipairs({ -D * 0.12 - 6, hz - 40 }) do
		kit.bench(f, pos(-14, G, z), math.pi / 2)
		kit.bench(f, pos(14, G, z), -math.pi / 2)
	end
end

return CondoBuilder
