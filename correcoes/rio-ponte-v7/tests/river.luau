local f=assert(loadstring(SOURCES.fixture))()(SOURCES.mock)
local m=f.mock;local V,C,E=m.Vector3,m.CFrame,m.Enum
local passed=0
local function check(ok,msg)assert(ok,msg);passed+=1;print('PASS',msg)end
local warnings={};m.env.warn=function(msg)table.insert(warnings,msg)end
local config=m.load('GameConfig',SOURCES.GameConfig)
local R=m.load('RiverLayout',SOURCES.RiverLayout)
local saved=m.env.script;m.env.script={Parent=m.services.ReplicatedStorage.Shared}
local roads=m.load('CityRoads',SOURCES.CityRoads);m.env.script=saved
local river=m.load('RiverBuilder',SOURCES.RiverBuilder,true)
local calls,voxels={},{}
local function key(x,y,z)return math.floor(x/4)..':'..math.floor(y/4)..':'..math.floor(z/4)end
m.env.Region3={new=function(a,b)return{a=a,b=b}end}
local terrain={}
function terrain:ReadVoxels(region,res)
 check(res==4 and region.a.X%4==0 and region.a.Z%4==0 and region.b.X%4==0 and region.b.Z%4==0,'aligned terrain chunk '..region.a.Z)
 local mat,occ={},{}
 for i=1,(region.b.X-region.a.X)/4 do
  mat[i]={};occ[i]={}
  for j=1,(region.b.Y-region.a.Y)/4 do
   mat[i][j]={};occ[i][j]={}
   for k=1,(region.b.Z-region.a.Z)/4 do
    mat[i][j][k]=E.Material.Air;occ[i][j][k]=0
   end
  end
 end
 return mat,occ
end
function terrain:WriteVoxels(region,res,mat,occ)
 table.insert(calls,region)
 for i=1,#mat do for j=1,#mat[i]do for k=1,#mat[i][j]do
  local fill=occ[i][j][k];assert(fill>=0 and fill<=1,'occupancy outside range')
  local x,y,z=region.a.X+(i-.5)*4,region.a.Y+(j-.5)*4,region.a.Z+(k-.5)*4
  voxels[key(x,y,z)]={mat=mat[i][j][k],fill=fill}
 end end end
end
function terrain:FillBall(pos,r,mat)
 for x=math.floor((pos.X-r)/4)*4,math.ceil((pos.X+r)/4)*4,4 do
 for y=math.floor((pos.Y-r)/4)*4,math.ceil((pos.Y+r)/4)*4,4 do
 for z=math.floor((pos.Z-r)/4)*4,math.ceil((pos.Z+r)/4)*4,4 do
  if(V.new(x+2,y+2,z+2)-pos).Magnitude<r then voxels[key(x,y,z)]={mat=mat,fill=mat==E.Material.Air and 0 or 1}end
 end end end
end
function terrain:FillBlock(cf,size,mat)
 for x=math.floor((cf.Position.X-size.X/2)/4)*4,math.ceil((cf.Position.X+size.X/2)/4)*4-4,4 do
 for y=math.floor((cf.Position.Y-size.Y/2)/4)*4,math.ceil((cf.Position.Y+size.Y/2)/4)*4-4,4 do
 for z=math.floor((cf.Position.Z-size.Z/2)/4)*4,math.ceil((cf.Position.Z+size.Z/2)/4)*4-4,4 do voxels[key(x,y,z)]={mat=mat,fill=1}end end end
end
m.Workspace.Terrain=terrain
local H={}
H.model=function(name,parent)local x=m.env.Instance.new('Model');x.Name=name;x.Parent=parent;return x end
H.folder=H.model
H.makePart=function(parent,props)
 local p=m.env.Instance.new(props.ClassName or 'Part')
 for k,v in pairs(props)do if k~='ClassName'then p[k]=v end end
 p.CanCollide=props.CanCollide~=false;p.Anchored=true;p.Parent=parent;return p
