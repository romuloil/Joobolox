-- Costa do Sol: coastal road data is shared by the road builder, map and GPS.
local Workspace=game:GetService("Workspace")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Roads=require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CityRoads"))
local Builder={}

-- Carve only the ocean rectangle out of the tiled Ground, preserving the rest.
function Builder.cutGround(map,o)
 for _,p in ipairs(map:GetChildren()) do
  if p.Name=="Ground" and p:IsA("BasePart") then
   local x0,x1=p.Position.X-p.Size.X/2,p.Position.X+p.Size.X/2
   local z0,z1=p.Position.Z-p.Size.Z/2,p.Position.Z+p.Size.Z/2
   local a,b=math.max(x0,o.MinX),math.min(x1,o.MaxX)
   local c,d=math.max(z0,o.MinZ),math.min(z1,o.MaxZ)
   if b>a and d>c then
    for _,r in ipairs({{x0,a,z0,z1},{b,x1,z0,z1},{a,b,z0,c},{a,b,d,z1}}) do
     if r[2]-r[1]>.001 and r[4]-r[3]>.001 then
      local copy=p:Clone();copy.Size=Vector3.new(r[2]-r[1],p.Size.Y,r[4]-r[3])
      copy.CFrame=CFrame.new((r[1]+r[2])/2,p.Position.Y,(r[3]+r[4])/2);copy.Parent=map
     end
    end
    p:Destroy()
   end
  end
 end
end

