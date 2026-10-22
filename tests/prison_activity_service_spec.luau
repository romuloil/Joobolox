-- Real activity service, controlled clock and authoritative police/prison doubles.
return function(mockSource,fixtureSource,configSource,rulesSource,serviceSource)
 local checks=0;local function check(v,name)checks+=1;assert(v,name)end
 local makeFixture=assert(loadstring(fixtureSource))()
 local function fixture()
  local f=makeFixture(mockSource);local m=f.mock
  local prisoner,officer,civilian=f.player(1,false),f.player(2,false),f.player(3,false)
  local detained,roles,cellIds={[prisoner]=true},{[officer]=true},{[prisoner]='A01'}
  prisoner:SetAttribute('Detained',true);prisoner:SetAttribute('PrisonCellOpensAt',f.now()+5)
  local offenses={};local police={isOnDuty=function(p)return roles[p]==true end,registerPrisonOffense=function(p,reason)
   if not detained[p]then return false end
   table.insert(offenses,{player=p,reason=reason});return true
  end}
  local prison={isDetained=function(p)return detained[p]==true end,getAssignedCellId=function(p)return cellIds[p]end,
   isCellLocked=function(p)return detained[p]and f.now()<(p:GetAttribute('PrisonCellOpensAt')or 0)end}
  m.load('GameConfig',"return {Remotes={UIUpdate='UIUpdate'}}")
  m.load('PrisonActivityConfig',configSource);m.load('PrisonActivityRules',rulesSource)
  local service=m.load('PrisonActivityService',serviceSource,true)
  local sites={stations={},drawers={},doors={}}
  for i,kind in ipairs({'meal','medical','exercise','visitor'})do table.insert(sites.stations,{id=kind,kind=kind,prompt=f.prompt((i-1)*30)})end
  sites.drawers={{id='A01',prompt=f.prompt(120)},{id='A02',prompt=f.prompt(140)}}
  local part=f.instance('Part');part.Size=m.Vector3.new(6,10,1);part.CFrame=m.CFrame.new(160,5,0);part.Parent=m.Workspace
  sites.doors={{id='armory',part=part,closed=part.CFrame,open=part.CFrame*m.CFrame.new(0,11,0),prompt=f.prompt(160)}}
  local messages={}
  service.init({UIUpdate={FireClient=function(_,player,kind,payload)table.insert(messages,{player=player,kind=kind,text=payload.text})end}},
   {prisonActivities=sites},{prisonService=prison,policeService=police})
  f.advance(0)
  local function trigger(prompt,p)prompt.Triggered:Fire(p)end
  local function pickPrompt()return officer.Character.HumanoidRootPart:FindFirstChild('PrisonPickpocketPrompt')end
  local function pickSetup()
   f.move(officer,0,0);f.move(prisoner,0,3)
   return pickPrompt()
  end
  local function steal()
   local prompt=pickSetup();prompt.PromptButtonHoldBegan:Fire(prisoner);f.advance(2.6);prompt.Triggered:Fire(prisoner)
  end
  f.p,f.o,f.c,f.detained,f.roles,f.cellIds,f.offenses=prisoner,officer,civilian,detained,roles,cellIds,offenses
  f.service,f.sites,f.messages,f.trigger,f.pickPrompt,f.pickSetup,f.steal=service,sites,messages,trigger,pickPrompt,pickSetup,steal
  return f
 end
 local f=fixture();local p,s=f.p,f.service;local h=p.Character:FindFirstChildOfClass('Humanoid')
 h.Health=40
 f.trigger(f.sites.stations[1].prompt,p)
 check(h.Health==40,'locked cell denies common facilities')
 f.advance(5.1);f.trigger(f.sites.stations[1].prompt,p)
 check(h.Health==50,'meal really heals small amount after cell opens')
 f.advance(.5);f.trigger(f.sites.stations[1].prompt,p)
 check(h.Health==50,'meal cooldown prevents farming')
 f.advance(30);h.Health=98;f.trigger(f.sites.stations[1].prompt,p)
 check(h.Health==100,'meal health capped at MaxHealth')
 f.move(p,30);f.advance(.5);h.Health=60;f.trigger(f.sites.stations[2].prompt,p)
 check(h.Health==85,'infirmary gives configured treatment')
 f.move(p,0);f.advance(.5);f.trigger(f.sites.stations[2].prompt,p)
 check(h.Health==85,'distant medical request denied')
 f.c:SetAttribute('Detained',true);f.move(f.c,0);f.c.Character:FindFirstChildOfClass('Humanoid').Health=20
 f.trigger(f.sites.stations[1].prompt,f.c)
 check(f.c.Character:FindFirstChildOfClass('Humanoid').Health==20,'forged detention attr gives no access')
 f.move(f.c,90);f.trigger(f.sites.stations[4].prompt,f.c)
 check(f.c:GetAttribute('PrisonVisitorRegisteredAt')~=nil,'public visitor checkin works')
 f.move(p,90);f.advance(.5);f.trigger(f.sites.stations[4].prompt,p)
 check(p:GetAttribute('PrisonVisitorRegisteredAt')==nil,'prisoner cannot use public visitors registration')
 f.move(p,60);f.advance(.5);f.trigger(f.sites.stations[3].prompt,p)
 check(p:GetAttribute('PrisonExerciseUntil')~=nil,'exercise starts timed series')
 f.advance(4.2)
 check(p:GetAttribute('PrisonExerciseUntil')==nil and p:GetAttribute('PrisonExercisesCompleted')==1,'stationary series completes once')
 f.advance(20);f.trigger(f.sites.stations[3].prompt,p);f.move(p,100);f.advance(.2)
 check(p:GetAttribute('PrisonExerciseUntil')==nil and p:GetAttribute('PrisonExercisesCompleted')==1,'moving away cancels exercise')
 local prompt=f.pickSetup()
 prompt.Triggered:Fire(p)
 check(not s.hasKeycard(p),'direct triggered without server hold denied')
 prompt.PromptButtonHoldBegan:Fire(p);f.advance(1);prompt.Triggered:Fire(p)
 check(not s.hasKeycard(p),'short hold denied')
 f.advance(.5);f.move(p,0,-3);prompt.PromptButtonHoldBegan:Fire(p);f.advance(2.6);prompt.Triggered:Fire(p)
 check(not s.hasKeycard(p),'standing in front of officer denied')
 f.move(p,0,3);prompt.PromptButtonHoldBegan:Fire(p);f.advance(1);f.move(p,0,-3);f.advance(.2);f.move(p,0,3);f.advance(1.5);prompt.Triggered:Fire(p)
 check(not s.hasKeycard(p),'leaving back position during hold invalidates it')
 f.steal()
 check(s.hasKeycard(p)and p:GetAttribute('PrisonKeycard')==true,'legitimate rear hold grants server keycard')
 check(#f.offenses==1 and f.offenses[1].reason=='Furto de cartão','steal registers crime once')
 local function noticesToOfficer()local n=0;for _,msg in ipairs(f.messages)do if msg.player==f.o then n+=1 end end;return n end
 check(noticesToOfficer()==0,'officer warning is delayed')
 f.advance(1.1);check(noticesToOfficer()==1,'officer warned after one second')
 f.steal();check(#f.offenses==1,'holding existing card cannot duplicate theft')
 f.move(p,140);f.trigger(f.sites.drawers[2].prompt,p)
 check(s.hasKeycard(p)and not p:GetAttribute('PrisonStoredKeycard'),'other cells drawer inaccessible')
 f.move(p,120);f.advance(1);f.trigger(f.sites.drawers[1].prompt,p)
 check(not s.hasKeycard(p)and p:GetAttribute('PrisonStoredKeycard'),'own drawer stores card')
 f.advance(1);f.trigger(f.sites.drawers[1].prompt,p)
 check(s.hasKeycard(p)and not p:GetAttribute('PrisonStoredKeycard'),'own drawer returns card')
 f.move(p,160);f.trigger(f.sites.doors[1].prompt,p)
 check(f.sites.doors[1].part:GetAttribute('Open')==true,'card opens restricted door')
 check(#f.offenses==2 and f.offenses[2].reason=='Área restrita','card use registers restricted breach')
 f.advance(6.1)
 check(f.sites.doors[1].part:GetAttribute('Open')==true,'door stays open while occupied')
 f.move(p,170);f.advance(.6)
 check(f.sites.doors[1].part:GetAttribute('Open')==false,'door closes when passage clears')
 f.c:SetAttribute('PrisonKeycard',true);f.move(f.c,160);f.trigger(f.sites.doors[1].prompt,f.c)
 check(f.sites.doors[1].part:GetAttribute('Open')==false,'forged keycard attr grants no access')
 f.move(f.o,160);f.trigger(f.sites.doors[1].prompt,f.o)
 check(f.sites.doors[1].part:GetAttribute('Open')==true,'real on-duty officer opens door')
 s.clearPlayer(p)
 check(not s.hasKeycard(p)and p:GetAttribute('PrisonStoredKeycard')==false,'arrest cleanup destroys all contraband')
 f.advance(21);f.steal();check(s.hasKeycard(p),'new legitimate theft after cleanup')
 f.detained[p]=false;p:SetAttribute('Detained',false)
 check(not s.hasKeycard(p)and p:GetAttribute('PrisonKeycard')==false,'release clears contraband state')
 local death=fixture();death.advance(5.1);death.steal();check(death.service.hasKeycard(death.p),'death setup card')
 death.p.Character:FindFirstChildOfClass('Humanoid').Died:Fire()
 check(not death.service.hasKeycard(death.p),'death destroys card')
 local wall=fixture();wall.advance(5.1);wall.mock.Workspace.Raycast=function()return {Instance={}}end
 wall.steal();check(not wall.service.hasKeycard(wall.p),'wall blocks theft despite rear distance')
 local changed=fixture();changed.advance(5.1);local cp=changed.pickSetup()
 cp.PromptButtonHoldBegan:Fire(changed.p);changed.advance(1);changed.roles[changed.o]=nil;changed.o:SetAttribute('PoliceDuty',false)
 changed.advance(2);cp.Triggered:Fire(changed.p)
 check(not changed.service.hasKeycard(changed.p),'leaving police duty invalidates pending hold')
 local joined=fixture()
 joined.roles[joined.o]=nil;joined.o:SetAttribute('PoliceDuty',false);joined.advance(0)
 check(joined.pickPrompt()==nil,'off-duty has no pickpocket prompt')
 joined.o:SetAttribute('PoliceDuty',true)
 joined.roles[joined.o]=true;joined.o:SetAttribute('WorkRole','Policial');joined.advance(0)
 check(joined.pickPrompt()~=nil,'prompt appears after actual work role is assigned during join')
 local breach=fixture();breach.advance(5.1)
 breach.sites.restrictedZones={{cf=breach.mock.CFrame.new(250,4,0),half=breach.mock.Vector3.new(8,8,8)}}
 breach.move(breach.p,250);breach.advance(.2)
 check(#breach.offenses==1 and breach.offenses[1].reason=='Área restrita','tailgating open restricted area records entry without card use')
 breach.advance(.3)
 check(#breach.offenses==1,'restricted area sampling is throttled')
 breach.move(breach.p,0);breach.move(breach.c,250);breach.advance(3.2)
 check(#breach.offenses==1,'public visitors are not criminals merely by position')
 print('PASS PrisonActivityService: '..checks..' checks (mock services)')
end
