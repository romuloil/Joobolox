-- LXR Táxis: emprego, despacho, passageiro e corrida pagos apenas pelo servidor.
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Workspace=game:GetService("Workspace")
local Shared=ReplicatedStorage:WaitForChild("Shared")
local GameConfig=require(Shared:WaitForChild("GameConfig"))
local Config=require(Shared:WaitForChild("TaxiConfig"))
local Rules=require(Shared:WaitForChild("TaxiRules"))
local Security=require(script.Parent:WaitForChild("SecurityService"))
local NPCKit=require(script.Parent:WaitForChild("NPCKit"))
local Economy=require(script.Parent:WaitForChild("EconomyService"))
local DailyBonus=require(script.Parent:WaitForChild("DailyBonusService"))
local TaxiService={}
local initialized=false
local sites,hooks,ui,request
local duty,trips={},{}
local count,sequence=0,0
local rng=Random.new(5317)
local function now()return Workspace:GetServerTimeNow()end
local function rootOf(player)local _,_,root=Security.getLivingCharacter(player);return root end
local function restricted(player)
 local untilAt=player:GetAttribute("StunnedUntil")
 return player:GetAttribute("Detained")==true or (type(untilAt)=="number" and untilAt>now())
end
local function location(point)
 if point.position then return point.position end
 if point.cf then return point.cf.Position end
 return point.marker and point.marker.Position
end
local function promptPosition(prompt)
 local p=prompt and prompt.Parent
 if p and p:IsA("BasePart")then return p.Position end
 if p and p:IsA("Attachment")then return p.WorldPosition end
end
local function near(player,prompt)
 local root=rootOf(player);local p=promptPosition(prompt)
 return root and p and Rules.point(root.Position) and (root.Position-p).Magnitude<=Config.InteractionDistance
end
local function notice(player,message)
 if player.Parent==Players then ui:FireClient(player,"Notice",{text=message})end
end
local function hasRole(player)
 return duty[player]~=nil and hooks.workRoleService.hasRole(player,"Taxista") and not restricted(player)
end
local function carOf(player)
 local c=hooks.vehicleService.getCar(player)
 return c and c.role=="Taxista" and c.model and c.model.Parent and c.model.PrimaryPart and c or nil
end
local function state(player)
 local trip=trips[player]
 local active=duty[player]~=nil
 local target=trip and (trip.stage=="pickup" and location(trip.pickup)or location(trip.destination))
  or (active and promptPosition(sites.dispatchPrompt) or nil)
 player:SetAttribute("TaxiDuty",active)
 player:SetAttribute("TaxiStage",trip and trip.stage or "idle")
 player:SetAttribute("TaxiTargetPosition",target)
 player:SetAttribute("TaxiPickupName",trip and trip.pickup.name or nil)
 player:SetAttribute("TaxiDestinationName",trip and trip.destination.name or nil)
 player:SetAttribute("TaxiTripId",trip and trip.id or nil)
 if player.Parent==Players then
  ui:FireClient(player,"TaxiState",{onDuty=active,count=count,slots=Config.Slots,stage=trip and trip.stage or "idle",
   target=target,pickupName=trip and trip.pickup.name,destinationName=trip and trip.destination.name,
   tripId=trip and trip.id,fare=trip and trip.fare})
 end
end
local function broadcast()for _,player in ipairs(Players:GetPlayers())do state(player)end end
local function releaseSeat(trip)
 if trip.passengerSeat and trip.passengerSeat.Parent then trip.passengerSeat:SetAttribute("TaxiPassengerReserved",false)end
 trip.passengerSeat=nil
end
local function destroyTrip(trip)
 releaseSeat(trip)
 if trip.folder then trip.folder:Destroy()end
 if trip.npc then trip.npc:Destroy()end
end
function TaxiService.cancel(player,message)
 local trip=trips[player]
 trips[player]=nil
 if trip then destroyTrip(trip)end
 if initialized then state(player)end
 if message and trip then notice(player,message)end
 return trip~=nil
