-- FavelaBuilder V6: três comunidades nos limites originais, com encostas distintas,
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
		if i % 12 == 0 then task.wait() end
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
-- Distinção estrutural: linhas de encosta, altura, estreitamentos, paleta e bordas diferentes.
local PROFILES = {
 CDA={name="Anfiteatro da Nebulosa",rows=7,rise=24,lane=7,stairs={-52,101},viewSide=1,
  target=Vector3.new(430,0,-1006),rock=Color3.fromRGB(113,116,108),soil=Color3.fromRGB(129,116,99),brick=.42,telha=.38,
  paint={Color3.fromRGB(74,143,166),Color3.fromRGB(218,174,91),Color3.fromRGB(153,175,128),Color3.fromRGB(188,141,147),CONCRETE}},
 TDE={name="Becos da Lua Negra",rows=8,rise=18,lane=6.5,stairs={-104,66},viewSide=1,
  target=Vector3.new(0,0,0),rock=Color3.fromRGB(100,99,96),soil=Color3.fromRGB(116,105,94),brick=.76,telha=.62,
  paint={Color3.fromRGB(152,149,137),Color3.fromRGB(125,148,140),Color3.fromRGB(165,142,115),Color3.fromRGB(131,139,155)}},
 CDS={name="Crista do Horizonte Solar",rows=9,rise=21,lane=7.5,stairs={-65,79},viewSide=-1,
  target=Vector3.new(900,0,-1900),rock=Color3.fromRGB(166,146,116),soil=Color3.fromRGB(169,132,94),brick=.65,telha=.25,
  paint={Color3.fromRGB(217,188,120),Color3.fromRGB(212,216,194),Color3.fromRGB(103,165,180),Color3.fromRGB(179,143,101)}},
}
local function buildCommunity(F,groups,profile)
 local hx,hz=F.size.X/2,F.size.Y/2
 local north=F.id=="TDE"
 local origin=CFrame.new(F.C+Vector3.new(0,0,north and -hz or hz))*CFrame.Angles(0,north and math.pi or 0,0)
 local function cf(x,y,t)return origin*CFrame.new(x,y,-t)end
 local band=(F.size.Y-78)/profile.rows
 local function curve(x,level)
  if F.id=="CDA"then return .00135*x*x+2*math.sin(level*.7) end
  if F.id=="TDE"then return math.max(0,math.abs(x+40)-90)*.20+(level%2==0 and -4 or 4) end
  return 22*math.sin(x/72+level*.08)+4*math.cos(x/110)
 end
 local function limit(level)
  if F.id=="CDS"then return hx-65-level*6 end
  if F.id=="CDA"then return hx-65-level*10 end
  return hx-65
 end
 local function tAt(x,level)return 20+level*band+curve(x,level)end
 local function yAt(level)
  if F.id=="TDE"then return BASE_Y+math.floor(level/2)*40+(level%2)*8 end
  return BASE_Y+level*profile.rise
 end
 local ground=K.folder("Chao",F.root);local paths=K.folder("Vielas",F.root);local rocks=K.folder("Encostas",F.root)
 F.palette=profile.paint
 -- Reservas locais orientadas: portas e escadarias ficam fora das casas, mesmo nas curvas.
 local parcels={}
 local function box(c,w,d)return {cf=c,w=w,d=d}end
 local function intersects(a,b)
  for _,axis in ipairs({a.cf.RightVector,a.cf.LookVector,b.cf.RightVector,b.cf.LookVector})do
   local ra=math.abs(axis:Dot(a.cf.RightVector))*a.w/2+math.abs(axis:Dot(a.cf.LookVector))*a.d/2
   local rb=math.abs(axis:Dot(b.cf.RightVector))*b.w/2+math.abs(axis:Dot(b.cf.LookVector))*b.d/2
   if math.abs(axis:Dot(b.cf.Position-a.cf.Position))>=ra+rb then return false end
  end
  return true
 end
 local function free(b)
  for _,a in ipairs(parcels)do if intersects(a,b)then return false end end
  return true
 end
 local function reserve(c,w,d)table.insert(parcels,box(c,w,d))end
 local function segment(a,b,width,name,parent)
  local delta=b-a
  local part=P(parent or paths,name,Vector3.new(width,.3,delta.Magnitude+.15),CFrame.lookAt((a+b)/2,b),profile.soil,M.Concrete)
  part:SetAttribute("Walkable",name~="GuardaCorpo")
  return part
 end
 local function stair(a,b,width,name)
  local flat=Vector3.new(b.X-a.X,0,b.Z-a.Z);local rise=b.Y-a.Y
  local n=math.max(1,math.ceil(math.abs(rise)/.55))
  for j=1,n do
   local p=a+flat*((j-.5)/n);local y=a.Y+rise*j/n
   local c=CFrame.lookAt(Vector3.new(p.X,y/2,p.Z),Vector3.new(p.X+flat.X,y/2,p.Z+flat.Z))
   local step=P(paths,name or "Degrau",Vector3.new(width,math.max(.3,y),flat.Magnitude/n+.04),c,CONCRETE,M.Concrete)
   step:SetAttribute("Walkable",true)
  end
 end
 P(ground,"Terra",Vector3.new(F.size.X,.6,F.size.Y),CFrame.new(F.C),profile.soil,M.Ground)
 -- Toda a circulação é reservada antes do assentamento.
 for _,x in ipairs(profile.stairs)do reserve(cf(x,0,F.size.Y/2),10,F.size.Y-12)end
 reserve(cf(F.id=="CDA"and 60 or 0,0,5),12,64)
 -- Pequeno largo de entrada; nenhuma clareira de quarteirão inteiro.
 reserve(cf(-23,0,45),44,30)
 reserve(cf(44,0,tAt(44,0)+16),23,23)
 reserve(cf(-61,0,39),15,17)
 local last=profile.rows-1;local topT=tAt(0,last)
 reserve(cf(0,0,topT+23),34,29)
 local roadSamples={}
 for level=0,last do
  local y=yAt(level);local extent=limit(level)
  local points={};local n=math.ceil(extent*2/34)
  for j=0,n do local x=-extent+j*extent*2/n;table.insert(points,cf(x,y+.2,tAt(x,level)).Position)end
  roadSamples[level]=points
  for j=1,#points-1 do
   segment(points[j],points[j+1],profile.lane,"VielaCurva")
   local a,b=points[j],points[j+1]
   reserve(CFrame.lookAt((a+b)/2,b),profile.lane+5,(b-a).Magnitude+.2)
  end
  -- Patamares seguem as curvas; a faixa das escadarias permanece recortada.
  for x=-extent-5,extent+5,5 do
   local clear=true
   for _,stairX in ipairs(profile.stairs)do if math.abs(x-stairX)<8 then clear=false end end
   if clear then
    local t0=tAt(x,level)-profile.lane/2-.4
    local t1=level<last and tAt(x,level+1)-profile.lane/2-.4 or t0+band-2
    P(ground,"Morro",Vector3.new(5.1,math.max(.6,y),t1-t0),cf(x,y/2,(t0+t1)/2),profile.rock,M.Rock)
    P(ground,"PisoEncosta",Vector3.new(5.1,.18,t1-t0),cf(x,y+.09,(t0+t1)/2),profile.soil,M.Ground)
   end
  end
  if level<last then
   for _,x in ipairs(profile.stairs)do
    local a=cf(x,y+.18,tAt(x,level)+profile.lane/2).Position
    local b=cf(x,yAt(level+1)+.18,tAt(x,level+1)-profile.lane/2-.4).Position
    stair(a,b,6.5)
    segment(cf(x,y+.2,tAt(x,level)).Position,a,6.5,"PeEscadaria")
    segment(b,cf(x,yAt(level+1)+.2,tAt(x,level+1)).Position,6.5,"Desembarque")
   end
  end
  -- Fiação mais baixa e irregular, acompanhando os becos.
  local prev
  for x=-extent+8,extent-8,77 do
   local blocked=false
   for _,stairX in ipairs(profile.stairs)do if math.abs(x-stairX)<9 then blocked=true end end
   if level==0 and math.abs(x-(F.id=="CDA"and 60 or 0))<9 then blocked=true end
   if blocked then continue end
   local t=tAt(x,level)-profile.lane/2-1.4
   P(F.enfeites,"Poste",Vector3.new(.55,14,.55),cf(x,y+7,t),CONCRETE,M.Concrete)
   local lamp=P(F.enfeites,"Luminaria",Vector3.new(1.5,.22,1),cf(x,y+13,t+1),WHITE,M.Neon,{collide=false})
   glow(lamp,20,.45)
   local pos=cf(x,y+12,t).Position
   if prev then
    local mid=(prev+pos)/2-Vector3.new(0,1.5,0)
    for _,ends in ipairs({{prev,mid},{mid,pos}})do
     P(F.enfeites,"Fio",Vector3.new(.06,.06,(ends[2]-ends[1]).Magnitude),CFrame.lookAt((ends[1]+ends[2])/2,ends[2]),DARK,M.Metal,{collide=false,shadow=false})
    end
   end
   prev=pos
  end
  task.wait()
 end
 -- Lotes seguindo a tangente da rua, com frente estreita e quase sem recuo lateral.
 local paidLevels={};local madeSpecs=0
 for level=0,last do
  local y=yAt(level);local extent=limit(level);local x=-extent+4
  while x<extent-17 do
   local w=rng:NextInteger(13,19);local d=rng:NextInteger(17,21)
   local cx=x+w/2;local t=tAt(cx,level)
   local a=cf(cx-.5,y,tAt(cx-.5,level)).Position;local b=cf(cx+.5,y,tAt(cx+.5,level)).Position
   local tangent=(b-a).Unit;local facing=Vector3.new(tangent.Z,0,-tangent.X)
   if facing:Dot(origin.LookVector)>0 then facing=-facing end
   local pos=cf(cx,y+.18,t).Position-facing*(profile.lane/2+4+d/2)
   local c=CFrame.lookAt(pos,pos+facing)
   local plot=box(c,w+1.3,d+1.1)
   local accepted=false
   local loc=origin:PointToObjectSpace(pos)
   if free(plot) and math.abs(loc.X)+w/2+2<hx-40 and -loc.Z+d/2<F.size.Y-14 then
    reserve(c,w+1.3,d+1.1)
    accepted=true
    local paid=level>=1 and level<=6 and not paidLevels[level]
    if paid then paidLevels[level]=true end
    local rel=pos-F.C;local floors=rng:NextInteger(1,4)
    if madeSpecs%3==0 or paid then floors=2 end
    table.insert(F.specs,{x=rel.X,z=rel.Z,y=rel.Y,w=w,d=d,nx=facing.X,nz=facing.Z,floors=floors,
     street=(F.id=="TDE"and "Beco do Eclipse "or F.id=="CDS"and "Ladeira do Sol "or "Viela da Nebulosa ")..(level+1),noHome=paid,paid=paid})
    madeSpecs+=1
   end
   x+=accepted and (w+1.5) or 2
  end
 end
 -- Casas do sopé ocupam as pontas abertas das curvas, com portas voltadas para a rua.
 local x=-limit(0)+4
 while x<limit(0)-19 do
  local w,d=16,18;local cx=x+w/2;local y=yAt(0)
  local a=cf(cx-.5,y,tAt(cx-.5,0)).Position;local b=cf(cx+.5,y,tAt(cx+.5,0)).Position
  local tangent=(b-a).Unit;local facing=Vector3.new(tangent.Z,0,-tangent.X)
  if facing:Dot(origin.LookVector)>0 then facing=-facing end
  local pos=cf(cx,y+.18,tAt(cx,0)).Position+facing*(profile.lane/2+4+d/2)
  local c=CFrame.lookAt(pos,pos-facing);local localPos=origin:PointToObjectSpace(pos)
  local accepted=false
  if -localPos.Z>d/2+8 and free(box(c,w+1.3,d+1.1)) then
   reserve(c,w+1.3,d+1.1);local rel=pos-F.C
   table.insert(F.specs,{x=rel.X,y=rel.Y,z=rel.Z,w=w,d=d,nx=-facing.X,nz=-facing.Z,
    floors=1+rng:NextInteger(0,2),street="Beco do Sopé",noHome=true})
   accepted=true
  end
  x+=accepted and (w+2) or 2
 end
 -- Entrada original intacta. As vielas são acessos a pé, distintos das ruas da cidade.
 local entryX=F.id=="CDA"and 60 or 0
 segment(cf(entryX,BASE_Y+.2,-16).Position,cf(entryX,BASE_Y+.2,tAt(entryX,0)).Position,9,"AcessoOriginal")
 portal(F,F.enfeites,cf(entryX,BASE_Y,1)*CFrame.Angles(0,math.pi,0),12,F.g.Community,F.g)
 campo(F,F.enfeites,cf(-23,BASE_Y+.18,45),36,22,profile.soil,true)
 bar(F,F.enfeites,cf(44,BASE_Y+.18,tAt(44,0)+10)*CFrame.Angles(0,math.pi,0),F.id=="TDE"and "Bar do Beco"or F.id=="CDS"and "Bar do Sol"or "Bar da Pedra",F.g.Color)
 paredao(F,F.enfeites,cf(-61,BASE_Y+.18,36)*CFrame.Angles(0,math.pi,0),F.g.Accent)
 local qg=K.folder("QG",F.root)
 hideoutProps(F,qg,cf(0,yAt(last)+.18,topT+24),28,22)
 chiefSpot(F,qg,cf(0,yAt(last)+.18,topT+10)*CFrame.Angles(0,math.pi,0))
 -- Crista lateral rochosa leva ao mirante na BORDA voltada à cidade, não atrás das casas.
 local ridgeX=profile.viewSide*(hx-20);local lookoutY=yAt(last)+24
 local upperT=tAt(profile.viewSide*limit(last),last)
 local stairEnd=cf(ridgeX-profile.viewSide*5.5,lookoutY,upperT).Position
 stair(cf(profile.viewSide*limit(last),yAt(last)+.2,upperT).Position,stairEnd,7,"EscadaMirante")
 segment(stairEnd,cf(ridgeX,lookoutY,upperT).Position,7,"PatamarMirante")
 local previous
 for t=60,upperT+1,18 do
  local rx=ridgeX+math.sin(t/37)*1.5
  local pos=cf(rx,lookoutY,t).Position
  if t<upperT-18 then
   P(rocks,"CristaPedra",Vector3.new(23,lookoutY-1,19),cf(rx,(lookoutY-1)/2,t)*CFrame.Angles(0,math.sin(t)*.08,0),profile.rock,M.Rock,{class="WedgePart"})
   P(rocks,"BaseTrilha",Vector3.new(9,lookoutY-1,19),cf(rx,(lookoutY-1)/2,t),profile.rock,M.Rock)
  end
  if previous then
   segment(previous,pos,8,"TrilhaMirante")
   for _,side in ipairs(t<upperT-18 and {-1,1} or {})do
    local off=origin.RightVector*(side*3.8)
    local p=segment(previous+off+Vector3.new(0,1.3,0),pos+off+Vector3.new(0,1.3,0),.3,"GuardaCorpo")
    p.Size=Vector3.new(.3,2.6,p.Size.Z);p.Color=SLAB_GREY
   end
  end
  previous=pos
 end
 -- Conecta a sobra final do percurso, evitando qualquer salto entre escada e trilha.
 if previous then segment(previous,cf(ridgeX,lookoutY,upperT).Position,8,"LigacaoCrista")end
 local viewPos=cf(profile.viewSide*(hx-29),lookoutY,30).Position
 local target=Vector3.new(profile.target.X,viewPos.Y,profile.target.Z)
 local viewCf=CFrame.lookAt(viewPos,target)
 local ridgeEntry=cf(ridgeX+math.sin(60/37)*1.5,lookoutY,60).Position
 local entryLocal=viewCf:PointToObjectSpace(ridgeEntry)
 local side=entryLocal.X>=0 and 1 or -1
 local corner=(viewCf*CFrame.new(side*21,0,16)).Position
 local rear=(viewCf*CFrame.new(0,0,16)).Position
 for _,ends in ipairs({{ridgeEntry,corner},{corner,rear},{rear,(viewCf*CFrame.new(0,0,5)).Position}})do
  local p=segment(ends[1],ends[2],7,"EntradaMirante")
  local supportCf=p.CFrame-Vector3.new(0,lookoutY/2+.5,0)
  P(rocks,"EsporaMirante",Vector3.new(5,lookoutY-1,p.Size.Z),supportCf,profile.rock,M.Rock)
 end
 local deck=P(qg,"Mirante",Vector3.new(28,.5,20),viewCf,CONCRETE,M.Concrete)
 deck:SetAttribute("ViewTarget",profile.target)
 for _,x in ipairs({-13,13})do
  P(qg,"GuardaCorpoMirante",Vector3.new(.3,2.6,20),viewCf*CFrame.new(x,1.5,0),SLAB_GREY,M.Metal)
 end
 P(qg,"GuardaCorpoFrente",Vector3.new(26,2.2,.3),viewCf*CFrame.new(0,1.3,-9.5),SLAB_GREY,M.Metal)
 for _,x in ipairs({-8,8})do seat(qg,viewCf*CFrame.new(x,1.6,6),Vector3.new(5,.4,2),WOOD,"Contemplar a cidade")end
 local sign=P(qg,"NomeMirante",Vector3.new(15,2,.2),viewCf*CFrame.new(0,3,8),F.g.Color,M.Metal,{collide=false})
 K.addSurfaceText(sign,"MIRANTE • "..F.g.Community,WHITE,F.g.Color)
 F.root:SetAttribute("MirantePosition",viewPos)
 F.root:SetAttribute("MiranteTarget",profile.target)
 F.root:SetAttribute("MiranteHeight",lookoutY)
 -- A encosta continua atrás das últimas casas: não sobra um campo plano entre bairro e costão.
 for x=-hx+42,hx-42,20 do
  local start=tAt(math.clamp(x,-limit(last),limit(last)),last)+band-2
  local finish=F.size.Y-27
  if finish>start then
   local height=yAt(last)+8
   P(ground,"EncostaFundo",Vector3.new(20.1,height,finish-start+.3),cf(x,height/2,(start+finish)/2),profile.rock,M.Rock)
  end
 end
 -- Costões e rochas de fundo têm silhuetas diferentes e ficam dentro da reserva original.
 for i=0,10 do
  local x=-hx+32+i*(F.size.X-64)/10
  local height=lookoutY+(F.id=="CDS"and 28 or 12)+12*math.sin(i*1.7)
  P(rocks,"Costao",Vector3.new(38,height,23),cf(x,height/2,F.size.Y-16)*CFrame.Angles(0,(i%3-1)*.08,0),profile.rock,M.Rock,{class="WedgePart"})
 end
 -- Vegetação em bolsões rochosos; não ocupa as vielas e não exige novos assets.
 if K.palm then
  for _,x in ipairs({-hx+34,hx-34})do K.palm(F.enfeites,cf(x,.3,9).Position,F.id=="CDS"and .7 or .9)end
 end
 for i=1,8 do
  local x=-profile.viewSide*(hx-25);local t=35+i*(F.size.Y-65)/9
  local h=F.id=="CDS"and 8+i*6 or 8+i*4
  P(rocks,"PedraSolta",Vector3.new(27,h,23),cf(x,h/2,t)*CFrame.Angles(0,i*.7,0),profile.rock,M.Rock,{class="WedgePart"})
  if F.id~="CDS" then
   P(F.enfeites,"ArbustoEncosta",Vector3.new(8,5,7),cf(x,h+1,t),Color3.fromRGB(66,98,64),M.Grass,{shape=BALL,collide=false})
  end
 end
 kites(F,F.enfeites,6,Vector2.new(hx-35,hz-35),lookoutY+25,lookoutY+65)
 local regular={}
 for _,s in ipairs(F.specs)do
  if s.paid then table.insert(purchaseQueue,{F=F,s=s})else table.insert(regular,s)end
 end
 F.specs=regular
 local made=buildHouses(F,groups,{brick=profile.brick,paint=profile.paint,telha=profile.telha,twoTanks=.2,brFlags=.08})
 F.root:SetAttribute("Revision","Comunidades V6")
 F.root:SetAttribute("Identity",profile.name)
 F.root:SetAttribute("Terraces",profile.rows)
 F.root:SetAttribute("LaneWidth",profile.lane)
 F.root:SetAttribute("Homes",made)
 F.root:SetAttribute("DecorativeHomes",#regular-made)
 return made
end
local function buildNebulosa(F,groups)return buildCommunity(F,groups,PROFILES.CDA)end
local function buildLuaNegra(F,groups)return buildCommunity(F,groups,PROFILES.TDE)end
local function buildHorizonteSolar(F,groups)return buildCommunity(F,groups,PROFILES.CDS)end

function FavelaBuilder.buildPurchasable(groups)
 local made=0
 for _,item in ipairs(purchaseQueue)do
  local F,s=item.F,item.s
  rng=Random.new(F.g.Seed+800+made)
  local pos=world(F,s.x,s.y,s.z)
  local base=CFrame.lookAt(pos,pos+Vector3.new(s.nx,0,s.nz))
  local id=K.nextHouseId()
  local m,_,door=house(groups.houses,"Casa "..id,base,{w=s.w,d=s.d,floors=2,color=pick(F.palette or MORRO_PAINT),brick=false,door="Door",tanks=1,telha=false})
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

local BUILDERS = { morro = buildNebulosa, complexo = buildLuaNegra, solar = buildHorizonteSolar }

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
