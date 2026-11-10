local f=assert(loadstring(SOURCES.fixture))()(SOURCES.mock)
local m=f.mock;local V,C=m.Vector3,m.CFrame
m.services.ServerStorage=f.instance('Folder');m.services.StarterPlayer={CameraMaxZoomDistance=128}
local passed=0
local function check(ok,msg)assert(ok,msg);passed+=1;print('PASS',msg)end
local config=m.load('GameConfig',SOURCES.GameConfig)
local hc=m.load('HomeConfig',SOURCES.HomeConfig)
m.load('FurnitureArt',SOURCES.FurnitureArt)
m.load('PlayerDataService','return {}',true);m.load('EconomyService','return {}',true);m.load('ZoneService','return {}',true)
local data,loadCallback,notices={},nil,{}
local saves=0;local charges=0
m.registry.PlayerDataService.get=function(p)return data[p]end
m.registry.PlayerDataService.set=function(p,k,v)data[p][k]=v;saves+=1 end
m.registry.PlayerDataService.onLoaded=function(cb)loadCallback=cb end
m.registry.EconomyService.spend=function(p,n)
 if data[p].money<n then return false end
 data[p].money-=n;charges+=1;return true
end
m.registry.EconomyService.add=function(p,n)data[p].money+=n end
m.registry.ZoneService.addZone=function()end;m.registry.ZoneService.removeZone=function()end
local function model(name,parent)local o=f.instance('Model');o.Name=name;o.Parent=parent;return o end
local map=model('Map',m.Workspace);local houses=model('Houses',map)
local id=0
local function house(tier,gang,x)
 id+=1;local h=model('Casa '..id,houses)
 h:SetAttribute('HouseNumber',id);h:SetAttribute('Tier',tier);h:SetAttribute('Gang',gang);h:SetAttribute('Address','Rua Teste '..id);h:SetAttribute('Remote',true)
 local door=f.instance('Part');door.Name='Door';door.Size=V.new(3,6,.4);door.CFrame=C.new(x,3,0);door.Parent=h
 return h
end
house('basica',nil,-100);house('basica',nil,-200)
for i,g in ipairs({'CDA','TDE','CDS'})do
 house('barraco',g,-300-i*20)
 house('comunidade_'..string.lower(g),g,i*100)
 house('comunidade_'..string.lower(g),g,i*100+30)
end
local src=SOURCES.HomeService:gsub('return HomeService%s*$','HomeService._test={slots=slots,slotsOf=slotsOf,insideOf=insideOf,buy=buyOrMove,release=release,assign=assign}\nreturn HomeService')
local home=m.load('HomeService',src,true)
local request={OnServerEvent=f.signal()}
local remotes={[config.Remotes.UIUpdate]={FireClient=function(_,p,kind,body)if kind=='Notice'then table.insert(notices,body.text)end end},[config.Remotes.HomeRequest]=request}
home.init(remotes)
local p=f.player(1);data[p]={money=100000,gang=nil};loadCallback(p,data[p])
local function slot(tier,n)local count=0;for _,s in ipairs(home._test.slots)do if s.tier==tier then count+=1;if count==(n or 1)then return s end end end end
local cda=slot('comunidade_cda');local tde=slot('comunidade_tde')
local function move(s)p.Character:PivotTo(s.door.CFrame*C.new(0,0,-4))end
move(cda);home._test.buy(p,cda)
check(data[p].money==100000 and not data[p].homes.comunidade_cda,'non-member cannot buy gang residence')
data[p].gang='TDE';home.refresh(p);home._test.buy(p,cda)
check(data[p].money==100000,'different gang cannot buy residence')
data[p].gang='CDA';home.refresh(p)
check(home._test.slotsOf[p].barraco.gang=='CDA','free home follows gang switch')
p.Character:PivotTo(C.new(5000,0,0));home._test.buy(p,cda)
check(not data[p].homes.comunidade_cda,'remote purchase rejected by server distance')
move(cda);data[p].money=100;home._test.buy(p,cda)
check(not data[p].homes.comunidade_cda and charges==0,'insufficient funds causes no ownership or charge')
data[p].money=100000;home._test.buy(p,cda)
check(data[p].money==65000 and data[p].homes.comunidade_cda~=nil,'member buys home for 35000')
check(cda.owner==p and home._test.slotsOf[p].comunidade_cda==cda,'purchase assigns actual housing facade')
check(data[p].homes.barraco~=nil,'optional purchase retains free gang home')
home._test.buy(p,cda)
check(charges==1,'duplicate request does not charge twice')
local cda2=slot('comunidade_cda',2);move(cda2);home._test.buy(p,cda2)
check(charges==1 and cda2.owner==p and not cda.owner,'moving within purchased tier is free')
local furnitureCount=#data[p].homes.comunidade_cda.items
local savedHome=data[p].homes.comunidade_cda
-- Real prompt opens existing interior and decor UI; exercise actual geometry creation.
f.advance(1.1);cda2.door.HomePrompt.Triggered:Fire(p)
check(home._test.insideOf[p]==cda2 and cda2.interior~=nil,'purchased house opens furnished interior')
check(#cda2.interior:GetDescendants()>25,'existing interior and furniture builders execute')
home.leaveHome(p)
check(home._test.insideOf[p]==nil,'player exits to community door')
data[p].gang='TDE';home.refresh(p)
check(not cda2.owner and not home._test.slotsOf[p].comunidade_cda,'gang change suspends residence use')
check(data[p].homes.comunidade_cda==savedHome and #savedHome.items==furnitureCount,'gang change preserves purchase and furniture')
data[p].gang='CDA';home.refresh(p)
check(home._test.slotsOf[p].comunidade_cda~=nil and charges==1,'returning to gang restores residence without charge')
home._test.release(p);home._test.assign(p,data[p])
check(home._test.slotsOf[p].comunidade_cda~=nil and charges==1,'rejoin restores purchased residence through existing migration')
local q=f.player(2);data[q]={money=100000,gang='CDA'};loadCallback(q,data[q])
local owned=home._test.slotsOf[p].comunidade_cda;q.Character:PivotTo(owned.door.CFrame)
home._test.buy(q,owned)
check(owned.owner==p and not data[q].homes.comunidade_cda,'occupied facade cannot be bought by second player')
check(saves>0,'purchases use existing PlayerDataService homes persistence interface')
check(#f.warnings==0,'housing flow has no runtime warnings')
print('TOTAL HOUSING',passed)