end
H.addSurfaceText=function(p,t)p:SetAttribute('Label',t)end
H.rect=function(cf,w,d)return{cf=cf,w=w,d=d}end
local areas={};H.occupy=function(r)table.insert(areas,r)end
H.withRng=function(_,fn,...)return fn(...)end
local start=SOURCES.MapBuilder:find('local function buildTree(',1,true)
local stop=SOURCES.MapBuilder:find('\nlocal function ',start+10,true)
local treeCode=SOURCES.MapBuilder:sub(start,stop-1)
local fn=assert(loadstring('return function(model,makePart,C,rng) '..treeCode..'\nreturn buildTree end'));setfenv(fn,m.env)
H.buildTree=fn()(H.model,H.makePart,config.Colors,m.env.Random.new(72))
H.palm=function(parent,pos,scale)return H.buildTree(parent,pos,scale)end
local map=H.folder('Map',m.Workspace)
local litoral=H.folder('Litoral',map);local restinga=H.folder('Restinga',litoral)
local obstruction=H.makePart(restinga,{Name='Estaca',CFrame=C.new(2220,2,3502),Size=V.new(1,3,1)})
local kept=H.makePart(restinga,{Name='Estaca',CFrame=C.new(1900,2,3502),Size=V.new(1,3,1)})
local plan=river.plan(map,H)
check(plan.root:GetAttribute('LengthStuds')>2700 and plan.root:GetAttribute('LengthStuds')<3100,'river length proportional to the world')
check(#areas>150,'river corridor reserved before farms and random lots')
local done=false
m.env.task.spawn(function()river.build(plan,map);done=true end);f.advance(8)
check(done and plan.root:GetAttribute('Built'),'river and bridge construction completes')
check(#warnings==0,'no builder warnings')
check(obstruction.Parent==nil and kept.Parent==restinga,'only beach decoration in the river corridor removed')
check(#calls>80,'complete terrain channel written')
local water=0
for z=1374,4026,4 do
 local x,w=R.at(z);local cell=voxels[key(x,-10,z)]
 assert(cell and cell.mat==E.Material.Water and cell.fill>.9,'water interrupted at '..z)
 water+=1
end
check(true,'continuous swimmable centerline to the sea: '..water..' samples')
local cx,w=R.at(R.BridgeZ);check(w==36 and math.abs(w*.28-10)<.1,'bridge crossing water width approximately ten meters')
check(R.Points[#R.Points][2]>config.Litoral.SeaZ+100 and R.WaterY==config.Litoral.SeaLevel,'river enters the ocean at the same water level')
for _,z in ipairs({1800,2400,3000,3400,3700})do
 local x,width=R.at(z);local cell=voxels[key(x,-10,z)]
 assert(cell and cell.mat==E.Material.Water,'water missing')
 local land=voxels[key(x+width/2+22,-2,z)]
 assert(land and land.mat~=E.Material.Water and land.fill>0,'bank missing '..z)
end
check(true,'solid banks contain the water channel')
-- Execute the actual ground builder and check its openings and unaffected land.
local a=SOURCES.MapBuilder:find('local function buildGround(',1,true)
local b=SOURCES.MapBuilder:find('\nlocal function buildSpawn',a,true)
local code=SOURCES.MapBuilder:sub(a,b-1)
local groundFunc=assert(loadstring('return function(makePart,M,C,GameConfig,RiverBuilder)'..code..'\nreturn buildGround end'));setfenv(groundFunc,m.env)
local ground=H.folder('GroundTest',m.Workspace)
groundFunc()(H.makePart,config.Map,config.Colors,config,river)(ground)
local function inside(p,x,y,z,pad)
 local v=p.CFrame:PointToObjectSpace(V.new(x,y,z));local s=p.Size/2
 return math.abs(v.X)<s.X+(pad or 0) and math.abs(v.Y)<s.Y+(pad or 0) and math.abs(v.Z)<s.Z+(pad or 0)
end
for z=1374,3440,8 do
 local x=R.at(z)
 for _,p in ipairs(ground:GetChildren())do assert(not inside(p,x,-.5,z),'ground covers river '..z)end
end
check(true,'real MapBuilder ground does not cover the river')
for _,v in ipairs({V.new(0,-.5,0),V.new(1500,-.5,3000),V.new(3000,-.5,2500),V.new(-3000,-.5,0)})do
 local hit=false;for _,p in ipairs(ground:GetChildren())do if inside(p,v.X,v.Y,v.Z,.01)then hit=true;break end end
 assert(hit,'unrelated ground removed')
end
check(true,'unrelated city and coast ground preserved')
local parts={};local deckParts={}
for _,p in ipairs(plan.root:GetDescendants())do
 if p:IsA('BasePart')then table.insert(parts,p);if p:GetAttribute('Driveable')then table.insert(deckParts,p)end end
end
local probes=0
for x=1840,2760,2 do
 local y=R.roadHeight(x);local width=R.roadWidth(x)
 for _,side in ipairs({-1,1})do
  local z=R.BridgeZ+side*width/4
  local supported=false
  for _,p in ipairs(deckParts)do if inside(p,x,y-.3,z,.08)then supported=true;break end end
  assert(supported,'road surface gap at '..x)
  for _,p in ipairs(parts)do
   if p.CanCollide then assert(not inside(p,x,y+2,z,1.1),'car blocked at '..x..' by '..p.Name)end
  end
  local wz=R.BridgeZ+side*(width/2+2.2)
  for _,p in ipairs(parts)do if p.CanCollide then assert(not inside(p,x,y+3,wz,.6),'sidewalk blocked '..x..' by '..p.Name)end end
  probes+=2
 end
end
check(true,'driveable lanes and sidewalks clear in '..probes..' samples')
check((R.DeckY-R.RoadY)/(R.DeckX0-R.ApproachX0)<.05,'approach gradients below five percent')
for z=3360,3440,4 do
 local x=R.at(z)
 for _,p in ipairs(parts)do if p.CanCollide then assert(not inside(p,x,-1,z,1),'waterway blocked under bridge by '..p.Name)end end
end
check(true,'open water passage under the bridge')
for z=R.BridgeZ+15,R.BridgeZ+41,1 do
 for _,p in ipairs(parts)do if p.CanCollide then assert(not inside(p,2298,9,z,.6),'river overlook access blocked by '..p.Name)end end
end
check(true,'public overlook has a clear sidewalk entrance')
local cables=0;for _,p in ipairs(parts)do if p.Name=='Estai'then cables+=1 end end
check(cables>=14 and #parts<2200,'cable stayed silhouette with bounded part count: '..#parts)
local model=plan.root:FindFirstChild(R.BridgeName)
check(model:GetAttribute('License')~=nil,'source attribution retained on bridge')
local road
for _,r in ipairs(roads.get().roads)do if r.CustomBuild=='RiverBridge'then road=r end end
check(road~=nil and road.Points[1].X==config.Litoral.BeiraMarHalf,'bridge road joins the existing eastern coastal return')
local route=m.load('RouteGraph',SOURCES.RouteGraph,true).route(V.new(1200,0,3400),V.new(2700,0,3400))
local bridgeNode=false
for _,p in ipairs(route)do if p.X>=R.DeckX0 and p.X<=R.DeckX1 and math.abs(p.Z-R.BridgeZ)<1 then bridgeNode=true end end
check(#route>=5 and bridgeNode,'GPS route crosses the bridge between the shore and eastern bank')
-- Exercise the real street builder at both bridge junctions; its sign posts must
-- respect the wide boulevard taper, and it must not lay a flat slab under the bridge.
H.ROAD_TOP=.5;H.SIDEWALK_TOP=.8;H.isFree=function()return true end
H.buildLamp=function()end
H.flatCylinder=function(parent,name,pos,r,h,color,material)
 return H.makePart(parent,{Name=name,Size=V.new(h,r*2,r*2),CFrame=C.new(pos)*C.Angles(0,0,math.pi/2),Shape=E.PartType.Cylinder,Color=color,Material=material})
end
local selectedRoads={};local selectedCircles={}
for _,r in ipairs(roads.get().roads)do if r.CustomBuild or r.Name==config.Litoral.BeiraMarName then table.insert(selectedRoads,r)end end
for _,c in ipairs(roads.get().circles)do if c.Center.X==1800 or c.Name=='Retorno da Foz'then table.insert(selectedCircles,c)end end
local wrapper=table.clone(roads)
wrapper.get=function()return{roads=selectedRoads,circles=selectedCircles,ends={}}end
wrapper.splits=function()local out={};for i in ipairs(selectedRoads)do out[i]={}end;return out end
m.registry.CityRoads=wrapper
local expansion=m.load('ExpansionBuilder',SOURCES.ExpansionBuilder,true)
local streetPlan=expansion.plan(map,H.folder('Props',map),H)
m.registry.CityRoads=roads
check(#warnings==0,'original street builder integrates the custom bridge without warnings')
for _,p in ipairs(streetPlan.root:GetDescendants())do
 if p:IsA('BasePart')then
  assert(not inside(p,2220,.1,3400),'ordinary road generated a slab inside the river')
  if p.CanCollide then
   for x=1838,1870,2 do
    for _,side in ipairs({-1,1})do assert(not inside(p,x,3,3400+side*R.roadWidth(x)/4,1),'junction sign blocks lane: '..p.Name)end
   end
  end
 end
end
check(true,'junction signs clear the taper and no ground-level road blocks the channel')

local oldScript=m.env.script;m.env.script={Parent=m.services.ReplicatedStorage.Shared}
local baseline=m.load('BaselineRoads',SOURCES.BaselineRoads);m.env.script=oldScript
local oldData,newData=baseline.get(),roads.get()
check(#newData.roads==#oldData.roads+1 and #newData.circles==#oldData.circles+1,'only one new road and one eastern return added')
for _,old in ipairs(oldData.roads)do
 local match=false
 for _,r in ipairs(newData.roads)do
  if r.Name==old.Name and #r.Points==#old.Points and r.Kind==old.Kind and r.Width==old.Width then
   local equal=true
   for i,p in ipairs(old.Points)do if(p-r.Points[i]).Magnitude>.001 then equal=false end end
   if equal then match=true;break end
  end
 end
 assert(match,'existing road changed: '..old.Name)
end
check(true,'every existing road retains its coordinates, type and width')

local before=#plan.root:GetDescendants();local terrainBefore=#calls;river.build(plan,map)
check(#plan.root:GetDescendants()==before and #calls==terrainBefore,'builder is idempotent')
-- Logs consumed by the technical preview, not screenshots of Roblox.
for _,s in ipairs(plan.samples)do print('RIVER',s.pos.X,s.pos.Z,s.width)end
for _,p in ipairs(parts)do
 local c=p.Color
 if p.Name~='Ponto' then
  local cf=p.CFrame;print('PART',p.Name,p.Size.X,p.Size.Y,p.Size.Z,p.Position.X,p.Position.Y,p.Position.Z,cf.RightVector.X,cf.RightVector.Y,cf.RightVector.Z,cf.UpVector.X,cf.UpVector.Y,cf.UpVector.Z,cf.LookVector.X,cf.LookVector.Y,cf.LookVector.Z,c.R,c.G,c.B)
 end
end
print('TOTAL RIVER',passed,'PARTS',#parts,'LENGTH',plan.root:GetAttribute('LengthStuds'))