end
function TaxiService.isOnDuty(player)return duty[player]~=nil end
function TaxiService.leave(player,silent)
 if not duty[player]then return false end
 duty[player]=nil;count=math.max(0,count-1)
 TaxiService.cancel(player)
 hooks.workRoleService.clear(player,"Taxista")
 hooks.vehicleService.destroyWorkVehicle(player,"Taxista")
 broadcast()
 if not silent then notice(player,"Turno encerrado. Táxi e uniforme devolvidos à empresa.")end
 return true
end
function TaxiService.join(player)
 if not initialized or player.Parent~=Players or restricted(player)or not rootOf(player)then return false end
 if duty[player]then state(player);return true end
 if not near(player,sites.dutyPrompt)then notice(player,"Entre em serviço no balcão da LXR Táxis.");return false end
 if count>=Config.Slots then notice(player,"As vagas de taxista estão ocupadas.");return false end
 duty[player]={joining=true};count+=1
 if hooks.beforeDuty then
  local ok,err=pcall(hooks.beforeDuty,player)
  if not ok then TaxiService.leave(player,true);warn("[TaxiService] Falha ao preparar turno: "..tostring(err));return false end
 end
 if player.Parent~=Players or not duty[player]or restricted(player)or not rootOf(player)then
  TaxiService.leave(player,true);return false
 end
 local accepted=hooks.workRoleService.assign(player,"Taxista")
 if not accepted then TaxiService.leave(player,true);notice(player,"Encerre seu outro emprego antes de entrar na LXR.");return false end
 if not duty[player]then return false end
 duty[player].joining=false
 broadcast()
 notice(player,"Bem-vindo à LXR! Retire uniforme e táxi na empresa e pegue uma corrida no despacho.")
 return true
end
local function missionFolder()
 local parent=Workspace:FindFirstChild("TaxiMissions")
 if not parent then parent=Instance.new("Folder");parent.Name="TaxiMissions";parent.Parent=Workspace end
 local f=Instance.new("Folder");f.Name="Corrida"..sequence;f.Parent=parent;return f
end
local function tripPrompt(folder,trip,point,stage)
 local p=Instance.new("Part");p.Name="Taxi"..stage.."Point";p.Anchored=true;p.Size=Vector3.new(1,1,1)
 p.CFrame=CFrame.new(location(point)+Vector3.new(0,2,0));p.Transparency=1;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.Parent=folder
 local prompt=Instance.new("ProximityPrompt");prompt.Name=stage=="pickup" and "TaxiPickupPrompt"or"TaxiDropoffPrompt"
 prompt.ActionText=stage=="pickup" and "Embarcar passageiro"or"Concluir corrida";prompt.ObjectText=point.name
 prompt.MaxActivationDistance=Config.ServiceRadius;prompt.RequiresLineOfSight=false;prompt.HoldDuration=0.5;prompt.KeyboardKeyCode=Enum.KeyCode.E
 prompt:SetAttribute("TaxiOwnerUserId",trip.player.UserId);prompt:SetAttribute("TaxiTripId",trip.id);prompt:SetAttribute("TaxiStage",stage)
 prompt.Parent=p
 prompt.Triggered:Connect(function(player)
  if player~=trip.player then return end
  if stage=="pickup"then TaxiService.pickup(player)else TaxiService.dropoff(player)end
 end)
 return prompt
