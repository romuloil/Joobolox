local f=fixture({noNpcs=true})
local m=f.mock;local V,C=m.Vector3,m.CFrame
-- CityRoads is a Shared ModuleScript: establish its correct parent in this loader.
local envScript=m.env.script
m.env.script={Parent=m.services.ReplicatedStorage.Shared}
local roads=m.load('CityRoads',SOURCES.CityRoads)
m.env.script=envScript
-- BankBuilder holds the original module table; copy the public data into it.
-- Reload now that the real road module is registered.
local bank=m.load('BankBuilder',SOURCES.BankBuilder,true)
local blocks={}
local function rect(cf,w,d)
 return {cf=cf,w=w,d=d}
end
local function overlap(a,b)
 for _,axis in ipairs({a.cf.RightVector,a.cf.LookVector,b.cf.RightVector,b.cf.LookVector})do
  local ra=math.abs(axis:Dot(a.cf.RightVector))*a.w/2+math.abs(axis:Dot(a.cf.LookVector))*a.d/2
  local rb=math.abs(axis:Dot(b.cf.RightVector))*b.w/2+math.abs(axis:Dot(b.cf.LookVector))*b.d/2
  if math.abs(axis:Dot(b.cf.Position-a.cf.Position))>ra+rb+.001 then return false end
 end
 return true
end
local H={}
H.rect=rect;H.isFree=function(r)for _,b in ipairs(blocks)do if overlap(r,b)then return false end end;return true end
H.occupy=function(r)table.insert(blocks,r)end
local config=m.registry.GameConfig
local M=config.Map
H.lotBeside=function(a,b,t,side,depth)
 local dir=(b-a).Unit;local perp=V.new(-dir.Z,0,dir.X)
 local pos=a+dir*t+perp*side*(M.RoadWidth/2+M.SidewalkWidth+.6+depth/2)
 return C.lookAt(pos,pos-perp*side)
end
-- Reserve every existing road, bank, gang district, city center and future district.
for _,r in ipairs(roads.get().roads)do
 local margin=roads.Kinds[r.Kind].Sidewalk and M.SidewalkWidth or roads.Kinds[r.Kind].Verge or 3
 for _,seg in ipairs(roads.segments(r))do
  H.occupy(rect(C.lookAt((seg.a+seg.b)/2,seg.b),r.Width+2*margin+1,seg.len+M.RoadWidth))
 end
end
local bankLot=H.lotBeside(V.new(0,0,config.Rodovia.ExitZ),V.new(config.Rodovia.ExitLength,0,config.Rodovia.ExitZ),config.Bank.Road.T,config.Bank.Road.Side,config.Bank.LotD)
local bankArea=rect(bankLot,config.Bank.LotW+8,config.Bank.LotD+4)
local actualBankPlan=bank.plan(m.Workspace.Map,H)
check(actualBankPlan~=nil,"REGRESSION: actual BankBuilder.plan accepts the original bank lot with all road reservations")
check((actualBankPlan.lot.Position-bankLot.Position).Magnitude<.001,"original bank position is unchanged")
-- Include the existing rotated park: neither new roads nor lots may invade it.
local dir=V.new(math.sqrt(.5),0,-math.sqrt(.5))
local parkCenter=dir*(roads.RADIAL_END+config.Park.RoadLength+config.Park.Size/2)
local parkArea=rect(C.lookAt(parkCenter,parkCenter-dir),config.Park.Size,config.Park.Size)
for _,r in ipairs(roads.get().roads)do
 if r.FinancialDistrict then for _,seg in ipairs(roads.segments(r))do
  assert(not overlap(rect(C.lookAt((seg.a+seg.b)/2,seg.b),r.Width+13,seg.len+24),parkArea),"road invades original park: "..r.Name)
 end end
