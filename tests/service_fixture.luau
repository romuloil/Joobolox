-- Shared controlled clock / Instance service doubles. No Roblox engine simulation.
return function(mockSource)
 local m=assert(loadstring(mockSource))()
 local time,queue=1000,{}
 local function signal()
  local callbacks={}
  return {Connect=function(_,fn)
   local c={active=true,fn=fn};table.insert(callbacks,c)
   return {Disconnect=function()c.active=false end}
  end,Fire=function(_,...)
   for _,c in ipairs(table.clone(callbacks))do if c.active then c.fn(...)end end
  end}
 end
 local function schedule(delay,fn,...)
  table.insert(queue,{at=time+delay,thread=coroutine.create(fn),args={...}})
 end
 local function advance(duration)
  local target=time+duration;local count=0
  while true do
   local selected,earliest
   for i,item in ipairs(queue)do if item.at<=target and(not earliest or item.at<earliest)then selected,earliest=i,item.at end end
   if not selected then break end
   time=earliest;local item=table.remove(queue,selected)
   local ok,delay=coroutine.resume(item.thread,table.unpack(item.args));assert(ok,delay)
   if coroutine.status(item.thread)~='dead'then table.insert(queue,{at=time+(delay or 0),thread=item.thread,args={}})end
   count+=1;assert(count<100000,'scheduler stalled')
  end
  time=target
 end
 m.env.task={spawn=function(fn,...)schedule(0,fn,...)end,defer=function(fn,...)schedule(0,fn,...)end,
  delay=function(delay,fn,...)schedule(delay,fn,...)end,wait=function(delay)return coroutine.yield(delay or 0.03)end}
 local original=m.Instance.new
 local sample=original('Part');local mt=getmetatable(sample);local originalSet=mt.__newindex
 mt.__newindex=function(object,key,value)
  local before=key=='Parent'and object.Parent or object[key]
  originalSet(object,key,value)
  if before~=value then
   local props=rawget(object,'_signals');if props and props[key]then props[key]:Fire()end
   if key=='Parent'then
    if before and before.ChildRemoved then before.ChildRemoved:Fire(object)end
    if value and value.ChildAdded then value.ChildAdded:Fire(object)end
    local p=value
    while p do if p.DescendantAdded then p.DescendantAdded:Fire(object)end;p=p.Parent end
    if object.AncestryChanged then object.AncestryChanged:Fire(object,value)end
   end
  end
 end
 local function instance(class)
  local p=original(class)
  rawset(p,'_signals',{})
  p.ChildAdded,p.ChildRemoved,p.DescendantAdded,p.AncestryChanged,p.Destroying=signal(),signal(),signal(),signal(),signal()
  rawset(p,'GetPropertyChangedSignal',function(self,key)
   if not self._signals[key]then self._signals[key]=signal()end;return self._signals[key]
  end)
  rawset(p,'GetAttributeChangedSignal',function(self,key)
   local id='@'..key;if not self._signals[id]then self._signals[id]=signal()end;return self._signals[id]
  end)
  rawset(p,'SetAttribute',function(self,key,value)
   local before=self._attributes[key];self._attributes[key]=value
   local sig=self._signals['@'..key];if before~=value and sig then sig:Fire()end
  end)
  rawset(p,'FindFirstAncestorOfClass',function(self,kind)
   local parent=self.Parent;while parent do if parent:IsA(kind)then return parent end;parent=parent.Parent end
  end)
  rawset(p,'Destroy',function(self)
   self.Destroying:Fire();for _,child in ipairs(self:GetChildren())do child:Destroy()end
   self.Parent=nil
  end)
  rawset(p,'SetNetworkOwner',function()end)
  rawset(p,'PivotTo',function(self,target)
   local old=self.PrimaryPart and self.PrimaryPart.CFrame or self._props.Pivot or self.CFrame
   local delta=target*old:Inverse()
   for _,part in ipairs(self:GetDescendants())do if part:IsA('BasePart')then part.CFrame=delta*part.CFrame end end
   self._props.Pivot=target
  end)
  rawset(p,'GetPivot',function(self)return self.PrimaryPart and self.PrimaryPart.CFrame or self._props.Pivot or self.CFrame end)
  if class=='Humanoid'then
   p.Health,p.WalkSpeed,p.JumpPower,p.JumpHeight,p.HipHeight=100,16,50,7.2,2
   p.Died,p.Running=signal(),signal()
   p.Sit,p.PlatformStand=false,false
   rawset(p,'ChangeState',function()end);rawset(p,'SetStateEnabled',function()end)
  elseif class=='ProximityPrompt'then p.Triggered=signal()
  elseif class=='Seat'or class=='VehicleSeat'then
   rawset(p,'Sit',function(self,humanoid)humanoid.Sit=true;humanoid.SeatPart=self;self.Occupant=humanoid end)
  elseif class=='Tool'then p.Activated,p.Equipped,p.Unequipped=signal(),signal(),signal()
  end
  if p:IsA('BasePart')then p.AssemblyLinearVelocity=m.Vector3.zero;p.AssemblyAngularVelocity=m.Vector3.zero end
  return p
 end
 m.env.Instance={new=instance};m.Instance={new=instance}
 local Players={list={},PlayerAdded=signal(),PlayerRemoving=signal()}
 function Players:GetPlayers()return self.list end
 function Players:GetPlayerByUserId(id)for _,p in ipairs(self.list)do if p.UserId==id then return p end end end
 function Players:GetPlayerFromCharacter(character)for _,p in ipairs(self.list)do if p.Character==character then return p end end end
 m.services.Players=Players
 m.services.RunService={IsStudio=function()return true end,Heartbeat=signal()}
 m.services.TweenService={Create=function(_,p,_,values)return{Play=function()for k,v in pairs(values)do p[k]=v end end}end}
 m.services.Debris={AddItem=function(_,p,delay)schedule(delay,function()p:Destroy()end)end}
 m.env.PhysicalProperties={new=function(...)return{...}end}
 m.env.TweenInfo={new=function()return{}end};m.env.RaycastParams={new=function()return{}end};m.env.OverlapParams={new=function()return{}end}
 m.Workspace.GetServerTimeNow=function()return time end
 m.Workspace.GetPartBoundsInBox=function()return{}end
 m.Workspace.Raycast=function(_,origin,direction)
  if direction.Y<0 then return{Position=m.Vector3.new(origin.X,0,origin.Z),Instance=nil}end
  return nil
 end
 local warnings={};m.env.warn=function(value)table.insert(warnings,value)end
 local function character(r6)
  local c=instance('Model');c.Name='Character';c.Parent=m.Workspace
  local names=r6 and {'HumanoidRootPart','Head','Torso','Left Arm','Right Arm','Left Leg','Right Leg'}or
   {'HumanoidRootPart','Head','UpperTorso','LowerTorso','LeftUpperArm','RightUpperArm','LeftUpperLeg','RightUpperLeg','LeftLowerLeg','RightLowerLeg','LeftFoot','RightFoot'}
  for _,name in ipairs(names)do local p=instance('Part');p.Name=name;p.Size=m.Vector3.new(2,2,1);p.CFrame=m.CFrame.new(0,name=='Head'and 5.5 or 4,0);p.Parent=c end
  local h=instance('Humanoid');h.Name='Humanoid';h.RigType=r6 and m.Enum.HumanoidRigType.R6 or m.Enum.HumanoidRigType.R15;h.Parent=c
  c.PrimaryPart=c:FindFirstChild('HumanoidRootPart');return c
 end
 local function player(id,r6)
  local attrs,changes={},{}
  local p={Parent=Players,Name='Player'..id,DisplayName='Player'..id,UserId=id,Character=character(r6),CharacterAdded=signal()}
  local backpack=instance('Backpack');backpack.Name='Backpack'
  function p:GetAttribute(name)return attrs[name]end
  function p:SetAttribute(name,value)local before=attrs[name];attrs[name]=value;if before~=value and changes[name]then changes[name]:Fire()end end
  function p:GetAttributeChangedSignal(name)if not changes[name]then changes[name]=signal()end;return changes[name]end
  function p:FindFirstChild(name)return name=='Backpack'and backpack end
  function p:FindFirstChildOfClass(name)return name=='Backpack'and backpack end
  function p:WaitForChild(name)return assert(self:FindFirstChild(name),'missing '..name)end
  table.insert(Players.list,p);return p
 end
 local rate={}
 local security={getLivingCharacter=function(p)
  local c=p.Character;local h=c and c:FindFirstChildOfClass('Humanoid');local r=c and c:FindFirstChild('HumanoidRootPart')
  if not h or not r or h.Health<=0 then return nil end;return c,h,r
 end,checkRate=function(p,key,interval)
  local id=tostring(p.UserId)..key;if rate[id]and time-rate[id]<interval then return false end;rate[id]=time;return true
 end,isShortString=function(v,n)return type(v)=='string'and#v>0 and#v<=n end}
 m.load('SecurityService','return {}',true);m.registry.SecurityService=security
 local function prompt(x,z)
  local anchor=instance('Part');anchor.CFrame=m.CFrame.new(x,4,z or 0);anchor.Parent=m.Workspace
  local q=instance('ProximityPrompt');q.Parent=anchor;return q
 end
 local function move(p,x,z)
  p.Character:PivotTo(m.CFrame.new(x,4,z or 0))
 end
 return{mock=m,instance=instance,players=Players,player=player,character=character,signal=signal,prompt=prompt,
  move=move,advance=advance,now=function()return time end,warnings=warnings,security=security}
end
