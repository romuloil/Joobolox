-- Complexo prisional inspirado na referência visual: blocos claros, faixas azuis,
-- coberturas laranja, muralha contínua e quatro torres. Toda autoridade é dos serviços.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CivicConfig"))
local PrisonBuilder = {}
local cached
local V = Vector3.new
local WHITE = Color3.fromRGB(233, 230, 215)
local BLUE = Color3.fromRGB(31, 111, 165)
local DARK = Color3.fromRGB(40, 57, 67)
local ORANGE = Color3.fromRGB(233, 151, 74)
local STONE = Color3.fromRGB(165, 174, 172)
local WOOD = Color3.fromRGB(149, 112, 75)
local GREEN = Color3.fromRGB(102, 143, 95)

local function model(parent, name)
 local m = Instance.new("Model"); m.Name = name; m.Parent = parent; return m
end
local function part(parent, base, name, size, pos, color, material, collide)
 local p = Instance.new("Part")
 p.Name, p.Size = name, size
 p.CFrame = base * (typeof(pos) == "CFrame" and pos or CFrame.new(pos))
 p.Color, p.Material = color or WHITE, material or Enum.Material.SmoothPlastic
 p.Anchored, p.CanCollide = true, collide ~= false
 p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
 p.Parent = parent; return p
end
local function label(target, text, face, color)
 local gui = Instance.new("SurfaceGui"); gui.Name = "Identificação"
 gui.Face = face or Enum.NormalId.Front; gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
 gui.PixelsPerStud, gui.LightInfluence = 25, 0; gui.Parent = target
 local l = Instance.new("TextLabel"); l.Size = UDim2.fromScale(1,1)
 l.BackgroundTransparency, l.TextScaled, l.TextWrapped = 1,true,true
 l.Font, l.TextColor3, l.Text = Enum.Font.GothamBold,color or WHITE,text
 l.Parent = gui
end
local function sign(parent, base, text, pos, size, color)
 local p = part(parent,base,"Letreiro",size or V(22,3,0.25),pos,color or BLUE,nil,false)
 label(p,text); return p
end
local function lamp(parent, base, position, size)
 local p = part(parent,base,"Luminária",size or V(4,0.2,2),position,Color3.fromRGB(255,241,206),Enum.Material.Neon,false)
 local l=Instance.new("PointLight"); l.Brightness,l.Range,l.Shadows=1.2,25,false; l.Color=p.Color; l.Parent=p
 return p
end
local function marker(parent, base, name, position)
 local p=part(parent,base,name,V(1,1,1),position,WHITE,nil,false)
 p.Transparency,p.CanTouch,p.CanQuery=1,false,false; return p
end
local function seat(parent,base,position,color)
 local p=Instance.new("Seat"); p.Name="Banco";p.Anchored,p.CanTouch=true,false
 p.Size,p.CFrame=V(6,0.5,2),base*CFrame.new(position);p.Color,p.Material=color or WOOD,Enum.Material.SmoothPlastic;p.Parent=parent
 for _,x in ipairs({-2.3,2.3}) do part(parent,p.CFrame,"PéBanco",V(0.4,1.6,1.5),V(x,-0.8,0),DARK) end
 part(parent,p.CFrame,"Encosto",V(6,1.5,0.3),V(0,0.8,0.8),color or WOOD);return p
end
local function window(parent,base,pos,size)
 local f=part(parent,base,"MolduraJanela",size+V(0.6,0.6,0),pos,BLUE,nil,false)
 local glass=part(parent,base,"Vidro",size,pos+V(0,0,-0.18),Color3.fromRGB(149,190,208),Enum.Material.Glass,false)
 glass.Transparency=0.35;return f
end
local function prompt(parent,base,name,pos,action,object,kind,hold)
 local p=part(parent,base,name,V(2,2,0.4),pos,BLUE,Enum.Material.Metal,false)
 local q=Instance.new("ProximityPrompt");q.Name=name.."Prompt";q.ActionText,q.ObjectText=action,object
 q.KeyboardKeyCode,q.MaxActivationDistance,q.HoldDuration=Enum.KeyCode.E,9,hold or 0.5
 q.RequiresLineOfSight,q.Enabled=true,true;q.Parent=p
 if kind then q:SetAttribute("PoliceAction",kind);q:SetAttribute("Facility","Prison") end
 return q
end
local function door(parent,base,id,pos,size,delta,police,name)
 local leaf=part(parent,base,id,size,pos,BLUE,Enum.Material.DiamondPlate,true)
 local closed=leaf.CFrame;local open=base*CFrame.new(pos+delta)
 leaf:SetAttribute("DoorId",id);leaf:SetAttribute("DoorClosed",closed);leaf:SetAttribute("DoorOpen",open)
 label(leaf,name or "ACESSO CONTROLADO")
 local entry={id=id,part=leaf,closed=closed,open=open,restricted=true,name=name or id}
 if police then
  local q=prompt(parent,base,id.."Control",pos+V(0,0,-2),"Abrir / fechar",name or "Porta restrita","Door",0.5)
  q:SetAttribute("DoorId",id);entry.prompt=q;table.insert(police.doors,entry)
 end
 return entry
