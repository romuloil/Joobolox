-- Actual TaxiService with controlled time, role/vehicle authority and NPC factory.
-- Validates server trip/payment decisions, not Roblox driving/replication/animation.
return function(mockSource,fixtureSource,configSource,rulesSource,serviceSource)
 local checks=0;local function check(value,name)checks+=1;assert(value,name)end
 local makeFixture=assert(loadstring(fixtureSource))()
 local function fixture(options)
  options=options or{}
  local f=makeFixture(mockSource);local m=f.mock;local p=f.player(1,false)
  m.load('GameConfig',"return {Remotes={UIUpdate='UIUpdate',TaxiRequest='TaxiRequest'}}")
  m.load('TaxiConfig',configSource);m.load('TaxiRules',rulesSource)
  local roles,listeners,cars={},{},{}
  local role={}
  function role.hasRole(player,name)return roles[player]==name end
  function role.assign(player,name)if roles[player]and roles[player]~=name then return false end;local old=roles[player];roles[player]=name;for _,fn in ipairs(listeners)do fn(player,name,old)end;return true end
  function role.clear(player,expected)if expected and roles[player]~=expected then return false end;local old=roles[player];roles[player]=nil;for _,fn in ipairs(listeners)do fn(player,nil,old)end;return true end
  function role.onChanged(fn)table.insert(listeners,fn)end
  local destroyedCars=0
  local vehicle={getCar=function(player)return cars[player]end,isDrivingWorkVehicle=function(player,name)
   local c=cars[player];local h=player.Character and player.Character:FindFirstChildOfClass('Humanoid')
   return c~=nil and c.role==name and role.hasRole(player,name)and h and h.SeatPart==c.driver,c
  end,destroyWorkVehicle=function(player,name)
   local c=cars[player];if c and c.role==name then cars[player]=nil;c.model:Destroy();destroyedCars+=1 end
  end}
  local spawned,spawnOptions={},{}
  m.load('NPCKit','return {}',true)
  m.registry.NPCKit={spawn=function(cf,opts)
   if options.noNPC then return nil end
   local npc=f.character(false);npc.Name='Passageiro LXR';npc:PivotTo(cf+m.Vector3.new(0,3.1,0))
   table.insert(spawned,npc);table.insert(spawnOptions,opts)
   if f.onSpawn then f.onSpawn()end
   return npc
  end,say=function()end,emote=function()end}
  local payments,bonus={},0
  m.load('EconomyService','return {}',true)
  m.registry.EconomyService={getMoney=function()return options.noData and nil or 100 end,add=function(player,amount,reason)
   table.insert(payments,{player=player,amount=amount,reason=reason});if f.onPayment then f.onPayment()end;return not options.failPayment
  end}
  m.load('DailyBonusService','return {}',true);m.registry.DailyBonusService={tryClaim=function()bonus+=1;return 0 end}
  local service=m.load('TaxiService',serviceSource,true)
  local sites={dutyPrompt=f.prompt(0),dispatchPrompt=f.prompt(0),pickupPoints={}}
  for i,x in ipairs({300,600,900})do
   table.insert(sites.pickupPoints,{name='Ponto '..i,position=m.Vector3.new(x,0,0),cf=m.CFrame.new(x,0,0)})
  end
  sites.destinations=sites.pickupPoints
  local messages={};local request={OnServerEvent=f.signal()}
  service.init({UIUpdate={FireClient=function(_,player,kind,data)table.insert(messages,{player=player,kind=kind,data=data})end},TaxiRequest=request},sites,
   {vehicleService=vehicle,workRoleService=role,beforeDuty=function(player)
    if options.failPreparation then error('expected failure')end
    role.clear(player)
   end})
  local function car(player)
   local model=f.instance('Model');model.Name='LXR';model.Parent=m.Workspace
   local root=f.instance('Part');root.Name='Chassis';root.CFrame=m.CFrame.new(0,2,0);root.Parent=model;model.PrimaryPart=root
   local driver=f.instance('VehicleSeat');driver.Name='DriverSeat';driver.CFrame=root.CFrame;driver.Parent=model
   local passenger=f.instance('Seat');passenger.Name='PassengerSeat';passenger.CFrame=root.CFrame*m.CFrame.new(1.65,0,-.9);passenger.Parent=model
   local c={model=model,driver=driver,passenger=passenger,role='Taxista',spec={MaxSpeed=76}}
   cars[player]=c;player.Character:FindFirstChildOfClass('Humanoid').SeatPart=driver
   return c
  end
  local function state(player)
   for i=#messages,1,-1 do local msg=messages[i];if msg.player==player and msg.kind=='TaxiState'then return msg.data end end
  end
  local function point(name)for _,q in ipairs(sites.pickupPoints)do if q.name==name then return q.position end end end
  local function drive(player,target)
   local c=cars[player];local start=c.model.PrimaryPart.Position;local n=math.max(1,math.ceil((target-start).Magnitude/20))
   for i=1,n do
    local pos=start:Lerp(target,i/n)
    c.model.PrimaryPart.CFrame=m.CFrame.new(pos);c.passenger.CFrame=m.CFrame.new(pos+m.Vector3.new(1.65,0,-.9))
    f.move(player,pos.X,pos.Z);f.advance(.5)
   end
  end
  f.p,f.service,f.sites,f.role,f.cars,f.car,f.state,f.point,f.drive=p,service,sites,role,cars,car,state,point,drive
  f.payments,f.spawned,f.spawnOptions,f.request=payments,spawned,spawnOptions,request
  f.bonus=function()return bonus end;f.destroyedCars=function()return destroyedCars end
  f.advance(0)
  return f
 end
 local f=fixture();local p,s=f.p,f.service
 p:SetAttribute('TaxiDuty',true);p:SetAttribute('WorkRole','Taxista')
 check(not s.accept(p),'forged duty attrs cannot obtain trip')
 f.move(p,50);check(not s.join(p),'duty requires LXR desk')
 f.move(p,0);check(s.join(p),'join near desk succeeds')
 check(f.role.hasRole(p,'Taxista')and s.isOnDuty(p),'taxi role and service agree')
 check(s.join(p)and f.state(p).count==1,'repeat duty does not consume slot')
 local second=f.player(2,false);local third=f.player(3,false)
 check(s.join(second),'second taxi slot available')
 check(not s.join(third),'third taxi slot denied')
 check(s.leave(second)and s.join(third),'leaving makes slot available')
 check(not s.accept(p),'cannot accept without company taxi')
 local c=f.car(p);f.advance(1.1)
 check(s.accept(p),'dispatch reserves actual trip')
 check(not s.accept(p),'cannot accept second concurrent trip')
 check(f.state(p).stage=='pickup'and#f.spawned==1,'one passenger spawned for pickup')
 check(f.spawnOptions[1].anchored==true and not f.spawnOptions[1].important,'passenger uses normal NPC factory/budget')
 check(not s.dropoff(p),'cannot pay before boarding')
 check(not s.pickup(p),'far pickup refused')
 local pick=f.point(f.state(p).pickupName);f.drive(p,pick)
 c.model.PrimaryPart.AssemblyLinearVelocity=f.mock.Vector3.new(6,0,0)
 check(not s.pickup(p),'moving taxi cannot board')
 c.model.PrimaryPart.AssemblyLinearVelocity=f.mock.Vector3.zero;f.advance(.6)
 local hum=p.Character:FindFirstChildOfClass('Humanoid');hum.SeatPart=nil
 check(not s.pickup(p),'passenger only boards actual driver')
 hum.SeatPart=c.driver;f.advance(.6)
 check(s.pickup(p),'parked owner boards waiting passenger')
 check(c.passenger:GetAttribute('TaxiPassengerReserved')==true,'NPC reserves passenger seat')
 check(f.state(p).stage=='dropoff','boarding changes trip state')
 check(not s.pickup(p),'boarding cannot be repeated')
 local dest=f.point(f.state(p).destinationName);f.drive(p,dest)
 local paidDuringCallback
 f.onPayment=function()paidDuringCallback=s.dropoff(p)end
 check(s.dropoff(p),'valid traveled route pays fare')
 check(#f.payments==1 and f.payments[1].amount>25,'one server-computed fare paid')
 check(f.bonus()==1,'daily bonus attempted after successful payment')
 check(not paidDuringCallback,'payment callback cannot reenter resolved trip')
 check(not c.passenger:GetAttribute('TaxiPassengerReserved'),'completed trip releases passenger seat')
 f.advance(1);check(not s.dropoff(p)and#f.payments==1,'repeated arrival cannot pay twice')
 check(f.state(p).stage=='idle','completed trip clears active stage')
 f.advance(3);check(f.spawned[1].Parent==nil,'completed NPC cleaned up')
 check(s.leave(p)and not f.role.hasRole(p,'Taxista')and f.cars[p]==nil,'leaving returns role and taxi')

 local teleport=fixture();local tp,ts=teleport.p,teleport.service
 ts.join(tp);local tc=teleport.car(tp);check(ts.accept(tp),'setup teleport test')
 tc.model.PrimaryPart.CFrame=teleport.mock.CFrame.new(teleport.point(teleport.state(tp).pickupName))
 teleport.advance(.26)
 check(teleport.state(tp).stage=='idle'and#teleport.payments==0,'teleport cancels trip without payment')
 check(teleport.spawned[1].Parent==nil,'canceled teleport removes passenger')

 local stolen=fixture();local sp,ss=stolen.p,stolen.service
 ss.join(sp);local sc=stolen.car(sp);ss.accept(sp);stolen.drive(sp,stolen.point(stolen.state(sp).pickupName));ss.pickup(sp)
 sc.passenger.Occupant=stolen.player(2,false).Character:FindFirstChildOfClass('Humanoid')
 stolen.advance(.26)
 check(stolen.state(sp).stage=='idle'and#stolen.payments==0,'human occupying NPC seat cancels trip')
 check(not sc.passenger:GetAttribute('TaxiPassengerReserved'),'cancellation releases reserved seat')

 local death=fixture();local dp,ds=death.p,death.service
 ds.join(dp);death.car(dp);ds.accept(dp);dp.CharacterAdded:Fire(dp.Character)
 check(not ds.isOnDuty(dp)and death.role.hasRole(dp,'Taxista')==false,'respawn cleans taxi employment')
 check(death.state(dp).stage=='idle'and death.spawned[1].Parent==nil,'respawn cancels passenger')

 local async=fixture();local ap,as=async.p,async.service
 as.join(ap);async.car(ap);async.onSpawn=function()as.leave(ap)end
 check(not as.accept(ap),'job loss while creating avatar cancels accept')
 check(async.spawned[1].Parent==nil and not as.isOnDuty(ap),'late avatar cleaned after cancellation')

 local unavailable=fixture({noNPC=true});unavailable.service.join(unavailable.p);unavailable.car(unavailable.p)
 check(not unavailable.service.accept(unavailable.p)and unavailable.state(unavailable.p).stage=='idle','NPC budget/factory failure cleans reservation')
 local failed=fixture({failPreparation=true})
 check(not failed.service.join(failed.p)and failed.state(failed.p).count==0,'preparation failure returns reserved slot')
 print('PASS TaxiService: '..checks..' lifecycle checks (mock services)')
end