function Builder.build(map,H)
 if map:FindFirstChild("Litoral") then return map.Litoral end
 local C=Roads.Coast
 local root=H.model("Litoral",map);root:SetAttribute("PlaceName",C.Name)
 root:SetAttribute("BridgeBuilt",false)
 local beaches=H.model("Praias",root)
 local sand=Color3.fromRGB(226,207,157)
 local colors={Color3.fromRGB(243,92,98),Color3.fromRGB(255,199,69),Color3.fromRGB(65,176,199),Color3.fromRGB(132,103,205),Color3.fromRGB(88,184,126),Color3.fromRGB(244,143,63)}
 local function part(parent,name,size,cf,color,material,class,collide)
  return H.makePart(parent,{ClassName=class,Name=name,Size=size,CFrame=cf,Color=color,Material=material or Enum.Material.SmoothPlastic,CanCollide=collide})
 end
 local function sign(parent,cf,text,width)
  local p=part(parent,"Placa",Vector3.new(width or 20,4,.3),cf,Color3.fromRGB(28,106,132),Enum.Material.Wood)
  H.addSurfaceText(p,text,Color3.new(1,1,1),Color3.fromRGB(28,106,132))
 end
 local o=C.Ocean
 Builder.cutGround(map,o)
 local terrain=Workspace.Terrain
 assert(terrain,"Terrain necessário para o mar")
 terrain.WaterColor=Color3.fromRGB(38,135,158);terrain.WaterTransparency=.3
 terrain.WaterReflectance=.2;terrain.WaterWaveSize=.15;terrain.WaterWaveSpeed=8
 for x=o.MinX,o.MaxX-1,400 do for z=o.MinZ,o.MaxZ-1,400 do
  local w,d=math.min(400,o.MaxX-x),math.min(400,o.MaxZ-z)
  terrain:FillBlock(CFrame.new(x+w/2,o.Bottom-2,z+d/2),Vector3.new(w,4,d),Enum.Material.Sand)
  terrain:FillBlock(CFrame.new(x+w/2,(o.Bottom+o.Surface)/2,z+d/2),Vector3.new(w,o.Surface-o.Bottom,d),Enum.Material.Water)
  task.wait()
 end end
 -- Wide sand coves alternate with shorter rocky banks. Wedge high edge is landward.
 for z=o.MinZ,o.MaxZ-1,40 do
  local d=math.min(40,o.MaxZ-z);local mid=z+d/2;local nearest=math.huge
  for _,b in ipairs(C.Beaches) do nearest=math.min(nearest,math.abs(mid-b.Z)) end
  local blend=nearest<=150 and 1 or (nearest>=270 and 0 or .5+.5*math.cos((nearest-150)/120*math.pi))
  local beach=blend>.1
  local w=90+130*blend
  part(root,beach and "AreiaDaEnseada" or "Costao",Vector3.new(d,10,w),CFrame.new(220+w/2,-4.5,mid)*CFrame.Angles(0,-math.pi/2,0),beach and sand or Color3.fromRGB(119,126,118),beach and Enum.Material.Sand or Enum.Material.Rock,"WedgePart")
  if not beach then
   local rock=part(root,"RochaCosteira",Vector3.new(18,9,22),CFrame.new(270,-2,mid)*CFrame.Angles(0,mid*.1,.12),Color3.fromRGB(111,119,111),Enum.Material.Rock,"WedgePart")
  end
 end
 for i,z in ipairs({3000,3500,4000,4500,5000,5450}) do
  terrain:FillBall(Vector3.new(-380,-22,z),90+(i%3)*12,Enum.Material.Grass)
  part(root,"Afloramento",Vector3.new(50,45,65),CFrame.new(-330,12,z+30)*CFrame.Angles(0,i,0),Color3.fromRGB(114,119,107),Enum.Material.Rock,"WedgePart")
 end
 local function beachY(x) return .5-(x-220)/22 end
 local function umbrella(parent,x,z,color)
  local cf=CFrame.new(x,beachY(x),z)
  part(parent,"Haste",Vector3.new(.22,7,.22),cf*CFrame.new(0,3.5,0),Color3.fromRGB(220,218,200),Enum.Material.Metal,nil,false)
  for i=1,8 do
   part(parent,"Lona",Vector3.new(2.5,1.7,3.2),cf*CFrame.Angles(0,i*math.pi/4,0)*CFrame.new(0,6.5,1.6)*CFrame.Angles(0,math.pi,0),i%2==0 and color or Color3.fromRGB(248,243,224),Enum.Material.Fabric,"WedgePart",false)
  end
  for _,side in ipairs({-1,1}) do
   local seat=part(parent,"CadeiraPraia",Vector3.new(2.4,.4,3),cf*CFrame.new(side*3,1,-1),color,Enum.Material.Fabric,"Seat")
   seat.CanTouch=false;seat:SetAttribute("SeatText","Descansar na praia")
   part(parent,"Encosto",Vector3.new(2.4,2.4,.35),seat.CFrame*CFrame.new(0,1.1,1.2)*CFrame.Angles(-.25,0,0),color,Enum.Material.Fabric)
  end
  part(parent,"Canga",Vector3.new(3,.05,5),cf*CFrame.new(0,.12,5),color,Enum.Material.Fabric,nil,false)
 end
 for i,b in ipairs(C.Beaches) do
  local beach=H.model("Praia"..i,beaches);beach:SetAttribute("PlaceName",b.Name)
  beach:SetAttribute("MapPosition",Vector3.new(180,.7,b.Z));beach:SetAttribute("Curb",CFrame.new(180,.7,b.Z))
  part(beach,"PasseioMadeira",Vector3.new(24,.35,330),CFrame.new(208,.6,b.Z),Color3.fromRGB(161,132,92),Enum.Material.WoodPlanks)
  sign(beach,CFrame.new(208,5,b.Z-145),b.Name:upper(),30)
  for j=1,6 do
   local x=j%2==0 and 330 or 275;local z=b.Z-120+math.floor((j-1)/2)*90
   umbrella(beach,x,z,colors[(j+i-2)%#colors+1])
  end
  for _,dz in ipairs({-155,-55,55,155}) do
   if H.beachPalm then H.beachPalm(beach,Vector3.new(190,.7,b.Z+dz),.9) else H.buildTree(beach,Vector3.new(190,.7,b.Z+dz),.9) end
   H.buildLamp(beach,CFrame.new(194,0,b.Z+dz))
  end
  -- Six parking spaces accessed from the local spur, clear of the highway.
  local parking=H.model("EstacionamentoPraia",beach)
  part(parking,"Piso",Vector3.new(64,.2,90),CFrame.new(174,.2,b.Z-70),Color3.fromRGB(83,87,85),Enum.Material.Asphalt)
  for n=1,7 do part(parking,"Faixa",Vector3.new(17,.05,.25),CFrame.new(190,.33,b.Z-105+(n-1)*11),Color3.fromRGB(238,228,194),nil,nil,false) end
  part(parking,"Entrada",Vector3.new(20,.2,26),CFrame.new(158,.2,b.Z-18),Color3.fromRGB(83,87,85),Enum.Material.Asphalt)
  sign(parking,CFrame.new(181,4,b.Z-30),"P • PRAIA",15)
  -- Wooden food kiosk and mobile ice-pop cart, both connected to CoastService.
  local kiosk=H.model("Quiosque",beach)
  local kcf=CFrame.new(204,.8,b.Z+100)
  part(kiosk,"Base",Vector3.new(16,.3,12),kcf,Color3.fromRGB(159,117,70),Enum.Material.WoodPlanks)
  for _,x in ipairs({-7,7}) do for _,z in ipairs({-5,5}) do part(kiosk,"Pilar",Vector3.new(.5,8,.5),kcf*CFrame.new(x,4,z),Color3.fromRGB(119,85,50),Enum.Material.Wood) end end
  part(kiosk,"Cobertura",Vector3.new(19,.5,15),kcf*CFrame.new(0,8.2,0),colors[i],Enum.Material.Fabric)
  local counter=part(kiosk,"Balcao",Vector3.new(13,3,2),kcf*CFrame.new(0,1.5,-4),Color3.fromRGB(188,143,82),Enum.Material.Wood)
  counter:SetAttribute("FoodId","agua");counter:SetAttribute("Price",15)
  sign(kiosk,kcf*CFrame.new(0,6.4,-5.1),"ÁGUA GELADA • $15",18)
  local cart=H.model("CarrinhoPicole",beach);local ccf=CFrame.new(202,.8,b.Z+35)
  local box=part(cart,"CaixaTermica",Vector3.new(6,3.5,4),ccf*CFrame.new(0,2,0),colors[i+2],Enum.Material.SmoothPlastic)
  box:SetAttribute("FoodId","picole");box:SetAttribute("Price",25)
  part(cart,"Tampa",Vector3.new(6.3,.25,4.3),ccf*CFrame.new(0,3.9,0),Color3.fromRGB(243,241,231))
  for _,x in ipairs({-3,3}) do
   local wheel=part(cart,"Roda",Vector3.new(.5,1.6,1.6),ccf*CFrame.new(x,.7,0),Color3.fromRGB(40,43,46),Enum.Material.SmoothPlastic)
   wheel.Shape=Enum.PartType.Cylinder
  end
  sign(cart,ccf*CFrame.new(0,5.5,-2.2),"PICOLÉ • $25",10)
  for j=1,4 do
   local x=j%2==0 and 305 or 250;local z=b.Z-105+(j-1)*65
   local marker=part(beach,"Turista"..j,Vector3.new(.2,.2,.2),CFrame.new(x,beachY(x)+.1,z),colors[j],nil,nil,false)
   marker.Transparency=1;marker.CanQuery=false;marker:SetAttribute("Tourist",true);marker:SetAttribute("Style",j)
  end
  local vendor=part(beach,"Vendedor",Vector3.new(.2,.2,.2),kcf*CFrame.new(0,0,0),colors[i],nil,nil,false)
  vendor.Transparency=1;vendor.CanQuery=false;vendor:SetAttribute("Tourist",true);vendor:SetAttribute("Vendor",true)
 end
 local lighthouse=H.model("FarolDaCosta",root)
 part(lighthouse,"Base",Vector3.new(18,1,18),CFrame.new(204,.5,4780),Color3.fromRGB(184,177,156),Enum.Material.Concrete)
 part(lighthouse,"Torre",Vector3.new(10,21,10),CFrame.new(204,11.5,4780),Color3.fromRGB(237,234,218),Enum.Material.Concrete)
 part(lighthouse,"FaixaAzul",Vector3.new(10.1,3,10.1),CFrame.new(204,15,4780),Color3.fromRGB(38,124,159))
 local lamp=part(lighthouse,"Lanterna",Vector3.new(7,4,7),CFrame.new(204,24,4780),Color3.fromRGB(255,228,159),Enum.Material.Neon,nil,false)
 local light=Instance.new("PointLight");light.Range=45;light.Brightness=1.4;light.Color=lamp.Color;light.Parent=lamp
 part(lighthouse,"Chapeu",Vector3.new(12,1,12),CFrame.new(204,27,4780),Color3.fromRGB(35,95,125),Enum.Material.Metal)
 -- A scenic overlook and a turnaround, not a bridge or a drivable deck over water.
 local lookout=H.model("MiranteDaPonte",root)
 part(lookout,"Deck",Vector3.new(24,.5,50),CFrame.new(192,1,5220),Color3.fromRGB(149,118,80),Enum.Material.WoodPlanks)
 for _,z in ipairs({5196,5244}) do part(lookout,"GuardaCorpo",Vector3.new(24,3,.3),CFrame.new(192,2.7,z),Color3.fromRGB(220,214,195),Enum.Material.Wood) end
 part(lookout,"GuardaCorpoMar",Vector3.new(.3,3,50),CFrame.new(204,2.7,5220),Color3.fromRGB(220,214,195),Enum.Material.Wood)
 sign(lookout,CFrame.new(188,5,5210),"MIRANTE DA COSTA",25)
 root:SetAttribute("BeachCount",#C.Beaches);root:SetAttribute("WaterSurface",o.Surface)
 return root
end
return Builder
