-- FavelaBuilder V5: três comunidades nos limites originais, com cinco patamares,
-- ladeiras, escadarias, moradias variadas e mirantes. Mantém os pontos do GangService.
-- As 30 moradias gratuitas de cada gangue são numeradas na etapa original.
-- Seis casas opcionais por comunidade são adicionadas após as moradias do mapa atual.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local FavelaBuilder = {}

local G = GameConfig.Gangs
local FH = 8.5 -- altura de um andar
local SLAB = 0.5 -- laje entre os andares
local STORY = FH + SLAB
local BASE_Y = 0.3 -- chão da favela (um pouco acima da grama)

local CYL = Enum.PartType.Cylinder
local BALL = Enum.PartType.Ball
local M = Enum.Material

local CONCRETE = Color3.fromRGB(176, 172, 164)
local SLAB_GREY = Color3.fromRGB(150, 148, 142)
local DARK = Color3.fromRGB(38, 38, 44)
local TANK = Color3.fromRGB(40, 110, 200)
local RUST = Color3.fromRGB(110, 70, 50)
local WOOD = Color3.fromRGB(130, 90, 55)
local WHITE = Color3.fromRGB(240, 238, 232)

-- tijolo cru (Material Brick já desenha os tijolos)
local BRICKS = { Color3.fromRGB(184, 98, 62), Color3.fromRGB(170, 88, 56), Color3.fromRGB(196, 112, 72), Color3.fromRGB(160, 92, 66) }
local SOLAR_BRICKS = { Color3.fromRGB(205, 110, 55), Color3.fromRGB(214, 122, 62), Color3.fromRGB(196, 102, 50) }
-- pinturas: o morro é bem colorido; o complexo é mais apagado
local MORRO_PAINT = {
	Color3.fromRGB(170, 140, 225), Color3.fromRGB(240, 170, 215), Color3.fromRGB(130, 190, 235), Color3.fromRGB(250, 220, 120),
	Color3.fromRGB(150, 210, 160), Color3.fromRGB(240, 240, 232), Color3.fromRGB(240, 150, 120), Color3.fromRGB(120, 210, 210),
	Color3.fromRGB(250, 190, 90), Color3.fromRGB(200, 120, 200),
}
local MUTED_PAINT = { Color3.fromRGB(200, 196, 186), Color3.fromRGB(170, 175, 180), Color3.fromRGB(205, 185, 150), Color3.fromRGB(150, 165, 150), Color3.fromRGB(190, 160, 150) }
local DOORS = { Color3.fromRGB(60, 120, 180), Color3.fromRGB(170, 70, 60), Color3.fromRGB(70, 140, 80), Color3.fromRGB(90, 90, 95), Color3.fromRGB(200, 170, 60), Color3.fromRGB(150, 150, 155) }
local BRIGHT = { Color3.fromRGB(255, 80, 80), Color3.fromRGB(80, 200, 255), Color3.fromRGB(255, 220, 60), Color3.fromRGB(120, 255, 120), Color3.fromRGB(255, 120, 255), Color3.fromRGB(255, 160, 60) }

local K -- ferramentas do MapBuilder
local rng -- sorteio da favela que está sendo montada