end
function TaxiService.accept(player)
 if not hasRole(player)or not near(player,sites.dispatchPrompt)or not Security.checkRate(player,"TaxiAccept",1)then return false end
 if trips[player]then notice(player,"Você já tem uma corrida em andamento.");return false end
 if Economy.getMoney(player)==nil then notice(player,"Aguarde seus dados carregarem para iniciar uma corrida.");return false end
 local c=carOf(player)
 if not c then notice(player,"Retire o táxi da LXR na garagem antes de aceitar uma corrida.");return false end
 local pickups=sites.pickupPoints or {};local destinations=sites.destinations or pickups
 if #pickups<2 or #destinations<2 then return false end
 local pickup=pickups[rng:NextInteger(1,#pickups)]
 local valid={}
 for _,point in ipairs(destinations)do
  if Rules.point(location(point))and (location(point)-location(pickup)).Magnitude>=100 then table.insert(valid,point)end
 end
 if #valid==0 then return false end
 local destination=valid[rng:NextInteger(1,#valid)]
 local distance=(location(destination)-location(pickup)).Magnitude
 local fare=Rules.fare(distance,Config.BaseFare,Config.FarePerStud)
 if not fare then return false end
 -- Reserva a corrida antes de criar um avatar, pois a criação pode ceder execução.
 sequence+=1
 local trip={player=player,id=sequence,stage="pickup",pickup=pickup,destination=destination,fare=fare,
  car=c.model,acceptedAt=now(),lastPosition=c.model.PrimaryPart.Position,lastAt=now(),covered=0,preparing=true}
 trips[player]=trip
 local npc=NPCKit.spawn(pickup.cf or CFrame.new(location(pickup)),{name="Passageiro LXR",anchored=true,showName=true})
 if trips[player]~=trip or not hasRole(player)then if npc then npc:Destroy()end;return false end
 if not npc then TaxiService.cancel(player,"Não foi possível chamar o passageiro agora. Tente novamente no despacho.");return false end
 trip.npc=npc;trip.preparing=false;npc:SetAttribute("TaxiPassengerOwner",player.UserId)
 for _,p in ipairs(npc:GetDescendants())do if p:IsA("BasePart")then p.CanCollide=false;p.CanTouch=false;p.Massless=true end end
 trip.folder=missionFolder();trip.pickupPrompt=tripPrompt(trip.folder,trip,pickup,"pickup");trip.dropoffPrompt=tripPrompt(trip.folder,trip,destination,"dropoff")
 NPCKit.say(npc,"Aguardando meu táxi da LXR!",4)
 state(player);notice(player,"Corrida recebida. Busque o passageiro em "..pickup.name..".")
 return true
end
local function serviceCheck(player,trip,point)
 if not hasRole(player)then return nil end
 local driving,c=hooks.vehicleService.isDrivingWorkVehicle(player,"Taxista")
 if not c then c=carOf(player)end
 if not c or c.model~=trip.car or not c.model.PrimaryPart then return nil end
 local chassis=c.model.PrimaryPart
 if not Rules.point(chassis.Position)or not Rules.point(chassis.AssemblyLinearVelocity)then return nil end
 if not Rules.canServe(true,driving,(chassis.Position-location(point)).Magnitude,chassis.AssemblyLinearVelocity.Magnitude,Config.ServiceRadius)then return nil end
 return c
end
local function seatPassenger(trip,c)
 local npc=trip.npc;local humanoid=npc and npc:FindFirstChildOfClass("Humanoid");local root=npc and npc:FindFirstChild("HumanoidRootPart")
 if not root or not humanoid or not c.passenger or c.passenger.Occupant then return false end
 -- O avatar acompanha o banco como decoração ancorada: nunca solda/ancora o carro.
 local animator=humanoid:FindFirstChildOfClass("Animator")
 if animator then for _,track in ipairs(animator:GetPlayingAnimationTracks())do track:Stop(0)end end
 humanoid.AutoRotate=false;humanoid.PlatformStand=true;root.Anchored=true
 trip.seatedJoints={}
 for _,joint in ipairs(npc:GetDescendants())do
  if joint:IsA("Motor6D")then
   if joint.Name=="LeftHip"or joint.Name=="RightHip"then
    table.insert(trip.seatedJoints,{joint=joint,c0=joint.C0});joint.C0=joint.C0*CFrame.Angles(-math.pi/2,0,0)
   elseif joint.Name=="LeftKnee"or joint.Name=="RightKnee"then
    table.insert(trip.seatedJoints,{joint=joint,c0=joint.C0});joint.C0=joint.C0*CFrame.Angles(math.pi/2,0,0)
   end
  end
 end
 npc:PivotTo(c.passenger.CFrame*CFrame.new(0,1.35,0))
 trip.passengerSeat=c.passenger;c.passenger:SetAttribute("TaxiPassengerReserved",true)
 return true
end
function TaxiService.pickup(player)
 local trip=trips[player]
 if not trip or trip.stage~="pickup"or not Security.checkRate(player,"TaxiPickup",0.5)then return false end
 local c=serviceCheck(player,trip,trip.pickup)
 if not c then notice(player,"Pare o seu táxi perto do passageiro, sentado ao volante.");return false end
 if not trip.npc or not trip.npc.Parent or (trip.npc:GetPivot().Position-location(trip.pickup)).Magnitude>12 then return false end
 if not seatPassenger(trip,c)then notice(player,"O banco do passageiro precisa estar livre.");return false end
 trip.stage="dropoff";trip.boardedAt=now();trip.lastAt=now();trip.lastPosition=c.model.PrimaryPart.Position
 trip.straight=(location(trip.destination)-trip.lastPosition).Magnitude;trip.covered=0;trip.driverMissingAt=nil
 state(player);NPCKit.say(trip.npc,"Pode seguir para "..trip.destination.name..", por favor!",4)
 return true
end
function TaxiService.dropoff(player)
 local trip=trips[player]
 if not trip or trip.stage~="dropoff"or not Security.checkRate(player,"TaxiDropoff",0.5)then return false end
 if not trip.npc or not trip.npc.Parent then TaxiService.cancel(player,"Corrida cancelada: passageiro indisponível.");return false end
 local c=serviceCheck(player,trip,trip.destination)
 if not c then notice(player,"Pare no destino com o seu táxi para concluir a corrida.");return false end
 if not c.passenger or c.passenger.Occupant or not trip.passengerSeat or not trip.passengerSeat.Parent then return false end
 local time=now();local moved=(c.model.PrimaryPart.Position-trip.lastPosition).Magnitude
 local speed=math.min(c.spec and c.spec.MaxSpeed or Config.MaxSpeed,120)
 if not Rules.plausible(moved,time-trip.lastAt,speed)then TaxiService.cancel(player,"Corrida cancelada por deslocamento inválido.");return false end
 if not Rules.canFinish(trip.stage,time-trip.boardedAt,trip.straight,trip.covered+moved,speed,Config.ServiceRadius)then
  notice(player,"A viagem ainda não foi validada. Percorra o trajeto até o destino.");return false
 end
 -- Resolve antes de pagar, impedindo pagamento duplicado por prompt e botão juntos.
 trips[player]=nil
 releaseSeat(trip)
 if trip.folder then trip.folder:Destroy()end
 local npc=trip.npc
 if npc and npc.Parent then
  for _,record in ipairs(trip.seatedJoints or {})do if record.joint.Parent then record.joint.C0=record.c0 end end
  local h=npc:FindFirstChildOfClass("Humanoid");if h then h.PlatformStand=false end
  local point=location(trip.destination)
  npc:PivotTo((trip.destination.cf or CFrame.new(point))+Vector3.new(0,3.1,0))
  NPCKit.say(npc,"Obrigado pela corrida! Até a próxima.",3);NPCKit.emote(npc,"wave")
  task.delay(3,function()if npc.Parent then npc:Destroy()end end)
 end
 local paid=Economy.add(player,trip.fare,"Corrida LXR #"..trip.id)
 local bonus=paid and DailyBonus.tryClaim(player) or 0
 state(player)
 notice(player,paid and ("Corrida concluída: $"..trip.fare..(bonus>0 and (" + bônus diário $"..bonus) or "")..". Volte ao despacho da LXR para outra.")or "Corrida concluída, mas o pagamento não pôde ser registrado. Confira o Output.")
 return paid
end
local function panel(player,kind)
 ui:FireClient(player,"TaxiPanel",{panel=kind,onDuty=duty[player]~=nil,count=count,slots=Config.Slots,stage=trips[player]and trips[player].stage or"idle"})
end
function TaxiService.init(remotes,taxiSites,options)
 if initialized then return end
 sites=assert(taxiSites,"Sede LXR ausente");hooks=options or {}
 assert(hooks.vehicleService and hooks.workRoleService,"Integrações LXR ausentes")
 ui=assert(remotes[GameConfig.Remotes.UIUpdate],"UIUpdate ausente")
 request=assert(remotes[GameConfig.Remotes.TaxiRequest or"TaxiRequest"],"TaxiRequest ausente")
 initialized=true
 sites.dutyPrompt.Enabled=true;sites.dispatchPrompt.Enabled=true
 sites.dutyPrompt.Triggered:Connect(function(player)if near(player,sites.dutyPrompt)then panel(player,"duty")end end)
 sites.dispatchPrompt.Triggered:Connect(function(player)if near(player,sites.dispatchPrompt)and hasRole(player)then panel(player,"dispatch")end end)
 request.OnServerEvent:Connect(function(player,action,payload)
  if not Security.isShortString(action,16)or not Security.checkRate(player,"TaxiRequest",0.2)then return end
  if action=="Duty"then if payload==true then TaxiService.join(player)elseif payload==false then TaxiService.leave(player)end
  elseif action=="Accept"then TaxiService.accept(player)
  elseif action=="Pickup"then TaxiService.pickup(player)
  elseif action=="Dropoff"then TaxiService.dropoff(player)
  elseif action=="Cancel"then TaxiService.cancel(player,"Corrida cancelada. Volte ao despacho para outra.")end
 end)
 local function watchPlayer(player)
  player.CharacterAdded:Connect(function()TaxiService.leave(player,true)end)
  player:GetAttributeChangedSignal("Detained"):Connect(function()if player:GetAttribute("Detained")then TaxiService.leave(player,true)end end)
  task.defer(function()if player.Parent==Players then state(player)end end)
 end
 Players.PlayerAdded:Connect(watchPlayer);for _,player in ipairs(Players:GetPlayers())do watchPlayer(player)end
 Players.PlayerRemoving:Connect(function(player)TaxiService.leave(player,true);TaxiService.cancel(player)end)
 hooks.workRoleService.onChanged(function(player,newRole)if duty[player]and not duty[player].joining and newRole~="Taxista"then TaxiService.leave(player,true)end end)
 task.spawn(function()
  while true do
   local time=now()
   for player,trip in pairs(trips)do
    local c=carOf(player)
    if trip.preparing then
     if not hasRole(player)or not c or c.model~=trip.car or time-trip.acceptedAt>30 then TaxiService.cancel(player,"Não foi possível confirmar o passageiro. Tente novamente no despacho.")
     else
      local position=c.model.PrimaryPart.Position
      local speed=math.min(c.spec and c.spec.MaxSpeed or Config.MaxSpeed,120)
      if not Rules.point(position)or not Rules.plausible((position-trip.lastPosition).Magnitude,time-trip.lastAt,speed)then
       TaxiService.cancel(player,"Corrida cancelada por deslocamento inválido.")
      else trip.lastPosition=position;trip.lastAt=time end
     end
    elseif not hasRole(player)or not c or c.model~=trip.car or not trip.npc or not trip.npc.Parent then
     TaxiService.cancel(player,"Corrida cancelada: o táxi ou o emprego não está mais disponível.")
    elseif time-trip.acceptedAt>Config.TripTimeout then TaxiService.cancel(player,"O passageiro cancelou a corrida por demora.")
    else
     local position=c.model.PrimaryPart.Position;local elapsed=time-trip.lastAt
     local speed=math.min(c.spec and c.spec.MaxSpeed or Config.MaxSpeed,120)
     if not Rules.point(position)or not Rules.plausible((position-trip.lastPosition).Magnitude,elapsed,speed)then
      TaxiService.cancel(player,"Corrida cancelada por deslocamento inválido.")
     else
      if trip.stage=="dropoff"then
       trip.covered+=(position-trip.lastPosition).Magnitude
       local driving=hooks.vehicleService.isDrivingWorkVehicle(player,"Taxista")
       if not driving then trip.driverMissingAt=trip.driverMissingAt or time else trip.driverMissingAt=nil end
       if trip.driverMissingAt and time-trip.driverMissingAt>Config.DriverGrace then TaxiService.cancel(player,"Corrida cancelada: motorista fora do táxi.")
       elseif c.passenger and c.passenger.Occupant then TaxiService.cancel(player,"Corrida cancelada: o banco reservado foi ocupado.")
       elseif c.passenger and trip.npc.Parent then trip.npc:PivotTo(c.passenger.CFrame*CFrame.new(0,1.35,0))end
      end
      trip.lastPosition=position;trip.lastAt=time
     end
    end
   end
   task.wait(Config.SampleInterval)
  end
 end)
end
return TaxiService