end
local function shell(parent,base,name,center,width,depth,height,roof,doorWidth)
 local m=model(parent,name);local b=base*CFrame.new(center)
 part(m,b,"Piso",V(width,0.3,depth),V(0,0.95,0),WHITE,Enum.Material.Concrete)
 part(m,b,"ParedeFundos",V(width,height,1),V(0,height/2+0.8,depth/2),WHITE)
 for _,x in ipairs({-width/2,width/2})do
  part(m,b,"ParedeLateral",V(1,height,depth),V(x,height/2+0.8,0),WHITE)
 end
 local gap=doorWidth or 10;local side=(width-gap)/2
 for _,s in ipairs({-1,1})do
  part(m,b,"Fachada",V(side,height,1),V(s*(gap/2+side/2),height/2+0.8,-depth/2),WHITE)
 end
 part(m,b,"Verga",V(gap,height-10,1),V(0,10.8+(height-10)/2,-depth/2),WHITE)
 part(m,b,"Cobertura",V(width+2,0.8,depth+2),V(0,height+1.2,0),roof)
 for _,z in ipairs({-depth/2-0.08,depth/2+0.08})do
  part(m,b,"FaixaAzul",V(width,2,0.2),V(0,4.2,z),BLUE,nil,false)
 end
 for _,x in ipairs({-width/4,width/4})do lamp(m,b,V(x,height+0.65,0))end
 return m,b
end
local function compoundTower(parent,base,x,z,index,police)
 local m=model(parent,"Torre "..index)
 -- A entrada das torres do sul aponta para o pátio, nunca para dentro da muralha.
 local b=base*CFrame.new(x,0,z)*CFrame.Angles(0,z<0 and math.pi or 0,0)
 for _,side in ipairs({-1,1})do
  part(m,b,"Pilar",V(1,29,14),V(side*6.5,15.3,0),WHITE,Enum.Material.Concrete)
  part(m,b,"FaixaAzul",V(1.1,3,14.1),V(side*6.5,18,0),BLUE)
 end
 part(m,b,"ParedeTorre",V(12,29,1),V(0,15.3,6.5),WHITE)
 part(m,b,"BaseCabineEsquerda",V(9,0.8,17),V(-4,29.8,0),WHITE)
 -- A abertura da escada ocupa a metade direita da cabine; o patamar fica à esquerda.
 part(m,b,"BaseCabineDireita",V(8,0.8,3),V(4.5,29.8,7),WHITE)
 -- Quatro lances com degraus baixos: desnível de 0,62 stud por pisada.
 for i=1,48 do
  local flight=math.floor((i-1)/12)
  local step=(i-1)%12
  local forward=flight%2==0
  local zz=forward and (-5+step*0.9) or (4.9-step*0.9)
  local xx=forward and -3.2 or 3.2
  part(m,b,"Degrau",V(5.6,0.35,1.05),V(xx,1+(i-1)*0.62,zz),STONE,Enum.Material.Concrete)
  if i%12==0 and i<48 then
   part(m,b,"Patamar",V(12,0.3,2.0),V(0,1+(i-1)*0.62+0.025,forward and 4.9 or -5),STONE)
  end
 end
 part(m,b,"GuardaEscada",V(0.25,2,10),V(0.65,31.3,1.5),DARK)
 -- Entrada de torre só pelo lado interior; não abre um buraco no muro.
 local inward=z<0 and 1 or -1
 local d=door(m,b,"TowerDoor"..index,V(0,5.8,-6.5),V(6,10,0.5),V(6.8,0,0),police,"TORRE "..index)
 for _,side in ipairs({-1,1})do
  part(m,b,"FachadaTorre",V(3.5,10,1),V(side*4.75,5.8,-6.5),WHITE)
 end
 part(m,b,"VergaTorre",V(13,18,1),V(0,19.8,-6.5),WHITE)
 for _,side in ipairs({-1,1})do
  local g=part(m,b,"VidroCabine",V(0.3,7,14),V(side*7.1,34,0),Color3.fromRGB(164,201,210),Enum.Material.Glass,true);g.Transparency=0.45
  local f=part(m,b,"VidroCabine",V(14,7,0.3),V(0,34,side*7.1),Color3.fromRGB(164,201,210),Enum.Material.Glass,true);f.Transparency=0.45
  for _,zz in ipairs({-7.2,7.2})do part(m,b,"Caixilho",V(0.25,7.5,0.3),V(side*3.5,34,zz),DARK,nil,false)end
  part(m,b,"CaixilhoLateral",V(0.3,7.5,0.25),V(side*7.2,34,0),DARK,nil,false)
  part(m,b,"GuardaCorpo",V(14,0.25,0.25),V(0,33,side*7.3),DARK)
 end
 for _,side in ipairs({-1,1})do
  part(m,b,"FaixaCabineLateral",V(0.6,2,15),V(side*7.3,29,0),BLUE)
 end
 part(m,b,"FaixaCabineFundos",V(14,2,0.6),V(0,29,7.3),BLUE)
 part(m,b,"FaixaCabineFrente",V(7.5,2,0.6),V(-3.5,29,-7.3),BLUE)
 for _,s in ipairs({-1,1})do
  local wedge=Instance.new("WedgePart");wedge.Name="TelhadoInclinado";wedge.Anchored=true
  wedge.Size=V(19,6,9.5);wedge.Color,wedge.Material=DARK,Enum.Material.Slate
  wedge.CFrame=b*CFrame.new(0,40.2,s*4.75)*(s==1 and CFrame.Angles(0,math.pi,0)or CFrame.new());wedge.Parent=m
 end
 lamp(m,b,V(0,37.3,0));return m
