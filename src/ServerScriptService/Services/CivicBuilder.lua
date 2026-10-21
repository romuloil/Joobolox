-- Delegacia urbana e prisão afastada; geometria sem autoridade de jogo.
-- PrisonService controla os prompts, a pena, a fuga e a entrada de teste no Studio.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CivicConfig"))

local PrisonBuilder = require(script.Parent:WaitForChild("PrisonBuilder"))

local CivicBuilder = { sites = nil }
local WHITE = Color3.fromRGB(235, 235, 224)
local BLUE = Color3.fromRGB(31, 69, 107)
local STEEL = Color3.fromRGB(82, 96, 104)
local STONE = Color3.fromRGB(173, 176, 163)
local WOOD = Color3.fromRGB(141, 104, 69)
local AMBER = Color3.fromRGB(235, 174, 70)

local function folder(parent, name)
	local f = Instance.new("Folder")
	f.Name, f.Parent = name, parent
	return f
end

local function part(parent, name, size, cf, color, material, collide)
	local p = Instance.new("Part")
	p.Name, p.Size, p.CFrame = name, size, cf
	p.Anchored = true
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Color, p.Material = color or WHITE, material or Enum.Material.SmoothPlastic
	p.CanCollide = collide ~= false
	p.Parent = parent
	return p
end

local function localPart(parent, base, name, size, position, color, material, collide)
	return part(parent, name, size, base * CFrame.new(position), color, material, collide)
end

local function label(target, text, color, face)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Letreiro"
	gui.Face = face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud, gui.LightInfluence = 35, 0
	gui.Parent = target
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.TextColor3 = color or WHITE
	t.TextScaled, t.TextWrapped = true, true
	t.Font, t.Text = Enum.Font.GothamBold, text
	t.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 5), UDim.new(0, 5)
	pad.Parent = t
end

local function sign(parent, base, text, pos, size, color)
	local p = localPart(parent, base, "Placa", size or Vector3.new(16, 3, 0.3), pos, color or BLUE, nil, false)
	label(p, text)
	return p
end

local function lamp(parent, base, pos)
	local lightPart = localPart(parent, base, "Luminária", Vector3.new(4, 0.2, 2), pos, Color3.fromRGB(255, 241, 205), Enum.Material.Neon, false)
	local light = Instance.new("PointLight")
	light.Brightness, light.Range, light.Shadows = 1.15, 23, false
	light.Color, light.Parent = lightPart.Color, lightPart
end

local function bench(parent, base, pos, color)
	local p = Instance.new("Seat")
	p.Name, p.Size, p.CFrame = "Banco", Vector3.new(7, 0.5, 2), base * CFrame.new(pos)
	p.Anchored, p.CanTouch = true, false
	p.Color, p.Material = color or WOOD, Enum.Material.SmoothPlastic
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	for _, x in ipairs({ -2.6, 2.6 }) do
		part(parent, "PéBanco", Vector3.new(0.5, 1.7, 1.6), p.CFrame * CFrame.new(x, -1, 0), STEEL)
	end
	part(parent, "Encosto", Vector3.new(7, 1.9, 0.3), p.CFrame * CFrame.new(0, 0.9, 0.9), color or WOOD)
	-- SeatService acrescenta o prompt E sem sentar automaticamente ao encostar.
end

local function plant(parent, base, pos)
	localPart(parent, base, "Floreira", Vector3.new(5, 1.8, 3), pos + Vector3.new(0, 0.9, 0), STONE, Enum.Material.Concrete)
	local foliage = localPart(parent, base, "Arbusto", Vector3.new(4.7, 2.6, 2.8), pos + Vector3.new(0, 2.3, 0), Color3.fromRGB(77, 125, 71), Enum.Material.Grass, false)
	foliage.Shape = Enum.PartType.Ball
end

local function marker(parent, base, name, position)
	local p = localPart(parent, base, name, Vector3.new(1, 1, 1), position, WHITE, nil, false)
	p.Transparency, p.CanTouch, p.CanQuery = 1, false, false
	return p
end

local function newSite(parent, name, mapLabel, kind, base)
	local m = Instance.new("Model")
	m.Name = name
	m:SetAttribute("PlaceName", name)
	m:SetAttribute("MapLabel", mapLabel)
	m:SetAttribute("Kind", kind)
	m:SetAttribute("MapPosition", base.Position)
	m.Parent = parent
	return m
end

