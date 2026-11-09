local f=fixture({noNpcs=true})
local m=f.mock;local V,C=m.Vector3,m.CFrame
local I=m.env.Instance.new
local studio=false
m.services.RunService.IsStudio=function()return studio end
m.services.TextService={}
m.env.game.BindToClose=function()end
local stored={};local readsFail=false;local writesFail=false
m.services.DataStoreService={GetDataStore=function()return {
 GetAsync=function(_,key)if readsFail then error('test load failure')end;return stored[key] and table.clone(stored[key])end,
 UpdateAsync=function(_,key,fn)if writesFail then error('test save failure')end;local data=fn(stored[key]);stored[key]=table.clone(data);stored[key].ownedCars=table.clone(data.ownedCars or {});return data end,
}end}
local cfg=m.registry.GameConfig
cfg.Data.Retries=1
cfg.Admins.UserIds={};cfg.Admins.InStudio=false
m.load('JobConfig','return {Jobs={Policial={Name="Policial"}}}')
m.load('RigMeasure','return {}')
for _,name in ipairs({'ZoneService','CarBuilder','SeatService','SecurityService'})do m.load(name,'return {}',true)end
m.registry.SecurityService.getLivingCharacter=function(p)
 local c=p.Character;local h=c and c:FindFirstChildOfClass('Humanoid');local r=c and c:FindFirstChild('HumanoidRootPart')
 if h and h.Health>0 then return c,h,r end
end
m.registry.SecurityService.checkRate=function()return true end
local p=f.player(71001);local root=p.Character.HumanoidRootPart
local data=m.load('PlayerDataService',SOURCES.PlayerDataService,true)
data.init();f.advance(.1)
local econ=m.load('EconomyService',SOURCES.EconomyService,true)
local events={}
local ui={FireClient=function(_,player,kind,payload)events[player]={kind=kind,payload=payload}end}
local expose=[[VehicleService._test={owns=ownsCar,list=carList,open=openGarage,action=garageAction,setup=setupGarages,setUi=function(value)uiUpdate=value end}
return VehicleService]]
local svc=m.load('VehicleService',SOURCES.VehicleService:gsub('return VehicleService%s*$',expose),true)._test
svc.setUi(ui)
local folder=I('Folder');folder.Name='Garages';folder.Parent=m.Workspace.Map
local function garage(name,dealer,job)
 local g=I('Model');g.Name=name;g:SetAttribute('Dealership',dealer);g:SetAttribute('ServiceJob',job);g.Parent=folder
 local b=I('Part');b.Name='Balcao';b.CFrame=C.new(0,3,0);b.Parent=g
 return g
