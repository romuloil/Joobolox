local f=assert(loadstring(SOURCES.fixture))()(SOURCES.mock)
local m=f.mock;local V,C=m.Vector3,m.CFrame
local passed=0
local function check(ok,msg)assert(ok,msg);passed+=1;print('PASS',msg)end
local warnings={};m.env.warn=function(msg)table.insert(warnings,msg)end
m.services.ServerStorage=m.env.Instance.new('Folder')
m.services.CollectionService={AddTag=function()end}
local config=m.load('GameConfig',SOURCES.GameConfig)
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
local fav=m.load('FavelaBuilder',SOURCES.FavelaBuilder,true)
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
  if p.Name=='LadeiraCurva'then curves+=1 end
 end
 check(chief==1 and bar>=1 and ball>=1,'gang interaction markers retained '..g.Community)
 check(stairs>=100 and curves==12,'connected stairs and curved ramps '..g.Community)
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
local dp=district.plan(map,H)
check(#dp.items>=60,'restored district contains at least 60 unobstructed lots: '..#dp.items)
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
print('TOTAL',passed,'DISTRICT',#dp.items,'HOMES',built,paid)
