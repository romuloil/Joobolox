-- Executes StreetNPCService against its actual map, with query/factory doubles.
-- Does not create Roblox avatars or run rendering/physics.
return function(mockSource, fixtureSource, sources)
 local checks=0
 local function check(name,value)checks+=1;assert(value,name)end
 local fixtureFactory=assert(loadstring(fixtureSource))()
 local function fixture(initialCount,blockFirst)
  local f=fixtureFactory(mockSource);local m=f.mock;local v,cf=m.Vector3,m.CFrame
  local names={'GameConfig','CivicConfig','PrisonBuilder','TaxiSiteBuilder','CivicBuilder','MapBuilder','StreetNPCConfig'}
  for _,name in ipairs(names)do m.load(name,assert(sources[name],name),name=='PrisonBuilder'or name=='TaxiSiteBuilder'or name=='CivicBuilder'or name=='MapBuilder')end
  m.registry.MapBuilder.build()
  local map=m.Workspace:FindFirstChild('Map')
  local parts={}
  for _,p in ipairs(map:GetDescendants())do if p:IsA('BasePart')then table.insert(parts,p)end end
  local rayCalls,queryCalls=0,0
  m.Workspace.Raycast=function(_,origin,direction)
   rayCalls+=1
   local best,bestT,bestNormal
   for _,p in ipairs(parts)do
    if p.CanQuery~=false then
     local o=p.CFrame:PointToObjectSpace(origin);local d=p.CFrame:VectorToObjectSpace(direction)
     local t0,t1=0,1;local normal=v.zero;local valid=true
     for _,axis in ipairs({'X','Y','Z'})do
      local half=p.Size[axis]/2
      if math.abs(d[axis])<0.000001 then
       if math.abs(o[axis])>half then valid=false;break end
      else
       local a,b=(-half-o[axis])/d[axis],(half-o[axis])/d[axis]
       local sign=-1
       if a>b then a,b=b,a;sign=1 end
       if a>t0 then
        t0=a;normal=axis=='X'and v.new(sign,0,0)or axis=='Y'and v.new(0,sign,0)or v.new(0,0,sign)
       end
       t1=math.min(t1,b)
       if t0>t1 then valid=false;break end
      end
     end
     if valid and t0>=0 and t0<=1 and(not bestT or t0<bestT)then best,bestT,bestNormal=p,t0,p.CFrame:VectorToWorldSpace(normal)end
    end
   end
   return best and{Instance=best,Position=origin+direction*bestT,Normal=bestNormal}or nil
  end
  local blocker
  local function projected(p,axis)
   return math.abs(axis:Dot(p.CFrame.RightVector))*p.Size.X/2+math.abs(axis:Dot(p.CFrame.UpVector))*p.Size.Y/2+math.abs(axis:Dot(p.CFrame.LookVector))*p.Size.Z/2
  end
  m.Workspace.GetPartBoundsInBox=function(_,center,size,params)
   queryCalls+=1
   if blockFirst and queryCalls==1 then
    blocker=f.instance('Part');blocker.Name='StandingSpotObstacle';blocker.Size=v.new(3,6,3);blocker.CFrame=center;blocker.Parent=map
   end
   local found={};local axes={v.xAxis,v.yAxis,v.zAxis}
   for _,p in ipairs(m.Workspace:GetDescendants())do
    if p:IsA('BasePart')and p.CanQuery~=false then
     local ignored=false
     for _,excluded in ipairs(params.FilterDescendantsInstances or{})do if p:IsDescendantOf(excluded)then ignored=true;break end end
     if not ignored then
      local delta=p.Position-center.Position;local hit=true
      for _,axis in ipairs({axes[1],axes[2],axes[3],p.CFrame.RightVector,p.CFrame.UpVector,p.CFrame.LookVector})do
       local radius=math.abs(axis.X)*size.X/2+math.abs(axis.Y)*size.Y/2+math.abs(axis.Z)*size.Z/2
       if math.abs(delta:Dot(axis))>radius+projected(p,axis)then hit=false;break end
      end
      if hit then table.insert(found,p)end
     end
    end
   end
   return found
  end
  local folder=f.instance('Folder');folder.Name='NPCs';folder.Parent=m.Workspace
  local count=initialCount or 0;local spawned,say,emotes={}, {}, {}
  local kit={MAX_NPCS=30,count=function()return count end,folder=function()return folder end}
  function kit.spawn(frame,opts)
   check('factory respects capacity',count<30)
   check('factory anchored option',opts.anchored==true)
   check('factory residents use shared NPC budget',opts.important==false)
   local model=f.instance('Model');model.Name=opts.name;model.Parent=folder
   local root=f.instance('Part');root.Name='HumanoidRootPart';root.Size=v.new(2,2,1);root.CFrame=frame+v.new(0,3.1,0);root.Anchored=opts.anchored;root.Parent=model
   local humanoid=f.instance('Humanoid');humanoid.Parent=model;model.PrimaryPart=root
   count+=1;table.insert(spawned,model);return model
  end
  function kit.say(npc,line,duration)table.insert(say,{npc=npc,line=line,duration=duration})end
  function kit.emote(npc,name)table.insert(emotes,{npc=npc,name=name})end
  m.load('NPCKit','return {}',true);m.registry.NPCKit=kit
  local service=m.load('StreetNPCService',sources.StreetNPCService,true)
  return{f=f,m=m,map=map,service=service,spawned=spawned,say=say,emotes=emotes,folder=folder,count=function()return count end,
   queries=function()return queryCalls,rayCalls end,blocker=function()return blocker end}
 end
 local x=fixture(0,true)
 x.service.init()
 check('init returns before avatar creation',#x.spawned==0)
 x.f.advance(0)
 check('one resident per eight radial streets',x.service.count()==8)
 check('same NPCKit factory called eight times',#x.spawned==8)
 local queries,rays=x.queries()
 check('queries actual map clearance',queries>=9 and rays>=queries)
 check('blocked first spot tried alternate',x.blocker()~=nil)
 local unique={}
 for _,npc in ipairs(x.spawned)do
  check('resident metadata',npc:GetAttribute('StreetResident')==true)
  local id=npc:GetAttribute('StreetResidentId');check('resident IDs unique',type(id)=='string'and not unique[id]);unique[id]=true
  check('resident street metadata',type(npc:GetAttribute('StreetName'))=='string')
  check('stationary root',npc.PrimaryPart.Anchored)
  check('no roaming walk speed',npc:FindFirstChildOfClass('Humanoid').WalkSpeed==0)
 end
 x.service.init();x.f.advance(0)
 check('second init does not duplicate avatars',#x.spawned==8)
 local npc=x.spawned[1];local root=npc.PrimaryPart;local prompt=root:FindFirstChild('StreetTalkPrompt')
 local player=x.f.player(123)
 x.f.move(player,root.Position.X+1,root.Position.Z+1)
 local before=root.Position
 prompt.Triggered:Fire(player)
 check('near living player talks',#x.say==1 and #x.emotes==1)
 check('first line resolves location template',string.find(x.say[1].line,npc:GetAttribute('StreetName'),1,true)~=nil)
 check('talk does not move stationary NPC',(root.Position-before).Magnitude<0.001)
 prompt.Triggered:Fire(player)
 check('rapid conversation denied',#x.say==1)
 x.f.advance(1.6);prompt.Triggered:Fire(player)
 check('next conversation advances prepared dialogue',#x.say==2 and x.say[1].line~=x.say[2].line)
 x.f.advance(1.6);x.f.move(player,root.Position.X+50,root.Position.Z);prompt.Triggered:Fire(player)
 check('forged distant prompt denied',#x.say==2)
 x.f.advance(1.6);x.f.move(player,root.Position.X+1,root.Position.Z+1);player.Character:FindFirstChildOfClass('Humanoid').Health=0;prompt.Triggered:Fire(player)
 check('dead caller denied',#x.say==2)
 local capped=fixture(28,false);capped.service.init();capped.f.advance(0)
 check('only available NPC capacity used',#capped.spawned==2 and capped.count()==30)
 check('service reports actual capped residents',capped.service.count()==2)
 print(('PASS StreetNPCService: %d lifecycle/placement checks (actual map query doubles)'):format(checks))
end