end
local ordinary=garage('Publica',false)
local dealer=garage('ConcessionariaDoVale',true)
local police=garage('PM',false,'Policial')
local id='L5';local price=cfg.Cars[id].Price
check(price>0,'catalog has a real server-defined price')
check(data.canPersist(p),'new player data loaded and saving is available')
check(#svc.list(p,ordinary)==0,'live new-player garage starts without unpurchased cars')
check(#svc.list(p,dealer)>0,'dealership displays purchasable personal cars')
for _,car in ipairs(svc.list(p,dealer))do assert(not car.service and not car.admin,'restricted cars sold')end
check(true,'job and admin cars cannot be bought at dealership')
local function buy(g,car,extra)
 local payload=extra or {};payload.op='Buy';payload.car=car or id;payload.garage=g.Name
 svc.action(p,payload)
end
data.set(p,'money',price*3)
local start=econ.getMoney(p)
buy(ordinary)
check(econ.getMoney(p)==start and not svc.owns(p,id,ordinary),'garage cannot sell cars through forged Buy request')
root.Position=V.new(100,3,0);buy(dealer)
check(econ.getMoney(p)==start,'remote purchase rejected outside dealership radius')
root.Position=V.new(0,3,0)
p:SetAttribute('Preso',true);buy(dealer);p:SetAttribute('Preso',nil)
check(econ.getMoney(p)==start,'prisoners cannot purchase vehicles')
root.Parent.Humanoid.Health=0;buy(dealer);root.Parent.Humanoid.Health=100
check(econ.getMoney(p)==start,'dead characters cannot buy')
data.set(p,'money',price-1);buy(dealer)
check(not svc.owns(p,id,ordinary) and econ.getMoney(p)==price-1,'insufficient funds leave ownership and money unchanged')
data.set(p,'money',start);buy(dealer,id,{price=0,owned=true})
check(econ.getMoney(p)==start-price,'server charges actual price despite client price/owned fields')
check(svc.owns(p,id,ordinary),'successful purchase unlocks withdrawal')
check(#svc.list(p,ordinary)==1 and svc.list(p,ordinary)[1].id==id,'only the purchased car appears in normal garage')
check(events[p].kind=='GarageOpen'and events[p].payload.dealership,'catalog refreshes after purchase')
buy(dealer);buy(dealer)
check(econ.getMoney(p)==start-price,'duplicate rapid requests cannot charge or grant twice')
f.advance(.1)
check(stored['Player_'..p.UserId].ownedCars[id]and stored['Player_'..p.UserId].money==start-price,'money and ownership saved together through actual PlayerDataService')
local q=f.player(p.UserId);m.services.Players.PlayerAdded:Fire(q);f.advance(.1)
check(data.get(q).ownedCars[id]and svc.owns(q,id,ordinary),'rejoin reloads purchased car from saved profile')
local before=econ.getMoney(p)
buy(dealer,'unknown');buy(dealer,{});buy(dealer,'Van');buy(dealer,'Viatura')
check(econ.getMoney(p)==before,'invalid IDs, payloads and service cars cannot debit funds')
p:SetAttribute('Job','Policial')
local work=svc.list(p,police)
check(#work>0 and #svc.list(p,ordinary)==1,'job cars stay in workplace garage rather than personal dealership inventory')
p:SetAttribute('Job',nil)
check(#svc.list(p,police)==0,'workplace withdrawal requires the job')
studio=true
check(svc.owns(p,'R18',ordinary),'Studio unlock allows testing an unpurchased personal car')
check(data.get(p).ownedCars.R18~=true,'Studio unlock does not grant permanent ownership')
check(#svc.list(p,ordinary)>1,'Studio personal garage offers unlocked cars')
studio=false
check(not svc.owns(p,'R18',ordinary),'published server ignores Studio-only free setting')
svc.setup()
root.Position=V.new(100,3,0);events[p]=nil
ordinary.Balcao.GaragePrompt.Triggered:Fire(p)
check(events[p]==nil,'forged prompt event cannot open a remote garage')
root.Position=V.new(0,3,0)
dealer.Balcao.GaragePrompt.Triggered:Fire(p)
check(events[p].kind=='GarageOpen'and events[p].payload.dealership,'E prompt opens the dealership catalog nearby')
-- Failed data loads may not buy into a temporary/default live profile.
readsFail=true
local bad=f.player(71002);m.env.task.spawn(function()m.services.Players.PlayerAdded:Fire(bad)end);f.advance(3)
check(not data.canPersist(bad),'failed profile load reports unavailable persistence')
data.set(bad,'money',price*3);bad.Character.HumanoidRootPart.Position=V.new(0,3,0)
svc.action(bad,{op='Buy',car=id,garage=dealer.Name})
check(not data.get(bad).ownedCars[id]and data.get(bad).money==price*3,'live purchase blocked when profile did not load safely')
-- Only expected datastore warning belongs to this deliberate failure.
for i=#f.warnings,1,-1 do if f.warnings[i]:find('Falha ao carregar',1,true)then table.remove(f.warnings,i)end end
f.assertClean()
print('TOTAL VEHICLES',passed)
