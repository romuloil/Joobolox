-- Delegacia urbana e prisão afastada; geometria sem autoridade de jogo.
-- PrisonService controla os prompts, a pena, a fuga e a entrada de teste no Studio.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CivicConfig"))

local PrisonBuilder = require(script.Parent:WaitForChild("PrisonBuilder"))
local TaxiSiteBuilder = require(script.Parent:WaitForChild("TaxiSiteBuilder"))

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
 m:SetAttribute("Role", "Policial")
 m:SetAttribute("Architecture", "BlueGlassCivic")
 local p=function(name,size,pos,color,material,collide)return localPart(m,base,name,size,pos,color,material,collide)end
 p("Esplanada",Vector3.new(124,0.8,148),Vector3.new(0,0.4,0),STONE,Enum.Material.Concrete)
 p("Piso",Vector3.new(84,0.3,58),Vector3.new(0,0.95,22),WHITE,Enum.Material.Marble)
 p("Fundos",Vector3.new(84,15,1),Vector3.new(0,8.3,51),WHITE)
 for _,x in ipairs({-42,42})do
  p("ParedeLateral",Vector3.new(1,15,58),Vector3.new(x,8.3,22),WHITE)
  for _,z in ipairs({3,22,41})do
   local glass=p("JanelaLateral",Vector3.new(0.25,8,15),Vector3.new(x*1.015,7,z),Color3.fromRGB(84,179,224),Enum.Material.Glass)
   glass.Transparency=0.25
  end
 end
 for _,side in ipairs({-1,1})do
  p("MuretaAzul",Vector3.new(36,2,1),Vector3.new(side*24,1.8,-7),BLUE)
  local glass=p("VidraçaRecepção",Vector3.new(34,8,0.3),Vector3.new(side*24,6.8,-7.1),Color3.fromRGB(88,186,230),Enum.Material.Glass)
  glass.Transparency=0.25
  p("VigaFachada",Vector3.new(36,4,1),Vector3.new(side*24,12.8,-7),WHITE)
  p("ColunaPorta",Vector3.new(0.8,11,1.2),Vector3.new(side*6.4,6.3,-7.1),WHITE)
 end
 p("VergaPorta",Vector3.new(12,4,1),Vector3.new(0,13.8,-7),BLUE)
 p("Laje",Vector3.new(87,0.6,61),Vector3.new(0,15.7,22),WHITE)
 -- Pavimento superior de fachada: grandes painéis azuis e molduras brancas.
 p("VolumeSuperior",Vector3.new(84,13,58),Vector3.new(0,22.5,22),Color3.fromRGB(92,181,222))
 for _,z in ipairs({-7.6,51.6})do
  for x=-35,35,14 do
   p("MolduraSuperior",Vector3.new(1.1,12.5,0.5),Vector3.new(x,22.4,z),WHITE,nil,false)
  end
  p("FaixaSuperior",Vector3.new(86,0.8,0.7),Vector3.new(0,22.3,z),WHITE,nil,false)
 end
 p("Cobertura",Vector3.new(88,0.9,62),Vector3.new(0,29.5,22),Color3.fromRGB(227,222,216))
 p("Platibanda",Vector3.new(88,1.4,1),Vector3.new(0,30.5,-8),WHITE)
 p("Marquise",Vector3.new(20,0.5,8),Vector3.new(0,11.4,-10),BLUE,nil,false)
 sign(m,base,"CENTRO POLICIAL",Vector3.new(0,13.4,-7.7),Vector3.new(60,2.8,0.4),BLUE)
 local crest=p("EscudoKinder",Vector3.new(12,14,0.7),Vector3.new(0,27,-8.5),Color3.fromRGB(227,174,60),Enum.Material.Metal,false)
 label(crest,"★\nKINDER",BLUE)
 p("BalcãoRecepção",Vector3.new(21,3.3,4),Vector3.new(0,2.7,17),WOOD)
 p("Tampo",Vector3.new(22,0.35,4.6),Vector3.new(0,4.5,17),BLUE)
 p("Monitor",Vector3.new(4,2.6,0.4),Vector3.new(0,5.95,17.7),STEEL,nil,false)
 sign(m,base,"RECEPÇÃO",Vector3.new(0,3,14.6),Vector3.new(14,1.7,0.2),BLUE)
 for _,x in ipairs({-24,24})do bench(m,base,Vector3.new(x,2.4,4),BLUE)end
 p("DivisóriaArmaria",Vector3.new(1,12,29),Vector3.new(-12,6.8,36.5),WHITE)
 p("MesaApoio",Vector3.new(21,3,5),Vector3.new(-26,2.7,36),WOOD)
 for _,x in ipairs({-34,-26,-18})do p("ArmárioAzul",Vector3.new(7,9,3),Vector3.new(x,5.3,47),BLUE,Enum.Material.Metal)end
 sign(m,base,"ARMARIA / UNIFORMES",Vector3.new(-26,12,49.8),Vector3.new(28,2.5,0.25),BLUE)
 p("MesaInformes",Vector3.new(20,3,5),Vector3.new(24,2.7,29),WOOD)
 p("TelaInformes",Vector3.new(5,3,0.3),Vector3.new(24,5.9,29.7),BLUE,nil,false)
 sign(m,base,"OCORRÊNCIAS",Vector3.new(24,11,49.8),Vector3.new(22,2.5,0.25),BLUE)
 for x=28,41,1 do p("GradeDecorativa",Vector3.new(0.23,9,0.3),Vector3.new(x,5.5,38),STEEL,Enum.Material.Metal)end
 sign(m,base,"CELA DE APOIO",Vector3.new(34,11.5,37.6),Vector3.new(15,2,0.25),BLUE)
 for _,x in ipairs({-55,55})do plant(m,base,Vector3.new(x,0.8,-9))end
 for _,x in ipairs({-25,25})do for _,z in ipairs({8,38})do lamp(m,base,Vector3.new(x,15.25,z))end end
 local spawns={}
 for i,x in ipairs({-38,0,38})do
  spawns[i]=marker(m,base,"PoliceVehicleSpawn"..i,Vector3.new(x,0.8,-43))
  for _,side in ipairs({-1,1})do p("MarcaVaga",Vector3.new(0.15,0.03,26),Vector3.new(x+side*7,0.83,-43),WHITE,nil,false)end
 end
 local intake=point(m,base,"SimulaçãoStudio",Vector3.new(-17,5,12),"Simular prisão (Studio)","Teste de 60 segundos",1)
 local duty=point(m,base,"PlantaoDelegacia",Vector3.new(17,4.5,12),"Plantão policial","Entrar / sair do serviço",0.5)
 local armory=point(m,base,"ArmariaDelegacia",Vector3.new(-26,5,32.8),"Retirar equipamento","Armaria policial",0.5)
 local report=point(m,base,"OcorrenciasDelegacia",Vector3.new(24,5,25.8),"Registrar informe","Terminal de ocorrências",0.5)
 local uniform=point(m,base,"UniformeDelegacia",Vector3.new(-26,5,45.2),"Retirar uniforme","Vestiário policial",0.5)
 local vehicle=point(m,base,"ViaturaDelegacia",Vector3.new(-53,4,-26),"Retirar viatura","Garagem policial",0.5)
 uniform:SetAttribute("Role","Policial");vehicle:SetAttribute("Role","Policial")
 return intake,{dutyPrompts={duty},armoryPrompts={armory},reportPrompts={report}},
  {uniformPrompts={uniform},vehiclePrompts={vehicle},vehicleSpawns=spawns}