end

-- Reúne referências de uma cena já construída sem duplicar nem substituir peças.
function PrisonBuilder.recover(parent)
 local m=parent.Name==Config.Prison.Name and parent or parent:FindFirstChild(Config.Prison.Name)
 assert(m and m:GetAttribute("ComplexVersion")==2,"Prisão existente precisa da arquitetura Marco 5.2 completa")
 if cached and cached.model==m then return cached end
 local base=Config.Prison.CFrame
 local police={dutyPrompts={},armoryPrompts={},reportPrompts={},controlPrompts={},patrolPrompts={},doors={}}
 local result={model=m,police=police,prisonCells={},escapeDoors={}}
 local lookup={Duty="dutyPrompts",Armory="armoryPrompts",Reports="reportPrompts",Control="controlPrompts",Patrol="patrolPrompts"}
 for _,object in ipairs(m:GetDescendants())do
  if object:IsA("ProximityPrompt")then
   local action=object:GetAttribute("PoliceAction")
   if lookup[action]then table.insert(police[lookup[action]],object)
   elseif action=="Training"then police.trainingPrompt=object
   elseif action=="SuspectTest"then police.suspectTestPrompt=object end
  elseif object:IsA("BasePart")then
   local id=object:GetAttribute("DoorId")
   if id and not object:GetAttribute("CellId")then
    local entry={id=id,part=object,closed=object:GetAttribute("DoorClosed"),open=object:GetAttribute("DoorOpen"),restricted=true,name=id}
    if id=="EscapeMaintenanceDoor"then result.escapeDoors[1]=entry
    else
     local terminal=m:FindFirstChild(id.."Control",true)
     entry.prompt=terminal and terminal:FindFirstChildOfClass("ProximityPrompt")
     assert(entry.prompt,"Terminal de porta ausente: "..id);table.insert(police.doors,entry)
    end
   end
  end
 end
 for row=1,2 do
  local cx=row==1 and -105 or -45;local face=row==1 and -90 or -60
  for i=0,7 do
   local id=(row==1 and "A"or"B")..string.format("%02d",i+1);local z=-46+i*18
   local spawn=m:FindFirstChild("CellSpawn_"..id,true)
   local leaf=m:FindFirstChild("CellDoor_"..id,true)
   assert(spawn and leaf,"Cela incompleta: "..id)
   table.insert(result.prisonCells,{id=id,spawn=spawn,door=leaf,closed=leaf:GetAttribute("DoorClosed"),open=leaf:GetAttribute("DoorOpen"),
    bounds={cf=base*CFrame.new(cx,9,z),half=V(14,8,8)},enclosure={cf=base*CFrame.new(cx,9,z),half=V(15,8,9)},
    exitPath={base*V(cx,4,z),base*V(face,4,z),base*V(-75,4,z)}})
  end
 end
 result.escapeSteps={}
 for _,name in ipairs({"EscapeHatch","EscapePassage","EscapeExit"})do
  local terminal=m:FindFirstChild(name,true)
  table.insert(result.escapeSteps,assert(terminal and terminal:FindFirstChildOfClass("ProximityPrompt"),"Passagem incompleta: "..name))
 end
 result.prisonSpawn=result.prisonCells[1].spawn
 result.prisonRelease=assert(m:FindFirstChild("PrisonRelease",true),"Saída da prisão ausente")
 result.prisonBounds={cf=base*CFrame.new(Config.Prison.BoundsCenter),half=Config.Prison.BoundsHalf}
 police.trainingSpawn=m:FindFirstChild("TrainingSpawn",true);police.trainingTarget=m:FindFirstChild("TrainingTarget",true)
 table.sort(police.patrolPrompts,function(a,b)return tonumber(a:GetAttribute("PatrolId"))<tonumber(b:GetAttribute("PatrolId"))end)
 local container=parent.Name==Config.Prison.Name and parent.Parent or parent
 local fuel=container:FindFirstChild(Config.Fuel.Name)
 assert(fuel,"Posto afastado ausente")
 local personal=fuel:FindFirstChild("GaragemPessoal",true)
 result.personalGarage={prompt=assert(personal):FindFirstChildOfClass("ProximityPrompt"),spawns={assert(fuel:FindFirstChild("PersonalVehicleSpawn1",true)),assert(fuel:FindFirstChild("PersonalVehicleSpawn2",true))}}
 local uniform=m:FindFirstChild("UniformePrisão",true);local vehicle=m:FindFirstChild("ViaturaPrisão",true)
 local spawns={};for i=1,3 do spawns[i]=assert(m:FindFirstChild("PrisonPoliceVehicleSpawn"..i,true))end
 result.prisonWorkplace={uniformPrompts={assert(uniform):FindFirstChildOfClass("ProximityPrompt")},vehiclePrompts={assert(vehicle):FindFirstChildOfClass("ProximityPrompt")},vehicleSpawns=spawns}
 cached=result;return result
end

