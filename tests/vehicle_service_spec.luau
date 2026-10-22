-- Execute actual VehicleService and CarBuilder with controlled role authority,
-- spatial-query responses and seats. Does not simulate driving or engine physics.
return function(mockSource,fixtureSource,gameConfigSource,carBuilderSource,vehicleSource)
 local count=0;local function check(value,message)count+=1;assert(value,message)end
 local makeFixture=assert(loadstring(fixtureSource))()
 local function fixture()
  local f=makeFixture(mockSource);local m=f.mock;local p=f.player(1,false)
  m.load('GameConfig',gameConfigSource)
  m.load('RigMeasure','return {}')
  m.load('ZoneService','return {}',true);m.registry.ZoneService={zoneAt=function()return nil end,isInside=function()return false end,onChange=function()end}
  m.load('SeatService','return {}',true);m.registry.SeatService={setup=function()end}
  local roles,listeners={},{}
  local work={hasRole=function(player,role)return roles[player]==role end,onChanged=function(fn)table.insert(listeners,fn)end}
  m.load('WorkRoleService','return {}',true);m.registry.WorkRoleService=work
  local function setRole(player,role)local before=roles[player];roles[player]=role;for _,fn in ipairs(listeners)do fn(player,role,before)end end
  m.load('CarBuilder',carBuilderSource,true)
  local service=m.load('VehicleService',vehicleSource,true)
  local messages={};local request={OnServerEvent=f.signal()}
  service.init({UIUpdate={FireClient=function(_,player,kind,data)table.insert(messages,{player=player,kind=kind,data=data})end},VehicleRequest=request})
  local pad=f.instance('Part');pad.CFrame=m.CFrame.new(20,0.8,0);pad.Parent=m.Workspace
  local policePad=f.instance('Part');policePad.CFrame=m.CFrame.new(120,0.8,0);policePad.Parent=m.Workspace
  local personalPad=f.instance('Part');personalPad.CFrame=m.CFrame.new(220,0.8,0);personalPad.Parent=m.Workspace
  local taxiPrompt,policePrompt,garagePrompt=f.prompt(0),f.prompt(100),f.prompt(200)
  service.configureWorkplaces({Taxista={vehiclePrompts={taxiPrompt},vehicleSpawns={pad}},Policial={vehiclePrompts={policePrompt},vehicleSpawns={policePad}}},{prompt=garagePrompt,spawns={personalPad}})
  f.player1,f.service,f.request,f.setRole,f.taxiPrompt,f.policePrompt,f.garagePrompt=p,service,request,setRole,taxiPrompt,policePrompt,garagePrompt
  return f
 end
 local f=fixture();local p,s=f.player1,f.service;local m=f.mock
 p:SetAttribute('WorkRole','Taxista');p:SetAttribute('TaxiDuty',true)
 check(not s.requestWorkVehicle(p,'Taxista'),'forged role attributes cannot obtain taxi')
 f.setRole(p,'Taxista');f.move(p,50)
 check(not s.requestWorkVehicle(p,'Taxista'),'taxi may only be picked up at job garage')
 f.move(p,0)
 local obstacle=f.instance('Part');m.Workspace.GetPartBoundsInBox=function()return{obstacle}end
 check(not s.requestWorkVehicle(p,'Taxista'),'blocked pad refuses pickup')
 f.advance(1.1);m.Workspace.GetPartBoundsInBox=function()return{}end
 check(s.requestWorkVehicle(p,'Taxista'),'employed taxi driver gets local work car')
 local c=s.getCar(p)
 check(c and c.role=='Taxista'and c.model:GetAttribute('WorkRole')=='Taxista','taxi record and model are rolebound')
 check(c.model:GetAttribute('Owner')==p.UserId,'car ownership belongs to actual player')
 check(c.model:GetAttribute('DoorStyle')=='Sedan','work vehicle is company sedan')
 check(c.spec.Name=='LXR Táxis' or string.find(c.spec.Name,'LXR')~=nil,'company taxi model selected')
 check(c.model:FindFirstChild('DriverSeat',true)and c.passenger,'driver and passenger seats exist')
 check(c.model.PrimaryPart:FindFirstChildOfClass('LinearVelocity')and c.model.PrimaryPart:FindFirstChildOfClass('AlignOrientation'),'actual arcade driving actuators retained')
 check(s.isDrivingWorkVehicle(p,'Taxista'),'actual driver of company taxi recognized')
 check(not s.isDrivingWorkVehicle(p,'Policial'),'taxi cannot pass for police car')
 local old=c.model
 p.Character:FindFirstChildOfClass('Humanoid').SeatPart=nil;c.driver.Occupant=nil
 f.move(p,500);f.advance(2.1);f.request.OnServerEvent:Fire(p,'ToggleCar')
 check(s.getCar(p).model==old,'V away from workplace cannot relocate a work car')
 local intruder=f.player(2,false);intruder.Character:FindFirstChildOfClass('Humanoid').SeatPart=c.driver
 c.driver.Occupant=intruder.Character:FindFirstChildOfClass('Humanoid')
 check(intruder.Character:FindFirstChildOfClass('Humanoid').Sit==false,'another player cannot drive leased car')
 c.driver.Occupant=nil
 f.setRole(p,nil)
 check(s.getCar(p)==nil and old.Parent==nil,'leaving role removes company car immediately')
 f.setRole(p,'Policial');f.move(p,100);f.advance(1.1)
 check(s.requestWorkVehicle(p,'Policial'),'police on duty gets local police sedan')
 c=s.getCar(p);check(c.role=='Policial'and c.model:GetAttribute('Spec')==c.spec.Name,'police record uses its own car spec')
 check(c.model:FindFirstChild('PoliceRed',true) and c.model:FindFirstChild('PoliceBlue',true),'police lightbar has colored lighting')
 p.Character:FindFirstChildOfClass('Humanoid').SeatPart=nil;c.driver.Occupant=nil
 f.move(p,200);f.advance(1.1)
 check(s.requestPersonalAtGarage(p),'fuel station can retrieve granted personal vehicle')
 c=s.getCar(p)
 check(c.role==nil and c.spec.Name==m.registry.GameConfig.Cars[m.registry.GameConfig.CarModel].Name,'fuel garage never grants taxi or police vehicle')
 f.setRole(p,nil);check(s.getCar(p)==c,'leaving role keeps civilian car')
 p:SetAttribute('StunnedUntil',f.now()+6);f.move(p,100);f.setRole(p,'Policial');f.advance(1)
 check(not s.requestWorkVehicle(p,'Policial'),'stunned character cannot pick up role vehicle')
 p:SetAttribute('StunnedUntil',nil);p:SetAttribute('Detained',true)
 check(not s.requestPersonalAtGarage(p),'detained character cannot retrieve car')
 p:SetAttribute('Detained',false);p.Character:FindFirstChildOfClass('Humanoid').SeatPart=nil;c.driver.Occupant=nil;f.move(p,100);f.advance(1.1);check(s.requestWorkVehicle(p,'Policial'),'setup vehicle for death cleanup')
 local doomed=s.getCar(p).model;p.Character:FindFirstChildOfClass('Humanoid').Died:Fire()
 check(s.getCar(p)==nil and doomed.Parent==nil,'death removes leased vehicle')
 -- A deployed strip changes the actual controller velocity, expires, and cannot
 -- be used on officers, passengers or forged/unregistered models.
 local slow=fixture();local sp,vs=slow.player1,slow.service;local sm=slow.mock
 slow.move(sp,200);check(vs.requestPersonalAtGarage(sp),'personal car for strip scenario')
 local sc=vs.getCar(sp);local chassis=sc.model.PrimaryPart
 chassis.AssemblyLinearVelocity=sm.Vector3.new(60,3,0)
 local drive=chassis:FindFirstChildOfClass('LinearVelocity');drive.VectorVelocity=sm.Vector3.new(85,-2,0)
 check(not vs.applyPoliceSlow(sp,0/0) and not vs.applyPoliceSlow(sp,-2),'invalid slow duration rejected')
 check(vs.applyPoliceSlow(sp,2),'registered civilian driver can be slowed')
 check(chassis.AssemblyLinearVelocity.X==12 and chassis.AssemblyLinearVelocity.Y==3,'server reduces horizontal speed without cancelling vertical support')
 check(drive.VectorVelocity.X==12 and drive.VectorVelocity.Y==-2,'driving actuator also capped')
 check(sc.model:GetAttribute('PoliceSlowUntil')==slow.now()+2,'client receives deadline for controller')
 chassis.AssemblyLinearVelocity=sm.Vector3.new(90,0,0);slow.advance(0.15)
 check(chassis.AssemblyLinearVelocity.X==12,'server repeats cap while effect is active')
 slow.advance(2)
 check(sc.model:GetAttribute('PoliceSlowUntil')==nil,'slow effect clears after deadline')
 slow.setRole(sp,'Policial')
 check(not vs.applyPoliceSlow(sp,3) and not vs.ejectFromVehicle(sp),'police immune to strip and cuff ejection')
 slow.setRole(sp,nil)
 check(vs.ejectFromVehicle(sp) and sp.Character:FindFirstChildOfClass('Humanoid').Sit==false,'cuff ejection releases actual registered occupant')
 sp.Character:FindFirstChildOfClass('Humanoid').SeatPart=nil
 check(not vs.applyPoliceSlow(sp,3) and not vs.ejectFromVehicle(sp),'on-foot character is not treated as driver')
 print('PASS VehicleService: '..count..' lifecycle checks (mock services, actual CarBuilder)')
end
