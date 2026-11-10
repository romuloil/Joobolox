-- CrimeBuilder (ModuleScript)
-- Caminho: ServerScriptService > Services > CrimeBuilder
-- Marco 10.5: lugares que o Ladrão pode assaltar (chamado pelo MapBuilder no fim da montagem).
--   * Lojas de conveniência: o térreo do prédio mais perto de cada ponto de GameConfig.Crime.StoreTargets
--     vira uma loja de verdade (porta aberta, prateleiras, geladeira, balcão e caixa registradora).
--     A conveniência do Posto Estrela também fica oca. O prédio continua no mesmo lugar e tamanho
--     (nada muda no resto da cidade nem na numeração das casas).
--   * Caixas eletrônicos: na frente do prédio mais perto de cada ponto de AtmTargets e um no posto.
--     Usa o modelo do Luís (ServerStorage > CrimeModels > CaixaEletronico); sem ele, monta de peças.
--     Marca "LLC" (GameConfig.Crime.AtmBrand) e as cores de AtmColors.
-- Tudo que dá para assaltar ganha a tag "CrimeSpot" (CollectionService) e os atributos
-- Robbery ("loja" ou "atm"), PlaceName e CrimeId. Quem cuida do assalto é o CrimeService.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local CrimeBuilder = {}

local CR = GameConfig.Crime
local H = 11 -- altura do térreo (MapBuilder.buildBuilding)
local GLASS = Color3.fromRGB(180, 215, 235)
local WHITE = Color3.new(1, 1, 1)
local K -- helpers do MapBuilder (makePart, model, addSurfaceText)

local function P(parent, name, size, cf, color, material, props)
	props = props or {}
	local p = K.makePart(parent, {
		Name = name,
		Size = size,
		CFrame = cf,
		Color = color,
		Material = material,
		Transparency = props.transparency,
		CanCollide = props.collide,
		CastShadow = props.shadow,
	})
	return p
end

---------------------------------------------------------------------------
-- Loja de conveniência (base = chão do térreo, frente -Z, w x d, altura H)
---------------------------------------------------------------------------

local SNACKS = {
	Color3.fromRGB(230, 60, 50), Color3.fromRGB(250, 200, 40), Color3.fromRGB(60, 140, 220),
	Color3.fromRGB(70, 180, 90), Color3.fromRGB(240, 130, 40), Color3.fromRGB(170, 80, 200),
}

