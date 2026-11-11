local f=assert(loadstring(SOURCES.fixture))()(SOURCES.mock)
local m=f.mock;local V,C=m.Vector3,m.CFrame
local passed=0
local function check(ok,msg)assert(ok,msg);passed+=1;print('PASS',msg)end
local warnings={};m.env.warn=function(msg)table.insert(warnings,msg)end
m.services.ServerStorage=m.env.Instance.new('Folder')
m.services.CollectionService={AddTag=function()end}
local config=m.load('GameConfig',SOURCES.GameConfig)
m.load('RiverLayout',SOURCES.RiverLayout)
local save=m.env.script;m.env.script={Parent=m.services.ReplicatedStorage.Shared}
local roads=m.load('CityRoads',SOURCES.CityRoads);m.env.script=save
local blocks={}
local function rect(cf,w,d)return{cf=cf,w=w,d=d}end
local function overlap(a,b)
 for _,axis in ipairs({a.cf.RightVector,a.cf.LookVector,b.cf.RightVector,b.cf.LookVector})do
  local ra=math.abs(axis:Dot(a.cf.RightVector))*a.w/2+math.abs(axis:Dot(a.cf.LookVector))*a.d/2
  local rb=math.abs(axis:Dot(b.cf.RightVector))*b.w/2+math.abs(axis:Dot(b.cf.LookVector))*b.d/2
  if math.abs(axis:Dot(b.cf.Position-a.cf.Position))>=ra+rb-.01 then return false end
 end
 return true
end
local H={rect=rect,occupy=function(r)table.insert(blocks,r)end}
H.isFree=function(r)for _,b in ipairs(blocks)do if overlap(r,b)then return false end end;return true end
H.model=function(name,parent)local p=m.env.Instance.new('Model');p.Name=name;p.Parent=parent;return p end
H.folder=H.model
H.makePart=function(parent,props)
 local p=m.env.Instance.new(props.ClassName or 'Part');for k,v in pairs(props)do if k~='ClassName'then p[k]=v end end
 p.Anchored=true;p.CanCollide=props.CanCollide~=false;p.Parent=parent;return p
end
H.addSurfaceText=function(part,text)local p=m.env.Instance.new('TextLabel');p.Text=text;p.Parent=part end
H.flatCylinder=function(parent,name,pos,r,h,color,material)return H.makePart(parent,{Name=name,Size=V.new(r*2,h,r*2),CFrame=C.new(pos),Color=color,Material=material})end
H.withRng=function(_,fn,...)return fn(...)end
H.buildTree=function()end;H.buildLamp=function()end
H.curbOf=function(cf,depth)return (cf*C.new(0,.7,-depth/2-4)).Position end
local nextId=10000;H.nextHouseId=function()nextId+=1;return nextId end
H.lotBeside=function(a,b,t,side,depth)
 local dir=(b-a).Unit;local perp=V.new(-dir.Z,0,dir.X)
 local pos=a+dir*t+perp*side*(config.Map.RoadWidth/2+config.Map.SidewalkWidth+.6+depth/2)
 return C.lookAt(pos,pos-perp*side)
