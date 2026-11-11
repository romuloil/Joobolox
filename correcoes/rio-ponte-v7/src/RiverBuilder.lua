-- Coastal river and driveable bridge, isolated from housing/economy systems.
local Workspace=game:GetService("Workspace")
local Shared=game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local R=require(Shared:WaitForChild("RiverLayout"))
local B={};local K
local RED=Color3.fromRGB(185,49,38)
local CONCRETE=Color3.fromRGB(181,178,166)
local STONE=Color3.fromRGB(113,119,104)
local WHITE=Color3.fromRGB(237,232,215)
local function part(parent,name,size,cf,color,material,collide)
 return K.makePart(parent,{Name=name,Size=size,CFrame=cf,Color=color,Material=material or Enum.Material.Concrete,CanCollide=collide~=false})
end
local function beam(parent,name,a,b,width,height,color,material,collide)
 return part(parent,name,Vector3.new(width,height,(b-a).Magnitude+.06),CFrame.lookAt((a+b)/2,b),color,material,collide)
end
local function marker(root,name,icon,pos)
 local m=K.model(name,root)
 local p=part(m,"Ponto",Vector3.new(1,1,1),CFrame.new(pos),WHITE,nil,false);p.Transparency=1;p.CanQuery=false;p.CanTouch=false;m.PrimaryPart=p
 m:SetAttribute("PlaceName",name);m:SetAttribute("Icon",icon);m:SetAttribute("IconColor",Color3.fromRGB(55,153,170))
 return m
end
function B.plan(map,helpers)
 K=helpers
 local root=K.folder("RioDaEnseada",map)
 root:SetAttribute("WaterWidth",36);root:SetAttribute("MetersPerStud",.28)
 root:SetAttribute("BridgePosition",Vector3.new(R.BridgeX,R.DeckY,R.BridgeZ))
 local samples=R.samples(16);local length=0
 for i=1,#samples-1 do
  local a,b=samples[i],samples[i+1];length+=(b.pos-a.pos).Magnitude
  K.occupy(K.rect(CFrame.lookAt((a.pos+b.pos)/2,b.pos),math.max(a.width,b.width)+2*(R.Bank+14),(b.pos-a.pos).Magnitude+16))
 end
 -- Keep the spring and public river overlooks clear of randomly placed farms.
 K.occupy(K.rect(CFrame.new(2400,0,1340),160,120))
 root:SetAttribute("LengthStuds",length)
 return {root=root,samples=samples}
