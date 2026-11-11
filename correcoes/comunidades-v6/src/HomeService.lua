-- HomeService (ModuleScript)
-- Caminho: ServerScriptService > Services > HomeService
-- Marco 6: moradia de cada jogador.
-- Três coisas separadas (documento mestre, seção 9):
--   1. PROPRIEDADE (salva): data.homes[nível] = { tier, lock, wall, items, nextId } nos dados do
--      jogador. Ninguém perde a casa: os dados são do jogador, não da fachada.
--      Marco 10.1: VÁRIAS casas, uma de cada nível (a "data.home" antiga vira data.homes).
--      Todo mundo tem a casinha da Vila Esperança ("basica"); quem é de gangue troca ela pelo
--      "barraco" na favela da gangue (GangService chama HomeService.refresh).
--   2. FACHADA (só nesta sessão): ao entrar no jogo, cada casa do jogador recebe uma fachada livre
--      do mesmo NÍVEL (a mesma da última vez, se estiver livre). Ao sair, as fachadas ficam livres.
--   3. INTERIOR (reutilizável): o mesmo cômodo para todos, montado longe da cidade quando alguém
--      entra (e desmontado quando fica vazio), com a decoração do dono.
--      Marco 10.2: apartamento, cobertura e mansão ficam NO LUGAR (InPlace, MoradiaBuilder): a
--      casa de verdade, com vidro e vista. Entrar = aparecer lá dentro; os móveis do dono ficam na
--      sala (peça "Origem"); quem sai das caixas "Limite" (pulou da sacada) deixa de estar dentro.
-- Tudo validado no servidor: só o dono decora, muda cor, tranca ou expulsa; o servidor confere
-- preço, limite de móveis, posição dentro do cômodo e se um móvel não fica em cima de outro.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local HomeConfig = require(Shared:WaitForChild("HomeConfig"))
local FurnitureArt = require(Shared:WaitForChild("FurnitureArt"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local SecurityService = require(script.Parent:WaitForChild("SecurityService"))
local ZoneService = require(script.Parent:WaitForChild("ZoneService"))

local HomeService = {}
local INTERIOR_START = Vector3.new(4000, 300, 0) -- longe da cidade (não aparece de lá)
local INTERIOR_GAP = 120
local ROOM_SLOTS = 60 -- lugares para interiores montados ao mesmo tempo (só os que têm gente dentro)
local EMPTY_RELEASE = 30 -- segundos com o interior vazio até desmontar

local uiUpdate
local dismountVehicle -- função do VehicleService (desce da bike)
local slots = {} -- uma por casa do mapa: { index, house, door, tier, gang, number, address, outside, owner, homeTier, origin, room, interior, models }
local usedRooms = {} -- usedRooms[i] = true (lugar de interior ocupado)
local slotsOf = {} -- slotsOf[player][nível] = slot (casas do jogador nesta sessão)
local insideOf = {} -- insideOf[player] = slot onde a pessoa está agora
local interiorsFolder

local function notice(player, text)
	uiUpdate:FireClient(player, "Notice", { text = text })
end

local function lockLabel(id)
	for _, mode in ipairs(HomeConfig.LockModes) do
		if mode.id == id then
			return mode.label
		end
	end
	return id
end

---------------------------------------------------------------------------
-- Dados das casas
---------------------------------------------------------------------------

-- Marco 10.7: nas casas padrão o baú medieval (20 itens) já vem na casa. Quem já tinha a casa
-- ganha um uma vez (home.bau), no primeiro lugar livre perto da parede do fundo.
local function placeChest(home, tierId)
	if home.bau then
		return
	end
	local want
	for id, spec in pairs(GameConfig.Inventory.Chests) do
		if spec.Give and spec.Tiers[tierId] then
			want = id
		end
	end
	if not want then
		return
	end
	home.bau = true
	for _, it in ipairs(home.items) do
		if it.id == want then
			return
		end
	end
	-- Marco 10.17: já tinha outro baú/guarda-roupa nesta casa? Ele vira o certo do nível
	for _, it in ipairs(home.items) do
		if want ~= "Bau" and GameConfig.Inventory.Chests[it.id] and it.id ~= "Bau" then
			it.id = want
			return
		end
	end
	local def = HomeConfig.tier(tierId)
	local itemDef = HomeConfig.item(want)
	if not itemDef or #home.items >= def.MaxItems then
		return
	end
	local room = def.Room
	for z = math.floor(room.Depth / 2), -math.floor(room.Depth / 2), -1 do
		for x = math.floor(room.Width / 2), -math.floor(room.Width / 2), -1 do
			local item = { u = home.nextId, id = want, x = x, z = z, r = 0, p = 0 }
			local ok = HomeConfig.insideRoom(itemDef, x, z, 0, tierId)
			for _, other in ipairs(home.items) do
				local od = HomeConfig.item(other.id)
				if ok and od and HomeConfig.insideRoom(od, other.x, other.z, other.r, tierId) and HomeConfig.overlaps(item, other) then
					ok = false
				end
			end
			if ok then
				table.insert(home.items, item)
				home.nextId += 1
				return
			end
		end
	end
end

-- Marco 10.18: o Armário de 70 virou o cofre antigo (mais fundo: 4.6 x 4.8). Quem já tinha um
-- encostado na parede ficaria "fora do cômodo" (e sumiria): empurra ele para dentro.
local function fitChests(home, tierId)
	local room = HomeConfig.tier(tierId).Room
	for _, it in ipairs(home.items) do
		local def = GameConfig.Inventory.Chests[it.id] and HomeConfig.item(it.id)
		if def and not HomeConfig.insideRoom(def, it.x, it.z, it.r, tierId) then
			local f = HomeConfig.footprint(def, it.r)
			local hx = room.Width / 2 - HomeConfig.Margin - f.X / 2
			local hz = room.Depth / 2 - HomeConfig.Margin - f.Y / 2
			it.x = math.clamp(it.x, -hx, hx)
			it.z = math.clamp(it.z, -hz, hz)
		end
	end
end

local function ensureChest(home, tierId)
	placeChest(home, tierId)
	fitChests(home, tierId)
end

local function newHome(tierId)
	local def = HomeConfig.tier(tierId)
	local home = { tier = tierId, lock = HomeConfig.DefaultLock, wall = 1, items = {}, nextId = 1, v = def.DataV or 2 }
	for _, d in ipairs(def.DefaultItems or HomeConfig.DefaultItems) do
		table.insert(home.items, { u = home.nextId, id = d.id, x = d.x, z = d.z, r = d.r, p = 0 })
		home.nextId += 1
	end
	ensureChest(home, tierId)
	return home
end

-- Confere e conserta dados salvos (nunca confia em formato antigo/estranho)
local function cleanHome(home, tierId)
	if type(home) ~= "table" then
		return newHome(tierId)
	end
	local valid = false
	for _, mode in ipairs(HomeConfig.LockModes) do
		valid = valid or mode.id == home.lock
	end
	home.lock = valid and home.lock or HomeConfig.DefaultLock
	home.tier = tierId
	home.wall = (type(home.wall) == "number" and HomeConfig.WallColors[home.wall]) and home.wall or 1
	home.nextId = type(home.nextId) == "number" and home.nextId or 1
	local items = {}
	for _, it in ipairs(type(home.items) == "table" and home.items or {}) do
		local def = type(it) == "table" and HomeConfig.item(it.id)
		if def and #items < HomeConfig.tier(tierId).MaxItems and type(it.x) == "number" and type(it.z) == "number" then
			it.r = (type(it.r) == "number" and it.r % 4) or 0
			it.p = type(it.p) == "number" and it.p or 0
			if type(it.u) ~= "number" then
				it.u = home.nextId
				home.nextId += 1
			end
			table.insert(items, it)
		end
	end
	home.items = items
	-- Marco 10.2: quem já tinha apartamento, cobertura ou mansão ganha uma vez os móveis novos
	-- (só os que cabem e não ficam em cima de outro móvel)
	local def = HomeConfig.tier(tierId)
	-- (Marco 10.6: a casa moderna virou casa de verdade; DataV = 3 dá os móveis de novo)
	if def.Style and def.Style.InPlace and home.v ~= (def.DataV or 2) then
		home.v = def.DataV or 2
		for _, d in ipairs(def.DefaultItems or {}) do
			local itemDef = HomeConfig.item(d.id)
			local item = { u = home.nextId, id = d.id, x = d.x, z = d.z, r = d.r, p = 0 }
			local ok = itemDef ~= nil and #home.items < def.MaxItems and HomeConfig.insideRoom(itemDef, d.x, d.z, d.r, tierId)
			for _, other in ipairs(home.items) do
				if ok and HomeConfig.insideRoom(HomeConfig.item(other.id), other.x, other.z, other.r, tierId) and HomeConfig.overlaps(item, other) then
					ok = false
				end
			end
			if ok then
				table.insert(home.items, item)
				home.nextId += 1
			end
		end
	end
	ensureChest(home, tierId)
	return home
end

-- Marco 10.1: data.home (uma casa) vira data.homes (várias). Quem tinha comprado uma casa da
-- cidade continua com ela e ganha a casinha da vila de volta.
local function migrate(data)
	local homes = {}
	if type(data.homes) == "table" then
		for tierId, home in pairs(data.homes) do
			if type(tierId) == "string" and HomeConfig.Tiers[tierId] then
				homes[tierId] = cleanHome(home, tierId)
			end
		end
	elseif type(data.home) == "table" then
		local old = data.home
		local tierId = HomeConfig.Tiers[old.tier] and old.tier or HomeConfig.StartTier
		homes[tierId] = cleanHome(old, tierId)
	end
	data.homes = homes
	data.home = nil
end

local function homesOf(player)
	local data = PlayerDataService.get(player)
	return data and data.homes
end

-- A casa (dados) que está numa fachada
local function homeOfSlot(slot)
	local homes = slot.owner and homesOf(slot.owner)
	return homes and homes[slot.homeTier]
end

local function saveHomes(player)
	local homes = homesOf(player)
	if homes then
		PlayerDataService.set(player, "homes", homes)
	end
end

local function gangOf(player)
	local data = PlayerDataService.get(player)
	local gang = data and data.gang
	return (type(gang) == "string" and GameConfig.Gangs.List[gang]) and gang or nil
end

-- Casa principal (a de nível mais alto): é a do botão "Sua casa" e do mapa
local function mainSlot(player)
	local best
	for _, slot in pairs(slotsOf[player] or {}) do
		if not best or HomeConfig.tier(slot.homeTier).order > HomeConfig.tier(best.homeTier).order then
			best = slot
		end
	end
	return best
end

---------------------------------------------------------------------------
-- Interior
---------------------------------------------------------------------------

local function newPart(parent, props)
	local p = Instance.new(props.ClassName or "Part")
	p.Name = props.Name
	p.Size = props.Size
	p.CFrame = props.CFrame
	p.Color = props.Color or Color3.new(1, 1, 1)
	p.Material = props.Material or Enum.Material.SmoothPlastic
	if props.Shape then
		p.Shape = props.Shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = true
	if props.CanCollide ~= nil then
		p.CanCollide = props.CanCollide
	end
	p.Transparency = props.Transparency or 0
	p.Parent = parent
	return p
end

local function paintWalls(slot, wallIndex)
	local color = HomeConfig.WallColors[wallIndex] or HomeConfig.WallColors[1]
	for _, p in ipairs(slot.interior:GetDescendants()) do
		if p:IsA("BasePart") and p.Name == "Wall" then
			p.Color = color
		end
	end
	-- Marco 10.2: na casa de verdade, as paredes de dentro (divisórias) são do mapa
	if slot.inPlace then
		for _, p in ipairs(slot.house:GetDescendants()) do
			if p:IsA("BasePart") and p.Name == "Wall" then
				p.Color = color
			end
		end
	end
end

-- Marco 10: "vista" pintada na janela. "cidade" = prédios contra o céu (alguns com janelas
-- acesas); "jardim" = árvores e morros (mansão). Sem sorteio solto: cada casa tem sempre a mesma vista.
local function paintView(m, cf, w, h, view, rng)
	if view == "cidade" then
		local n = math.max(3, math.floor(w / 2.4))
		local step = w / n
		for i = 1, n do
			local bw = step * rng:NextNumber(0.7, 1)
			local bh = h * rng:NextNumber(0.25, 0.8)
			local x = -w / 2 + (i - 0.5) * step
			local shade = rng:NextInteger(45, 75)
			newPart(m, { Name = "Skyline", Size = Vector3.new(bw, bh, 0.36), CFrame = cf * CFrame.new(x, -h / 2 + bh / 2, 0), Color = Color3.fromRGB(shade - 10, shade, shade + 20), CanCollide = false })
			if bh > h * 0.4 and rng:NextNumber() < 0.6 then
				newPart(m, { Name = "SkylineLight", Size = Vector3.new(math.min(0.4, bw / 3), 0.3, 0.38), CFrame = cf * CFrame.new(x, -h / 2 + bh * rng:NextNumber(0.5, 0.85), 0), Color = Color3.fromRGB(255, 225, 140), Material = Enum.Material.Neon, CanCollide = false })
			end
		end
	elseif view == "favela" then
		-- Marco 10.1: barracos de tijolo com caixas d'água azuis
		local n = math.max(3, math.floor(w / 1.8))
		local step = w / n
		for i = 1, n do
			local bw = step * rng:NextNumber(0.85, 1)
			local bh = h * rng:NextNumber(0.2, 0.6)
			local x = -w / 2 + (i - 0.5) * step
			newPart(m, { Name = "Barracos", Size = Vector3.new(bw, bh, 0.36), CFrame = cf * CFrame.new(x, -h / 2 + bh / 2, 0), Color = Color3.fromRGB(rng:NextInteger(170, 205), rng:NextInteger(90, 115), 60), CanCollide = false })
			if rng:NextNumber() < 0.5 then
				newPart(m, { Name = "Caixa", Size = Vector3.new(math.min(0.5, bw / 3), 0.35, 0.38), CFrame = cf * CFrame.new(x, -h / 2 + bh + 0.17, 0), Color = Color3.fromRGB(40, 110, 200), CanCollide = false })
			end
		end
	elseif view == "jardim" then
		newPart(m, { Name = "Hill", Size = Vector3.new(w, h * 0.3, 0.36), CFrame = cf * CFrame.new(0, -h / 2 + h * 0.15, 0), Color = Color3.fromRGB(95, 160, 80), CanCollide = false })
		for i = 1, math.max(2, math.floor(w / 3)) do
			local size = math.min(h * rng:NextNumber(0.2, 0.35), w * 0.8)
			local x = (w - size) * (rng:NextNumber() - 0.5) -- disco inteiro dentro da janela
			-- disco (cilindro deitado com o eixo para fora da janela)
			newPart(m, { Name = "TreeTop", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.37, size, size), CFrame = cf * CFrame.new(x, -h / 2 + h * 0.3 + size * 0.3, 0) * CFrame.Angles(0, math.pi / 2, 0), Color = Color3.fromRGB(60, rng:NextInteger(120, 150), 60), CanCollide = false })
		end
	end
end

local function buildInterior(slot, home)
	local o = slot.origin
	local tierDef = HomeConfig.tier(home.tier)
	local room = tierDef.Room
	local style = tierDef.Style or {}
	local W, D, H = room.Width, room.Depth, room.Height
	local rng = Random.new((tonumber(slot.number) or slot.index) * 7919)
	local m = Instance.new("Model")
	m.Name = "Interior_" .. slot.index
	-- Paredes, piso e teto GROSSOS (T = 4): parede fina deixa a luz do céu "vazar" para dentro
	-- e, depois de uns segundos, o motor de luz do Roblox estoura as paredes de branco.
	-- O tamanho de dentro do cômodo continua W x D x H.
	local T = 4
	newPart(m, { Name = "Floor", Size = Vector3.new(W + 2 * T, T, D + 2 * T), CFrame = o * CFrame.new(0, -T / 2, 0), Color = style.Floor or Color3.fromRGB(170, 120, 75), Material = style.FloorMaterial or Enum.Material.WoodPlanks })
	newPart(m, { Name = "Ceiling", Size = Vector3.new(W + 2 * T, T, D + 2 * T), CFrame = o * CFrame.new(0, H + T / 2, 0), Color = Color3.fromRGB(250, 250, 248) })
	local walls = {
		{ Vector3.new(W + 2 * T, H, T), CFrame.new(0, H / 2, D / 2 + T / 2) },
		{ Vector3.new(T, H, D + 2 * T), CFrame.new(-W / 2 - T / 2, H / 2, 0) },
		{ Vector3.new(T, H, D + 2 * T), CFrame.new(W / 2 + T / 2, H / 2, 0) },
		-- parede da porta (-Z), com o vão da porta no meio
		{ Vector3.new(W / 2 - 3 + T, H, T), CFrame.new(-W / 4 - 1.5 - T / 2, H / 2, -D / 2 - T / 2) },
		{ Vector3.new(W / 2 - 3 + T, H, T), CFrame.new(W / 4 + 1.5 + T / 2, H / 2, -D / 2 - T / 2) },
		{ Vector3.new(6, H - 8, T), CFrame.new(0, 8 + (H - 8) / 2, -D / 2 - T / 2) },
	}
	for _, w in ipairs(walls) do
		newPart(m, { Name = "Wall", Size = w[1], CFrame = o * w[2] })
	end
	-- rodapé
	newPart(m, { Name = "Baseboard", Size = Vector3.new(W, 0.6, 0.2), CFrame = o * CFrame.new(0, 0.3, D / 2 - 0.1), Color = Color3.new(1, 1, 1), CanCollide = false })
	for _, s in ipairs({ -1, 1 }) do
		newPart(m, { Name = "Baseboard", Size = Vector3.new(0.2, 0.6, D), CFrame = o * CFrame.new(s * (W / 2 - 0.1), 0.3, 0), Color = Color3.new(1, 1, 1), CanCollide = false })
	end
	-- Marco 10: moldura de gesso no alto das paredes (mansão)
	if style.Moldura then
		newPart(m, { Name = "Crown", Size = Vector3.new(W, 0.8, 0.5), CFrame = o * CFrame.new(0, H - 0.4, D / 2 - 0.25), Color = Color3.new(1, 1, 1), CanCollide = false })
		newPart(m, { Name = "Crown", Size = Vector3.new(W, 0.8, 0.5), CFrame = o * CFrame.new(0, H - 0.4, -D / 2 + 0.25), Color = Color3.new(1, 1, 1), CanCollide = false })
		for _, s in ipairs({ -1, 1 }) do
			newPart(m, { Name = "Crown", Size = Vector3.new(0.5, 0.8, D), CFrame = o * CFrame.new(s * (W / 2 - 0.25), H - 0.4, 0), Color = Color3.new(1, 1, 1), CanCollide = false })
		end
	end
	-- janelas com "céu" (o interior fica longe da cidade, então a vista é pintada)
	local view = style.View
	local winW, winH = 5.8, math.min(3.8 + (H - 10) * 0.5, 8)
	local winY = math.max(6, H * 0.45)
	local function window(cf, ww, wh)
		ww, wh = ww or winW, wh or winH
		newPart(m, { Name = "WindowFrame", Size = Vector3.new(ww + 0.6, wh + 0.6, 0.3), CFrame = cf, Color = Color3.new(1, 1, 1), CanCollide = false })
		-- Marco 10.6: céu mais escuro. O neon claro (150, 205, 250) "estourava" (branco brilhando) dentro
		-- de casa; com a cor mais escura o neon fica azul-céu, sem mexer na luz do jogo.
		newPart(m, { Name = "WindowSky", Size = Vector3.new(ww, wh, 0.32), CFrame = cf, Color = Color3.fromRGB(64, 108, 150), Material = Enum.Material.Neon, CanCollide = false })
		paintView(m, cf, ww, wh, view, rng)
		local bars = math.floor(ww / (ww > 12 and 8 or 3.2))
		for i = 1, bars do
			newPart(m, { Name = "WindowBar", Size = Vector3.new(0.2, wh, 0.4), CFrame = cf * CFrame.new(-ww / 2 + i * ww / (bars + 1), 0, 0), Color = Color3.new(1, 1, 1), CanCollide = false })
		end
		newPart(m, { Name = "WindowSill", Size = Vector3.new(ww + 1, 0.3, 0.8), CFrame = cf * CFrame.new(0, -wh / 2 - 0.45, 0.3), Color = Color3.new(1, 1, 1), CanCollide = false })
	end
	if style.Panorama then
		-- parede do fundo quase toda de vidro (vista panorâmica)
		local pw, ph = W - 12, H - 5
		window(o * CFrame.new(0, 2 + ph / 2, D / 2 - 0.05) * CFrame.Angles(0, math.pi, 0), pw, ph)
	else
		for _, x in ipairs(W < 30 and { -W / 4, W / 4 } or { -W / 3.6, 0, W / 3.6 }) do
			window(o * CFrame.new(x, winY, D / 2 - 0.05) * CFrame.Angles(0, math.pi, 0))
		end
	end
	for _, s in ipairs({ -1, 1 }) do
		for _, z in ipairs(D < 40 and { 0 } or { -D / 5, D / 5 }) do
			window(o * CFrame.new(s * (W / 2 - 0.05), winY, z) * CFrame.Angles(0, s * math.pi / 2, 0))
		end
	end
	-- luzes do teto
	local lampXs = W < 30 and { 0 } or (W < 70 and { -W / 4, W / 4 } or { -W / 3, 0, W / 3 })
	local lampZs = D < 50 and { 0 } or { -D / 4, D / 4 }
	for _, x in ipairs(lampXs) do
		for _, z in ipairs(lampZs) do
			if not (style.Lustre and x == 0) then
				local lamp = newPart(m, { Name = "CeilingLight", Size = Vector3.new(3, 0.3, 3), CFrame = o * CFrame.new(x, H - 0.15, z), Color = Color3.fromRGB(255, 245, 225), Material = Enum.Material.Neon, CanCollide = false })
				local light = Instance.new("PointLight")
				-- Marco 7.5: bem mais fraca. Com 1.3 / 30 o quarto todo ficava "estourado" (branco) uns
				-- segundos depois de entrar, quando a luz terminava de carregar
				light.Range = 18
				light.Brightness = 0.45
				light.Color = Color3.fromRGB(255, 240, 215)
				light.Parent = lamp
			end
		end
	end
	-- Marco 10: lustre de cristal no meio do salão (mansão). Alto: não atrapalha os móveis.
	if style.Lustre then
		local gold = Color3.fromRGB(215, 175, 80)
		local top = o * CFrame.new(0, H, 0)
		newPart(m, { Name = "LustreRod", Size = Vector3.new(0.3, 3, 0.3), CFrame = top * CFrame.new(0, -1.5, 0), Color = gold, Material = Enum.Material.Metal, CanCollide = false })
		newPart(m, { Name = "LustreRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 7, 7), CFrame = top * CFrame.new(0, -3.2, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = gold, Material = Enum.Material.Metal, CanCollide = false })
		local core = newPart(m, { Name = "LustreCore", Shape = Enum.PartType.Ball, Size = Vector3.new(2.2, 2.2, 2.2), CFrame = top * CFrame.new(0, -4, 0), Color = Color3.fromRGB(255, 245, 220), Material = Enum.Material.Neon, CanCollide = false })
		for i = 0, 7 do
			local a = i * math.pi / 4
			newPart(m, { Name = "Crystal", Shape = Enum.PartType.Ball, Size = Vector3.new(0.8, 0.8, 0.8), CFrame = top * CFrame.new(math.cos(a) * 3.3, -3.9, math.sin(a) * 3.3), Color = Color3.fromRGB(255, 250, 235), Material = Enum.Material.Neon, CanCollide = false })
		end
		local light = Instance.new("PointLight")
		light.Range = 26
		light.Brightness = 0.55
		light.Color = Color3.fromRGB(255, 235, 200)
		light.Parent = core
	end
	-- porta de saída (apartamento e cobertura: elevador de aço)
	local elevator = style.Exit == "Elevador"
	local door = newPart(m, { Name = "ExitDoor", Size = Vector3.new(5, 8, 0.4), CFrame = o * CFrame.new(0, 4, -D / 2 - 0.3), Color = elevator and Color3.fromRGB(185, 190, 196) or Color3.fromRGB(150, 95, 55), Material = elevator and Enum.Material.Metal or Enum.Material.Wood })
	-- tampa o vão da parede grossa atrás da porta (a luz de fora não entra)
	newPart(m, { Name = "DoorPlug", Size = Vector3.new(6, 8, T - 0.6), CFrame = o * CFrame.new(0, 4, -D / 2 - 0.6 - (T - 0.6) / 2), Color = Color3.fromRGB(60, 45, 35) })
	if elevator then
		newPart(m, { Name = "ElevatorSeam", Size = Vector3.new(0.1, 8, 0.05), CFrame = door.CFrame * CFrame.new(0, 0, 0.22), Color = Color3.fromRGB(90, 92, 96), CanCollide = false })
		local panel = newPart(m, { Name = "ElevatorPanel", Size = Vector3.new(0.8, 1.6, 0.1), CFrame = o * CFrame.new(3.6, 4.4, -D / 2 + 0.05), Color = Color3.fromRGB(40, 40, 45), CanCollide = false })
		newPart(m, { Name = "ElevatorButton", Shape = Enum.PartType.Ball, Size = Vector3.new(0.35, 0.35, 0.35), CFrame = panel.CFrame * CFrame.new(0, 0.3, 0.05), Color = Color3.fromRGB(255, 190, 60), Material = Enum.Material.Neon, CanCollide = false })
	else
		newPart(m, { Name = "Knob", Size = Vector3.new(0.3, 0.3, 0.3), CFrame = door.CFrame * CFrame.new(1.8, 0, 0.3), Color = Color3.fromRGB(220, 190, 80), Material = Enum.Material.Metal, CanCollide = false })
	end
	newPart(m, { Name = "Doormat", Size = Vector3.new(5, 0.1, 3), CFrame = o * CFrame.new(0, 0.05, -D / 2 + 1.8), Color = Color3.fromRGB(120, 90, 60), Material = Enum.Material.Fabric, CanCollide = false })
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Sair"
	prompt.ObjectText = elevator and "Elevador" or "Porta"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = door
	prompt.Triggered:Connect(function(player)
		if insideOf[player] == slot then
			HomeService.leaveHome(player)
		end
	end)

	local furniture = Instance.new("Folder")
	furniture.Name = "Moveis"
	furniture.Parent = m
	m:SetAttribute("Owner", slot.owner and slot.owner.UserId or 0)
	m:SetAttribute("Tier", home.tier) -- Marco 10.5: o guarda-roupa das casas maiores vira baú
	m.Parent = interiorsFolder
	slot.interior = m
	slot.furniture = furniture
	slot.models = {}
	paintWalls(slot, home.wall)
	ZoneService.addZone("Casa_" .. slot.index, o, Vector3.new(W, H, D))
end

-- Marco 10.2: casa de verdade (apartamento, cobertura, mansão). Paredes, vidro e o que é fixo já
-- estão no mapa; aqui só entram as luzes da sala e a pasta dos móveis do dono.
local function buildInPlace(slot, home)
	local o = slot.origin
	local room = HomeConfig.tier(home.tier).Room
	local m = Instance.new("Model")
	m.Name = "Interior_" .. slot.index
	for _, x in ipairs({ -room.Width / 4, room.Width / 4 }) do
		for _, z in ipairs({ -room.Depth / 4, room.Depth / 4 }) do
			local p = newPart(m, { Name = "LuzSala", Size = Vector3.new(0.4, 0.4, 0.4), CFrame = o * CFrame.new(x, room.Height - 0.8, z), Transparency = 1, CanCollide = false })
			p.CanQuery = false
			p.CanTouch = false
			local light = Instance.new("PointLight")
			light.Range = 20
			light.Brightness = 0.45
			light.Color = Color3.fromRGB(255, 240, 215)
			light.Parent = p
		end
	end
	local furniture = Instance.new("Folder")
	furniture.Name = "Moveis"
	furniture.Parent = m
	m:SetAttribute("Owner", slot.owner and slot.owner.UserId or 0)
	m:SetAttribute("Tier", home.tier) -- Marco 10.5: o guarda-roupa das casas maiores vira baú
	m.Parent = interiorsFolder
	slot.interior = m
	slot.furniture = furniture
	slot.models = {}
	paintWalls(slot, home.wall)
	ZoneService.addZone("Casa_" .. slot.index, o, Vector3.new(room.Width, room.Height, room.Depth))
end

local function placeModel(slot, item)
	local model = FurnitureArt.build(item.id)
	if not model then
		return
	end
	model:PivotTo(FurnitureArt.placement(slot.origin, item.x, item.z, item.r))
	model:SetAttribute("Uid", item.u)
	model:SetAttribute("ItemId", item.id)
	model.Parent = slot.furniture
	slot.models[item.u] = model
end

local function removeModel(slot, uid)
	local model = slot.models[uid]
	if model then
		model:Destroy()
		slot.models[uid] = nil
	end
end

---------------------------------------------------------------------------
-- Fachada (placa com o nome do dono) e permissões
---------------------------------------------------------------------------

local function money(n)
	local text = tostring(n):reverse():gsub("(%d%d%d)", "%1."):reverse()
	return "$" .. text:gsub("^%.", "")
end

-- Placa na porta: "Casa de Fulano" (com dono), "À VENDA" + preço (livre, da cidade) ou nada
-- (casinha livre da vila). O aviso da porta muda junto: Entrar / Comprar / desligado.
-- Marco 10.6: a placa "À VENDA" fica na frente do lote (no muro, perto do portão), com o botão de
-- comprar nela. Antes ficava em cima da porta, lá no fundo, e era difícil achar.
local function saleSignCf(slot)
	local curb = slot.house:GetAttribute("Curb")
	if typeof(curb) ~= "CFrame" then
		return nil -- apartamento e cobertura: a placa fica no elevador, como antes
	end
	local edge = curb * CFrame.new(0, 0, 0.6 + GameConfig.Map.SidewalkWidth * 0.55) -- frente do lote
	local doorX = edge:PointToObjectSpace(slot.door.Position).X
	return edge * CFrame.new(doorX + (doorX > 0 and -6 or 6), 0, -0.35)
end

local function signText(part, text, bg, fg)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = bg
	label.BackgroundTransparency = 0
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = fg
	label.Text = text
	label.Parent = gui
end

local buyOrMove -- (abaixo)

local function setSaleSign(slot, text)
	local old = slot.house:FindFirstChild("PlacaVenda")
	if old then
		old:Destroy()
	end
	local cf = text and saleSignCf(slot)
	if not cf then
		return false
	end
	local m = Instance.new("Model")
	m.Name = "PlacaVenda"
	local function part(name, size, at, color)
		local p = newPart(m, { Name = name, Size = size, CFrame = cf * at, Color = color, CanCollide = false })
		p.CastShadow = false
		return p
	end
	for _, x in ipairs({ -2.2, 2.2 }) do
		part("Poste", Vector3.new(0.25, 4.6, 0.25), CFrame.new(x, 2.3, 0.2), Color3.fromRGB(60, 60, 66))
	end
	local board = part("Placa", Vector3.new(5.6, 2, 0.15), CFrame.new(0, 3.6, 0), Color3.fromRGB(200, 50, 45))
	signText(board, text, Color3.fromRGB(200, 50, 45), Color3.new(1, 1, 1))
	local tier = HomeConfig.tier(slot.tier)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ComprarPrompt"
	prompt.ActionText = "Comprar " .. money(tier.price)
	prompt.ObjectText = tier.label .. " à venda" .. (tier.GangRequired and (" • " .. tier.GangRequired) or "")
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0.5
	prompt.Parent = board
	prompt.Triggered:Connect(function(player)
		if not slot.owner and SecurityService.checkRate(player, "EnterHome", 1) then
			buyOrMove(player, slot)
		end
	end)
	m.Parent = slot.house
	return true
end

local function setFacade(slot)
	local old = slot.house:FindFirstChild("OwnerSign")
	if old then
		old:Destroy()
	end
	setSaleSign(slot, nil)
	-- Marco 10.6: garagem só do dono (mansão). O VehicleService confere o OwnerId.
	if slot.garage then
		slot.garage:SetAttribute("OwnerId", slot.owner and slot.owner.UserId or nil)
	end
	local prompt = slot.door:FindFirstChild("HomePrompt")
	local tier = HomeConfig.tier(slot.tier)
	local text, bg, fg
	if slot.owner then
		-- Marco 10: "Apê de", "Cobertura de", "Mansão de" (o nível da fachada, não o do dono)
		local title = (tier.Owner or "Casa de") .. " " .. slot.owner.DisplayName
		text, bg, fg = title, Color3.fromRGB(250, 245, 230), Color3.fromRGB(60, 40, 25)
		prompt.ActionText = "Entrar"
		prompt.ObjectText = title
		prompt.Enabled = true
	elseif tier.price > 0 then
		text, bg, fg = "À VENDA " .. money(tier.price), Color3.fromRGB(200, 50, 45), Color3.new(1, 1, 1)
		prompt.ActionText = "Comprar " .. money(tier.price)
		prompt.ObjectText = tier.label .. " à venda" .. (tier.GangRequired and (" • " .. tier.GangRequired) or "")
		prompt.Enabled = true
		if setSaleSign(slot, text) then
			return -- a placa da frente substitui a da porta
		end
	else
		prompt.Enabled = false
		return
	end
	local sign = Instance.new("Part")
	sign.Name = "OwnerSign"
	sign.Anchored = true
	sign.CanCollide = false
	sign.CanQuery = false
	sign.Size = Vector3.new(5, 1, 0.15)
	sign.CFrame = slot.door.CFrame * CFrame.new(0, slot.door.Size.Y / 2 + 0.9, -0.3)
	sign.Color = bg
	sign.Material = Enum.Material.Wood
	sign.Parent = slot.house
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = fg
	label.Text = text
	label.Parent = gui
end

local function canEnter(player, slot)
	local owner = slot.owner
	if not owner then
		return false, "Esta casa está vazia."
	end
	if owner == player then
		return true
	end
	local home = homeOfSlot(slot)
	local lock = home and home.lock or "trancada"
	if lock == "aberta" then
		return true
	elseif lock == "amigos" then
		local ok, friends = pcall(function()
			return player:IsFriendsWith(owner.UserId)
		end)
		if ok and friends then
			return true
		end
		return false, ("Só amigos de %s podem entrar."):format(owner.DisplayName)
	end
	return false, ("A casa de %s está trancada."):format(owner.DisplayName)
end

-- Painel da casa: a casa onde o jogador está (se for dele) ou a principal
local function sendInfo(player)
	local here = insideOf[player]
	local slot = (here and here.owner == player) and here or mainSlot(player)
	local home = slot and homeOfSlot(slot)
	if not slot or not home then
		return
	end
	local list = {}
	for tierId, s in pairs(slotsOf[player] or {}) do
		table.insert(list, { tier = tierId, label = HomeConfig.tier(tierId).label, address = s.address, order = HomeConfig.tier(tierId).order })
	end
	table.sort(list, function(a, b)
		return a.order > b.order
	end)
	uiUpdate:FireClient(player, "HomeInfo", {
		address = slot.address,
		lock = home.lock,
		wall = home.wall,
		count = #home.items,
		max = HomeConfig.tier(home.tier).MaxItems,
		tier = home.tier,
		insideOwn = here == slot,
		insideOther = (here and here ~= slot and here.owner) and here.owner.DisplayName or nil,
		origin = slot.origin,
		homes = list, -- Marco 10.1: todas as casas do jogador
	})
end

-- Atributos do jogador: casa principal (botão "Sua casa", mapa) e a lista de todas para o mapa
local function updateAttributes(player)
	local main = mainSlot(player)
	player:SetAttribute("HomeAddress", main and main.address or nil)
	player:SetAttribute("HomePosition", main and main.door.Position or nil)
	player:SetAttribute("HomeTier", main and main.homeTier or nil)
	local parts = {}
	for tierId, s in pairs(slotsOf[player] or {}) do
		local p = s.door.Position
		table.insert(parts, ("%s:%.0f:%.0f"):format(HomeConfig.tier(tierId).label, p.X, p.Z))
	end
	table.sort(parts)
	player:SetAttribute("HomePositions", table.concat(parts, ";"))
end

---------------------------------------------------------------------------
-- Entrar e sair
---------------------------------------------------------------------------

local function teleport(player, cf)
	local character, humanoid, root = SecurityService.getLivingCharacter(player)
	if not character then
		return false
	end
	if humanoid.SeatPart then
		notice(player, "Saia do veículo ou do banco primeiro.")
		return false
	end
	if dismountVehicle then
		dismountVehicle(player)
	end
	pcall(function()
		player:RequestStreamAroundAsync(cf.Position)
	end)
	root.AssemblyLinearVelocity = Vector3.zero
	character:PivotTo(cf + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2 + 0.2, 0))
	return true
end

-- Dentro de casa a câmera não se afasta muito (senão ela atravessa o teto e as paredes)
local StarterPlayer = game:GetService("StarterPlayer")
local function roomCamera(player, inside, wide)
	-- Marco 10.2: na casa de verdade (vidro) dá para afastar um pouco mais
	local zoom = wide and 26 or 16
	player.CameraMaxZoomDistance = inside and math.min(zoom, StarterPlayer.CameraMaxZoomDistance) or StarterPlayer.CameraMaxZoomDistance
end

local placeItems -- (abaixo)

-- Monta o interior de uma fachada ocupada (só quando alguém entra)
local function ensureInterior(slot)
	if slot.interior then
		return true
	end
	local home = homeOfSlot(slot)
	if not home then
		return false
	end
	if slot.inPlace then
		slot.origin = slot.fixedOrigin
		buildInPlace(slot, home)
		return placeItems(slot, home)
	end
	local roomIndex
	for i = 1, ROOM_SLOTS do
		if not usedRooms[i] then
			roomIndex = i
			break
		end
	end
	if not roomIndex then
		return false
	end
	usedRooms[roomIndex] = true
	slot.room = roomIndex
	slot.origin = CFrame.new(INTERIOR_START + Vector3.new((roomIndex - 1) * INTERIOR_GAP, 0, 0))
	buildInterior(slot, home)
	return placeItems(slot, home)
end

-- Põe os móveis do dono. Os que não cabem nesta casa (dados antigos) voltam como dinheiro.
function placeItems(slot, home)
	local kept = {}
	for _, item in ipairs(home.items) do
		local def = HomeConfig.item(item.id)
		if def and HomeConfig.insideRoom(def, item.x, item.z, item.r, home.tier) then
			table.insert(kept, item)
			placeModel(slot, item)
		elseif item.p > 0 then
			EconomyService.add(slot.owner, item.p, "Móvel devolvido: " .. item.id)
		end
	end
	if #kept ~= #home.items then
		home.items = kept
		saveHomes(slot.owner)
	end
	return true
end

-- Desmonta o interior (ninguém dentro)
local function releaseInterior(slot)
	if slot.interior then
		ZoneService.removeZone("Casa_" .. slot.index)
		slot.interior:Destroy()
	end
	if slot.room then
		usedRooms[slot.room] = nil
	end
	slot.interior, slot.furniture, slot.models, slot.room, slot.origin = nil, nil, nil, nil, nil
end

local function someoneInside(slot)
	for _, where in pairs(insideOf) do
		if where == slot then
			return true
		end
	end
	return false
end

-- Interior vazio por um tempo: desmonta (libera o lugar para outra casa)
local function scheduleRelease(slot)
	task.delay(EMPTY_RELEASE, function()
		if slot.interior and not someoneInside(slot) then
			releaseInterior(slot)
		end
	end)
end

local function enterHome(player, slot)
	local ok, why = canEnter(player, slot)
	if not ok then
		notice(player, why)
		return
	end
	if not ensureInterior(slot) then
		return notice(player, "Muitas casas abertas agora. Tente de novo daqui a pouco.")
	end
	local entrance
	if slot.inPlace then
		entrance = slot.entry
	else
		local room = HomeConfig.tier(slot.homeTier).Room
		entrance = slot.origin * CFrame.new(0, 0, -room.Depth / 2 + 4) -- olhando para dentro (+Z)
		entrance = CFrame.lookAt(entrance.Position, (slot.origin * CFrame.new(0, 0, 0)).Position)
	end
	if teleport(player, entrance) then
		insideOf[player] = slot
		player:SetAttribute("InHomeIndex", slot.index)
		roomCamera(player, true, slot.inPlace)
		sendInfo(player)
		if slot.owner ~= player then
			notice(slot.owner, player.DisplayName .. " entrou na sua casa.")
		end
	end
end

function HomeService.leaveHome(player)
	local slot = insideOf[player]
	if not slot then
		return
	end
	if teleport(player, slot.outside) then
		insideOf[player] = nil
	if player.Parent then player:SetAttribute("InHomeIndex", nil) end
		player:SetAttribute("InHomeIndex", nil)
		roomCamera(player, false)
		sendInfo(player)
		if not someoneInside(slot) then
			scheduleRelease(slot)
		end
	end
end

-- Tira da casa todo mundo que não é o dono (e que não pode mais entrar, se onlyDenied)
local function removeVisitors(slot, onlyDenied)
	for visitor, where in pairs(insideOf) do
		if where == slot and visitor ~= slot.owner then
			local allowed = onlyDenied and canEnter(visitor, slot)
			if not allowed then
				HomeService.leaveHome(visitor)
				notice(visitor, "Você saiu da casa (o dono mudou quem pode entrar).")
			end
		end
	end
end

---------------------------------------------------------------------------
-- Dono chega e sai do jogo
---------------------------------------------------------------------------

-- Ocupa uma fachada com uma das casas do jogador (o interior só é montado quando alguém entra)
local function occupy(player, slot, home)
	slot.owner = player
	slot.homeTier = home.tier
	slotsOf[player] = slotsOf[player] or {}
	slotsOf[player][home.tier] = slot
	home.lastHouse = slot.number
	setFacade(slot)
end

-- Desocupa uma fachada (quem estava dentro sai pela porta)
local function vacate(slot, reasonText)
	local owner = slot.owner
	if not owner then
		return
	end
	for visitor, where in pairs(insideOf) do
		if where == slot then
			HomeService.leaveHome(visitor)
			insideOf[visitor] = nil
			if visitor.Parent then visitor:SetAttribute("InHomeIndex", nil) end
			if visitor ~= owner and reasonText then
				notice(visitor, reasonText)
			end
		end
	end
	releaseInterior(slot)
	if slotsOf[owner] and slotsOf[owner][slot.homeTier] == slot then
		slotsOf[owner][slot.homeTier] = nil
	end
	slot.owner, slot.homeTier = nil, nil
	setFacade(slot)
end

-- Escolhe a fachada: a mesma da última vez (se livre e do mesmo nível), senão a livre do nível
-- mais perto da praça. Barraco: só na favela da gangue. Casinha: sem nenhuma livre na vila, usa
-- qualquer casa livre da cidade (todo mundo tem onde morar). Os outros níveis esperam vagar.
local function pickSlot(home, gang)
	local best
	for _, s in ipairs(slots) do
		if not s.owner and s.tier == home.tier and (not s.gang or s.gang == gang) then
			if s.number == home.lastHouse then
				return s
			end
			best = best or s
		end
	end
	if best or home.tier ~= HomeConfig.StartTier then
		return best
	end
	for _, s in ipairs(slots) do
		if not s.owner and s.tier ~= HomeConfig.GangTier and not s.remote then
			return s
		end
	end
	return nil
end

-- Perde uma casa: os móveis comprados voltam como dinheiro
local function dropHome(player, homes, tierId)
	local home = homes[tierId]
	if not home then
		return
	end
	local refund = 0
	for _, item in ipairs(home.items) do
		refund += item.p or 0
	end
	if refund > 0 then
		EconomyService.add(player, refund, "Móveis devolvidos: " .. HomeConfig.tier(tierId).label)
	end
	homes[tierId] = nil
end

-- Confere as casas do jogador (gangue: barraco e sem casinha; sem gangue: casinha e sem barraco),
-- solta as fachadas de casas que ele não tem mais e arruma fachada para as que faltam.
function HomeService.refresh(player)
	local data = PlayerDataService.get(player)
	if not data or not player.Parent then
		return
	end
	if type(data.homes) ~= "table" then
		migrate(data)
	end
	local homes = data.homes
	local gang = gangOf(player)
	if gang then
		dropHome(player, homes, HomeConfig.StartTier)
		homes[HomeConfig.GangTier] = homes[HomeConfig.GangTier] or newHome(HomeConfig.GangTier)
	else
		dropHome(player, homes, HomeConfig.GangTier)
		homes[HomeConfig.StartTier] = homes[HomeConfig.StartTier] or newHome(HomeConfig.StartTier)
	end
	for tierId, slot in pairs(slotsOf[player] or {}) do
		if not homes[tierId] or (slot.gang and slot.gang ~= gang) then
			vacate(slot, "O dono se mudou.")
		end
	end
	for tierId, home in pairs(homes) do
		local requiredGang = HomeConfig.tier(tierId).GangRequired
		if (not requiredGang or requiredGang == gang) and not (slotsOf[player] and slotsOf[player][tierId]) then
			local slot = pickSlot(home, gang)
			if slot then
				occupy(player, slot, home)
			else
				notice(player, ("Sem %s livre neste servidor agora. Ela continua sua!"):format(HomeConfig.tier(tierId).label))
			end
		end
	end
	saveHomes(player)
	updateAttributes(player)
	sendInfo(player)
end

-- Endereço da casa de um nível (para avisos, ex.: o barraco)
function HomeService.addressOf(player, tierId)
	local slot = slotsOf[player] and slotsOf[player][tierId]
	return slot and slot.address
end

local function assign(player, data)
	if slotsOf[player] or not player.Parent then
		return
	end
	migrate(data)
	slotsOf[player] = {}
	HomeService.refresh(player)
end

local function release(player)
	insideOf[player] = nil
	for _, slot in pairs(slotsOf[player] or {}) do
		vacate(slot, "O dono da casa saiu do jogo.")
	end
	slotsOf[player] = nil
end

-- Porta de uma casa à venda: compra mais uma casa desse NÍVEL (Marco 10.1: soma, não troca).
-- Se já tem uma desse nível, muda essa casa para cá de graça.
function buyOrMove(player, slot)
 -- Validação autoritativa também protege os prompts da placa e da porta.
 if slot.owner then return end
 local requiredGang = HomeConfig.tier(slot.tier).GangRequired
 if requiredGang then
  local character = player.Character
  local root = character and character:FindFirstChild("HumanoidRootPart")
  local humanoid = character and character:FindFirstChildOfClass("Humanoid")
  if not root or not humanoid or humanoid.Health <= 0 or (root.Position-slot.door.Position).Magnitude > 18 then return end
 end
 if (requiredGang and gangOf(player) ~= requiredGang) or (slot.gang and gangOf(player) ~= slot.gang) then
  return notice(player, "Esta residência é exclusiva para integrantes da gangue desta comunidade.")
 end
	local homes = homesOf(player)
	if not homes or not slotsOf[player] then
		return
	end
	local want = HomeConfig.tier(slot.tier)
	if want.Free or want.price <= 0 then
		return
	end
	local mine = homes[slot.tier]
	if mine then
		local old = slotsOf[player][slot.tier]
		if old then
			vacate(old, "O dono se mudou de casa.")
		end
		occupy(player, slot, mine)
		notice(player, ("Você mudou seu(sua) %s para %s."):format(want.label, slot.address))
	else
		if not EconomyService.spend(player, want.price, "Compra de casa: " .. want.label) then
			return notice(player, ("Você precisa de %s para comprar esta casa."):format(money(want.price)))
		end
		local home = newHome(slot.tier)
		homes[slot.tier] = home
		occupy(player, slot, home)
		local n = 0
		for _ in pairs(homes) do
			n += 1
		end
		notice(player, ("Parabéns! Você comprou um(a) %s em %s. Agora você tem %d casas."):format(want.label, slot.address, n))
	end
	saveHomes(player)
	updateAttributes(player)
	sendInfo(player)
end

---------------------------------------------------------------------------
-- Pedidos do cliente (tudo conferido aqui)
---------------------------------------------------------------------------

local function isNumber(v, limit)
	return type(v) == "number" and v == v and math.abs(v) <= limit
end

-- Valida uma posição (sem contar o próprio móvel "ignoreUid")
local function validSpot(home, def, x, z, r, ignoreUid)
	if not HomeConfig.insideRoom(def, x, z, r, home.tier) then
		return false, "Não cabe aí (muito perto da parede ou da porta)."
	end
	local probe = { id = def.id, x = x, z = z, r = r }
	for _, other in ipairs(home.items) do
		if other.u ~= ignoreUid and HomeConfig.overlaps(probe, other) then
			return false, "Tem outro móvel nesse lugar."
		end
	end
	return true
end

local function readSpot(data)
	if type(data) ~= "table" or not isNumber(data.x, 100) or not isNumber(data.z, 100) or not isNumber(data.r, 4) then
		return nil
	end
	-- grade de meio stud e giro em passos de 90°
	return math.floor(data.x * 2 + 0.5) / 2, math.floor(data.z * 2 + 0.5) / 2, math.floor(data.r) % 4
end

local Actions = {}

function Actions.Place(player, slot, home, data)
	local def = type(data) == "table" and SecurityService.isShortString(data.id, 20) and HomeConfig.item(data.id)
	local x, z, r = readSpot(data)
	if not def or not x then
		return
	end
	local maxItems = HomeConfig.tier(home.tier).MaxItems
	if #home.items >= maxItems then
		return notice(player, ("Limite de %d móveis nesta casa."):format(maxItems))
	end
	local ok, why = validSpot(home, def, x, z, r)
	if not ok then
		return notice(player, why)
	end
	if not EconomyService.spend(player, def.price, "Móvel: " .. def.label) then
		return notice(player, ("Dinheiro insuficiente ($%d)."):format(def.price))
	end
	local item = { u = home.nextId, id = def.id, x = x, z = z, r = r, p = def.price }
	home.nextId += 1
	table.insert(home.items, item)
	placeModel(slot, item)
	saveHomes(player)
	sendInfo(player)
end

local function findItem(home, uid)
	for i, it in ipairs(home.items) do
		if it.u == uid then
			return it, i
		end
	end
	return nil
end

function Actions.Move(player, slot, home, data)
	local x, z, r = readSpot(data)
	local item = x and type(data.u) == "number" and findItem(home, data.u)
	if not item then
		return
	end
	local ok, why = validSpot(home, HomeConfig.item(item.id), x, z, r, item.u)
	if not ok then
		return notice(player, why)
	end
	item.x, item.z, item.r = x, z, r
	removeModel(slot, item.u)
	placeModel(slot, item)
	saveHomes(player)
end

function Actions.Remove(player, slot, home, data)
	if type(data) ~= "table" or type(data.u) ~= "number" then
		return
	end
	local item, index = findItem(home, data.u)
	if not item then
		return
	end
	table.remove(home.items, index)
	removeModel(slot, item.u)
	if item.p > 0 then
		EconomyService.add(player, item.p, "Venda de móvel: " .. item.id) -- devolve o que pagou
	end
	saveHomes(player)
	sendInfo(player)
end

function Actions.SetWall(player, slot, home, data)
	local index = type(data) == "table" and data.index
	if type(index) ~= "number" or not HomeConfig.WallColors[index] then
		return
	end
	home.wall = index
	paintWalls(slot, index)
	saveHomes(player)
	sendInfo(player)
end

local function onRequest(player, action, data)
	if not SecurityService.checkRate(player, "HomeRequest", 0.25) or not SecurityService.isShortString(action, 16) then
		return
	end
	local mine = slotsOf[player]
	if not mine or not next(mine) then
		return
	end
	if action == "SetLock" then
		-- vale para todas as casas do jogador
		local mode = type(data) == "table" and data.mode
		for _, m in ipairs(HomeConfig.LockModes) do
			if m.id == mode then
				for _, slot in pairs(mine) do
					local home = homeOfSlot(slot)
					if home then
						home.lock = mode
					end
					removeVisitors(slot, true)
				end
				saveHomes(player)
				notice(player, "Suas casas: " .. m.label)
				sendInfo(player)
			end
		end
	elseif action == "Kick" then
		for _, slot in pairs(mine) do
			removeVisitors(slot, false)
		end
	-- Marco 8.3: "Ir para casa" (teleporte) saiu: o jogador vai dirigindo até a casa
	elseif Actions[action] then
		-- decorar: só o dono, e só dentro de uma casa dele
		local slot = insideOf[player]
		if not slot or slot.owner ~= player or not slot.interior then
			return notice(player, "Entre na sua casa para decorar.")
		end
		local home = homeOfSlot(slot)
		if home then
			Actions[action](player, slot, home, data)
		end
	end
end

---------------------------------------------------------------------------
-- Início
---------------------------------------------------------------------------

-- Toda casa do mapa com nível (atributo Tier, do MapBuilder) vira um lugar de moradia
local function findSlots()
	local houses = Workspace:WaitForChild("Map"):FindFirstChild("Houses")
	local list = {}
	for _, house in ipairs(houses and houses:GetChildren() or {}) do
		local door = house:FindFirstChild("Door")
		if door and house:GetAttribute("Address") and HomeConfig.Tiers[house:GetAttribute("Tier")] then
			table.insert(list, { house = house, door = door, dist = Vector3.new(door.Position.X, 0, door.Position.Z).Magnitude })
		end
	end
	table.sort(list, function(a, b)
		return a.dist < b.dist
	end)
	for i, e in ipairs(list) do
		local out = e.door.CFrame * CFrame.new(0, -e.door.Size.Y / 2, -4)
		local slot = {
			index = i,
			house = e.house,
			door = e.door,
			tier = e.house:GetAttribute("Tier"),
			gang = e.house:GetAttribute("Gang"), -- Marco 10.1: barraco da favela de uma gangue
			remote = e.house:GetAttribute("Remote"), -- longe da cidade (Bairro Horizonte, favelas)
			number = e.house:GetAttribute("HouseNumber"),
			address = e.house:GetAttribute("Address"),
			outside = CFrame.lookAt(out.Position, out.Position + e.door.CFrame.LookVector),
		}
		local garageName = e.house:GetAttribute("Garagem")
		local garages = Workspace.Map:FindFirstChild("Garages")
		slot.garage = garageName and garages and garages:FindFirstChild(garageName) or nil
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "HomePrompt"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.MaxActivationDistance = 8
		prompt.RequiresLineOfSight = false
		prompt.HoldDuration = 0
		prompt.Parent = e.door
		prompt.Triggered:Connect(function(player)
			if not SecurityService.checkRate(player, "EnterHome", 1) then
				return
			end
			if slot.sharedDoor and insideOf[player] == slot then
				HomeService.leaveHome(player) -- Marco 10.5: mesma porta para entrar e sair
			elseif slot.owner then
				enterHome(player, slot)
			else
				buyOrMove(player, slot)
			end
		end)
		-- Marco 10.2: casa de verdade (MoradiaBuilder): origem dos móveis, entrada, porta de dentro
		local origin = e.house:FindFirstChild("Origem")
		local entry = e.house:FindFirstChild("Entrada")
		local exitDoor = e.house:FindFirstChild("SaidaPorta")
		if origin and entry and exitDoor then
			slot.inPlace = true
			slot.fixedOrigin = origin.CFrame
			slot.entry = entry.CFrame
			slot.bounds = {}
			for _, c in ipairs(e.house:GetChildren()) do
				if c:IsA("BasePart") and c.Name == "Limite" then
					table.insert(slot.bounds, c)
				end
			end
			-- Marco 10.5: na mansão a porta de dentro fica colada na de fora e apareciam 2 avisos
			-- (Sair de um lado, Entrar do outro). Aí vale um botão só: a porta de fora entra e sai
			-- (o cliente troca o texto para "Sair" para quem está dentro).
			e.door:SetAttribute("HomeIndex", i)
			local sharedDoor = (exitDoor.Position - e.door.Position).Magnitude < 6
			slot.sharedDoor = sharedDoor
			local exitPrompt = Instance.new("ProximityPrompt")
			exitPrompt.Enabled = not sharedDoor
			exitPrompt.Name = "ExitPrompt"
			exitPrompt.ActionText = "Sair"
			exitPrompt.ObjectText = e.house:GetAttribute("ExitText") or "Porta"
			exitPrompt.KeyboardKeyCode = Enum.KeyCode.E
			exitPrompt.MaxActivationDistance = 8
			exitPrompt.RequiresLineOfSight = false
			exitPrompt.Parent = exitDoor
			exitPrompt.Triggered:Connect(function(player)
				if insideOf[player] == slot and SecurityService.checkRate(player, "EnterHome", 1) then
					HomeService.leaveHome(player)
				end
			end)
		end
		table.insert(slots, slot)
		setFacade(slot)
	end
end

-- Marco 10.2: na casa de verdade dá para sair sem a porta (pular da sacada, cair da escada do
-- prédio...). Quem não está mais em nenhuma caixa "Limite" deixa de contar como "dentro".
local function insideBounds(slot, position)
	for _, b in ipairs(slot.bounds or {}) do
		local rel = b.CFrame:PointToObjectSpace(position)
		local half = b.Size / 2
		if math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y and math.abs(rel.Z) <= half.Z then
			return true
		end
	end
	return false
end

local function watchInPlace()
	while true do
		task.wait(1)
		local gone = {}
		for player, slot in pairs(insideOf) do
			if slot.inPlace then
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root and not insideBounds(slot, root.Position) then
					table.insert(gone, player)
				end
			end
		end
		for _, player in ipairs(gone) do
			local slot = insideOf[player]
			insideOf[player] = nil
			if player.Parent then player:SetAttribute("InHomeIndex", nil) end
			roomCamera(player, false)
			sendInfo(player)
			if slot and not someoneInside(slot) then
				scheduleRelease(slot)
			end
		end
	end
end

function HomeService.init(remotes, onDismount)
	uiUpdate = remotes[GameConfig.Remotes.UIUpdate]
	dismountVehicle = onDismount
	interiorsFolder = Instance.new("Folder")
	interiorsFolder.Name = "Interiores"
	interiorsFolder.Parent = Workspace
	-- Marco 10.7: móveis com modelo 3D (baú medieval): cópia para o cliente ver na prévia do Decorar
	local models = ServerStorage:FindFirstChild("FurnitureModels")
	if models and not ReplicatedStorage:FindFirstChild("MoveisModelos") then
		local copy = models:Clone()
		copy.Name = "MoveisModelos"
		for _, d in ipairs(copy:GetDescendants()) do
			if d:IsA("Script") or d:IsA("LocalScript") then
				d:Destroy()
			elseif d:IsA("BasePart") then
				d.Anchored = true
			end
		end
		copy.Parent = ReplicatedStorage
	end
	-- Marco 10.18: + CofreAntigo (Armário de 70) e GuardaRoupaNordico (guarda-roupa)
	for _, info in ipairs({ { "BauMedieval", "Baú medieval" }, { "CofreAntigo", "Armário (cofre antigo)" }, { "GuardaRoupaNordico", "Guarda-roupa nórdico" } }) do
		print(("[HomeService] %s: %s."):format(info[2], models and models:FindFirstChild(info[1]) and "modelo 3D em ServerStorage > FurnitureModels" or "sem modelo (versão de peças)"))
	end
	findSlots()

	remotes[GameConfig.Remotes.HomeRequest].OnServerEvent:Connect(onRequest)
	PlayerDataService.onLoaded(assign)
	Players.PlayerRemoving:Connect(release)
	local function watch(player)
		player.CharacterAdded:Connect(function()
			local slot = insideOf[player]
			if slot then
				insideOf[player] = nil -- renasceu na praça
				if player.Parent then player:SetAttribute("InHomeIndex", nil) end
				roomCamera(player, false)
				sendInfo(player)
				if not someoneInside(slot) then
					scheduleRelease(slot)
				end
			end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in ipairs(Players:GetPlayers()) do
		watch(player)
	end
	task.spawn(watchInPlace)
	local count = {}
	for _, slot in ipairs(slots) do
		count[slot.tier] = (count[slot.tier] or 0) + 1
	end
	print(("[HomeService] Casas: %d casinhas, %d médias, %d sobrados, %d apartamentos, %d casas modernas, %d coberturas, %d mansões, %d barracos."):format(
		count.basica or 0, count.media or 0, count.sobrado or 0, count.apartamento or 0, count.casamoderna or 0, count.cobertura or 0, count.mansao or 0, count.barraco or 0))
end

return HomeService