end
local map=H.model('Map',m.Workspace)
local groups={houses=H.model('Houses',map),buildings=H.model('Buildings',map)}
local favSource=SOURCES.FavelaBuilder:gsub('local made=buildHouses%(F,groups,', 'for _,s in ipairs(F.specs)do print("PARCEL",F.id,s.x,s.y,s.z,s.w,s.d,s.floors,s.nx,s.nz)end\n local made=buildHouses(F,groups,')
local fav=m.load('FavelaBuilder',favSource,true)
local plan=fav.plan(map,H);check(#plan.items==3,'three original community sites retained')
local built,paid
m.env.task.spawn(function()built=fav.build(plan,groups);paid=fav.buildPurchasable(groups)end)
f.advance(5)
for _,w in ipairs(warnings)do print('WARNING',w)end
check(#warnings==0,'community build has no swallowed errors')
check(built==90,'all 90 existing free gang homes retained: '..tostring(built))
check(paid==18,'18 optional purchasable homes built')
local doors={};local houseAreas={}
for _,house in ipairs(groups.houses:GetChildren())do
 check(house:FindFirstChild('Door')~=nil,'housing entry '..house.Name)
 local gang=house:GetAttribute('Gang');local pos=house:FindFirstChild('Door').Position;local g=config.Gangs.List[gang]
 assert(math.abs(pos.X-g.Center.X)<g.Size.X/2 and math.abs(pos.Z-g.Center.Z)<g.Size.Y/2,'home outside community')
 table.insert(doors,pos)
end
for _,root in ipairs(plan.root:GetChildren())do
 local g=config.Gangs.List[root:GetAttribute('Gang')]
 local chief,bar,ball,stairs,curves=0,0,0,0,0
 for _,p in ipairs(root:GetDescendants())do
  if p.Name=='ChefeSpot'then chief+=1 end
  if p:GetAttribute('BarBalcao')then bar+=1 end
  if p:GetAttribute('Bola')then ball+=1 end
  if p.Name=='Degrau'then stairs+=1 end
  if p.Name=='VielaCurva'then curves+=1 end
 end
 check(chief==1 and bar>=1 and ball>=1,'gang interaction markers retained '..g.Community)
 check(stairs>=300 and curves>=60,'connected stairs and curved ramps '..g.Community)
 print('COMMUNITY',root.Name,root:GetAttribute('Homes'),root:GetAttribute('DecorativeHomes'),#root:GetDescendants())
end
-- Each housing exit leaves enough free body space in front of its real door.
local candidates=plan.root:GetDescendants()
for _,part in ipairs(groups.houses:GetDescendants())do table.insert(candidates,part)end
for _,h in ipairs(groups.houses:GetChildren())do
 local door=h:FindFirstChild("Door");local probe=(door.CFrame*C.new(0,0,-4)).Position
 for _,part in ipairs(candidates)do
  if part:IsA("BasePart") and part.CanCollide and part~=door then
   local p=part.CFrame:PointToObjectSpace(probe);local size=part.Size/2
   assert(not(math.abs(p.X)<size.X+.8 and math.abs(p.Z)<size.Z+.8 and math.abs(p.Y)<size.Y+1),"blocked housing exit "..h.Name.." by "..part.Name)
  end
 end
end
check(true,"all 108 housing exits have unobstructed player body space")
-- Spatial checks of actual generated geometry (not Roblox physics).
local spatial={};local cell=16
local function key(x,z)return math.floor(x/cell)..":"..math.floor(z/cell)end
for _,p in ipairs(candidates)do
 if p:IsA("BasePart")and p.CanCollide then
  local s=p.Size/2;local c=p.CFrame
  local ex=math.abs(c.RightVector.X)*s.X+math.abs(c.UpVector.X)*s.Y+math.abs(c.LookVector.X)*s.Z+1
  local ez=math.abs(c.RightVector.Z)*s.X+math.abs(c.UpVector.Z)*s.Y+math.abs(c.LookVector.Z)*s.Z+1
  for x=math.floor((p.Position.X-ex)/cell),math.floor((p.Position.X+ex)/cell)do
   for z=math.floor((p.Position.Z-ez)/cell),math.floor((p.Position.Z+ez)/cell)do
    local k=x..":"..z;spatial[k]=spatial[k]or{};table.insert(spatial[k],p)
   end
  end
 end
end
local walkSamples=0
local function bodyFree(probe,own,margin)
 for _,p in ipairs(spatial[key(probe.X,probe.Z)]or{})do
  if p~=own then
   local v=p.CFrame:PointToObjectSpace(probe);local s=p.Size/2
   if math.abs(v.X)<s.X+margin and math.abs(v.Z)<s.Z+margin and math.abs(v.Y)<s.Y+1 then
    return false,p
   end
  end
 end
 return true
end
for _,root in ipairs(plan.root:GetChildren())do
 local ident=root:GetAttribute('Identity');local view=root:GetAttribute('MirantePosition');local target=root:GetAttribute('MiranteTarget')
 check(type(ident)=='string','community has distinct named terrain profile '..root.Name)
 check(view.Y>=145,'lookout is substantially above city ground '..root.Name)
 check(root:GetAttribute('LaneWidth')<=7.5,'narrow pedestrian lanes '..root.Name)
 local deck=root:FindFirstChild('Mirante',true)
 local direction=V.new(target.X-view.X,0,target.Z-view.Z).Unit
 check(deck.CFrame.LookVector:Dot(direction)>.999,'lookout faces marked city direction '..root.Name)
 check(root:GetAttribute('DecorativeHomes')>65,'dense infill leaves free and paid homes intact '..root.Name)
 for t=0,90,3 do
  local ok,part=bodyFree(view+V.new(0,5,0)+direction*t,deck,.05)
  assert(ok,'city view blocked '..root.Name..' by '..(part and part.Name or '?'))
 end
 check(true,'first 90 studs of city view unobstructed '..root.Name)
 for _,p in ipairs(root.Vielas:GetDescendants())do
  if p:GetAttribute('Walkable')then
   local n=(p.Name=='Degrau'or p.Name=='EscadaMirante')and 1 or math.max(1,math.ceil(p.Size.Z/4))
   if type(n)~='number'then n=1 end
   for j=0,n do
    local point=(p.CFrame*C.new(0,p.Size.Y/2+3,(j/n-.5)*math.max(0,p.Size.Z-.5))).Position
    local ok,obstacle=bodyFree(point,p,.65)
    assert(ok,'path blocked '..root.Name..' '..p.Name..' at '..tostring(point)..' by '..(obstacle and obstacle.Name or '?'))
    walkSamples+=1
   end
  end
 end
 print('LOOKOUT',root:GetAttribute('Gang'),view.X,view.Y,view.Z,target.X,target.Z)
end
check(true,'traversal body clearance for '..walkSamples..' path/stair samples')

-- The extension must meet a real highway vertex and an existing city street.
local access,joined=false,false
for _,r in ipairs(roads.get().roads)do
 if r.Name=='Acesso Financeiro ao Rodoanel'then access=r end
end
check(access~=false,'financial extension has a highway access road')
local endpoint=access.Points[#access.Points]
for _,r in ipairs(roads.get().roads)do
 if r.Code==config.Rodovia.RingCode then
  for _,p in ipairs(r.Points)do if(p-endpoint).Magnitude<.01 then joined=true end end
 end
end
check(joined,'highway access shares a real Rodoanel vertex')

-- District reservation uses every active road plus actual bank / construction site / park.
blocks={}
for _,r in ipairs(roads.get().roads)do
 local margin=roads.Kinds[r.Kind].Sidewalk and config.Map.SidewalkWidth or roads.Kinds[r.Kind].Verge or 3
 for _,seg in ipairs(roads.segments(r))do H.occupy(rect(C.lookAt((seg.a+seg.b)/2,seg.b),r.Width+2*margin+1,seg.len+config.Map.RoadWidth))end
end
for _,g in pairs(config.Gangs.List)do H.occupy(rect(C.new(g.Center),g.Size.X,g.Size.Y))end
local bank=m.load('BankBuilder',SOURCES.BankBuilder,true)
local bp=bank.plan(map,H);check(bp~=nil,'current bank still fits unchanged roads')
local obra=m.load('ObraBuilder',SOURCES.ObraBuilder,true)
local op=obra.plan(map,H,config);check(op~=nil,'friend construction site still fits')
check(math.abs(op.lot.Position.X-800)<.01,'construction site keeps original first-choice location')
local dir=V.new(math.sqrt(.5),0,-math.sqrt(.5));local center=dir*(roads.RADIAL_END+config.Park.RoadLength+config.Park.Size/2)
local dealerArea=rect(C.lookAt(center,center-dir),config.Park.Size,config.Park.Size)
H.occupy(dealerArea);H.occupy(rect(C.new(),1500,1500))
local district=m.load('FinancialDistrictBuilder',SOURCES.FinancialDistrictBuilder,true)
local originalReservations=table.clone(blocks)
local baseline=m.load('BaselineDistrict',SOURCES.BaselineDistrict,true)
local oldPlan=baseline.plan(map,H)
blocks=originalReservations
local dp=district.plan(map,H)
check(dp.previousLots==75 and #oldPlan.items==75,'75 existing district lots preserved')
for i,old in ipairs(oldPlan.items)do
 local item=dp.items[i]
 assert(old.kind==item.kind and(old.lot.Position-item.lot.Position).Magnitude<.001,'existing district lot changed at '..i)
end
check(true,'all existing district lots retain their type, position and ordering')
check(#dp.items>=125,'expanded district includes at least 125 unobstructed lots: '..#dp.items)
check(dp.dealership==nil and dp.coast==nil and #dp.mountains==0,'no old dealership/coast/terrain reinstated')
for _,item in ipairs(dp.items)do
 assert(not overlap(rect(item.lot,item.w,item.d),rect(bp.lot,config.Bank.LotW,config.Bank.LotD)),'bank overlap')
 assert(not overlap(rect(item.lot,item.w,item.d),rect(op.lot,158,144)),'construction overlap')
 assert(not overlap(rect(item.lot,item.w,item.d),dealerArea),'dealership overlap')
 print('LOT',item.kind,item.lot.Position.X,item.lot.Position.Z,item.w,item.d)
end
m.load('MoradiaBuilder',SOURCES.MoradiaBuilder,true);m.load('JewelryBuilder','return {}',true)
local horizonte=m.load('HorizonteBuilder',SOURCES.HorizonteBuilder,true)
horizonte.init(H);m.registry.MoradiaBuilder.init(H,horizonte.palm);H.financialTower=horizonte.buildTower
local shop=SOURCES.MapBuilder:match('(local SHOP_W, SHOP_D, SHOP_H =.-)\nlocal function buildComingSoon')
local make=assert(loadstring('return function(makePart,model,addSurfaceText)\n'..shop..'\nreturn buildShop\nend'));setfenv(make,m.env);H.buildShop=make()(H.makePart,H.model,H.addSurfaceText)
local districtModel
m.env.task.spawn(function()districtModel=district.build(dp,H,groups)end);f.advance(10)
check(districtModel~=nil,'restored district builds with original tower and housing builders')
check(districtModel:GetAttribute('Towers')>=25,'metropolitan skyline retained')
check(districtModel:GetAttribute('Services')>=20,'commercial interiors restored')
check(#warnings==0,'no builder warnings')
print('EXTENSION',#dp.items-dp.previousLots)
print('TOTAL',passed,'DISTRICT',#dp.items,'HOMES',built,paid)