end
local function terrainRiver()
 local terrain=Workspace.Terrain
 local z0,z1=R.Points[1][2],R.Points[#R.Points][2]
 for z=z0,z1-1,32 do
  local endZ=math.min(z+32,z1);local minX,maxX=math.huge,-math.huge
  for zz=z,endZ,2 do
   local x,w=R.at(zz);minX=math.min(minX,x-w/2-R.Bank-12);maxX=math.max(maxX,x+w/2+R.Bank+12)
  end
  minX=math.floor(minX/4)*4;maxX=math.ceil(maxX/4)*4;endZ=math.ceil(endZ/4)*4
  local region=Region3.new(Vector3.new(minX,-24,z),Vector3.new(maxX,40,endZ))
  local mat,occ=terrain:ReadVoxels(region,4)
  for ix=1,#mat do
   local x=minX+(ix-.5)*4
   for iz=1,#mat[ix][1] do
    local zz=z+(iz-.5)*4;local cx,w=R.at(zz)
    if cx and math.abs(x-cx)<=w/2+R.Bank+8 then
     local top=R.surface(x,zz)
     for iy=1,#mat[ix] do
      local bottom=-24+(iy-1)*4
      local material,fill=Enum.Material.Air,0
      if top>bottom then
       fill=math.clamp((top-bottom)/4,0,1)
       material=zz>3440 and Enum.Material.Sand or (top>-2 and Enum.Material.Grass or Enum.Material.Ground)
       if bottom<-16 then material=Enum.Material.Rock end
      elseif bottom<R.WaterY then
       material=Enum.Material.Water;fill=math.clamp((R.WaterY-bottom)/4,0,1)
      end
      mat[ix][iy][iz]=material;occ[ix][iy][iz]=fill
     end
    end
   end
  end
  terrain:WriteVoxels(region,4,mat,occ);task.wait()
 end
 -- Close the upstream cut with a natural bowl and spring, not a square water end.
 terrain:FillBall(Vector3.new(2400,-14,1338),23,Enum.Material.Rock)
end
local function trimBeachDecor(map)
 local litoral=map:FindFirstChild("Litoral");local restinga=litoral and litoral:FindFirstChild("Restinga",true)
 if not restinga then return end
 for _,child in ipairs(restinga:GetChildren())do
  local hit=false;local pieces=child:IsA("BasePart")and{child}or child:GetDescendants()
  for _,p in ipairs(pieces)do
   if p:IsA("BasePart")and(R.contains(p.Position.X,p.Position.Z,R.Bank+6)or R.onRoad(p.Position.X,p.Position.Z,4))then hit=true;break end
  end
  if hit then child:Destroy()end
 end
end
local function bridge(root)
 local model=K.model(R.BridgeName,root)
 model:SetAttribute("DesignReference","Bridge Road Lowpoly — 00amza")
 model:SetAttribute("SourceURL","https://sketchfab.com/3d-models/bridge-road-lowpoly-a91e8f0d30f140e6b7ccbdf3044cd7c5")
 model:SetAttribute("License","CC BY 4.0; adaptation in native Roblox parts")
 local road=K.model("PistaEPasseios",model)
 -- Piecewise planar slopes: surface height is shared with CityRoads and tests.
 for x=R.RoadX0,R.RoadX1-1,10 do
  local x1=math.min(x+10,R.RoadX1);local mid=(x+x1)/2
  local a,b=Vector3.new(x,R.roadHeight(x),R.BridgeZ),Vector3.new(x1,R.roadHeight(x1),R.BridgeZ)
  local width=R.roadWidth(mid);local depth=.7
  local deck=beam(road,"Pista",a-Vector3.new(0,depth/2,0),b-Vector3.new(0,depth/2,0),width+.12,depth,Color3.fromRGB(48,51,56),Enum.Material.Asphalt)
  deck:SetAttribute("Driveable",true)
  for _,side in ipairs({-1,1})do
   local offset=Vector3.new(0,.07,side*(width/2-1))
   beam(road,"FaixaLateral",a+offset,b+offset,.22,.035,WHITE,Enum.Material.SmoothPlastic,false)
   local walkOffset=Vector3.new(0,-.1,side*(width/2+2.2))
   local walk=beam(road,"Passeio",a+walkOffset,b+walkOffset,4.4,.5,CONCRETE)
   walk:SetAttribute("Walkable",true)
   if mid>R.DeckX0-25 and mid<R.DeckX1+25 and not(side==1 and mid>=2290 and mid<=2310)then
    local rail=Vector3.new(0,2.3,side*(width/2+4.15))
    beam(road,"Protecao",a+rail,b+rail,.28,2.8,RED,Enum.Material.Metal)
    part(road,"Refletor",Vector3.new(.2,.24,.5),CFrame.new(mid,R.roadHeight(mid)+2.3,R.BridgeZ+side*(width/2+3.96)),WHITE,Enum.Material.Neon,false)
   end
  end
  if mid>=2020 then
   for _,side in ipairs({-1,1})do
    local offset=Vector3.new(0,.045,side*.35)
    beam(road,"DuplaAmarela",a+offset,b+offset,.2,.035,Color3.fromRGB(241,195,60),Enum.Material.SmoothPlastic,false)
   end
  else
   -- Taper the boulevard's central island into the two-lane bridge access.
   local median=10*(1-math.clamp((mid-1840)/180,0,1))
   if median>.2 and mid>1840 then beam(road,"CanteiroTransicao",a,b,median,.25,Color3.fromRGB(112,139,83),Enum.Material.Grass)end
  end
  -- Solid embankments underneath the approach ramps, outside the water channel.
  if mid<R.DeckX0 or mid>R.DeckX1 then
   local h=math.max(.6,R.roadHeight(mid)-.6)
   part(road,"AterroAcesso",Vector3.new(10.05,h,width+9),CFrame.new(mid,h/2-.6,R.BridgeZ),CONCRETE,Enum.Material.Rock)
  end
 end
 -- Reinforced abutments on land leave the waterway open underneath.
 for _,x in ipairs({R.DeckX0+2,R.DeckX1-2})do
  part(model,"Encontro",Vector3.new(6,20,34),CFrame.new(x,-4,R.BridgeZ),CONCRETE)
 end
 beam(model,"Longarina",Vector3.new(R.DeckX0,R.DeckY-1.1,R.BridgeZ),Vector3.new(R.DeckX1,R.DeckY-1.1,R.BridgeZ),30,1.3,RED,Enum.Material.Metal)
 -- Red portal and fan stays follow the supplied GLB's cable-stayed silhouette.
 local towerX=2182;local topY=R.DeckY+49
 for _,side in ipairs({-1,1})do
  local z=R.BridgeZ+side*19.5
  part(model,"FundacaoTorre",Vector3.new(10,20,9),CFrame.new(towerX,-6,z),CONCRETE)
  local leg=beam(model,"MastroVermelho",Vector3.new(towerX,2,z),Vector3.new(towerX,topY,z),3.6,3.6,RED,Enum.Material.Metal)
  leg:SetAttribute("Structural",true)
  for x=R.DeckX0+4,R.DeckX1-4,12 do
   if math.abs(x-towerX)>8 then
    local cable=beam(model,"Estai",Vector3.new(towerX,topY-2,z),Vector3.new(x,R.DeckY+.2,R.BridgeZ+side*16.7),.16,.16,RED,Enum.Material.Metal,false)
    cable.CanQuery=false;cable.CanTouch=false
   end
  end
  part(model,"SinalAereo",Vector3.new(.7,.7,.7),CFrame.new(towerX,topY+.5,z),Color3.fromRGB(255,65,45),Enum.Material.Neon,false)
 end
 beam(model,"TravessaAlta",Vector3.new(towerX,topY,R.BridgeZ-19.5),Vector3.new(towerX,topY,R.BridgeZ+19.5),3.4,3.4,RED,Enum.Material.Metal)
 for _,x in ipairs({2050,2145,2295,2390,2510,2630})do
  for _,side in ipairs({-1,1})do
   local px=(x==2295 and side==1)and 2277 or x
   local y=R.roadHeight(px);local z=R.BridgeZ+side*18
   part(model,"Poste",Vector3.new(.35,10,.35),CFrame.new(px,y+5,z),Color3.fromRGB(67,72,76),Enum.Material.Metal)
   local lamp=part(model,"Luminaria",Vector3.new(2.2,.3,1),CFrame.new(px,y+10,z-side),WHITE,Enum.Material.Neon,false)
   local light=Instance.new("PointLight");light.Range=22;light.Brightness=.7;light.Color=Color3.fromRGB(255,229,187);light.Parent=lamp
  end
 end
 for _,item in ipairs({{2050,-1},{2390,1}})do
  local x,side=item[1],item[2];local z=R.BridgeZ+side*23
  part(model,"PostePlaca",Vector3.new(.3,8,.3),CFrame.new(x,4,z),CONCRETE,Enum.Material.Metal)
  local cf=CFrame.lookAt(Vector3.new(x,7,z),Vector3.new(x-side,7,z))
  local p=part(model,"PlacaPonte",Vector3.new(10,4,.2),cf,Color3.fromRGB(28,105,71),nil,false)
  K.addSurfaceText(p,"PONTE DA FOZ\nRIO DA ENSEADA • 40",WHITE,Color3.fromRGB(28,105,71))
 end
 return model
end
local function banks(root,samples)
 local f=K.model("MargensNaturais",root);local rng=Random.new(R.Seed)
 for i=3,#samples-3,4 do
  local p=samples[i];local z=p.pos.Z
  for _,side in ipairs({-1,1})do
   local x=p.pos.X+side*(p.width/2+16+rng:NextNumber(0,5))
   if not R.onRoad(x,z,18)and z<3830 then
    local y=R.surface(x,z)or 0
    local s=rng:NextNumber(2,4)
    local rock=part(f,"RochaMargem",Vector3.new(s*1.5,s,s),CFrame.new(x,y+s*.25,z)*CFrame.Angles(.13,rng:NextNumber(0,6),.18),STONE,Enum.Material.Rock)
    if i%3==0 and z<3300 then
     K.withRng(rng,K.buildTree,f,Vector3.new(x+side*10,0,z),rng:NextNumber(.8,1.2))
    elseif z>3450 and K.palm then K.palm(f,Vector3.new(x+side*10,math.max(y,0),z),rng:NextNumber(.7,1.1))end
    for j=1,3 do
     local xx=x+side*(2+j);local h=rng:NextNumber(1.3,3)
     part(f,"Junco",Vector3.new(.18,h,.2),CFrame.new(xx,y+h/2,z+j),Color3.fromRGB(105,137,66),Enum.Material.Grass,false)
    end
   end
  end
 end
 -- Compact riverside place to stop, connected to the bridge's southern sidewalk.
 local foz=K.model("RecantoDaFoz",root)
 local x=R.DeckX1+18
 part(foz,"Deck",Vector3.new(22,.6,27),CFrame.new(x,5.7,R.BridgeZ+33),Color3.fromRGB(145,116,83),Enum.Material.WoodPlanks)
 local y=R.roadHeight(x)
 beam(foz,"Acesso",Vector3.new(x,y,R.BridgeZ+15),Vector3.new(x,6,R.BridgeZ+25),6,.5,CONCRETE)
 for _,z in ipairs({R.BridgeZ+26,R.BridgeZ+40})do
  for _,dx in ipairs({-9,9})do part(foz,"Pilar",Vector3.new(1,14,1),CFrame.new(x+dx,-1,z),CONCRETE)end
 end
 for _,z in ipairs({R.BridgeZ+46})do beam(foz,"Corrimao",Vector3.new(x-11,7.8,z),Vector3.new(x+11,7.8,z),.3,2.6,RED,Enum.Material.Metal)end
 for _,dx in ipairs({-10.8,10.8})do beam(foz,"Corrimao",Vector3.new(x+dx,7.8,R.BridgeZ+20),Vector3.new(x+dx,7.8,R.BridgeZ+46),.3,2.6,RED,Enum.Material.Metal)end
 local seat=K.makePart(foz,{ClassName="Seat",Name="Banco",Size=Vector3.new(6,.5,2),CFrame=CFrame.new(x+6,7.5,R.BridgeZ+40)*CFrame.Angles(0,math.pi/2,0),Color=CONCRETE,Material=Enum.Material.WoodPlanks})
 seat:SetAttribute("SeatText","Ver a foz")
 local places=K.folder("Lugares",root)
 marker(places,R.BridgeName,"🌉",Vector3.new(R.BridgeX,R.DeckY,R.BridgeZ))
 marker(places,"Recanto da Foz","🌊",Vector3.new(x,6,R.BridgeZ+33))
end
function B.build(plan,map)
 if plan.root:GetAttribute("Built")then return plan.root end
 terrainRiver();trimBeachDecor(map);bridge(plan.root);banks(plan.root,plan.samples)
 plan.root:SetAttribute("Built",true)
 return plan.root
end
B.layout=R
return B
