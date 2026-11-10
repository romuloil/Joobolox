local f=fixture({noNpcs=true})
local m=f.mock;local V,C=m.Vector3,m.CFrame;local I=m.env.Instance.new
local scriptBefore=m.env.script;m.env.script={Parent=m.services.ReplicatedStorage.Shared}
local roads=m.load('CityRoads',SOURCES.CityRoads);m.env.script=scriptBefore
local water,bed,hills={},{},{}
m.Workspace.Terrain={FillBlock=function(_,cf,size,material)
 table.insert(material==m.Enum.Material.Water and water or bed,{cf=cf,size=size})
end,FillBall=function(_,pos,radius,material)table.insert(hills,{pos=pos,radius=radius})end}
local H={}
H.model=function(name,parent)local p=I('Model');p.Name=name;p.Parent=parent;return p end
H.makePart=function(parent,props)local p=I(props.ClassName or'Part');for k,v in pairs(props)do if k~='ClassName'then p[k]=v end end;p.Anchored=true;p.Parent=parent;return p end
H.addSurfaceText=function(p,text)local l=I('TextLabel');l.Text=text;l.Parent=p end
H.buildTree=function()end;H.buildLamp=function()end;H.beachPalm=function()end
local map=m.Workspace.Map
for _,x in ipairs({0,2000})do for _,z in ipairs({3000,5000})do
 H.makePart(map,{Name='Ground',Size=V.new(2000,1,2000),CFrame=C.new(x,-.5,z)})
end end
local function groundAt(x,z)
 for _,p in ipairs(map:GetChildren())do if p.Name=='Ground'and math.abs(p.Position.X-x)<=p.Size.X/2 and math.abs(p.Position.Z-z)<=p.Size.Z/2 then return p end end