end

local function prison(parent)
	return PrisonBuilder.build(parent)
end

function CivicBuilder.build(map)
 if CivicBuilder.sites then return CivicBuilder.sites end
 local locations=map:FindFirstChild("CivicLocations")
 local fresh=locations==nil
 if fresh then
  locations=folder(map,"CivicLocations")
  local roads=folder(map,"CivicRoads")
  for _,road in ipairs(Config.Roads)do street(roads,road)end
 end
 CivicBuilder.sites=prison(locations)
 local stationModel=locations:FindFirstChild(Config.Station.Name)
 local intake,police,workplace
 if stationModel then
  assert(stationModel:GetAttribute("Architecture")=="BlueGlassCivic","A delegacia antiga precisa ser regenerada para o Marco 5.3")
  local function q(name)local target=assert(stationModel:FindFirstChild(name),name);return assert(target:FindFirstChildOfClass("ProximityPrompt"))end
  local spawns={};for i=1,3 do spawns[i]=assert(stationModel:FindFirstChild("PoliceVehicleSpawn"..i))end
  intake=q("SimulaçãoStudio")
  police={dutyPrompts={q("PlantaoDelegacia")},armoryPrompts={q("ArmariaDelegacia")},reportPrompts={q("OcorrenciasDelegacia")}}
  workplace={uniformPrompts={q("UniformeDelegacia")},vehiclePrompts={q("ViaturaDelegacia")},vehicleSpawns=spawns}
 else intake,police,workplace=station(locations)end
 CivicBuilder.sites.intakePrompt=intake
 local function worldPath(points)
  local result={};for _,p in ipairs(points)do table.insert(result,Config.Station.CFrame*p)end;return result
 end
 CivicBuilder.sites.stationRoutes={
  {name="nova delegacia / recepção",points=worldPath({Vector3.new(0,4,-74),Vector3.new(0,4,-3),Vector3.new(17,4,12)})},
  {name="nova delegacia / vestiário",points=worldPath({Vector3.new(0,4,-3),Vector3.new(-20,4,12),Vector3.new(-26,4,28),Vector3.new(-38,4,28),Vector3.new(-38,4,42),Vector3.new(-26,4,42)})},
  {name="nova delegacia / garagem",points=worldPath({Vector3.new(0,4,-3),Vector3.new(0,4,-15),Vector3.new(-20,4,-20),Vector3.new(-53,4,-26)})},
 }
 for key,prompts in pairs(police)do
  for _,target in ipairs(prompts)do table.insert(CivicBuilder.sites.police[key],target)end
 end
 local taxi=TaxiSiteBuilder.build(map)
 CivicBuilder.sites.taxi=taxi
 CivicBuilder.sites.workplaces={Policial=workplace,Taxista={uniformPrompts={taxi.uniformPrompt},vehiclePrompts={taxi.vehiclePrompt},vehicleSpawns=taxi.vehicleSpawns}}
 if CivicBuilder.sites.prisonWorkplace then
  for key,items in pairs(CivicBuilder.sites.prisonWorkplace)do
   workplace[key]=workplace[key]or{}
   for _,item in ipairs(items)do table.insert(workplace[key],item)end
  end
 end
 map:SetAttribute("CivicReady",true)
 return CivicBuilder.sites
end
return CivicBuilder