local function pick(list)
	return list[rng:NextInteger(1, #list)]
end

local function chance(p)
	return rng:NextNumber() < p
end

-- Peça simples. extra: shape, collide, transparency, class
local function P(parent, name, size, cf, color, material, extra)
	extra = extra or {}
	return K.makePart(parent, {
		ClassName = extra.class,
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
end

local function glow(part, range, brightness, color)
	local light = Instance.new("PointLight")
	light.Range = range
	light.Brightness = brightness
	light.Color = color or Color3.fromRGB(255, 225, 170)
	light.Parent = part
end

-- Cilindro em pé (eixo Y)
local function upright(cf)
	return cf * CFrame.Angles(0, 0, math.rad(90))
end

---------------------------------------------------------------------------
-- Espaço ocupado dentro da favela (retângulos alinhados com os eixos, coordenadas locais)
---------------------------------------------------------------------------

local occ

local function isFreeLocal(x0, z0, x1, z1)
	for _, r in ipairs(occ) do
		if x0 < r[3] and x1 > r[1] and z0 < r[4] and z1 > r[2] then
			return false
		end
	end
	return true
end

local function block(x0, z0, x1, z1)
	table.insert(occ, { math.min(x0, x1), math.min(z0, z1), math.max(x0, x1), math.max(z0, z1) })
end

---------------------------------------------------------------------------
-- Casa da favela: 1 a 4 andares meio tortos, laje, caixa d'água, ferro aparecendo
---------------------------------------------------------------------------

-- base = CFrame no chão, no meio da casa, com a frente (-Z) virada para a viela.
-- o = { w, d, floors, color, brick, door ("Door" = dá para morar), tanks, telha, accent }
-- Devolve o modelo e a altura do topo.
local function house(parent, name, base, o)
	local m = K.model(name, parent)
	local w, d, floors = o.w, o.d, o.floors
	local doorX = (chance(0.5) and -1 or 1) * math.max(0, w / 2 - 2.6)
	-- andares: { largura, deslocamento, cor, material }. Andares iguais seguidos viram um bloco só
	-- (menos peças); a laje só aparece onde o andar muda (puxadinho) e no topo.
	local levels = {}
	local ox, fw = 0, w
	for f = 0, floors - 1 do
		local color, mat = o.color, o.brick and M.Brick or M.Plaster
		if f > 0 then
			if chance(0.3) then
				fw = w - rng:NextInteger(1, 3) -- andar de cima menor (puxadinho)
				ox = (w - fw) / 2 * (chance(0.5) and -1 or 1)
			end
			if not o.brick and chance(0.25) then
				color, mat = pick(BRICKS), M.Brick -- andar de cima sem reboco
			end
		end
		local prev = levels[#levels]
		if prev and prev.w == fw and prev.ox == ox and prev.color == color then
			prev.n += 1
		else
			table.insert(levels, { w = fw, ox = ox, color = color, mat = mat, f0 = f, n = 1 })
		end
	end
	for _, lv in ipairs(levels) do
		local y0 = lv.f0 * STORY
		local h = lv.n * STORY - SLAB
		P(m, "Parede", Vector3.new(lv.w, h, d), base * CFrame.new(lv.ox, y0 + h / 2, 0), lv.color, lv.mat)
		P(m, "Laje", Vector3.new(lv.w + 0.5, SLAB, d + 0.5), base * CFrame.new(lv.ox, y0 + h + SLAB / 2, 0), SLAB_GREY, M.Concrete)
		-- janelas da frente: uma por andar (às vezes duas nas casas largas), longe da porta
		for f = lv.f0, lv.f0 + lv.n - 1 do
			local y = f * STORY
			local xs = { lv.ox + rng:NextNumber(-lv.w / 4, lv.w / 4) }
			if lv.w >= 12 and chance(0.3) then
				xs = { lv.ox - lv.w / 4, lv.ox + lv.w / 4 }
			end
			if f > 0 and chance(0.25) then
				xs = {} -- parede cega (sem janela) às vezes
			end
			for _, wx in ipairs(xs) do
				if f == 0 and math.abs(wx - doorX) < 3.4 then
					wx = -doorX * 0.5
				end
				if not (f == 0 and math.abs(wx - doorX) < 3.4) then
					local wc = chance(0.2) and pick(DOORS) or DARK
					P(m, "Janela", Vector3.new(2.4, 2.6, 0.3), base * CFrame.new(wx, y + 4.8, -d / 2 - 0.1), wc, M.SmoothPlastic, { collide = false })
				end
			end
		end
	end
	local topLv = levels[#levels]
	local topW, tox = topLv.w, topLv.ox
	if floors > 1 and chance(0.1) then
		P(m, "ArCondicionado", Vector3.new(2, 1.3, 1), base * CFrame.new(tox + topW / 2 - 1.6, (floors - 1) * STORY + 2.2, -d / 2 - 0.5), WHITE, M.SmoothPlastic, { collide = false })
	end
	-- porta no térreo
	local door = P(m, o.door or "Porta", Vector3.new(3.2, 6.6, 0.35), base * CFrame.new(doorX, 3.3, -d / 2 - 0.15), pick(DOORS), M.Metal)
	-- pichação colorida em algumas fachadas (cor da gangue às vezes)
	if chance(0.1) then
		local c = (o.accent and chance(0.5)) and o.accent or pick(BRIGHT)
		P(m, "Grafite", Vector3.new(math.min(5, w - 4), 2.2, 0.1), base * CFrame.new(-doorX * 0.5, 1.8, -d / 2 - 0.06), c, M.SmoothPlastic, { collide = false })
	end
	-- topo: telha de metal ou laje com caixa d'água e ferro para cima
	local top = floors * STORY
	if o.telha then
		P(m, "Telha", Vector3.new(topW + 1, 0.3, d + 1.4), base * CFrame.new(tox, top + 0.5, 0) * CFrame.Angles(math.rad(5), 0, 0), chance(0.5) and Color3.fromRGB(150, 150, 155) or Color3.fromRGB(170, 90, 60), M.CorrodedMetal)
	else
		for i = 1, o.tanks or 1 do
			local tx = tox + (i == 1 and -1 or 1) * math.max(0, topW / 2 - 2.2) * (chance(0.5) and 1 or -1)
			P(m, "CaixaDagua", Vector3.new(2.6, 3.2, 3.2), upright(base * CFrame.new(tx, top + 1.3, d / 2 - 2.4)), TANK, M.SmoothPlastic, { shape = CYL })
		end
		if chance(0.2) then
			P(m, "Ferro", Vector3.new(0.2, 2.6, 0.2), base * CFrame.new(tox - topW / 2 + 0.5, top + 1.3, -d / 2 + 0.5), RUST, M.Metal, { collide = false })
		end
		if chance(0.08) then
			-- varal na laje
			P(m, "Varal", Vector3.new(topW - 2, 0.08, 0.08), base * CFrame.new(tox, top + 2.6, -d / 4), WHITE, M.SmoothPlastic, { collide = false })
			P(m, "Roupa", Vector3.new(1.4, 1.6, 0.08), base * CFrame.new(tox - 1.5, top + 1.8, -d / 4), pick(BRIGHT), M.Fabric, { collide = false })
			P(m, "Roupa", Vector3.new(1.2, 1.4, 0.08), base * CFrame.new(tox + 1.5, top + 1.9, -d / 4), pick(BRIGHT), M.Fabric, { collide = false })
		end
	end
 -- Estrutura aparente, reboco parcial e esquadrias de cada pavimento.
 for f=0,floors-1 do
  local y=f*STORY
  for _,x in ipairs({-w/2+.3,w/2-.3})do
   P(m,"PilarConcreto",Vector3.new(.6,STORY,.45),base*CFrame.new(x,y+STORY/2,-d/2-.16),CONCRETE,M.Concrete)
  end
  P(m,"Viga",Vector3.new(w,.5,.45),base*CFrame.new(0,y+FH,-d/2-.18),SLAB_GREY,M.Concrete)
  -- Janelas laterais dão leitura de casa nas curvas, além da fachada frontal.
  for _,side in ipairs({-1,1})do
   local wc=base*CFrame.new(side*(w/2+.08),y+4.6,1)*CFrame.Angles(0,math.pi/2,0)
   P(m,"Esquadria",Vector3.new(3.4,3,.22),wc,WHITE,M.Metal,{collide=false})
   P(m,"VidroEscuro",Vector3.new(2.9,2.5,.24),wc,DARK,M.Glass,{collide=false})
   for k=-1,1 do P(m,"Grade",Vector3.new(.08,2.5,.28),wc*CFrame.new(k*.8,0,0),SLAB_GREY,M.Metal,{collide=false}) end
  end
 end
 if o.brick then
  P(m,"RebocoParcial",Vector3.new(w*.35,3,.12),base*CFrame.new(w*.26,2,-d/2-.25),CONCRETE,M.Plaster,{collide=false})
 end
 if floors>=2 and chance(.5) then
  local balcony=base*CFrame.new(0,STORY,-d/2-1.2)
  P(m,"Varanda",Vector3.new(w*.7,.35,2.6),balcony,CONCRETE,M.Concrete)
  P(m,"CorrimaoVaranda",Vector3.new(w*.7,.14,.14),balcony*CFrame.new(0,2.5,-1.2),DARK,M.Metal)
  for k=-2,2 do P(m,"GradeVaranda",Vector3.new(.12,2.5,.12),balcony*CFrame.new(k*w*.16,1.25,-1.2),DARK,M.Metal) end
 end
 if o.telha then
  for k=0,7 do
   P(m,"OndaTelha",Vector3.new(.16,.14,d+1.4),base*CFrame.new(-w/2+k*w/7,top+.72,0)*CFrame.Angles(math.rad(5),0,0),SLAB_GREY,M.CorrodedMetal,{collide=false})
  end
 else
  P(m,"ParapeitoLaje",Vector3.new(w,.8,.4),base*CFrame.new(0,top+.4,-d/2),CONCRETE,M.Concrete)
  for _,tank in ipairs(m:GetChildren())do
   if tank.Name == "CaixaDagua" then
    P(m,"TampaCaixa",Vector3.new(.24,3.5,3.5),upright(CFrame.new(tank.Position+Vector3.new(0,1.42,0))),TANK,M.SmoothPlastic,{shape=CYL,collide=false})
   end
  end
 end
 if chance(.3)then
  P(m,"AntenaHaste",Vector3.new(.12,3,.12),base*CFrame.new(w/2-1,top+1.5,0),SLAB_GREY,M.Metal,{collide=false})
  P(m,"Antena",Vector3.new(3,.12,.12),base*CFrame.new(w/2-1,top+2.8,0),SLAB_GREY,M.Metal,{collide=false})
 end
 if chance(.45)then
  for _,x in ipairs({-w/2+1,w/2-1})do P(m,"SuporteVaral",Vector3.new(.12,3,.12),base*CFrame.new(x,top+1.5,-d/4),WOOD,M.Wood,{collide=false})end
  P(m,"CordaVaral",Vector3.new(w-2,.06,.06),base*CFrame.new(0,top+3,-d/4),WHITE,M.Fabric,{collide=false})
  for k=-2,2 do P(m,"RoupaColorida",Vector3.new(1.3,1.7,.08),base*CFrame.new(k*2.1,top+2.15,-d/4),pick(BRIGHT),M.Fabric,{collide=false})end
 end
	return m, top, door
end

---------------------------------------------------------------------------
-- Montagem comum
---------------------------------------------------------------------------

-- F = favela sendo montada: { g, id, C, root, casas, enfeites, specs, streets }
local function world(F, x, y, z)
	return F.C + Vector3.new(x, y, z)
end

local function at(F, x, y, z)
	return CFrame.new(world(F, x, y, z))
end

-- Fileira de casas com a frente numa linha reta. (sx, sz) = começo da linha, (tx, tz) = sentido da
-- fileira (eixo X ou Z), len = comprimento, (nx, nz) = para onde as casas olham (a viela).
-- opt: y, street, wMin, wMax, dMin, dMax, floors = {pesos}, setback
local function row(F, sx, sz, tx, tz, len, nx, nz, opt)
	local t = 0
	local count = 0
	while t + opt.wMin <= len do
		local w = rng:NextInteger(opt.wMin, opt.wMax)
		if t + w > len then
			w = math.floor(len - t)
		end
		if w < opt.wMin then
			break
		end
		local d = rng:NextInteger(opt.dMin, opt.dMax)
		local back = opt.setback or 0
		local ax, az = sx + tx * (t + w / 2), sz + tz * (t + w / 2)
		local cx, cz = ax - nx * (back + d / 2), az - nz * (back + d / 2)
		local hx = math.abs(tx) * w / 2 + math.abs(nx) * d / 2
		local hz = math.abs(tz) * w / 2 + math.abs(nz) * d / 2
		if isFreeLocal(cx - hx + 0.05, cz - hz + 0.05, cx + hx - 0.05, cz + hz - 0.05) then
			block(cx - hx, cz - hz, cx + hx, cz + hz)
			-- andares sorteados pelos pesos
			local total = 0
			for _, p in ipairs(opt.floors) do
				total += p
			end
			local r, floors = rng:NextNumber() * total, 1
			for i, p in ipairs(opt.floors) do
				r -= p
				if r <= 0 then
					floors = i
					break
				end
			end
			table.insert(F.specs, { x = cx, z = cz, y = opt.y or BASE_Y, w = w, d = d, nx = nx, nz = nz, floors = floors, street = opt.street, gap = opt.gap })
			count += 1
			-- vão entre as casas: quase sempre colado, às vezes uma frestinha
			t += w + (chance(0.15) and rng:NextNumber(1, 3) or 0)
		else
			t += 2
		end
	end
	return count
end

-- Escada reta: sobe "rise" ao longo de (dx, dz) em "run" studs, a partir de (x, z) local, altura y.
local function stairs(F, parent, x, z, dx, dz, run, rise, width, y, color)
	local n = math.max(4, math.floor(rise / 0.75 + 0.5))
	local step = run / n
	for i = 1, n do
		local h = rise * i / n
		local cx, cz = x + dx * (step * (i - 0.5)), z + dz * (step * (i - 0.5))
		local sx = math.abs(dx) * step + math.abs(dz) * width
		local sz = math.abs(dz) * step + math.abs(dx) * width
		P(parent, "Degrau", Vector3.new(sx, h, sz), at(F, cx, y + h / 2, cz), color or CONCRETE, M.Concrete)
	end
end

-- Mureta reta entre dois pontos locais (mesma altura)
local function wall(F, parent, x0, z0, x1, z1, y, height, thick, color, material, name)
	local a, b = world(F, x0, 0, z0), world(F, x1, 0, z1)
	local len = (b - a).Magnitude
	if len < 0.5 then
		return nil
	end
	local mid = (a + b) / 2
	return P(parent, name or "Mureta", Vector3.new(thick, height, len), CFrame.lookAt(mid, b) + Vector3.new(0, y + height / 2, 0), color or CONCRETE, material or M.Concrete)
end

-- Poste com fios até o próximo (gato de luz)
local function poles(F, parent, points, y)
	local tops = {}
	for _, p in ipairs(points) do
		local base = world(F, p[1], p[3] or y, p[2])
		P(parent, "Poste", Vector3.new(0.6, 15, 0.6), CFrame.new(base + Vector3.new(0, 7.5, 0)), Color3.fromRGB(150, 145, 135), M.Concrete)
		P(parent, "Cruzeta", Vector3.new(3, 0.3, 0.3), CFrame.new(base + Vector3.new(0, 14.2, 0)), WOOD, M.Wood, { collide = false })
		table.insert(tops, base + Vector3.new(0, 14, 0))
	end
	for i = 1, #tops - 1 do
		local a, b = tops[i], tops[i + 1]
		local len = (b - a).Magnitude
		if len < 140 then
			for _, off in ipairs({ -1.2, 1.2 }) do
				local o = Vector3.new(off, -0.4 * math.abs(off), 0)
				P(parent, "Fio", Vector3.new(0.08, 0.08, len), CFrame.lookAt((a + b) / 2 + o, b + o), DARK, M.SmoothPlastic, { collide = false, shadow = false })
			end
		end
	end
end

-- Bandeira num mastro: pano com a sigla
local function flag(F, parent, x, y, z, face, text, color, accent, height)
	height = height or 12
	local base = world(F, x, y, z)
	P(parent, "Mastro", Vector3.new(0.4, height, 0.4), CFrame.new(base + Vector3.new(0, height / 2, 0)), Color3.fromRGB(200, 200, 205), M.Metal)
	local cf = CFrame.lookAt(base + Vector3.new(0, height - 2, 0), base + Vector3.new(0, height - 2, 0) + face) * CFrame.new(2.8, 0, 0)
	local cloth = P(parent, "Bandeira", Vector3.new(5.4, 3.4, 0.12), cf, color, M.Fabric, { collide = false })
	K.addSurfaceText(cloth, text, accent, color)
	return cloth
end

-- Bandeira do Brasil pequena (para as lajes do Horizonte Solar)
local function brFlag(parent, cf)
	P(parent, "MastroBR", Vector3.new(0.2, 5, 0.2), cf * CFrame.new(0, 2.5, 0), WHITE, M.Metal, { collide = false })
	local cloth = cf * CFrame.new(1.6, 4.1, 0)
	P(parent, "BandeiraBR", Vector3.new(3, 2, 0.1), cloth, Color3.fromRGB(0, 150, 60), M.Fabric, { collide = false })
	P(parent, "LosangoBR", Vector3.new(1.3, 1.3, 0.12), cloth * CFrame.Angles(0, 0, math.rad(45)), Color3.fromRGB(250, 215, 0), M.Fabric, { collide = false })
	P(parent, "CirculoBR", Vector3.new(0.14, 0.9, 0.9), cloth * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(30, 50, 150), M.Fabric, { shape = CYL, collide = false })
end

-- Pipas no céu (o cliente faz elas balançarem)
local function kites(F, parent, n, spread, minY, maxY)
	for _ = 1, n do
		local x, z = rng:NextNumber(-spread.X, spread.X), rng:NextNumber(-spread.Y, spread.Y)
		local cf = at(F, x, rng:NextNumber(minY, maxY), z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
		local kite = P(parent, "Pipa", Vector3.new(3, 3, 0.1), cf * CFrame.Angles(0, 0, math.rad(45)), pick(BRIGHT), M.SmoothPlastic, { collide = false, shadow = false })
		kite:SetAttribute("Base", kite.CFrame)
		kite.CanQuery = false
		local tail = P(kite, "Rabiola", Vector3.new(0.15, 4, 0.05), cf * CFrame.new(0, -3.6, 0), pick(BRIGHT), M.SmoothPlastic, { collide = false, shadow = false })
		tail.CanQuery = false
	end
end

-- Banquinho de bar / banco: Seat (o SeatService liga o "Sentar")
local function seat(parent, cf, size, color, text)
	local s = P(parent, "Banco", size or Vector3.new(1.8, 0.4, 1.8), cf, color or Color3.fromRGB(200, 50, 45), M.SmoothPlastic, { class = "Seat" })
	if text then
		s:SetAttribute("SeatText", text)
	end
	return s
end

-- Bar: balcão virado para a rua, banquinhos, placa. cf = chão no meio da frente (frente -Z).
local function bar(F, parent, cf, name, color)
	local b = K.model(name, parent)
	P(b, "Parede", Vector3.new(16, FH, 0.6), cf * CFrame.new(0, FH / 2, 12), color, M.Plaster)
	for _, s in ipairs({ -1, 1 }) do
		P(b, "Parede", Vector3.new(0.6, FH, 12), cf * CFrame.new(s * 8, FH / 2, 6), color, M.Plaster)
	end
	P(b, "Laje", Vector3.new(17, SLAB, 13.5), cf * CFrame.new(0, FH + SLAB / 2, 6), SLAB_GREY, M.Concrete)
	P(b, "Toldo", Vector3.new(17, 0.3, 4), cf * CFrame.new(0, FH - 1, -1.6) * CFrame.Angles(math.rad(-12), 0, 0), color:Lerp(Color3.new(1, 1, 1), 0.3), M.Fabric, { collide = false })
	local counter = P(b, "BarBalcao", Vector3.new(12, 3.6, 1.6), cf * CFrame.new(0, 1.8, 1.4), WOOD, M.WoodPlanks)
	counter:SetAttribute("BarBalcao", name)
	P(b, "Prateleira", Vector3.new(12, 0.3, 1.2), cf * CFrame.new(0, 5, 11), WOOD, M.Wood)
	for i = -2, 2 do
		P(b, "Garrafa", Vector3.new(0.5, 1.2, 0.5), cf * CFrame.new(i * 2.2, 5.75, 11), pick(BRIGHT), M.Glass, { collide = false, transparency = 0.2 })
	end
	P(b, "Geladeira", Vector3.new(3, 6.5, 2.6), cf * CFrame.new(6, 3.25, 9.6), Color3.fromRGB(200, 40, 40), M.SmoothPlastic)
	for i = -2, 2, 2 do
		seat(b, cf * CFrame.new(i * 2, 2.6, -1.4), nil, nil, "Banquinho")
		P(b, "PeBanco", Vector3.new(0.4, 2.4, 0.4), cf * CFrame.new(i * 2, 1.2, -1.4), DARK, M.Metal)
	end
	local sign = P(b, "Placa", Vector3.new(10, 2, 0.3), cf * CFrame.new(0, FH + 1.6, -0.2), WHITE, M.SmoothPlastic, { collide = false })
	K.addSurfaceText(sign, name, Color3.fromRGB(180, 40, 40), WHITE)
	local lamp = P(b, "Lampada", Vector3.new(0.6, 0.6, 0.6), cf * CFrame.new(0, FH - 0.6, 4), Color3.fromRGB(255, 230, 170), M.Neon, { shape = BALL, collide = false })
	glow(lamp, 18, 0.6)
	return b
end

-- Paredão de som (luzes acendem com o botão; música se GameConfig.Gangs.MusicId > 0)
local function paredao(F, parent, cf, accent)
	local m = K.model("Paredao", parent)
	local box = P(m, "Caixas", Vector3.new(10, 7, 3), cf * CFrame.new(0, 3.5, 0), DARK, M.SmoothPlastic)
	box:SetAttribute("Paredao", true)
	for i = -1, 1 do
		for j = 0, 1 do
			P(m, "Alto", Vector3.new(0.3, 2.4, 2.4), cf * CFrame.new(i * 3.2, 2 + j * 3, -1.55) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(70, 70, 76), M.SmoothPlastic, { shape = CYL, collide = false })
		end
	end
	for i = -1, 1, 2 do
		local strip = P(m, "Luz", Vector3.new(0.6, 6, 0.4), cf * CFrame.new(i * 5.2, 3.5, -1.3), accent, M.Neon, { collide = false, transparency = 0.6 })
		strip:SetAttribute("ParedaoLuz", true)
	end
	return m
end

-- Campo de terra com traves e uma bola solta. cf = centro no chão; comprimento no eixo Z.
local function campo(F, parent, cf, w, l, dirt, withBall)
	local m = K.model("Campo", parent)
	P(m, "Terra", Vector3.new(w, 0.3, l), cf * CFrame.new(0, 0.15, 0), dirt, M.Ground)
	for _, s in ipairs({ -1, 1 }) do
		P(m, "Linha", Vector3.new(w, 0.05, 0.4), cf * CFrame.new(0, 0.32, s * (l / 2 - 1)), WHITE, M.SmoothPlastic, { collide = false })
		local goal = cf * CFrame.new(0, 0, s * (l / 2 - 1))
		for _, px in ipairs({ -4, 4 }) do
			P(m, "Trave", Vector3.new(0.4, 5, 0.4), goal * CFrame.new(px, 2.5, 0), WHITE, M.Metal)
		end
		P(m, "Travessao", Vector3.new(8.4, 0.4, 0.4), goal * CFrame.new(0, 5, 0), WHITE, M.Metal)
	end
	P(m, "Meio", Vector3.new(w, 0.05, 0.4), cf * CFrame.new(0, 0.32, 0), WHITE, M.SmoothPlastic, { collide = false })
	if withBall then
		local ball = P(m, "Bola", Vector3.new(2, 2, 2), cf * CFrame.new(0, 2, 0), WHITE, M.SmoothPlastic, { shape = BALL })
		ball:SetAttribute("Bola", true)
		ball:SetAttribute("Home", ball.CFrame)
		ball:SetAttribute("Radius", math.max(w, l) / 2 + 8)
		ball.Anchored = false
	end
	return m
end

-- Placa de entrada da comunidade (pórtico com o nome e a sigla)
local function portal(F, parent, cf, width, title, g)
	local m = K.model("Portal", parent)
	for _, s in ipairs({ -1, 1 }) do
		-- Marco 10.2: o pilar para embaixo da placa (antes atravessava e cortava o nome)
		P(m, "Pilar", Vector3.new(1.4, 11, 1.4), cf * CFrame.new(s * width / 2, 5.5, 0), CONCRETE, M.Concrete)
	end
	local board = P(m, "Placa", Vector3.new(width + 3, 3.2, 0.5), cf * CFrame.new(0, 12.6, 0), g.Color, M.SmoothPlastic, { collide = false })
	K.addSurfaceText(board, title, g.Accent, g.Color)
	local back = P(m, "PlacaVerso", Vector3.new(width + 3, 3.2, 0.1), cf * CFrame.new(0, 12.6, 0.31) * CFrame.Angles(0, math.pi, 0), g.Color, M.SmoothPlastic, { collide = false })
	K.addSurfaceText(back, title, g.Accent, g.Color)
	return m
end

-- Onde o chefe fica (o GangService põe o NPC aqui). cf = chão, olhando para a frente.
local function chiefSpot(F, parent, cf)
	local spot = P(parent, "ChefeSpot", Vector3.new(2, 0.2, 2), cf * CFrame.new(0, 0.1, 0), F.g.Color, M.SmoothPlastic, { collide = false, transparency = 1 })
	spot.CanQuery = false
	spot:SetAttribute("Gang", F.id)
	return spot
end

-- Área da laje / pátio do QG: sofá, mesa, churrasqueira, som, mural e bandeira
local function hideoutProps(F, parent, cf, w, d)
	local g = F.g
	-- sofá (2 lugares) virado para a frente
	for i = -1, 1, 2 do
		seat(parent, cf * CFrame.new(-w / 2 + 6 + i * 1.6, 1.4, d / 2 - 4), Vector3.new(3, 0.8, 2.6), g.Color, "Sofá")
	end
	P(parent, "SofaBase", Vector3.new(7, 1.2, 2.8), cf * CFrame.new(-w / 2 + 6, 0.6, d / 2 - 4), g.Color, M.Fabric)
	P(parent, "SofaEncosto", Vector3.new(7, 2.4, 0.8), cf * CFrame.new(-w / 2 + 6, 1.8, d / 2 - 2.6), g.Color, M.Fabric)
	P(parent, "Mesa", Vector3.new(4, 0.3, 2.4), cf * CFrame.new(-w / 2 + 6, 1.8, d / 2 - 8), WOOD, M.WoodPlanks)
	P(parent, "PeMesa", Vector3.new(0.5, 1.7, 0.5), cf * CFrame.new(-w / 2 + 6, 0.85, d / 2 - 8), DARK, M.Metal)
	-- churrasqueira
	P(parent, "Churrasqueira", Vector3.new(4, 3.4, 2.4), cf * CFrame.new(w / 2 - 5, 1.7, d / 2 - 3), Color3.fromRGB(170, 90, 60), M.Brick)
	local coal = P(parent, "Brasa", Vector3.new(3.2, 0.2, 1.6), cf * CFrame.new(w / 2 - 5, 3.5, d / 2 - 3), Color3.fromRGB(255, 110, 40), M.Neon, { collide = false })
	glow(coal, 10, 0.5, Color3.fromRGB(255, 140, 60))
	-- som
	paredao(F, parent, cf * CFrame.new(w / 2 - 7, 0, -d / 2 + 3) * CFrame.Angles(0, math.pi, 0), g.Accent)
	-- varal de luzes da cor da gangue
	for i = 0, 6 do
		local bulb = P(parent, "Luzinha", Vector3.new(0.5, 0.5, 0.5), cf * CFrame.new(-w / 2 + 3 + i * (w - 6) / 6, 6.5 - (i % 2) * 0.4, 0), i % 2 == 0 and g.Accent or g.Color, M.Neon, { shape = BALL, collide = false })
		if i == 3 then
			glow(bulb, 16, 0.5, g.Accent)
		end
	end
	P(parent, "FioLuzes", Vector3.new(w - 6, 0.06, 0.06), cf * CFrame.new(0, 6.6, 0), DARK, M.SmoothPlastic, { collide = false })
end

-- Separa as casas: 30 viram barracos de morar (Map.Houses), o resto é enfeite. Monta todas.
local function buildHouses(F, groups, opt)
	local candidates = {}
	for i, s in ipairs(F.specs) do
		if s.floors <= 2 and not s.noHome then
			table.insert(candidates, i)
		end
	end
	-- Garante a capacidade original também com o gerador Random do motor Roblox.
	if #candidates < G.ShacksPerFavela then
		for i, s in ipairs(F.specs) do
			if #candidates >= G.ShacksPerFavela then break end
			if s.floors > 2 and not s.noHome then
				s.floors = 2
				table.insert(candidates, i)
			end
		end
	end
	-- embaralha e pega os primeiros
	for i = #candidates, 2, -1 do
		local j = rng:NextInteger(1, i)
		candidates[i], candidates[j] = candidates[j], candidates[i]
	end
	local homes = {}
	for i = 1, math.min(G.ShacksPerFavela, #candidates) do
		homes[candidates[i]] = true
	end
	local numbers = {}
	local made = 0
	for i, s in ipairs(F.specs) do
		local pos = world(F, s.x, s.y, s.z)
		local base = CFrame.lookAt(pos, pos + Vector3.new(s.nx, 0, s.nz))
		local brick = chance(opt.brick)
		local color = brick and pick(opt.bricks or BRICKS) or pick(opt.paint)
		local o = {
			w = s.w,
			d = s.d,
			floors = s.floors,
			color = color,
			brick = brick,
			accent = F.g.Accent,
			telha = chance(opt.telha or 0.1),
			tanks = chance(opt.twoTanks or 0.2) and 2 or 1,
		}
		numbers[s.street] = (numbers[s.street] or 0) + 1
		local number = numbers[s.street]
		if homes[i] then
			local id = K.nextHouseId()
			o.door = "Door"
			o.telha = false
			local m, _, door = house(groups.houses, "Casa " .. id, base, o)
			local plate = P(m, "NumberPlate", Vector3.new(1.4, 1, 0.1), door.CFrame * CFrame.new(0, 4, -0.1), WHITE, M.SmoothPlastic, { collide = false })
			K.addSurfaceText(plate, tostring(number), DARK, WHITE)
			m:SetAttribute("HouseNumber", id)
			m:SetAttribute("Street", s.street .. " - " .. F.g.Community)
			m:SetAttribute("StreetNumber", number)
			m:SetAttribute("Address", ("%s, %d - %s"):format(s.street, number, F.g.Community))
			m:SetAttribute("Tier", "barraco")
			m:SetAttribute("Gang", F.id)
			m:SetAttribute("Remote", true)
			made += 1
		else
			local m, top = house(F.casas, "Casa", base, o)
			if opt.brFlags and top > 10 and chance(opt.brFlags) then
				brFlag(m, base * CFrame.new(-s.w / 2 + 1, top, -s.d / 2 + 1))
			end
		end
	end
	return made
end

---------------------------------------------------------------------------
-- Morro da Nebulosa: morro em patamares
---------------------------------------------------------------------------

-- V5: assentamento em encosta, dentro das reservas originais. Corredores livres antes das casas.
local purchaseQueue = {}
local function buildEncosta(F, groups)
 local hx, hz = F.size.X/2, F.size.Y/2
 local north = F.id == "TDE"
 local origin = CFrame.new(F.C + Vector3.new(0,0,north and -hz or hz)) * CFrame.Angles(0,north and math.pi or 0,0)
 local function cf(x,y,t) return origin*CFrame.new(x,y,-t) end
 local function spec(x,y,t,w,d,floors,street,paid)
  local c=cf(x,y,t);local p=c.Position-F.C;local look=c.LookVector
  -- A frente das casas olha para a viela, em direção à entrada.
  look=-look
  local s={x=p.X,z=p.Z,y=p.Y,w=w,d=d,nx=look.X,nz=look.Z,floors=floors,street=street,noHome=paid,paid=paid}
  table.insert(F.specs,s)
 end
 local ground=K.folder("Chao",F.root)
 local paths=K.folder("Vielas",F.root)
 local baseColor=Color3.fromRGB(124,115,97)
 local laneColor=Color3.fromRGB(153,137,124)
 local band=(F.size.Y-66)/5
 local rise=F.id=="CDA" and 13 or (F.id=="CDS" and 11 or 9)
 local edge=hx-24
 local function path(a,b,width,name)
  local delta=b-a
  local p=P(paths,name,Vector3.new(width,.35,delta.Magnitude+.25),CFrame.lookAt((a+b)/2,b),laneColor,M.Concrete)
  p:SetAttribute("Walkable",true)
  return p
 end
 -- Solo e patamares: corredores laterais vazios para as rampas, sem paredões atravessando-as.
 P(ground,"Terra",Vector3.new(F.size.X,.6,F.size.Y),CFrame.new(F.C),baseColor,M.Ground)
 for level=0,4 do
  local y=BASE_Y+level*rise;local t=30+level*band
  P(ground,"Morro",Vector3.new((hx-44)*2,math.max(.6,y),band),cf(0,y/2,t+band/2-10),baseColor,M.Rock)
  P(ground,"PisoPatamar",Vector3.new((hx-44)*2,.18,band),cf(0,y+.09,t+band/2-10),Color3.fromRGB(139,127,109),M.Ground)
  path(cf(-edge,y+.2,t).Position,cf(edge,y+.2,t).Position,18,"Viela do Mirante "..level)
  -- Corrimão da beira, com aberturas para duas escadarias transversais.
  if level>0 then
   for _,limits in ipairs({{-hx+48,-80},{-60,60},{80,hx-48}}) do
    local mid=(limits[1]+limits[2])/2;local len=limits[2]-limits[1]
    P(paths,"Mureta",Vector3.new(len,2,.5),cf(mid,y+1,t-8),CONCRETE,M.Concrete)
   end
  end
  if level<4 then
   -- Curvas suaves em três segmentos, subida máxima inferior a 18 graus.
   local side=level%2==0 and 1 or -1
   local pts={cf(side*(edge-24),y+.2,t).Position,cf(side*edge,y+.2,t+9).Position,
    cf(side*edge,y+rise+.2,t+band-9).Position,cf(side*(edge-24),y+rise+.2,t+band).Position}
   for j=1,#pts-1 do path(pts[j],pts[j+1],18,"LadeiraCurva") end
   -- Escadarias cortam os quarteirões e chegam ao próximo passeio sem muro no desembarque.
   for _,x in ipairs({-70,70}) do
    local run=band-20;local n=math.ceil(rise/.6)
    for j=1,n do
     local top=y+rise*j/n
     P(paths,"Degrau",Vector3.new(8,top-y,run/n+.05),cf(x,y+(top-y)/2,t+10+run*(j-.5)/n),CONCRETE,M.Concrete)
    end
    path(cf(x,y+.2,t).Position,cf(x,y+.2,t+10).Position,8,"Travessa")
    path(cf(x,y+rise+.2,t+band-10).Position,cf(x,y+rise+.2,t+band).Position,8,"Desembarque")
   end
  end
  -- Casas compactas com recuos, profundidades e alturas diferentes. Becos nunca são preenchidos.
  local x=-hx+50;local count=0
  while x<hx-64 do
   local w=rng:NextInteger(15,22);local d=rng:NextInteger(22,30)
   local center=x+w/2
   local alley=(center-w/2<77 and center+w/2>63)or(center-w/2< -63 and center+w/2> -77)
   local square=(level==0 or level==1 or level==3 or level==4)and math.abs(center)<112
   if not alley and not square and x+w<hx-48 then
    local floors=rng:NextInteger(1,4)
    if count%3==0 then floors=2 end
    spec(center,y+.18,t+12+d/2,w,d,floors,"Viela do Mirante "..(level+1),false)
    count+=1
   end
   x+=w+rng:NextNumber(1.5,3)
  end
  -- Seis casas à venda: dois pequenos grupos ao longo das vielas intermediárias.
  if level==1 or level==3 then
   for j=1,3 do
    local x0=-40+(j-1)*40
    -- Usam a faixa traseira do quarteirão, frente voltada a uma travessa própria.
    local paidT=t+band-13
    spec(x0,y+.18,paidT,17,16,2,"Travessa das Lajes "..level,true)
   end
   path(cf(-54,y+.2,t+band-24).Position,cf(54,y+.2,t+band-24).Position,7,"Travessa das Lajes")
   for _,x0 in ipairs({-54,54}) do path(cf(x0,y+.2,t+8).Position,cf(x0,y+.2,t+band-24).Position,7,"BecoResidencial") end
  end
  -- Iluminação e fiação acompanham as ruas, sem bloquear o piso.
  local previous
  for x0=-hx+50,hx-50,95 do
   local lamp=P(F.enfeites,"Poste",Vector3.new(.65,15,.65),cf(x0,y+7.5,t-6),CONCRETE,M.Concrete)
   local light=P(F.enfeites,"Luminaria",Vector3.new(2,.25,1.1),cf(x0,y+14,t-4.7),WHITE,M.Neon,{collide=false})
   glow(light,23,.55)
   local top=cf(x0,y+13,t-6).Position
   if previous then
    local mid=(previous+top)/2-Vector3.new(0,1.3,0)
    for _,pair in ipairs({{previous,mid},{mid,top}})do
     P(F.enfeites,"Fio",Vector3.new(.07,.07,(pair[2]-pair[1]).Magnitude),CFrame.lookAt((pair[1]+pair[2])/2,pair[2]),DARK,M.Metal,{collide=false,shadow=false})
    end
   end
   previous=top
  end
  task.wait()
 end
 -- Ligação com a estrada original: CDA entra deslocada 60 studs; demais pelo eixo.
 local entryX=F.id=="CDA" and 60 or 0
 path(cf(entryX,BASE_Y+.2,-16).Position,cf(entryX,BASE_Y+.2,30).Position,18,"AcessoOriginal")
 portal(F,F.enfeites,cf(entryX,BASE_Y,2)*CFrame.Angles(0,math.pi,0),20,F.g.Community,F.g)
 if K.palm then
  for _,x in ipairs({-145,145})do K.palm(F.enfeites,cf(x,BASE_Y,10).Position,1)end
 end
 local plaza=cf(0,BASE_Y+.18,57)
 campo(F,F.enfeites,plaza,54,34,Color3.fromRGB(150,116,85),true)
 bar(F,F.enfeites,cf(-91,BASE_Y+.18,53)*CFrame.Angles(0,math.pi,0),"Bar da Comunidade",F.g.Color)
 paredao(F,F.enfeites,cf(91,BASE_Y+.18,53)*CFrame.Angles(0,math.pi,0),F.g.Accent)
 -- Mirante e sede acessíveis pelas ladeiras e escadarias; mantém contratos do GangService.
 local topY=BASE_Y+4*rise;local topT=30+4*band
 local qg=K.folder("QG",F.root)
 local terrace=cf(0,topY+.2,topT+27)
 P(qg,"Mirante",Vector3.new(110,.4,32),terrace,CONCRETE,M.Concrete)
 for _,x in ipairs({-46,46})do seat(qg,terrace*CFrame.new(x,1.5,0),Vector3.new(10,.5,3),WOOD,"Vista da cidade") end
 local sign=P(qg,"NomeMirante",Vector3.new(26,3,.3),cf(0,topY+5,topT+40)*CFrame.Angles(0,math.pi,0),F.g.Color,M.Metal)
 K.addSurfaceText(sign,"MIRANTE • "..F.g.Community,WHITE,F.g.Color)
 hideoutProps(F,qg,cf(-86,topY+.2,topT+28),30,26)
 chiefSpot(F,qg,cf(-87,topY+.2,topT+20)*CFrame.Angles(0,math.pi,0))
 for _,x in ipairs({-105,105})do
  local p=cf(x,topY+.2,topT+30).Position-F.C
  flag(F,qg,p.X,p.Y,p.Z,Vector3.new(0,0,north and -1 or 1),F.g.Short,F.g.Color,F.g.Accent,12)
 end
 kites(F,F.enfeites,6,Vector2.new(hx-30,hz-30),75,110)
 -- Casas pagas são montadas só depois das moradias antigas do restante do mapa.
 local regular={}
 for _,s in ipairs(F.specs)do
  if s.paid then table.insert(purchaseQueue,{F=F,s=s}) else table.insert(regular,s) end
 end
 F.specs=regular
 local made=buildHouses(F,groups,{brick=.48,paint=MORRO_PAINT,telha=.38,twoTanks=.22,brFlags=.08})
 F.root:SetAttribute("Revision","Encostas V5")
 F.root:SetAttribute("Terraces",5)
 F.root:SetAttribute("Homes",made)
 F.root:SetAttribute("DecorativeHomes",#regular-made)
 return made
end

function FavelaBuilder.buildPurchasable(groups)
 local made=0
 for _,item in ipairs(purchaseQueue)do
  local F,s=item.F,item.s
  rng=Random.new(F.g.Seed+800+made)
  local pos=world(F,s.x,s.y,s.z)
  local base=CFrame.lookAt(pos,pos+Vector3.new(s.nx,0,s.nz))
  local id=K.nextHouseId()
  local m,_,door=house(groups.houses,"Casa "..id,base,{w=s.w,d=s.d,floors=2,color=pick(MORRO_PAINT),brick=false,door="Door",tanks=1,telha=false})
  m:SetAttribute("HouseNumber",id)
  m:SetAttribute("Tier","comunidade_"..string.lower(F.id))
  m:SetAttribute("Gang",F.id)
  m:SetAttribute("Remote",true)
  m:SetAttribute("Street",s.street.." - "..F.g.Community)
  m:SetAttribute("StreetNumber",100+made)
  m:SetAttribute("Address",s.street..", "..(100+made).." - "..F.g.Community)
  local plate=P(m,"NumberPlate",Vector3.new(3,1.1,.1),door.CFrame*CFrame.new(0,4,0),WHITE,M.Concrete,{collide=false})
  K.addSurfaceText(plate,tostring(100+made),DARK,WHITE)
  made+=1
 end
 table.clear(purchaseQueue)
 return made
end

local BUILDERS = { morro = buildEncosta, complexo = buildEncosta, solar = buildEncosta }

---------------------------------------------------------------------------
-- Etapas chamadas pelo MapBuilder
---------------------------------------------------------------------------

-- Etapa 1: reserva a área de cada favela (depois das estradas, antes das casas da cidade)
function FavelaBuilder.plan(map, helpers)
	K = helpers
	table.clear(purchaseQueue)
	local plan = { root = K.folder("Favelas", map), items = {} }
	for _, id in ipairs(G.Order) do
		local g = G.List[id]
		local area = K.rect(CFrame.new(g.Center), g.Size.X, g.Size.Y)
		if K.isFree(area) then
			K.occupy(area)
			table.insert(plan.items, { id = id, g = g })
		else
			warn(("[Favelas] Sem espaço livre para %s em (%d, %d)"):format(g.Community, g.Center.X, g.Center.Z))
		end
	end
	return plan
end

-- Etapa 2: monta tudo. Devolve quantos barracos de morar foram feitos.
function FavelaBuilder.build(plan, groups)
	local total = 0
	for _, item in ipairs(plan.items) do
		local g = item.g
		rng = Random.new(g.Seed)
		occ = {}
		-- fora da favela não se constrói (as fileiras da beira não passam do limite)
		local hx, hz = g.Size.X / 2, g.Size.Y / 2
		block(-1e5, -1e5, 1e5, -hz)
		block(-1e5, hz, 1e5, 1e5)
		block(-1e5, -hz, -hx, hz)
		block(hx, -hz, 1e5, hz)
		local root = K.folder(g.Community, plan.root)
		root:SetAttribute("Gang", item.id)
		local F = {
			id = item.id,
			g = g,
			C = g.Center,
			size = g.Size,
			root = root,
			casas = K.folder("Casas", root),
			enfeites = K.folder("Enfeites", root),
			specs = {},
		}
		-- área (o mapa M desenha e põe o nome)
		local area = P(root, "Area", Vector3.new(g.Size.X, 0.2, g.Size.Y), CFrame.new(g.Center + Vector3.new(0, -2, 0)), Color3.fromRGB(150, 120, 95), M.Ground, { collide = false, transparency = 1 })
		area.CanQuery = false
		area.CanTouch = false
		local ok, made = pcall(BUILDERS[g.Style], F, groups)
		if ok then
			total += made
		else
			warn(("[Favelas] Erro ao montar %s: %s"):format(g.Community, tostring(made)))
		end
	end
	return total
end

return FavelaBuilder
