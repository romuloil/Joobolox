-- Sede LXR: fachada amarela, identificação azul e pátio de retirada aberto.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CivicConfig"))
local TaxiSiteBuilder = {}
local cached
local V = Vector3.new
local YELLOW = Color3.fromRGB(245, 190, 43)
local BLUE = Color3.fromRGB(24, 74, 135)
local WHITE = Color3.fromRGB(242, 241, 226)
local STEEL = Color3.fromRGB(65, 76, 84)
local function part(parent, base, name, size, position, color, collide)
 local p = Instance.new("Part")
 p.Name, p.Size, p.CFrame = name, size, base * CFrame.new(position)
 p.Anchored, p.CanCollide = true, collide ~= false
 p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
 p.Color, p.Material = color or WHITE, Enum.Material.SmoothPlastic
 p.Parent = parent
 return p
end
local function label(p, text, color)
 local g = Instance.new("SurfaceGui"); g.Face = Enum.NormalId.Front
 g.SizingMode, g.PixelsPerStud, g.LightInfluence = Enum.SurfaceGuiSizingMode.PixelsPerStud, 30, 0
 g.Parent = p
 local t = Instance.new("TextLabel"); t.Size = UDim2.fromScale(1, 1)
 t.BackgroundTransparency, t.TextScaled, t.TextWrapped = 1, true, true
 t.Font, t.TextColor3, t.Text, t.Parent = Enum.Font.GothamBold, color or BLUE, text, g
end
local function prompt(parent, base, name, pos, action)
 local p = part(parent, base, name, V(2.2, 2.2, 0.35), pos, BLUE, false)
 local q = Instance.new("ProximityPrompt"); q.Name = name .. "Prompt"
 q.ActionText, q.ObjectText = action, "LXR Táxis"
 q.MaxActivationDistance, q.HoldDuration = 9, 0.5
 q.KeyboardKeyCode, q.RequiresLineOfSight, q.Enabled = Enum.KeyCode.E, true, false
 q:SetAttribute("Role", "Taxista"); q.Parent = p
 return q
end
local function marker(parent, base, name, pos)
 local p = part(parent, base, name, V(1, 1, 1), pos, WHITE, false)
 p.Transparency, p.CanTouch, p.CanQuery = 1, false, false
 return p