local function point(parent, base, name, pos, action, object, hold)
	local p = localPart(parent, base, name, Vector3.new(2.5, 2.5, 0.5), pos, AMBER, Enum.Material.Metal, false)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name .. "Prompt"
	prompt.ActionText, prompt.ObjectText = action, object
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration, prompt.MaxActivationDistance = hold or 1, 9
	prompt.RequiresLineOfSight, prompt.Enabled = true, false
	prompt.Parent = p
	return prompt
end

local function street(parent, road)
	local length = (road.b - road.a).Magnitude
	local cf = CFrame.lookAt((road.a + road.b) / 2, road.b)
	local p = part(parent, road.name, Vector3.new(road.width, 0.5, length), cf * CFrame.new(0, 0.25, 0), Color3.fromRGB(67, 70, 73), Enum.Material.Asphalt)
	p:SetAttribute("RoadStart", road.a)
	p:SetAttribute("RoadEnd", road.b)
	for _, side in ipairs({ -1, 1 }) do
		part(parent, "Calçada", Vector3.new(3, 0.6, length), cf * CFrame.new(side * (road.width / 2 + 1.5), 0.4, 0), STONE, Enum.Material.Concrete)
	end
	if road.width > 15 then
		for z = -length / 2 + 7, length / 2 - 4, 16 do
			part(parent, "Faixa", Vector3.new(0.25, 0.03, 7), cf * CFrame.new(0, 0.52, z), AMBER, nil, false)
		end
		for z = -length / 2 + 20, length / 2 - 10, 65 do
			local poleCf = cf * CFrame.new(road.width / 2 + 3, 0, z)
			localPart(parent, poleCf, "Poste", Vector3.new(0.5, 11, 0.5), Vector3.new(0, 5.5, 0), STEEL, Enum.Material.Metal)
			lamp(parent, poleCf, Vector3.new(-1, 11, 0))
		end
	end
end

local function station(parent)
	local base = Config.Station.CFrame
	local m = newSite(parent, Config.Station.Name, "Delegacia", "Police", base)
	local function p(name, size, pos, color, material, collide)
		return localPart(m, base, name, size, pos, color, material, collide)
	end
	p("Pátio", Vector3.new(52, 0.8, 72), Vector3.new(0, 0.4, 0), STONE, Enum.Material.Concrete)
	p("Piso", Vector3.new(44, 0.3, 54), Vector3.new(0, 0.95, 0), WHITE, Enum.Material.Marble)
	p("ParedeFundos", Vector3.new(44, 16, 1), Vector3.new(0, 8.8, 26.5))
	for _, x in ipairs({ -21.5, 21.5 }) do
		p("ParedeLateral", Vector3.new(1, 16, 54), Vector3.new(x, 8.8, 0))
		p("FaixaAzul", Vector3.new(1.05, 2.3, 53), Vector3.new(x, 12, 0), BLUE)
	end
	for _, side in ipairs({ -1, 1 }) do
		p("Fachada", Vector3.new(18, 16, 1), Vector3.new(side * 13, 8.8, -26.5))
		local glass = p("Janela", Vector3.new(9, 5, 0.2), Vector3.new(side * 13, 6, -27.1), Color3.fromRGB(142, 185, 202), Enum.Material.Glass)
		glass.Transparency = 0.15
		p("Pórtico", Vector3.new(1, 10, 1), Vector3.new(side * 4.5, 5.8, -27.5), BLUE)
	end
	p("VigaPorta", Vector3.new(8, 6, 1), Vector3.new(0, 13.8, -26.5), BLUE)
	p("Cobertura", Vector3.new(46, 0.8, 56), Vector3.new(0, 17.2, 0), BLUE)
	p("Marquise", Vector3.new(14, 0.5, 6), Vector3.new(0, 10.6, -29), BLUE, nil, false)
	sign(m, base, "CENTRO POLICIAL\nLITTLE LITTLE KINDER", Vector3.new(0, 14, -27.1), Vector3.new(35, 4, 0.35))
	p("BalcãoRecepção", Vector3.new(18, 3.5, 3), Vector3.new(-5, 2.7, -5), WOOD)
	p("Tampo", Vector3.new(19, 0.3, 3.6), Vector3.new(-5, 4.6, -5), BLUE)
	sign(m, base, "RECEPÇÃO", Vector3.new(-5, 3.1, -6.8), Vector3.new(9, 1.5, 0.2))
	p("Monitor", Vector3.new(3, 2, 0.3), Vector3.new(-4, 5.75, -4.8), STEEL)
	bench(m, base, Vector3.new(12, 2.4, -15), BLUE)
	plant(m, base, Vector3.new(-18, 1.1, -20))
	-- Sala de apoio à esquerda; passagem de 8 studs na divisória.
	p("DivisóriaApoio", Vector3.new(1, 10, 19), Vector3.new(-1, 5.8, 16))
	sign(m, base, "APOIO À PATRULHA", Vector3.new(-11, 9, 25.8), Vector3.new(17, 2, 0.2))
	p("MesaApoio", Vector3.new(12, 2.8, 6), Vector3.new(-11, 2.5, 15), WOOD)
	p("MapaDePatrulha", Vector3.new(12, 7, 0.3), Vector3.new(-11, 8.6, 25.8), Color3.fromRGB(94, 129, 109), nil, false)
	for i = 1, 4 do
		p("Armário", Vector3.new(2.7, 7, 2.5), Vector3.new(-18 + i * 3, 4.5, 22.5), BLUE)
	end
	-- Cela decorativa: não participa da pena, que acontece na prisão afastada.
	for x = 3, 20, 2 do
		p("GradeDecorativa", Vector3.new(0.3, 9, 0.3), Vector3.new(x, 5.4, 9), STEEL, Enum.Material.Metal)
	end
	p("TravessaGrade", Vector3.new(18, 0.4, 0.4), Vector3.new(12, 9.8, 9), STEEL)
	bench(m, base, Vector3.new(12, 2.4, 21), STONE)
	sign(m, base, "CELA DE APOIO\nÁrea cenográfica", Vector3.new(12, 11.5, 8.9), Vector3.new(17, 2.5, 0.2))
	for _, x in ipairs({ -11, 11 }) do
		for _, z in ipairs({ -15, 14 }) do lamp(m, base, Vector3.new(x, 16.5, z)) end
	end
	-- Duas vagas pintadas no recuo, sem veículos autônomos ou bloqueio da entrada.
	for _, x in ipairs({ -17, 17 }) do
		for _, side in ipairs({ -1, 1 }) do p("Vaga", Vector3.new(0.15, 0.05, 7), Vector3.new(x + side * 3.7, 0.84, -31), WHITE, nil, false) end
	end
	local intake = point(m, base, "SimulaçãoStudio", Vector3.new(-10, 5.2, -8), "Simular prisão (Studio)", "Teste de 60 segundos", 1)
	local duty = point(m, base, "PlantaoDelegacia", Vector3.new(10, 4.5, -9), "Plantão policial", "Entrar / sair do serviço", 0.5)
	local armory = point(m, base, "ArmariaDelegacia", Vector3.new(-9, 5, 21), "Retirar equipamento", "Armário policial", 0.5)
	local report = point(m, base, "OcorrenciasDelegacia", Vector3.new(-3, 5, -6), "Registrar informe", "Terminal de ocorrências", 0.5)
	return intake, { dutyPrompts = { duty }, armoryPrompts = { armory }, reportPrompts = { report } }
