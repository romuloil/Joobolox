-- This executes production BankBuilder, BankService and HeistEvents. Roblox
-- physics, avatar HTTP loading and the shared jewelry minigame UI are doubles.
local passed = 0
local function check(ok, message)
 assert(ok, message); passed += 1; print('PASS '..message)
end
local function fixture(options)
 options = options or {}
 local f = assert(loadstring(SOURCES.fixture))()(SOURCES.mock)
 local m, I = f.mock, f.instance
 local V, C = m.Vector3, m.CFrame
 m.env.os = {clock=f.now}
 m.env.print = function() end
 m.services.ServerStorage = I('Folder')
 m.services.RunService.Heartbeat.Wait = function() return m.env.task.wait(1/60) end
 m.Workspace.Raycast = function() return nil end
 local new = m.env.Instance.new
 m.env.Instance.new = function(class)
  local p = new(class)
  if class == 'Sound' then p.Play=function()end end
  local oldIsA = p.IsA
  p.IsA = function(self,kind)
   return oldIsA(self,kind) or (kind=='BasePart' and (class=='MeshPart' or class=='TrussPart'))
  end
  p.Clone = function(self)
   local clone = m.env.Instance.new(self.ClassName)
   for k,v in pairs(self._props) do
    if k~='Parent' and type(v)~='function' then clone[k]=v end
   end
   for k,v in pairs(self:GetAttributes())do clone:SetAttribute(k,v)end
   for _,child in ipairs(self:GetChildren())do child:Clone().Parent=clone end
   return clone
  end
  if class=='Humanoid' then p.TakeDamage=function(self,n) self.Health=math.max(0,self.Health-n) end end
  return p
 end
 I=m.env.Instance.new
 local tags = {}
 m.services.CollectionService = {
  AddTag=function(_,part,tag) tags[tag]=tags[tag] or {};table.insert(tags[tag],part) end,
  GetTagged=function(_,tag) return tags[tag] or {} end,
  GetInstanceAddedSignal=function()return f.signal()end,
 }
 local config=m.load('GameConfig',SOURCES.GameConfig)
 local B=config.Bank
 for _,event in pairs(B.Events) do event.Chance=0 end
 if options.event then B.Events[options.event].Chance=1; B.TestAllEvents=true end
 -- No shortening of preparation, keys, drilling or vault timers.
 m.load('CityRoads','return {}')
 local function model(name,parent)
  local p=I('Model');p.Name=name;p.Parent=parent;return p
 end
 local map=model('Map',m.Workspace)
 if not options.fallback then
  local models=model('BankModels',m.services.ServerStorage)
  local vault=model('CofreBanco',models)
  for _,asset in ipairs(VAULT)do
   local p=I('MeshPart');p.Name=asset.name;p.Size=V.new(table.unpack(asset.size))
   p.CFrame=C.fromMatrix(V.new(table.unpack(asset.position)),V.new(table.unpack(asset.basis[1])),V.new(table.unpack(asset.basis[2])),V.new(table.unpack(asset.basis[3])))
   p.Parent=vault
  end
 end
 local ground=I('Part');ground.Name='Ground';ground.Size=V.new(1000,1,1000);ground.Position=V.new(0,-0.5,0);ground.Parent=map
 local K={model=model,lotBeside=function()return C.new()end,rect=function()return {}end,isFree=function()return true end,occupy=function()end,buildLamp=function()end}
 K.makePart=function(parent,props)
  local p=I(props.ClassName or 'Part')
  for k,v in pairs(props)do if k~='ClassName' then p[k]=v end end
  p.Anchored=true;p.Parent=parent;return p
 end
 local builder=m.load('BankBuilder',SOURCES.BankBuilder,true)
 local bank=builder.build(builder.plan(map,K))
 -- The absent imported vault intentionally exercises the fallback branch here.
 for i=#f.warnings,1,-1 do if f.warnings[i]:find('CofreBanco não encontrado',1,true)then table.remove(f.warnings,i)end end
 local function part(name)return assert(bank:FindFirstChild(name,true),'missing bank marker '..name)end
 local mini, notices, calls, earned, updates = {}, {}, {}, {}, {}
 local npcKit={}
 npcKit.spawn=function(cf,def)
  if options.noNpcs then return nil end
  if options.npcDelay then m.env.task.wait(options.npcDelay) end
  local c=f.character(); c.Name=def.name;c:PivotTo(cf*C.new(0,3,0));return c
 end
 for _,name in ipairs({'pose','say','emote','rope','wearBag','walk'})do npcKit[name]=function()end end
 npcKit.hold=function(npc,name,size,color)
  local p=I('Part');p.Name=name;p.Size=size;p.Color=color;p.Parent=npc;return p
 end
 npcKit.bagItems=function(b) b.items=b.items or {};return b.items end
 npcKit.bagCheapest=function(b,need,max)
  local copy=table.clone(npcKit.bagItems(b));table.sort(copy,function(a,b)return a.value<b.value end)
  local result,slots,value={},max-b.slots,0
  for _,item in ipairs(copy)do table.insert(result,item);slots+=item.slots;value+=item.value;if slots>=need then return result,value end end
 end
 local crime={
  isPolice=function(p)return p:GetAttribute('Job')=='Policial'end,
  isCuffed=function(p)return p:GetAttribute('Algemado')==true end,
  notice=function(p,text)notices[p]=text end,
  addWanted=function(p,n)p:SetAttribute('Wanted',(p:GetAttribute('Wanted')or 0)+n)end,
  policeCount=function()return 0 end,alert=function(...)table.insert(calls,{...})end,blink=function()end,
  onArrest=function(fn)f.arrest=fn end,
 }
 local downed={isDowned=function(p)return p:GetAttribute('Caido')==true end,onGiveUp=function(fn)f.giveUp=fn end}
 local chiefs={}
 local weapon={onShot=function(fn)f.shot=fn end,isAimingAt=function()return false end}
 local jewelry={minigame=function(p,rule,anchor,title,done,miss)
  if mini[p] then return false end
  mini[p]={done=done,miss=miss,rule=rule};return true
 end}
 for name,value in pairs({CrimeService=crime,DownedService=downed,NPCKit=npcKit,EconomyService={add=function(p,n)earned[p]=(earned[p]or 0)+n;return true end},
  CareerService={taskPay=function(_,_,n)return n end},GangService={getChiefs=function()return chiefs end},WeaponService=weapon,JewelryService=jewelry})do
  m.load(name,'return {}',true);m.registry[name]=value
 end
 local engine=m.load('HeistEvents',SOURCES.HeistEvents,true)
 local realNew=engine.new
 engine.new=function(...)local e=realNew(...);f.events=e;return e end
 local ui={FireClient=function(_,p,kind,data)updates[p]=updates[p]or {};updates[p][kind]=data end,FireAllClients=function()end}
 local request={OnServerEvent=f.signal()}
 local service=m.load('BankService',SOURCES.BankService,true)
 service.init({[config.Remotes.UIUpdate]=ui,[config.Remotes.BankRequest]=request})
 f.advance(0)
 f.bank,f.B,f.part,f.notices,f.updates,f.calls,f.earned,f.mini=bank,B,part,notices,updates,calls,earned,mini
 f.newPlayer=function(id,gang)
  local p=f.player(id);if gang then p:SetAttribute('Gang',gang)end
  f.players.PlayerAdded:Fire(p);return p
 end
 f.gun=function(p)
  local tool=I('Tool');tool.Name='Pistola';tool:SetAttribute('Use','gun');tool.Parent=p.Character;return tool
 end
 f.at=function(p,name,offset)
  local target=type(name)=='string'and part(name)or name
  p.Character:PivotTo(C.new(target.Position+(offset or V.zero)))
 end
 f.prompt=function(action)
  for _,d in ipairs(m.Workspace:GetDescendants())do if d.ClassName=='ProximityPrompt'and d.ActionText==action then return d end end
  error('prompt missing: '..action)
 end
 f.use=function(p,action,move)
  local q=type(action)=='string'and f.prompt(action)or action
  if move~=false then f.at(p,q.Parent)end
  check(q.Enabled and q:GetAttribute('Ativo'),'interaction active: '..q.ActionText)
  q.PromptButtonHoldBegan:Fire(p);f.advance(q.HoldDuration+.02);q.Triggered:Fire(p);q.PromptButtonHoldEnded:Fire(p);f.advance(.45)
 end
 f.status=function(p)
  f.advance(.31);request.OnServerEvent:Fire(p,'Status');return assert(updates[p].BancoStatus)
 end
 f.request=function(p,action,arg)f.advance(.31);request.OnServerEvent:Fire(p,action,arg)end
 f.complete=function(p)
  local session=assert(mini[p],'minigame did not start');mini[p]=nil;session.done();return session
 end
 f.chief=function(gang)
  local npc=f.character();npc:PivotTo(C.new(400,4,400))
  local chief={npc=npc,root=npc.PrimaryPart};chiefs[gang]=chief;f.advance(4)
  return chief,chief.root:FindFirstChild('BancoReceptador')
 end
 f.assertClean=function()
  check(#f.warnings==0,'no runtime warnings'..(#f.warnings>0 and ': '..table.concat(f.warnings,' | ') or ''))
 end
 return f
end

local f=fixture()
local p=f.newPlayer(1,'Teste')
check(f.bank~=nil,'real BankBuilder constructs bank')
check(f.prompt('Pegar o crachá emprestado').Enabled,'badge is enabled on server')
check(f.prompt('Cortar a energia').Parent.Name=='PainelTransformador','transformer interaction is on accessible external panel')
f.use(p,'Pegar o crachá emprestado')
f.use(p,'Cortar a energia')
local status=f.status(p)
check(status.prep.cracha and status.prep.energia,'preparation is recorded for gang')
f.use(p,'Anunciar o assalto')
check(f.status(p).state=='aberto','announcement without equipped gun is refused')
check(f.updates[p].BancoAviso.text:find('arma'),'missing gun explains what to do')
f.gun(p)
f.use(p,'Anunciar o assalto')
check(f.status(p).state=='assalto','armed announcement starts heist')
check(p:GetAttribute('CrachaBanco')==true,'announcer receives prepared badge')
check(#f.calls==0,'power preparation delays police alarm')
f.use(p,'Passar o crachá')
check(f.status(p).phase==3,'badge unlocks restricted area')
f.use(p,'Hackear o sistema');f.complete(p)
f.use(p,'Girar a chave 1');f.use(p,'Girar a chave 2')
check(f.status(p).phase==4,'solo dual keys open basement gate')
f.use(p,'Cortar os lasers');f.complete(p)
check(f.part('Lasers'):GetChildren()[1].Transparency==1,'laser minigame disables lasers')
f.use(p,'Montar a furadeira térmica')
f.advance(f.B.DrillTime+1)
f.use(p,'Girar o volante');f.advance(f.B.DoorOpenTime+1)
check(not f.part('BloqueioCofre').CanCollide,'vault passage opens after drilling and wheel')
-- Conservative collision sweep of a 2 x 5 x 2 character through the vault throat.
local function blockedAt(x,foot,z)
 local found={}
 local v=f.mock.Vector3.new(x,foot+2.6,z)
 for _,d in ipairs(f.bank:GetDescendants())do
  if d:IsA('BasePart') and d.CanCollide and d.Name~='DegrauCofre' and d.Name~='Soleira' and d.Name~='ChaoCofre' then
   local pos=d.CFrame:PointToObjectSpace(v)
   local h=d.Size/2
   -- Conservative oriented-box bounds for a vertical avatar; ignore contact under feet.
   if math.abs(pos.X)<h.X+0.95 and math.abs(pos.Y)<h.Y+2.45 and math.abs(pos.Z)<h.Z+0.95 then
    table.insert(found,d.Name)
   end
  end
 end
 return found
end
local previousTop
for i=0,32 do
 local z=34.5+i*.5
 local top=-17.3
 for _,d in ipairs(f.bank:GetDescendants())do
  if d.Name=='DegrauCofre' or d.Name=='Soleira' or d.Name=='ChaoCofre' then
   if z>=d.Position.Z-d.Size.Z/2-.01 and z<=d.Position.Z+d.Size.Z/2+.01 then top=math.max(top,d.Position.Y+d.Size.Y/2)end
  end
 end
 if previousTop then assert(math.abs(top-previousTop)<=.65,"vault stair requires jumping") end
 previousTop=top
 local hit=blockedAt(-2.4,top,z)
 assert(#hit==0,('vault path blocked at z=%.2f floor=%.2f: %s'):format(z,top,table.concat(hit,',')))
end
check(true,'continuous collision-free walking route into and out of vault')
f.use(p,'Pegar maços de dinheiro')
local value=p:GetAttribute('MaloteBanco')
check(value and value>0,'vault loot enters bag')
f.use(p,'Plantar o C4');f.advance(f.B.TunnelFuse+1)
check(not f.part('ParedeTunel').CanCollide,'tunnel wall opens')
f.use(p,'Subir pelo bueiro')
check((p.Character.PrimaryPart.Position-f.part('PontoBueiro').Position).Magnitude<1,'tunnel exit reaches surface')
local chief,prompt=f.chief('Teste')
f.assertClean()
f.use(p,prompt)
check(f.earned[p]==value and not p:GetAttribute('MaloteBanco'),'escape and fence pay once, clear bag')
f.use(p,prompt)
check(f.earned[p]==value,'fence refuses duplicate payout')
f.advance(32)
check(f.status(p).state=='fechado','heist closes after crew leaves')
f.advance(f.B.Cooldown+1)
f.use(p,'Pegar o crachá emprestado')
f.use(p,'Cortar a energia')
check(f.status(p).state=='aberto','bank and preparation work again after cooldown')
f.assertClean()

-- Guard against invalid requests and interrupted interactions.
local a=fixture({noNpcs=true})
local robber=a.newPlayer(11,'A')
local visitor=a.newPlayer(12,nil)
a.gun(visitor)
a.use(visitor,'Anunciar o assalto')
check(a.status(visitor).state=='aberto' and a.notices[visitor]:find('gangue'),'visitor gets gang requirement instead of a silent failure')
local nonGun=a.mock.env.Instance.new('Tool');nonGun.Parent=robber.Character
local gun=a.gun(robber)
local start=a.prompt('Anunciar o assalto')
a.at(robber,start.Parent);start.PromptButtonHoldBegan:Fire(robber);a.advance(.1);start.PromptButtonHoldEnded:Fire(robber);a.advance(1);start.Triggered:Fire(robber)
check(a.status(robber).state=='aberto','cancelled hold cannot announce')
a.at(robber,start.Parent);start.PromptButtonHoldBegan:Fire(robber);a.advance(1.1);a.move(robber,400,400);start.Triggered:Fire(robber)
check(a.status(robber).state=='aberto','distant announcement is rejected by server')
robber:SetAttribute('Caido',true);a.use(robber,'Anunciar o assalto')
check(a.status(robber).state=='aberto','downed player cannot announce')
robber:SetAttribute('Caido',nil);robber:SetAttribute('Job','Policial');a.use(robber,'Anunciar o assalto')
check(a.status(robber).state=='aberto','police cannot announce')
robber:SetAttribute('Job',nil)
a.use(robber,'Pegar o crachá emprestado')
check(a.status(robber).prep.cracha~=nil,'badge works even when avatar creation fails')
a.use(robber,'Anunciar o assalto')
check(a.status(robber).state=='assalto','equipped gun is recognized alongside another tool')
local wheel=a.prompt('Girar o volante');wheel.PromptButtonHoldBegan:Fire(robber);a.advance(4);wheel.Triggered:Fire(robber)
check(a.part('BloqueioCofre').CanCollide,'vault cannot be opened before drill stage')
a.use(robber,'Passar o crachá')
a.use(robber,'Hackear o sistema');a.move(robber,400,400);a.complete(robber)
a.at(robber,'TerminalSeguranca')
check(a.status(robber).goalText:find('Hackeie'),'walking away cancels minigame completion')
a.use(robber,'Hackear o sistema');a.complete(robber)
a.use(robber,'Girar a chave 1');a.advance(a.B.SoloDualWindow+1);a.use(robber,'Girar a chave 2')
check(a.status(robber).phase==3,'expired solo key does not unlock gate')
a.use(robber,'Girar a chave 1')
check(a.status(robber).phase==4,'expired key pair can be retried')
-- Service exit occupancy and repeated-opening timer.
a.use(robber,'Abrir a saída de serviço');a.advance(7)
check(not a.part('SaidaServico').CanCollide,'service exit stays open while player occupies doorway')
a.at(robber,'TerminalSeguranca');a.advance(1)
check(a.part('SaidaServico').CanCollide,'service exit closes after player clears doorway')
a.use(robber,'Abrir a saída de serviço');a.advance(3);a.use(robber,'Abrir a saída de serviço')
a.at(robber,'TerminalSeguranca');a.advance(2)
check(not a.part('SaidaServico').CanCollide,'old close timer cannot cancel a renewed exit opening')
a.assertClean()

-- Multiplayer keys require two distinct participants, and other gangs cannot hack.
local c=fixture({noNpcs=true})
local one=c.newPlayer(21,'C');local two=c.newPlayer(22,'C');local rival=c.newPlayer(23,'D')
c.gun(one);c.at(two,'PontoAnuncio');c.use(one,'Anunciar o assalto')
c.use(one,'Arrombar a porta')
c.use(rival,'Hackear o sistema')
check(c.mini[rival]==nil,'rival gang cannot advance another gang heist')
c.use(one,'Hackear o sistema');c.complete(one)
c.use(one,'Girar a chave 1');c.use(one,'Girar a chave 2')
check(c.status(one).phase==3,'same player cannot satisfy multiplayer dual control')
c.use(one,'Girar a chave 1');c.use(two,'Girar a chave 2')
check(c.status(one).phase==4,'two participants unlock dual control')
c.assertClean()

local function toVault(case,id)
 local t=fixture({event=case,noNpcs=true});local p=t.newPlayer(id,'Event')
 t.gun(p);t.use(p,'Pegar o crachá emprestado');t.use(p,'Anunciar o assalto');t.use(p,'Passar o crachá')
 t.use(p,'Hackear o sistema');t.complete(p);t.use(p,'Girar a chave 1');t.use(p,'Girar a chave 2')
 t.use(p,'Cortar os lasers');t.complete(p);t.use(p,'Montar a furadeira térmica')
 return t,p
end
local jam,j=toVault('Furadeira',31)
jam.advance(jam.B.DrillTime+1)
check(jam.status(j).jam==true and not jam.prompt('Girar o volante').Enabled,'jam pauses drill and blocks premature opening')
jam.use(j,'Destravar a furadeira');jam.complete(j);jam.advance(jam.B.DrillTime+1)
jam.use(j,'Girar o volante');jam.advance(jam.B.DoorOpenTime+1)
check(not jam.part('BloqueioCofre').CanCollide,'drill recovers after jam minigame')
jam.assertClean()
local door,d=toVault('Teimosa',32)
door.advance(door.B.DrillTime+1);door.use(d,'Girar o volante');door.advance(door.B.DoorOpenTime+1)
door.use(d,'Pegar maços de dinheiro');door.at(d,'AlavancaEmergencia');door.advance(27)
check(door.part('BloqueioCofre').CanCollide,'stubborn-door event closes the vault')
door.use(d,'Puxar a alavanca');door.advance(door.B.DoorOpenTime+1)
check(not door.part('BloqueioCofre').CanCollide,'emergency lever releases trapped player')
door.assertClean()

local delayed=fixture({npcDelay=3})
local lag=delayed.newPlayer(40,'Lag');delayed.gun(lag)
delayed.use(lag,'Pegar o crachá emprestado');delayed.use(lag,'Anunciar o assalto');delayed.advance(30)
check(delayed.status(lag).state=='assalto','slow NPC loading does not block initiation')
delayed.assertClean()
local fallback=fixture({fallback=true,noNpcs=true})
check(fallback.prompt('Anunciar o assalto').Enabled,'bank also initializes with fallback vault')
fallback.assertClean()

-- Stale minigames may not modify a later robbery.
local stale=fixture({noNpcs=true})
local old=stale.newPlayer(50,'Old');stale.gun(old)
stale.use(old,'Anunciar o assalto');stale.use(old,'Arrombar a porta');stale.use(old,'Hackear o sistema')
local callback=stale.mini[old].done;stale.mini[old]=nil
stale.move(old,400,400);stale.advance(stale.B.AbandonTime+2);stale.advance(stale.B.Cooldown+1)
stale.use(old,'Anunciar o assalto');stale.use(old,'Arrombar a porta');stale.at(old,'TerminalSeguranca');callback()
check(stale.status(old).goalText:find('Hackeie'),'old minigame completion cannot advance a new robbery')
stale.assertClean()

-- Filling a bag and moving away while a swap dialog is open must not discard loot.
for i=1,13 do
 local q
 for _,x in ipairs(door.bank:GetDescendants())do
  if x.ClassName=='ProximityPrompt' and x.ActionText=='Pegar maços de dinheiro' and x:GetAttribute('Ativo') then q=x;break end
 end
 door.use(d,assert(q))
end
check(door.updates[d].BancoBolsa.slots==door.B.BagSlots,'bag respects its configured capacity')
door.use(d,'Abrir cofrinho');door.complete(d)
check(door.updates[d].BancoAchado~=nil,'full bag offers a swap')
local before=d:GetAttribute('MaloteBanco')
door.at(d,'TerminalSeguranca');door.request(d,'Trocar')
check(d:GetAttribute('MaloteBanco')==before,'distant swap neither awards nor discards loot')
door.use(d,'Abrir cofrinho');door.complete(d);door.request(d,'Trocar')
check(door.updates[d].BancoBolsa.slots==door.B.BagSlots,'valid nearby swap keeps bag capacity')
local after=d:GetAttribute('MaloteBanco');door.request(d,'Trocar')
check(d:GetAttribute('MaloteBanco')==after,'swap dialog cannot be accepted twice')
door.assertClean()

-- Actual BankController: prompt filtering, late replication and UI startup.
local ui=fixture({noNpcs=true})
local m=ui.mock
local localPlayer=ui.newPlayer(60,'UI')
m.services.Players.LocalPlayer=localPlayer
m.Workspace.DescendantAdded=ui.signal()
m.services.ProximityPromptService={PromptButtonHoldBegan=ui.signal(),PromptButtonHoldEnded=ui.signal()}
m.services.UserInputService={InputBegan=ui.signal()}
m.services.RunService.RenderStepped=ui.signal()
local gui=m.env.Instance.new('PlayerGui')
local find=localPlayer.FindFirstChild
localPlayer.FindFirstChild=function(self,name)return name=='PlayerGui'and gui or find(self,name)end
local remotes=m.env.Instance.new('Folder');remotes.Name='Remotes';remotes.Parent=m.services.ReplicatedStorage
local request=m.env.Instance.new('RemoteEvent');request.Name='BankRequest';request.Parent=remotes
local requested=0
request.FireServer=function()requested+=1 end
local buttons={}
for name,value in pairs({HudController={toast=function()end,setHeistTask=function()end},UIScaler={onChanged=function(fn)fn(1)end},
 MobileButtons={add=function(id,data)buttons[id]=data end,show=function()end},MochilaController={offer=function()end,update=function()end},JewelryController={playGrab=function()end}})do
 m.load(name,'return {}',true);m.registry[name]=value
end
local controller=m.load('BankController',SOURCES.BankController,true)
controller.init()
check(gui:FindFirstChild('BancoUI')~=nil,'actual BankController builds UI without runtime errors')
check(requested==0,'initial status request waits for bootstrap listener')
ui.advance(0)
check(requested==1,'deferred status request fires')
local announcement=ui.prompt('Anunciar o assalto')
check(announcement.Enabled,'robber sees announcement')
localPlayer:SetAttribute('Job','Policial')
check(not announcement.Enabled,'police client hides robbery prompts')
localPlayer:SetAttribute('Job',nil);localPlayer:SetAttribute('Caido',true)
check(not announcement.Enabled,'downed client hides prompts')
localPlayer:SetAttribute('Caido',nil);localPlayer:SetAttribute('Gang',nil)
check(announcement.Enabled,'new player can request explanation without joining gang first')
localPlayer:SetAttribute('Gang','UI')
local card=ui.prompt('Passar o crachá');local force=ui.prompt('Arrombar a porta');local inside=ui.prompt('Abrir por dentro')
card:SetAttribute('Ativo',true);force:SetAttribute('Ativo',true);inside:SetAttribute('Ativo',true)
ui.at(localPlayer,'PontoAnuncio');m.services.RunService.RenderStepped:Fire(.2)
check(not card.Enabled and force.Enabled and not inside.Enabled,'outside player sees forcing action, not unusable inside action')
localPlayer:SetAttribute('CrachaBanco',true)
check(card.Enabled and not force.Enabled,'badge holder sees card reader instead of forcing prompt')
ui.at(localPlayer,'AreaRestrita');m.services.RunService.RenderStepped:Fire(.2)
check(inside.Enabled,'inside opening becomes available on restricted side')
localPlayer:SetAttribute('Job','Policial')
announcement.Enabled=true
check(not announcement.Enabled,'server Enabled replication cannot bypass client role filter')
localPlayer:SetAttribute('Job',nil)
controller.handle('BancoStatus',{state='aberto',phase=1,prep={},events={},startPos=ui.part('PontoAnuncio').Position})
m.services.RunService.RenderStepped:Fire(.2)
check(gui:FindFirstChild('PainelBanco',true).Visible,'preparation panel renders received status')
ui.assertClean()

print('TOTAL '..passed..' checks passed')