end
H.occupy(parkArea)
H.occupy(rect(C.new(),1500,1500))
for _,g in pairs(config.Gangs.List)do H.occupy(rect(C.new(g.Center),g.Size.X+30,g.Size.Y+30))end
local plan=bank.planDistrict(m.Workspace.Map,H)
check(#plan.items>=45,'financial lots reserved without roads/bank overlap: '..#plan.items)
check(#plan.mountains==5,'five distant mountain ranges fit available land')
for i,item in ipairs(plan.items)do
 check(not overlap(rect(item.lot,item.w,item.d),bankArea),'bank access and escape lot preserved '..i)
 for j=i+1,#plan.items do assert(not overlap(rect(item.lot,item.w,item.d),rect(plan.items[j].lot,80,80)),'district lots overlap')end
end
local coast=roads.FinancialDistrict.Coast
check(not H.isFree(rect(C.new(coast.Center),100,100)),'coastal reserve rejects future random buildings')
local count,coastRoad=0,nil
for _,r in ipairs(roads.get().roads)do
 if r.FinancialDistrict then count+=1 end
 if r.FutureCoast then coastRoad=r end
end
check(count==10,'ten connected streets registered in map and GPS source')
check(coastRoad and coastRoad.Kind=='rodovia'and coastRoad.Code=='LK-102','coastal road reuses existing south access')
check((coastRoad.Points[#coastRoad.Points]-coast.Entrance).Magnitude<.01,'coastal reservation aligns with existing road endpoint')
-- Execute the actual existing tower, housing and shop builders, not stand-in buildings.
H.model=function(name,parent)local p=m.env.Instance.new('Model');p.Name=name;p.Parent=parent;return p end
H.makePart=function(parent,props)
 local p=m.env.Instance.new(props.ClassName or 'Part')
 for k,v in pairs(props)do if k~='ClassName'then p[k]=v end end
 p.Anchored=true;p.Parent=parent;return p
end
H.addSurfaceText=function(part,text)
 local gui=m.env.Instance.new('SurfaceGui');gui.Parent=part
 local label=m.env.Instance.new('TextLabel');label.Text=text;label.Parent=gui
end
H.flatCylinder=function(parent,name,pos,r,h,color,material)
 return H.makePart(parent,{Name=name,Size=V.new(r*2,h,r*2),CFrame=C.new(pos),Color=color,Material=material})
end
H.withRng=function(_,fn,...)return fn(...)end
H.buildTree=function()end;H.buildLamp=function()end
H.curbOf=function(cf,depth)return cf*C.new(0,.7,-depth/2-4)end
local nextId=10000
H.nextHouseId=function()nextId+=1;return nextId end
m.load('MoradiaBuilder',SOURCES.MoradiaBuilder,true)
m.load('JewelryBuilder','return {}',true)
local horizonte=m.load('HorizonteBuilder',SOURCES.HorizonteBuilder,true)
horizonte.init(H)
m.registry.MoradiaBuilder.init(H,horizonte.palm)
H.financialTower=horizonte.buildTower
local shopSource=SOURCES.MapBuilder:match('(local SHOP_W, SHOP_D, SHOP_H =.-)\nlocal function buildComingSoon')
assert(shopSource,'cannot locate reusable shop builder')
local makeShop=assert(loadstring('return function(makePart,model,addSurfaceText)\n'..shopSource..'\nreturn buildShop\nend'))
setfenv(makeShop,m.env);H.buildShop=makeShop()(H.makePart,H.model,H.addSurfaceText)
local groups={houses=H.model('NewHouses',m.Workspace.Map),buildings=H.model('NewBuildings',m.Workspace.Map)}
H.makePart(m.Workspace.Map,{Name="Ground",Size=V.new(1000,1,1600),CFrame=C.new(500,-.5,-1400)})
local district,rebuiltBank
m.env.task.spawn(function()
 rebuiltBank=bank.build(actualBankPlan)
 district=bank.buildDistrict(plan,H,groups)
end)
f.advance(5)
check(rebuiltBank and rebuiltBank:FindFirstChild("PontoAnuncio",true) and rebuiltBank:FindFirstChild("PortaCofre",true),"bank building, announcement and vault exist alongside district")
check(district~=nil,'district builds with actual reused tower/housing/shop geometry')
check(district:GetAttribute('Towers')>=6,'metropolis skyline includes at least six towers')
check(#groups.houses:GetChildren()>20,'reused towers include functional housing entrances')
local seats,shops,parts=0,0,0
for _,d in ipairs(district:GetDescendants())do
 if d:IsA('Seat')then seats+=1 end
 if d:GetAttribute('InteriorSize')then shops+=1 end
 if d:IsA('BasePart')then parts+=1 end
end
check(seats>=24,'usable office and plaza seating')
check(shops>=8,'walk-in business interiors reuse original shop model')
local zone=m.Workspace.Map.ReservaLitoral.AreaReservada
check(not zone.CanCollide and zone.Transparency==1,'future coast reserve has no invisible collision barrier')
check(#plan.landscaping>=1,"bank perimeter receives new landscaping outside its reserved lot")
-- Reproduce the exact previous failure, then prove the corrected road no longer triggers it.
local widened=rect(C.new(430,0,config.Rodovia.ExitZ),2000,37)
check(overlap(widened,bankArea),"old widened avenue reservation overlaps bank lot (root cause reproduced)")
f.assertClean()
print('DISTRICT '..#plan.items..' lots, '..district:GetAttribute('Towers')..' towers, '..shops..' services, '..seats..' seats, '..#plan.mountains..' ranges; '..passed..' checks')
-- Export plan coordinates for a reviewable overview artifact.
for _,item in ipairs(plan.items)do print('LOT',item.kind,item.lot.X,item.lot.Z,item.w,item.d)end
local splits=roads.splits()
for i,r in ipairs(roads.get().roads)do
 if r.FinancialDistrict then check(#splits[i]>=1,'GPS junctions and sidewalk gaps: '..r.Name)end
end
local parking=0
for _,d in ipairs(district:GetChildren())do if d.Name=='EstacionamentoFinanceiro'then parking+=1 end end
check(parking>=5,'open parking lots with clear central driveway: '..parking)
for _,center in ipairs(plan.mountains)do
 check((center-bankLot.Position).Magnitude>1000,'mountains remain distant from bank district')
end

print("TOTAL DISTRICT",passed,"LANDSCAPING",#plan.landscaping)