function PrisonBuilder.build(parent)
 if cached and cached.model.Parent==parent then return cached end
 if parent:FindFirstChild(Config.Prison.Name)then return PrisonBuilder.recover(parent)end
 local base=Config.Prison.CFrame
 local m=model(parent,Config.Prison.Name)
 m:SetAttribute("PlaceName",Config.Prison.Name);m:SetAttribute("MapLabel","Prisão");m:SetAttribute("Kind","Prison");m:SetAttribute("MapPosition",base.Position);m:SetAttribute("ComplexVersion",2)
 local police={dutyPrompts={},armoryPrompts={},reportPrompts={},controlPrompts={},patrolPrompts={},doors={}}
 local sites={police=police,prisonCells={},escapeDoors={}}
 local p=function(name,size,pos,color,material,collide)return part(m,base,name,size,pos,color,material,collide)end
 p("Esplanada",V(285,0.8,270),V(0,0.4,27.5),STONE,Enum.Material.Concrete)
 p("PátioRecepção",V(132,0.8,43),V(0,0.4,-127),STONE,Enum.Material.Concrete)
 p("PasseioVisitantes",V(10,0.8,20),V(0,0.4,-156),STONE,Enum.Material.Concrete)
 p("CaminhoPrincipal",V(21,0.05,150),V(0,0.85,10),Color3.fromRGB(191,194,186),Enum.Material.Concrete,false)
 -- Perímetro contínuo com só os portões controlados e a passagem técnica.
 for _,x in ipairs({-140,140})do
  if x<0 then p("MuralhaOeste",V(2,23,265),V(x,12.3,27.5),WHITE,Enum.Material.Concrete)
  else
   p("MuralhaLesteSul",V(2,23,216),V(x,12.3,3),WHITE,Enum.Material.Concrete)
   p("MuralhaLesteNorte",V(2,23,31),V(x,12.3,144.5),WHITE,Enum.Material.Concrete)
   p("VergaPassagem",V(2,14,18),V(x,16.8,120),WHITE,Enum.Material.Concrete)
  end
  p("FaixaMuralha",V(2.12,3,265),V(x,17,27.5),BLUE,nil,false)
 end
 for _,z in ipairs({-105,160})do
  if z>0 then p("MuralhaNorte",V(280,23,2),V(0,12.3,z),WHITE,Enum.Material.Concrete)
  else
   for _,s in ipairs({-1,1})do p("MuralhaSul",V(130,23,2),V(s*75,12.3,z),WHITE,Enum.Material.Concrete)end
   p("VergaPortão",V(20,11,2),V(0,18.3,z),WHITE)
  end
  for _,s in ipairs({-1,1})do
   p("FaixaMuralha",V(z>0 and 140 or 130,3,2.1),V(s*(z>0 and 70 or 75),17,z),BLUE,nil,false)
  end
 end
 -- Entradas consecutivas: visitantes no bloco público, equipe no interior seguro.
 door(m,base,"PrisonOuterGate",V(0,6.8,-105),V(20,12,1),V(21,0,0),police,"PORTÃO EXTERNO")
 door(m,base,"PrisonInnerGate",V(0,6.8,-57),V(20,12,0.6),V(21,0,0),police,"PORTÃO INTERNO")
 p("AntecâmaraOeste",V(1,13,48),V(-10.5,7.3,-81),WHITE)
 p("AntecâmaraLesteSul",V(1,13,21),V(10.5,7.3,-94.5),WHITE)
 p("AntecâmaraLesteNorte",V(1,13,19),V(10.5,7.3,-66.5),WHITE)
 p("AntecâmaraVerga",V(1,3,8),V(10.5,12.3,-80),WHITE)
 door(m,base,"PrisonSideAccess",V(10.5,5.8,-80),V(0.6,10,8),V(0,0,9.5),police,"ACESSO À ARMARIA")
 sign(m,base,"CENTRO DE REINTEGRAÇÃO KINDER",V(0,20.3,-106.2),V(105,4.3,0.3),BLUE)
 sign(m,base,"RECEPÇÃO / VISITAS     •     ACESSO CONTROLADO",V(0,9.5,-145.6),V(92,2.7,0.4))
 -- Administração branca/azul, com entrada pública e portas internas controladas.
 local admin,ab=shell(m,base,"Administração",V(0,0,-125),112,40,16,BLUE,16)
 admin:FindFirstChild("ParedeFundos"):Destroy()
 for _,side in ipairs({-1,1})do part(admin,ab,"ParedeFundos",V(46,16,1),V(side*33,8.8,20),WHITE)end
 part(admin,ab,"VergaAcessoSeguro",V(20,4,1),V(0,14.8,20),WHITE)
 p("ParedesSaguão",V(1,12,39),V(-16,6.8,-125),WHITE)
 p("DivisóriaApoio",V(1,12,39),V(38,6.8,-125),WHITE)
 sign(admin,ab,"RECEPÇÃO E INFORMAÇÕES",V(0,7,19.3),V(28,3,0.3))
 part(admin,ab,"Balcão",V(22,3.3,3),V(0,2.5,12),WOOD)
 part(admin,ab,"Tampo",V(23,0.3,3.4),V(0,4.3,12),BLUE)
 for _,x in ipairs({-10,10})do seat(admin,ab,V(x,2.5,-10),BLUE)end
 lamp(admin,ab,V(0,16.4,0),V(8,0.2,3))
 local duty=prompt(admin,ab,"PlantãoPrisão",V(8,4,8),"Entrar / sair do serviço","Plantão policial","Duty")
 table.insert(police.dutyPrompts,duty)
 police.suspectTestPrompt=prompt(admin,ab,"TesteSuspeitoStudio",V(-8,4,3),"Participar do teste","Simular suspeito (Studio)","SuspectTest")
 police.suspectTestPrompt.Enabled=false
 local report=prompt(admin,ab,"TerminalRelatórios",V(26,4,-4),"Registrar ocorrência","Central de informes","Reports")
 table.insert(police.reportPrompts,report)
 sign(admin,ab,"CENTRAL DE INFORMES",V(25,9.5,19.3),V(22,2.3,0.3))
 part(admin,ab,"MesaRelatórios",V(17,2.6,5),V(25,2.4,4),WOOD)
 for _,x in ipairs({21,29})do
  part(admin,ab,"Monitor",V(4,2.6,0.3),V(x,4.9,4.5),DARK)
  part(admin,ab,"Tela",V(3.4,2,0.1),V(x,4.9,4.3),Color3.fromRGB(76,143,165),Enum.Material.Neon,false)
 end
 -- A parte administrativa segura fica após o portão, evitando passagem pública pelo armamento.
 local armory,ar=shell(m,base,"Armaria",V(75,0,-76),76,42,16,BLUE,10)
 door(armory,ar,"PrisonArmory",V(0,5.8,-21),V(10,10,0.6),V(11,0,0),police,"ARMARIA")
 sign(armory,ar,"ARMARIA / EQUIPAMENTOS",V(0,13,-21.7),V(50,3,0.4))
 for _,x in ipairs({-29,-18,-7,4,15,26})do
  part(armory,ar,"ArmárioAzul",V(8,9,3),V(x,5.3,16),BLUE,Enum.Material.Metal)
  part(armory,ar,"Alça",V(0.2,1.2,0.15),V(x+2,5.2,14.4),STONE,nil,false)
 end
 local gear=prompt(armory,ar,"RetiradaEquipamento",V(0,4.8,7),"Retirar equipamento","Lançador de água, algemas e rádio","Armory")
 table.insert(police.armoryPrompts,gear)
 part(armory,ar,"BancadaEquipamentos",V(28,3,5),V(0,2.5,11),WOOD)
 sign(armory,ar,"EQUIPAMENTOS CARTUNESCOS\nUso autorizado em serviço",V(-25,7.5,20.3),V(20,5,0.3))
 for _,x in ipairs({-31,31})do window(armory,ar,V(x,8,-21.7),V(9,5,0.2))end
 -- Centro de controle junto ao pátio e à passagem entre os dois portões.
 local control,cb=shell(m,base,"Controle",V(38,0,-28),56,38,16,BLUE,10)
 door(control,cb,"PrisonControl",V(0,5.8,-19),V(10,10,0.6),V(11,0,0),police,"CONTROLE")
 sign(control,cb,"CENTRO DE CONTROLE",V(0,13,-19.7),V(43,3,0.3))
 part(control,cb,"Console",V(34,3,5),V(0,2.5,9),DARK)
 for _,x in ipairs({-12,0,12})do
  part(control,cb,"MonitorControle",V(9,4,0.3),V(x,5.7,11),BLUE)
  label(control:GetChildren()[#control:GetChildren()],"SETOR SEGURO",Enum.NormalId.Front)
 end
 local q=prompt(control,cb,"PainelControle",V(0,4,4),"Abrir painel","Portões e emergência","Control")
 table.insert(police.controlPrompts,q)
 -- Volume superior octagonal e heliponto decorativo como a referência.
 local hub=p("VolumeSuperior",V(15,36,36),CFrame.new(0,25.2,-125)*CFrame.Angles(0,0,math.pi/2),WHITE,Enum.Material.Concrete)
 hub.Shape=Enum.PartType.Cylinder
 local band=p("FaixaSuperior",V(4,36.3,36.3),CFrame.new(0,25.2,-125)*CFrame.Angles(0,0,math.pi/2),BLUE)
 band.Shape=Enum.PartType.Cylinder
 local heli=p("HelipontoCenográfico",V(0.7,47,47),CFrame.new(0,33.1,-125)*CFrame.Angles(0,0,math.pi/2),DARK)
 heli.Shape=Enum.PartType.Cylinder;label(heli,"H",Enum.NormalId.Right,WHITE);heli:SetAttribute("Decorative",true)
 -- Bloco de celas fechado: duas alas, oito celas individuais em cada lado.
 local wing=model(m,"Bloco de Celas A / B")
 part(wing,base,"PisoAlojamentos",V(92,0.3,146),V(-75,0.95,17),WHITE)
 part(wing,base,"ParedeOeste",V(1,17,146),V(-120,9.3,17),WHITE)
 part(wing,base,"ParedeLeste",V(1,17,146),V(-30,9.3,17),WHITE)
 part(wing,base,"ParedeFundos",V(90,17,1),V(-75,9.3,89),WHITE)
 for _,s in ipairs({-1,1})do part(wing,base,"ParedeFrontal",V(39,17,1),V(-75+s*25.5,9.3,-55),WHITE)end
 part(wing,base,"VergaCorredor",V(12,7,1),V(-75,14.3,-55),WHITE)
 part(wing,base,"CoberturaLaranja",V(94,0.8,148),V(-75,18.2,17),ORANGE)
 for _,x in ipairs({-97,-53})do
  part(wing,base,"Claraboia",V(10,0.2,80),V(x,18.75,17),Color3.fromRGB(190,220,223),Enum.Material.Glass,false)
 end
 sign(wing,base,"ALOJAMENTOS A — B",V(-75,14.2,-55.7),V(57,3,0.3))
 for row=1,2 do
  local cx=row==1 and -105 or -45;local face=row==1 and -90 or -60
  for i=0,7 do
   local z=-46+i*18;local id=(row==1 and "A"or"B")..string.format("%02d",i+1)
   local cell=model(wing,"Cela "..id)
   for _,zz in ipairs({z-9,z+9})do part(cell,base,"DivisóriaCela",V(30,17,0.5),V(cx,9.3,zz),WHITE,Enum.Material.Concrete)end
   for _,side in ipairs({-1,1})do
    -- Painéis de aço laterais e grades visíveis: intervalo inferior a um stud.
    part(cell,base,"PainelBaixo",V(0.65,2,6),V(face,1.8,z+side*6),BLUE,Enum.Material.Metal)
    for offset=-2.5,2.5,1 do part(cell,base,"GradeCela",V(0.25,8,0.25),V(face,6.8,z+side*6+offset),DARK,Enum.Material.Metal)end
    part(cell,base,"TravessaGrade",V(0.6,0.3,6),V(face,10.7,z+side*6),DARK,Enum.Material.Metal)
   end
   part(cell,base,"VergaCela",V(0.8,6.2,18),V(face,14.4,z),WHITE)
   local leaf=door(cell,base,"CellDoor_"..id,V(face,5.8,z),V(0.6,10,6),V(0,0,6.8),nil,"CELA "..id)
   -- Portas não participam do painel genérico: o serviço mantém a ocupação por cela.
   leaf.part:SetAttribute("CellId",id)
   local spawn=marker(cell,base,"CellSpawn_"..id,V(cx,4,z));spawn:SetAttribute("CellId",id)
   local outer=row==1 and -113 or -37
   part(cell,base,"EstruturaBeliche",V(6,1,8),V(outer,1.6,z-3.6),DARK,Enum.Material.Metal)
   part(cell,base,"Colchão",V(5.8,0.6,7.8),V(outer,2.4,z-3.6),Color3.fromRGB(80,134,166),Enum.Material.Fabric)
   part(cell,base,"Travesseiro",V(5,0.4,1.7),V(outer,2.9,z-5.8),WHITE,Enum.Material.Fabric,false)
   part(cell,base,"Vaso",V(2.3,1.8,2.8),V(outer,1.7,z+5.2),WHITE,Enum.Material.SmoothPlastic)
   part(cell,base,"CaixaDescarga",V(2.3,2.3,1.1),V(outer,2,z+7),WHITE)
   part(cell,base,"Pia",V(3,0.7,1.8),V(cx,3.1,z+7.5),WHITE)
   lamp(cell,base,V(cx,17.5,z),V(4,0.15,2))
   table.insert(sites.prisonCells,{id=id,spawn=spawn,door=leaf.part,closed=leaf.closed,open=leaf.open,bounds={cf=base*CFrame.new(cx,9,z),half=V(14,8,8)},enclosure={cf=base*CFrame.new(cx,9,z),half=V(15,8,9)},exitPath={base*V(cx,4,z),base*V(face,4,z),base*V(-75,4,z)}})
  end
 end
 -- Refeitório e enfermaria dão funções e identidade aos blocos laranja.
 local cafe,fb=shell(m,base,"Refeitório",V(86,0,35),65,50,16,ORANGE,12)
 sign(cafe,fb,"REFEITÓRIO",V(0,13,-25.7),V(39,3,0.3))
 for _,x in ipairs({-18,0,18})do
  part(cafe,fb,"Mesa",V(12,0.6,8),V(x,3.2,3),WOOD)
  for _,z in ipairs({-4,10})do seat(cafe,fb,V(x,2.2,z),BLUE)end
 end
 part(cafe,fb,"BalcãoRefeições",V(46,3.5,5),V(0,2.6,18),STONE)
 for _,x in ipairs({-14,0,14})do part(cafe,fb,"Bandeja",V(9,0.3,3),V(x,4.5,18),DARK,nil,false)end
 local infirm,ib=shell(m,base,"Enfermaria",V(80,0,91),76,40,16,ORANGE,12)
 sign(infirm,ib,"ENFERMARIA",V(0,13,-20.7),V(42,3,0.3))
 for _,x in ipairs({-26,-9,9,26})do
  part(infirm,ib,"Leito",V(8,2,15),V(x,1.9,6),WHITE)
  part(infirm,ib,"ColchãoLeito",V(7.8,0.7,14.7),V(x,3.2,6),Color3.fromRGB(126,178,189),Enum.Material.Fabric)
 end
 -- Quadra, área de exercícios e visitantes; cercas densas sem frestas atravessáveis.
 p("Quadra",V(50,0.05,62),V(5,0.86,68),GREEN,Enum.Material.Concrete,false)
 for _,x in ipairs({-20,30})do p("LinhaQuadra",V(0.2,0.1,62),V(x,0.9,68),WHITE,nil,false)end
 for _,z in ipairs({37,99})do p("LinhaQuadra",V(50,0.1,0.2),V(5,0.9,z),WHITE,nil,false)end
 p("LinhaMeio",V(50,0.1,0.2),V(5,0.9,68),WHITE,nil,false)
 for _,z in ipairs({40,96})do
  p("SuporteCesta",V(0.5,11,0.5),V(5,6.3,z),DARK)
  p("Tabela",V(8,4,0.35),V(5,10,z),WHITE)
  p("Aro",V(3,0.2,1.8),V(5,8.5,z+(z<68 and 1.2 or -1.2)),ORANGE,nil,false)
 end
 for _,x in ipairs({-10,10})do seat(m,base,V(x,2.3,20),BLUE)end
 -- Posto de treinamento: boneco é criado pelo serviço, não uma armadilha para civis.
 police.trainingSpawn=marker(m,base,"TrainingSpawn",V(92,4,-14))
 police.trainingTarget=marker(m,base,"TrainingTarget",V(92,4,8))
 police.trainingPrompt=prompt(m,base,"Treinamento",V(110,4,-12),"Iniciar treino","Abordagem e equipamentos","Training")
 sign(m,base,"ÁREA DE TREINAMENTO",V(92,8,-18),V(35,3,0.3))
 -- Patrulha cobre os quatro setores em uma rota plana, fora das salas e das celas.
 local patrolPoints={V(-128,3,-65),V(-128,3,115),V(24,3,142),V(126,3,-30)}
 for i,pos in ipairs(patrolPoints)do
  local patrol=prompt(m,base,"Ronda"..i,pos,"Registrar ronda","Setor "..i,"Patrol")
  patrol:SetAttribute("PatrolId",tostring(i));table.insert(police.patrolPrompts,patrol)
 end
 -- Passagem de manutenção: fechada no muro até a primeira ação validada do preso.
 p("PassagemPiso",V(82,0.8,20),V(149,0.4,120),STONE,Enum.Material.Concrete)
 for _,z in ipairs({110,130})do p("PassagemParede",V(82,9,0.7),V(149,5.3,z),STONE,Enum.Material.Concrete)end
 p("PassagemTeto",V(83,0.6,21),V(149,10.1,120),STONE)
 local hatch=door(m,base,"EscapeMaintenanceDoor",V(140,5.3,120),V(0.7,9,17.2),V(0,0,20),nil,"MANUTENÇÃO")
 sites.escapeDoors[1]=hatch
 sites.escapeSteps={
  prompt(m,base,"EscapeHatch",V(115,3.5,119),"Abrir passagem","1/3 • Painel de manutenção",nil,2),
  prompt(m,base,"EscapePassage",V(153,3.5,119),"Atravessar passagem","2/3 • Corredor técnico",nil,1),
  prompt(m,base,"EscapeExit",V(182,3.5,119),"Concluir fuga","3/3 • Saída externa",nil,1),
 }
 for _,q in ipairs(sites.escapeSteps)do q.Enabled=false end
 for _,x in ipairs({120,150,179})do lamp(m,base,V(x,9.65,120))end
 sign(m,base,"SERVIÇO",V(101,5,110),V(11,2,0.25),DARK)
 -- A saída técnica desemboca numa trilha discreta; o posto não revela a fuga.
 local trail=model(parent,"Trilha da Serra")
 local trailPoints={base*V(182,0,120),base*V(225,0,120),V(-300,0,-1020),V(-465,0,-880),V(-465,0,-830),V(-458,0,-805)}
 for i=1,#trailPoints-1 do
  local a,b=trailPoints[i],trailPoints[i+1]
  local cf=CFrame.lookAt((a+b)/2,b)
  local floor=part(trail,cf,"TrilhaPedestre",V(10,0.2,(b-a).Magnitude+1),V(0,0.12,0),Color3.fromRGB(149,143,124),Enum.Material.Ground)
  floor:SetAttribute("PedestrianOnly",true)
  for _,side in ipairs({-1,1})do
   local shrub=part(trail,cf,"VegetaçãoDiscreta",V(4,2.5,5),V(side*9,1.2,0),GREEN,Enum.Material.Grass,false)
   shrub.Shape=Enum.PartType.Ball
  end
 end
 -- Conveniência afastada, acesso rodoviário próprio e garagem de veículo pessoal.
 local fuel=model(parent,Config.Fuel.Name);local fb2=Config.Fuel.CFrame
 fuel:SetAttribute("PlaceName",Config.Fuel.Name);fuel:SetAttribute("MapLabel","Posto / Conveniência");fuel:SetAttribute("Kind","Fuel");fuel:SetAttribute("MapPosition",fb2.Position)
 part(fuel,fb2,"PátioPosto",V(110,0.8,100),V(0,0.4,0),STONE,Enum.Material.Concrete)
 part(fuel,fb2,"PisoConveniência",V(46,0.3,20),V(0,0.95,22),WHITE)
 part(fuel,fb2,"FundosConveniência",V(46,12,1),V(0,6.8,32),WHITE)
 for _,x in ipairs({-23,23})do part(fuel,fb2,"LateralConveniência",V(1,12,20),V(x,6.8,22),WHITE)end
 for _,side in ipairs({-1,1})do part(fuel,fb2,"FrenteConveniência",V(18,12,1),V(side*14,6.8,12),WHITE)end
 part(fuel,fb2,"VergaConveniência",V(10,3,1),V(0,11.3,12),BLUE)
 part(fuel,fb2,"TetoConveniência",V(48,0.7,22),V(0,13.1,22),BLUE)
 sign(fuel,fb2,"PARADA DA SERRA\nCONVENIÊNCIA",V(0,10.2,11.3),V(41,3,0.3),BLUE)
 part(fuel,fb2,"BalcãoConveniência",V(24,3,3),V(0,2.5,26),WOOD)
 for _,x in ipairs({-14,14})do
  part(fuel,fb2,"BombaCenográfica",V(4,5,3),V(x,3.3,-1),BLUE)
  part(fuel,fb2,"VisorBomba",V(3,1.5,0.2),V(x,4.3,-2.6),DARK,nil,false)
 end
 part(fuel,fb2,"CoberturaPosto",V(64,0.7,26),V(0,12,-1),BLUE)
 for _,x in ipairs({-27,27})do part(fuel,fb2,"PilarPosto",V(0.6,11.2,0.6),V(x,6,-1),STONE)end
 local personal=prompt(fuel,fb2,"GaragemPessoal",V(40,4,8),"Retirar meu carro","Garagem pessoal",nil,0.5)
 personal:SetAttribute("PersonalGarage",true)
 local personalSpawns={marker(fuel,fb2,"PersonalVehicleSpawn1",V(-38,0.8,-25)),marker(fuel,fb2,"PersonalVehicleSpawn2",V(38,0.8,-25))}
 sites.personalGarage={prompt=personal,spawns=personalSpawns,clearance=V(14,7,24)}
 sites.postEscapeRoute={}
 for _,point in ipairs(trailPoints)do table.insert(sites.postEscapeRoute,point+V(0,4,0))end
 -- Uniforme e viatura permanecem vinculados ao trabalho policial, nunca ao posto.
 local prisonUniform=prompt(armory,ar,"UniformePrisão",V(26,4.5,12),"Retirar uniforme","Vestiário policial",nil,0.5)
 prisonUniform:SetAttribute("Role","Policial")
 local prisonVehicle=prompt(m,base,"ViaturaPrisão",V(65,4,-139),"Retirar viatura","Garagem policial",nil,0.5)
 prisonVehicle:SetAttribute("Role","Policial")
 part(m,base,"PátioViaturas",V(130,0.7,48),V(115,0.35,-142),STONE,Enum.Material.Concrete)
 local policeSpawns={}
 for i,x in ipairs({80,115,150})do
  policeSpawns[i]=marker(m,base,"PrisonPoliceVehicleSpawn"..i,V(x,0.8,-142))
 end
 sites.prisonWorkplace={uniformPrompts={prisonUniform},vehiclePrompts={prisonVehicle},vehicleSpawns=policeSpawns}
 -- Torres fora dos corredores, com acesso pelo pátio.
 for i,pos in ipairs({V(-130,0,-94),V(130,0,-94),V(-130,0,149),V(130,0,149)})do compoundTower(m,base,pos.X,pos.Z,i,police)end
 sites.prisonSpawn=sites.prisonCells[1].spawn
 sites.prisonRelease=marker(m,base,"PrisonRelease",V(0,4,-150))
 sites.prisonBounds={cf=base*CFrame.new(Config.Prison.BoundsCenter),half=Config.Prison.BoundsHalf}
 sites.model=m
 sites.routes={
  public={V(0,4,-150),V(0,4,-135),V(0,4,-116)},
  officer={V(0,4,-100),V(0,4,-59),V(18,4,-52),V(30,4,-10)},
  inmate={V(-105,4,-46),V(-75,4,-46),V(-75,4,-65),V(-20,4,-65),V(-20,4,120),V(115,4,120),V(153,4,120),V(182,4,120)},
 }
 local function worldPoints(points)
  local result={};for _,point in ipairs(points)do table.insert(result,base*point)end;return result
 end
 sites.validationRoutes={
  {name="recepção pública",points=worldPoints({V(0,4,-150),V(0,4,-125),V(14,4,-125),V(14,4,-108),V(0,4,-108),V(0,4,-100)}),doors=police.doors},
  {name="armaria",points=worldPoints({V(0,4,-100),V(0,4,-80),V(20,4,-80),V(20,4,-102),V(75,4,-102),V(75,4,-88),V(75,4,-71)}),doors=police.doors},
  {name="controle",points=worldPoints({V(0,4,-100),V(0,4,-52),V(38,4,-52),V(38,4,-35),V(38,4,-24)}),doors=police.doors},
  {name="rota de fuga",points=worldPoints({V(-75,4,-46),V(-75,4,-65),V(-20,4,-65),V(-20,4,120),V(115,4,120),V(153,4,120),V(182,4,120)}),doors={sites.escapeDoors[1]}},
 }
 for index,anchor in ipairs({V(-130,0,-94),V(130,0,-94),V(-130,0,149),V(130,0,149)})do
  local towerBase=base*CFrame.new(anchor)*CFrame.Angles(0,anchor.Z<0 and math.pi or 0,0)
  local points={towerBase*V(0,4,-10),towerBase*V(0,4.4,-4)}
  for i=1,48 do
   local flight=math.floor((i-1)/12);local step=(i-1)%12
   local forward=flight%2==0
   local zz=forward and (-5+step*0.9) or (4.9-step*0.9)
   local xx=forward and -3.2 or 3.2
   table.insert(points,towerBase*V(xx,4.175+(i-1)*0.62,zz))
  end
  table.insert(points,towerBase*V(-3.2,33.315,-5))
  table.insert(points,towerBase*V(-3.2,33.3,0))
  table.insert(sites.validationRoutes,{name="escadaria torre "..index,points=points,doors=police.doors,stairs=true})
 end
 m:SetAttribute("CellCount",#sites.prisonCells);m:SetAttribute("Architecture","WhiteBlueOrange")
 cached=sites;return sites
end
return PrisonBuilder