local function shelf(parent, cf, length)
	P(parent, "Gondola", Vector3.new(2.6, 5, length), cf * CFrame.new(0, 2.5, 0), Color3.fromRGB(235, 235, 238))
	local n = 0
	for _, side in ipairs({ -1, 1 }) do
		for level = 0, 2 do
			local segs = math.max(2, math.floor(length / 3))
			for k = 0, segs - 1 do
				n += 1
				local seg = length / segs
				P(parent, "Produtos", Vector3.new(0.4, 0.9, seg - 0.3), cf * CFrame.new(side * 1.45, 1.1 + level * 1.5, -length / 2 + seg * (k + 0.5)), SNACKS[(n % #SNACKS) + 1], nil, { collide = false, shadow = false })
			end
		end
	end
end

-- opts: { ceiling = true (sem andar de cima), wall = cor, accent = cor, name = nome da loja }
local function buildStore(parent, base, w, d, opts)
	local wall = opts.wall or Color3.fromRGB(235, 230, 220)
	local accent = opts.accent or Color3.fromRGB(200, 50, 45)
	local function at(x, y, z)
		return base * CFrame.new(x, y, z)
	end
	local zf = -d / 2 + 0.5 -- linha da fachada
	-- paredes
	P(parent, "LojaParede", Vector3.new(w, H, 1), at(0, H / 2, d / 2 - 0.5), wall)
	for _, sx in ipairs({ -1, 1 }) do
		P(parent, "LojaParede", Vector3.new(1, H, d - 2), at(sx * (w / 2 - 0.5), H / 2, 0), wall)
		P(parent, "LojaColuna", Vector3.new(2, H, 1), at(sx * (w / 2 - 1), H / 2, zf), accent)
	end
	-- fachada: vidro dos dois lados da porta (6 de largura), mureta e faixa de cima
	local pw = (w - 4 - 6) / 2
	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * (3 + pw / 2)
		P(parent, "LojaMureta", Vector3.new(pw, 0.8, 1), at(x, 0.4, zf), accent)
		P(parent, "LojaVidro", Vector3.new(pw, 7.2, 0.3), at(x, 0.8 + 3.6, zf), GLASS, nil, { transparency = 0.55 })
		P(parent, "LojaBatente", Vector3.new(0.5, 8, 1.1), at(sx * 3.25, 4, zf), accent)
	end
	P(parent, "LojaFaixa", Vector3.new(w - 4, H - 8, 1), at(0, 8 + (H - 8) / 2, zf), wall)
	-- chão e teto
	P(parent, "LojaPiso", Vector3.new(w - 2, 0.2, d - 2), at(0, 0.1, 0), Color3.fromRGB(225, 225, 228), Enum.Material.SmoothPlastic)
	if opts.ceiling then
		P(parent, "LojaTetoDentro", Vector3.new(w - 2, 0.4, d - 2), at(0, H - 0.2, 0), WHITE)
	end
	for _, x in ipairs({ -w / 4, w / 4 }) do
		local lamp = P(parent, "LojaLuz", Vector3.new(1.2, 0.2, d - 8), at(x, H - 0.55, 0), Color3.fromRGB(255, 252, 240), Enum.Material.Neon, { collide = false })
		local light = Instance.new("PointLight")
		light.Range = 22
		light.Brightness = 0.9
		light.Shadows = false
		light.Parent = lamp
	end
	-- caixa de luz suave (LightingController)
	local zone = P(parent, "LojaDentro", Vector3.new(w - 2, H - 0.6, d - 2), at(0, H / 2, 0), WHITE, nil, { transparency = 1, collide = false })
	zone.CanQuery = false
	zone.CanTouch = false
	zone:SetAttribute("Indoor", true)

	-- balcão (à direita de quem entra) com a caixa registradora
	local cx, cz = w / 2 - 7, -d / 2 + 7.5
	P(parent, "Balcao", Vector3.new(9, 3.4, 2.2), at(cx, 1.7, cz), accent)
	P(parent, "BalcaoTampo", Vector3.new(9.4, 0.3, 2.6), at(cx, 3.55, cz), Color3.fromRGB(60, 55, 50))
	local register = P(parent, "CaixaRegistradora", Vector3.new(1.8, 1.1, 1.4), at(cx + 2, 4.25, cz), Color3.fromRGB(40, 40, 45))
	P(parent, "CaixaTela", Vector3.new(1.2, 0.7, 0.1), at(cx + 2, 4.75, cz - 0.4) * CFrame.Angles(math.rad(-20), 0, 0), Color3.fromRGB(80, 200, 120), Enum.Material.Neon, { collide = false })
	P(parent, "Doces", Vector3.new(3, 1.2, 1), at(cx - 2.5, 4.3, cz - 0.6), SNACKS[2], nil, { collide = false })
	-- atrás do balcão: prateleira de parede
	P(parent, "PrateleiraFundo", Vector3.new(1, 7, 8), at(w / 2 - 1.5, 3.5, cz + 3.5), Color3.fromRGB(120, 85, 60), Enum.Material.Wood)
	-- gôndolas
	local glen = d - 13
	shelf(parent, at(-w / 2 + 5, 0, 0.5), glen)
	if w >= 30 then
		shelf(parent, at(-w / 2 + 11, 0, 0.5), glen)
	end
	-- geladeiras no fundo
	local fw = w - 10
	P(parent, "Geladeira", Vector3.new(fw, 7.5, 2.4), at(-w / 2 + 1 + fw / 2, 3.75, d / 2 - 2.2), Color3.fromRGB(230, 232, 236), Enum.Material.Metal)
	P(parent, "GeladeiraPorta", Vector3.new(fw - 0.4, 6.4, 0.2), at(-w / 2 + 1 + fw / 2, 3.9, d / 2 - 3.45), Color3.fromRGB(190, 225, 255), Enum.Material.Neon, { transparency = 0.6, collide = false })
	for k = 0, math.floor(fw / 1.6) - 1 do
		P(parent, "Bebidas", Vector3.new(0.6, 1.4, 0.6), at(-w / 2 + 2 + k * 1.6, 2 + (k % 3) * 1.9, d / 2 - 2.6), SNACKS[(k % #SNACKS) + 1], nil, { collide = false, shadow = false })
	end
	-- luz de alarme (pisca vermelha no assalto) em cima da porta
	local alarm = P(parent, "LuzAlarme", Vector3.new(1.2, 0.8, 0.6), at(0, 8.6, zf - 0.6), Color3.fromRGB(90, 20, 20), Enum.Material.SmoothPlastic, { collide = false })
	-- lugar do caixa (NPC atrás do balcão, olhando para a porta)
	local spot = P(parent, "CaixaSpot", Vector3.new(1, 1, 1), at(cx, 0.6, cz + 2.6) * CFrame.Angles(0, 0, 0), WHITE, nil, { transparency = 1, collide = false })
	spot.CanQuery = false
	spot.CanTouch = false

	register:SetAttribute("Robbery", "loja")
	register:SetAttribute("PlaceName", opts.name)
	CollectionService:AddTag(register, "CrimeSpot")
	return register, alarm, spot
end

-- Prédio da cidade: o bloco "Body" vira andar de cima + térreo oco com a loja
local function convertBuilding(b, name)
	local body = b:FindFirstChild("Body")
	if not body then
		return nil
	end
	local w, h, d = body.Size.X, body.Size.Y, body.Size.Z
	local base = body.CFrame * CFrame.new(0, -h / 2, 0)
	local color = body.Color
	body.Size = Vector3.new(w, h - H, d)
	body.CFrame = base * CFrame.new(0, H + (h - H) / 2, 0)
	for _, nm in ipairs({ "Shopfront", "Door" }) do
		local part = b:FindFirstChild(nm)
		if part then
			part:Destroy()
		end
	end
	local sign = b:FindFirstChild("Sign")
	local label = sign and sign:FindFirstChildWhichIsA("SurfaceGui") and sign:FindFirstChildWhichIsA("SurfaceGui"):FindFirstChildWhichIsA("TextLabel")
	local accent = label and label.TextColor3 or Color3.fromRGB(200, 50, 45)
	if label then
		label.Text = name
	end
	b:SetAttribute("Business", name)
	b:SetAttribute("PlaceName", name)
	local register, alarm, spot = buildStore(b, base, w, d, { wall = color, accent = accent, name = name })
	return register, alarm, spot
end

---------------------------------------------------------------------------
-- Caixa eletrônico (cf = chão, frente -Z)
---------------------------------------------------------------------------

local function overlays(m, cf, width, height, depth)
	local front = -depth / 2 - 0.04
	local plate = P(m, "PlacaLLC", Vector3.new(width * 0.78, height * 0.11, 0.08), cf * CFrame.new(0, height * 0.925, front), CR.AtmColors.Detalhe, nil, { collide = false })
	K.addSurfaceText(plate, CR.AtmBrand, CR.AtmColors.Corpo, CR.AtmColors.Detalhe)
	local screen = P(m, "Tela", Vector3.new(width * 0.56, height * 0.17, 0.08), cf * CFrame.new(0, height * 0.7, front - 0.02), Color3.fromRGB(40, 110, 200), Enum.Material.Neon, { collide = false })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Parent = screen
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundColor3 = Color3.fromRGB(20, 60, 140)
	t.TextColor3 = WHITE
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.Text = CR.AtmBrand .. " 24h\nInsira o cartão"
	t.Name = "Texto"
	t.Parent = gui
	return screen
end

local function atmFromParts(m, cf)
	local w, h, d = 1.8, CR.AtmHeight, 2
	local col = CR.AtmColors
	P(m, "Corpo", Vector3.new(w, h, d), cf * CFrame.new(0, h / 2, 0), col.Corpo, Enum.Material.Metal)
	P(m, "Teclado", Vector3.new(w * 0.6, 0.15, 0.6), cf * CFrame.new(0, h * 0.5, -d / 2 - 0.25) * CFrame.Angles(math.rad(-15), 0, 0), col.Metal, Enum.Material.Metal)
	P(m, "Cartao", Vector3.new(0.5, 0.25, 0.1), cf * CFrame.new(w * 0.25, h * 0.56, -d / 2 - 0.05), col.Detalhe, Enum.Material.Neon)
	P(m, "SaidaNotas", Vector3.new(w * 0.5, 0.15, 0.1), cf * CFrame.new(0, h * 0.42, -d / 2 - 0.05), Color3.fromRGB(15, 15, 18))
	P(m, "Faixa", Vector3.new(w + 0.05, 0.25, d + 0.05), cf * CFrame.new(0, h * 0.83, 0), col.Detalhe, Enum.Material.Metal)
	return w, h, d
end

local function atmFromMesh(m, cf)
	local folder = ServerStorage:FindFirstChild("CrimeModels")
	local template = folder and folder:FindFirstChild("CaixaEletronico", true)
	if not template or not template:IsA("Model") then
		return nil
	end
	local atm = template:Clone()
	local marker = atm:FindFirstChild("FrontMarker", true)
	local bcf, size = atm:GetBoundingBox()
	local bottom = bcf.Position - Vector3.new(0, size.Y / 2, 0)
	local dir = Vector3.new(0, 0, -1)
	if marker then
		local v = marker.Position - bcf.Position
		v = Vector3.new(v.X, 0, v.Z)
		if v.Magnitude > 1e-3 then
			dir = v.Unit
		end
		marker:Destroy()
	end
	atm.WorldPivot = CFrame.lookAt(bottom, bottom + dir) -- pivô no chão, olhando para a frente do caixa
	atm:ScaleTo(CR.AtmHeight / size.Y)
	atm:PivotTo(cf) -- a frente do caixa fica para -Z do cf
	local _, s2 = atm:GetBoundingBox()
	for _, p in ipairs(atm:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = true
			local role = p.Name:match("^(%a+)")
			local color = role and CR.AtmColors[role]
			if color then
				p.Color = color
				p.Material = role == "Metal" and Enum.Material.Metal or Enum.Material.SmoothPlastic
			end
			p.Parent = m
		end
	end
	atm:Destroy()
	return s2.X, s2.Y, s2.Z -- a caixa segue o pivô: X = largura, Z = fundo
end

local atmCount = 0
local function buildAtm(parent, cf, placeName)
	atmCount += 1
	local m = K.model("CaixaEletronico", parent)
	local ok, w, h, d = pcall(atmFromMesh, m, cf)
	if not ok or not w then
		if not ok then
			warn("[CrimeBuilder] Modelo do caixa eletrônico deu erro: " .. tostring(w))
		end
		m:ClearAllChildren()
		w, h, d = atmFromParts(m, cf)
	end
	local screen = overlays(m, cf, w, h, d)
	local hit = P(m, "Painel", Vector3.new(w, h, d), cf * CFrame.new(0, h / 2, 0), WHITE, nil, { transparency = 1, collide = false })
	hit.CanQuery = false
	hit.CanTouch = false
	hit:SetAttribute("Robbery", "atm")
	hit:SetAttribute("PlaceName", ("Caixa eletrônico (%s)"):format(placeName))
	hit:SetAttribute("Screen", screen.Name)
	CollectionService:AddTag(hit, "CrimeSpot")
	m:SetAttribute("PlaceName", hit:GetAttribute("PlaceName"))
	return hit
end

---------------------------------------------------------------------------

local function candidates(map)
	local list = {}
	local buildings = map:FindFirstChild("Buildings")
	for _, b in ipairs(buildings and buildings:GetChildren() or {}) do
		local body = b.Name == "Predio" and b:FindFirstChild("Body")
		if body and body.Size.Y >= H + 7 and body.Size.X >= 26 then
			table.insert(list, { model = b, pos = body.Position * Vector3.new(1, 0, 1) })
		end
	end
	return list
end

local function nearest(list, target, used)
	local best, bestD
	for _, c in ipairs(list) do
		if not used[c.model] then
			local dist = (c.pos - target).Magnitude
			if not bestD or dist < bestD then
				best, bestD = c, dist
			end
		end
	end
	return best
end

function CrimeBuilder.build(map, helpers)
	K = helpers
	local crimeFolder = K.model("Crime", map)
	local list = candidates(map)
	local used = {}
	local id = 0
	local stores, atms = 0, 0

	for i, target in ipairs(CR.StoreTargets) do
		local c = nearest(list, target, used)
		if c then
			used[c.model] = true
			local name = CR.StoreNames[((i - 1) % #CR.StoreNames) + 1]
			local ok, register = pcall(convertBuilding, c.model, name)
			if ok and register then
				id += 1
				register:SetAttribute("CrimeId", id)
				stores += 1
			else
				warn("[CrimeBuilder] Erro na loja " .. name .. ": " .. tostring(register))
			end
		end
	end

	-- conveniência do Posto Estrela: o bloco vira loja oca
	local posto = map:FindFirstChild("PostoEstrela", true)
	local loja = posto and posto:FindFirstChild("Loja")
	if loja then
		local ok, err = pcall(function()
			local base = loja.CFrame * CFrame.new(0, -loja.Size.Y / 2, 0)
			local w, d = loja.Size.X, loja.Size.Z
			local wall = loja.Color
			loja:Destroy()
			local glass = posto:FindFirstChild("LojaVidro")
			if glass then
				glass:Destroy()
			end
			local register = buildStore(posto, base, w, d, { ceiling = true, wall = wall, accent = Color3.fromRGB(200, 40, 45), name = "Conveniência Estrela" })
			id += 1
			register:SetAttribute("CrimeId", id)
			stores += 1
			local hit = buildAtm(crimeFolder, base * CFrame.new(-w / 2 + 4, 0, -d / 2 - 1.3), GameConfig.Rodovia.PostoName)
			id += 1
			hit:SetAttribute("CrimeId", id)
			atms += 1
		end)
		if not ok then
			warn("[CrimeBuilder] Erro na conveniência do posto: " .. tostring(err))
		end
	end

	for _, target in ipairs(CR.AtmTargets) do
		local c = nearest(list, target, used)
		if c then
			used[c.model] = true
			local body = c.model:FindFirstChild("Body")
			local w, h, d = body.Size.X, body.Size.Y, body.Size.Z
			local base = body.CFrame * CFrame.new(0, -h / 2, 0)
			local ok, hit = pcall(buildAtm, crimeFolder, base * CFrame.new(w / 2 - 6.5, 0, -d / 2 - 1.3), c.model:GetAttribute("Address") or "cidade")
			if ok then
				id += 1
				hit:SetAttribute("CrimeId", id)
				atms += 1
			else
				warn("[CrimeBuilder] Erro no caixa eletrônico: " .. tostring(hit))
			end
		end
	end
	print(("[CrimeBuilder] %d lojas de conveniência e %d caixas eletrônicos."):format(stores, atms))
	return stores, atms
end

return CrimeBuilder