end

local function prison(parent)
	return PrisonBuilder.build(parent)
end

function CivicBuilder.build(map)
	if CivicBuilder.sites then return CivicBuilder.sites end
	-- A reconstrução de referências preserva o mapa congelado desta versão.
	local existing = map:FindFirstChild("CivicLocations")
	if existing and map:GetAttribute("CivicReady") then
		local stationModel = existing:FindFirstChild(Config.Station.Name)
		CivicBuilder.sites = PrisonBuilder.build(existing)
		assert(stationModel, "Delegacia ausente no mapa existente")
		local function prompt(name)
			local target = stationModel:FindFirstChild(name)
			return target and target:FindFirstChildOfClass("ProximityPrompt")
		end
		CivicBuilder.sites.intakePrompt = assert(prompt("SimulaçãoStudio"), "Entrada de teste ausente")
		local police = CivicBuilder.sites.police
		for key, name in pairs({ dutyPrompts = "PlantaoDelegacia", armoryPrompts = "ArmariaDelegacia", reportPrompts = "OcorrenciasDelegacia" }) do
			local target = prompt(name)
			if target then table.insert(police[key], target) end
		end
		return CivicBuilder.sites
	end
	assert(not existing, "CivicLocations parcial já existe; restaure a versão completa antes de reconstruir.")
	local locations = folder(map, "CivicLocations")
	local roads = folder(map, "CivicRoads")
	for _, road in ipairs(Config.Roads) do street(roads, road) end
	CivicBuilder.sites = prison(locations)
	local intake, stationPolice = station(locations)
	CivicBuilder.sites.intakePrompt = intake
	for key, prompts in pairs(stationPolice) do
		for _, target in ipairs(prompts) do
			table.insert(CivicBuilder.sites.police[key], target)
		end
	end
	map:SetAttribute("CivicReady", true)
	return CivicBuilder.sites
end

return CivicBuilder