end
check(groundAt(1000,3300)~=nil,'ocean starts as ordinary tiled ground in fixture')
local builder=m.load('CoastBuilder',SOURCES.CoastBuilder,true);local coast
m.env.task.spawn(function()coast=builder.build(map,H)end);f.advance(4)
check(coast and coast:GetAttribute('BeachCount')==3,'three coastal coves build successfully')
check(not groundAt(1000,3300),'ground is cut out beneath ocean rather than covering swimming water')
check(groundAt(100,3300)~=nil and groundAt(2300,3300)~=nil,'ground outside ocean cut remains intact')
check(#water==35 and #bed==35,'ocean uses 35 bounded water tiles with seabed, not a collidable blue plane')
local volume=0
for _,w in ipairs(water)do
 check(w.cf.Y+w.size.Y/2==-8,'water surface aligned at -8')
 assert(w.cf.X-w.size.X/2>=220 and w.cf.X+w.size.X/2<=2220 and w.cf.Z-w.size.Z/2>=2880 and w.cf.Z+w.size.Z/2<=5680,'ocean spill outside approved coast')
 volume+=w.size.X*w.size.Y*w.size.Z
end
check(volume==2000*2800*40,'water volume has no tile gaps or duplicated slabs')
check(#hills==6,'six inland coastal hills')
check(coast:GetAttribute('BridgeBuilt')==false,'future bridge is not constructed')
check(builder.build(map,H)==coast and #water==35,'coast builder is idempotent')
local canopy,seats,markers,foods=0,0,0,0
for _,p in ipairs(coast:GetDescendants())do
 if p.Name=='Lona'then canopy+=1 end
 if p:IsA('Seat')then seats+=1 end
 if p:GetAttribute('Tourist')then markers+=1 end
 if p:GetAttribute('FoodId')then foods+=1 end
end
check(canopy==18*8 and seats==36,'18 colorful umbrellas with 36 usable beach seats')
check(markers==15 and foods==6,'12 tourists, three vendor positions and six snack counters')
local cfg=roads.Coast
local network=roads.get();local coastal={};local oldExit=false;local finalExit=false
for _,r in ipairs(network.roads)do if r.Coastal then table.insert(coastal,r)end end
for _,e in ipairs(network.ends)do
 if (e.Pos-V.new(0,0,2840)).Magnitude<1 then oldExit=true end
 if(e.Pos-cfg.BridgeApproach).Magnitude<1 then finalExit=true end
end
check(not oldExit and finalExit,'old barrier removed from LK-102; future bridge endpoint is signed and closed')
check(#coastal==4,'coastal highway and all three beach access roads registered for GPS')
local main=coastal[1]
check((main.Points[1]-roads.FinancialDistrict.Coast.Entrance).Magnitude<.01,'new winding road joins exact existing LK-102 endpoint')
for _,p in ipairs(main.Points)do assert(p.X<=200,'road enters water intended for the future bridge')end
check(true,'coastal road remains on land and stops before open water')
local splits=roads.splits()
for i,r in ipairs(network.roads)do if r.Coastal then assert(#splits[i]>=1,'disconnected coastal road '..r.Name)end end
check(true,'every new coastal road has a GPS junction')
-- Actual CoastService against controlled NPC/wallet/inventory adapters.
local balance,spent={},0;local hasSpace=true;local spawned={};local said=0
m.registry.EconomyService={spend=function(player,amount)
 if(balance[player]or 0)<amount then return false end
 balance[player]-=amount;spent+=amount;return true
end}
m.load('InventoryService','return {}',true);m.registry.InventoryService.hasRoom=function()return hasSpace end
m.registry.NPCKit.spawn=function(cf,opts)
 local npc=f.character();npc.Name=opts.name;npc:PivotTo(cf);npc.HumanoidRootPart.Anchored=opts.anchored
 table.insert(spawned,npc);return npc
end
m.registry.NPCKit.say=function()said+=1 end
local notices={};local ui={FireClient=function(_,p,_,payload)notices[p]=payload.text end}
local service=m.load('CoastService',SOURCES.CoastService,true)
service.init({[m.registry.GameConfig.Remotes.UIUpdate]=ui});f.advance(3)
check(#spawned==15,'existing NPCKit reused to create fifteen fixed coastal characters')
service.init({[m.registry.GameConfig.Remotes.UIUpdate]=ui});f.advance(3)
check(#spawned==15,'service reinitialization cannot duplicate tourists')
local counter
for _,p in ipairs(coast:GetDescendants())do if p:GetAttribute('FoodId')=='picole'then counter=p;break end end
local prompt=counter.ComprarLanche
local player=f.player(91001);balance[player]=100
local root=player.Character.HumanoidRootPart
root.Position=counter.Position+V.new(100,0,0);prompt.Triggered:Fire(player)
check(balance[player]==100,'remote snack activation rejected')
root.Position=counter.Position;hasSpace=false;prompt.Triggered:Fire(player)
check(balance[player]==100,'full inventory cannot be charged')
hasSpace=true;f.advance(1.1);balance[player]=20;prompt.Triggered:Fire(player)
check(balance[player]==20,'insufficient funds cannot buy a snack')
balance[player]=100;f.advance(1.1);prompt.Triggered:Fire(player)
local tool=player:FindFirstChild('Backpack'):FindFirstChild('Picolé do Litoral')
check(tool and balance[player]==75,'purchase gives actual consumable and charges configured price')
f.advance(1.1);prompt.Triggered:Fire(player)
check(balance[player]==75,'duplicate owned snack cannot charge again')
local hum=player.Character.Humanoid;hum.Health=60
 tool.Activated:Fire();check(hum.Health==60,'unequipped snack cannot heal')
 tool.Parent=player.Character;tool.Activated:Fire();check(hum.Health==70 and tool.Parent==nil,'equipped snack consumes once and restores ten health')
 tool.Activated:Fire();check(hum.Health==70,'destroyed snack cannot be reused')
local talk=spawned[1].HumanoidRootPart.ConversarPraia
root.Position=V.new(0,3,0);talk.Triggered:Fire(player);check(said==0,'tourist conversation validates distance')
root.Position=talk.Parent.Position;talk.Triggered:Fire(player);talk.Triggered:Fire(player)
check(said==1,'nearby tourist conversation works with cooldown')
f.assertClean()
print('TOTAL COAST',passed,'VOLUME',volume)