end
function TaxiSiteBuilder.build(map)
 if cached then return cached end
 local locations = map:FindFirstChild("CivicLocations")
 assert(locations, "CivicLocations ausente")
 local old = locations:FindFirstChild(Config.Taxi.Name)
 if old then
  local function q(n) return assert(old:FindFirstChild(n)):FindFirstChildOfClass("ProximityPrompt") end
  local spawns = {}; for i=1,3 do spawns[i]=assert(old:FindFirstChild("TaxiVehicleSpawn"..i)) end
  local stops = {}
  for i,stop in ipairs(Config.TaxiStops)do
   local m = assert(old:FindFirstChild("TaxiStop"..i))
   table.insert(stops,{name=stop.name,position=stop.position,cf=CFrame.new(stop.position),marker=m})
  end
  cached={model=old,dutyPrompt=q("TaxiDuty"),dispatchPrompt=q("TaxiDispatch"),uniformPrompt=q("TaxiUniform"),vehiclePrompt=q("TaxiVehicle"),vehicleSpawns=spawns,pickupPoints=stops,destinations=stops}
  return cached
 end
 local base = Config.Taxi.CFrame
 local m = Instance.new("Model"); m.Name = Config.Taxi.Name; m.Parent = locations
 for k,v in pairs({PlaceName=Config.Taxi.Name,MapLabel="LXR Táxis",Kind="Taxi",MapPosition=base.Position,Role="Taxista"})do m:SetAttribute(k,v)end
 local p=function(n,size,pos,col,collide)return part(m,base,n,size,pos,col,collide)end
 p("Pátio LXR",V(124,0.8,148),V(0,0.4,0),Color3.fromRGB(175,180,178))
 p("Piso",V(74,0.3,48),V(0,0.95,24),WHITE)
 p("ParedeFundos",V(74,15,1),V(0,8.3,48),YELLOW)
 for _,x in ipairs({-37,37})do p("ParedeLateral",V(1,15,48),V(x,8.3,24),YELLOW)end
 for _,side in ipairs({-1,1})do
  p("MuretaFachada",V(31,2.2,1),V(side*21.5,1.9,0),YELLOW)
  local g=p("VidroRecepção",V(29,8.4,0.3),V(side*21.5,7.2,-0.15),Color3.fromRGB(145,199,226));g.Material=Enum.Material.Glass;g.Transparency=0.32
  p("FaixaFachada",V(31,3.6,1),V(side*21.5,13.2,0),YELLOW)
  p("ColunaEntrada",V(0.8,12,1.1),V(side*6.2,6.8,-0.1),BLUE)
 end
 p("VergaEntrada",V(12,4,1),V(0,13.8,0),BLUE)
 p("Cobertura",V(77,0.7,51),V(0,16.1,24),BLUE)
 p("Marquise",V(20,0.5,6),V(0,11.8,-2.5),YELLOW,false)
 local brand=p("LetreiroLXR",V(57,6,0.5),V(0,20,-0.6),YELLOW,false);label(brand,"LXR TÁXIS",BLUE)
 local sub=p("Atendimento",V(25,2.2,0.25),V(0,9.3,-0.7),BLUE,false);label(sub,"CENTRAL DE CORRIDAS",WHITE)
 p("BalcãoDespacho",V(23,3,4),V(0,2.5,16),YELLOW)
 p("TampoBalcão",V(24,0.35,4.7),V(0,4.2,16),BLUE)
 p("Computador",V(4,3,0.4),V(0,5.9,16.7),STEEL,false)
 for _,x in ipairs({-29,-20})do
  p("ArmárioUniforme",V(7,9,3),V(x,5.3,43),BLUE)
  p("AlçaArmário",V(0.2,1.2,0.2),V(x+2,5.3,41.4),WHITE,false)
 end
 local u=p("PlacaUniforme",V(20,2.2,0.2),V(-24,11.5,41.3),YELLOW,false);label(u,"UNIFORMES LXR")
 for _,x in ipairs({-13,13})do
  local s=Instance.new("Seat");s.Name="Banco";s.Anchored=true;s.CanTouch=false
  s.Size,s.CFrame=V(7,0.5,2),base*CFrame.new(x,2.4,7);s.Color,s.Parent=BLUE,m
 end
 for _,x in ipairs({-21,21})do
  local light=p("Luminária",V(7,0.2,2),V(x,15.6,22),WHITE,false);light.Material=Enum.Material.Neon
  local l=Instance.new("PointLight");l.Range,l.Brightness,l.Shadows=26,1.3,false;l.Parent=light
 end
 local spawns={}
 for i,x in ipairs({-38,0,38})do
  spawns[i]=marker(m,base,"TaxiVehicleSpawn"..i,V(x,0.8,-43))
  for _,side in ipairs({-1,1})do p("MarcaVaga",V(0.15,0.03,26),V(x+side*7,0.83,-43),WHITE,false)end
 end
 local stops={}
 for i,stop in ipairs(Config.TaxiStops)do
  local s=marker(m,CFrame.new(),"TaxiStop"..i,stop.position)
  s:SetAttribute("StopName",stop.name)
  table.insert(stops,{name=stop.name,position=stop.position,cf=CFrame.new(stop.position),marker=s})
 end
 cached={model=m,dutyPrompt=prompt(m,base,"TaxiDuty",V(24,4.5,15),"Trabalhar como taxista"),dispatchPrompt=prompt(m,base,"TaxiDispatch",V(0,5,13.3),"Central de corridas"),uniformPrompt=prompt(m,base,"TaxiUniform",V(-24,5,40.8),"Retirar uniforme"),vehiclePrompt=prompt(m,base,"TaxiVehicle",V(-53,4,-26),"Retirar táxi LXR"),vehicleSpawns=spawns,pickupPoints=stops,destinations=stops}
 local function worldPath(points)
  local result={};for _,p in ipairs(points)do table.insert(result,base*p)end;return result
 end
 cached.validationRoutes={
  {name="LXR / recepção",points=worldPath({V(0,4,-74),V(0,4,6),V(0,4,11.3)})},
  {name="LXR / vestiário",points=worldPath({V(0,4,6),V(-24,4,17),V(-24,4,38)})},
  {name="LXR / retirada de táxi",points=worldPath({V(0,4,6),V(0,4,-20),V(-53,4,-26)})},
 }
 return cached
end
return TaxiSiteBuilder
