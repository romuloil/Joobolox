-- Headless geometry only. Does not implement Roblox physics, rendering or networking.
local V = {}
local Vmt = {}
local function vec(x,y,z) return setmetatable({X=x or 0,Y=y or 0,Z=z or 0,_kind="Vector3"},Vmt) end
function Vmt.__index(a,k)
 if k=="Magnitude" then return math.sqrt(a.X*a.X+a.Y*a.Y+a.Z*a.Z) end
 if k=="Unit" then return a/a.Magnitude end
 return V[k]
end
function Vmt.__add(a,b) return vec(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
function Vmt.__sub(a,b) return vec(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
function Vmt.__unm(a) return vec(-a.X,-a.Y,-a.Z) end
function Vmt.__mul(a,b)
 if type(a)=="number" then return vec(a*b.X,a*b.Y,a*b.Z) end
 if type(b)=="number" then return vec(a.X*b,a.Y*b,a.Z*b) end
 return vec(a.X*b.X,a.Y*b.Y,a.Z*b.Z)
end
function Vmt.__div(a,b) return vec(a.X/b,a.Y/b,a.Z/b) end
function Vmt.__tostring(a) return string.format("(%g,%g,%g)",a.X,a.Y,a.Z) end
function V:Dot(b) return self.X*b.X+self.Y*b.Y+self.Z*b.Z end
function V:Cross(b) return vec(self.Y*b.Z-self.Z*b.Y,self.Z*b.X-self.X*b.Z,self.X*b.Y-self.Y*b.X) end
function V:Lerp(b,t) return self+(b-self)*t end
local Vector3={new=vec,zero=vec(),one=vec(1,1,1),xAxis=vec(1,0,0),yAxis=vec(0,1,0),zAxis=vec(0,0,1)}
local F={}; local Fmt={}
local function cf(p,r,u,b) return setmetatable({_kind="CFrame",p=p,r=r or vec(1,0,0),u=u or vec(0,1,0),b=b or vec(0,0,1)},Fmt) end
function Fmt.__index(a,k)
 if k=="Position" or k=="p" then return rawget(a,"p") end
 if k=="X" or k=="Y" or k=="Z" then return a.p[k] end
 if k=="RightVector" or k=="XVector" then return a.r end
 if k=="UpVector" or k=="YVector" then return a.u end
 if k=="LookVector" then return -a.b end
 if k=="ZVector" then return a.b end
 return F[k]
end
function F:VectorToWorldSpace(v) return self.r*v.X+self.u*v.Y+self.b*v.Z end
function F:PointToWorldSpace(v) return self.p+self:VectorToWorldSpace(v) end
function F:VectorToObjectSpace(v) return vec(v:Dot(self.r),v:Dot(self.u),v:Dot(self.b)) end
function F:PointToObjectSpace(v) return self:VectorToObjectSpace(v-self.p) end
function F:Inverse()
 local n=cf(vec(),vec(self.r.X,self.u.X,self.b.X),vec(self.r.Y,self.u.Y,self.b.Y),vec(self.r.Z,self.u.Z,self.b.Z))
 n.p=n:VectorToWorldSpace(-self.p); return n
end
function F:ToObjectSpace(other) return self:Inverse()*other end
function Fmt.__mul(a,b)
 if b._kind=="Vector3" then return a:PointToWorldSpace(b) end
 return cf(a:PointToWorldSpace(b.p),a:VectorToWorldSpace(b.r),a:VectorToWorldSpace(b.u),a:VectorToWorldSpace(b.b))
end
function Fmt.__add(a,b) return cf(a.p+b,a.r,a.u,a.b) end
function Fmt.__sub(a,b) return cf(a.p-b,a.r,a.u,a.b) end
local CFrame={}
function CFrame.new(x,y,z)
 if type(x)=="table" then
  if y then return CFrame.lookAt(x,y) end
  return cf(x)
 end
 return cf(vec(x,y,z))
end
function CFrame.lookAt(p,q,up)
 local look=(q-p).Unit; local right=look:Cross(up or vec(0,1,0)).Unit
 if right.Magnitude~=right.Magnitude then right=vec(1,0,0) end
 return cf(p,right,right:Cross(look),-look)
end
function CFrame.Angles(x,y,z)
 local cx,sx=math.cos(x),math.sin(x); local cy,sy=math.cos(y),math.sin(y); local cz,sz=math.cos(z),math.sin(z)
 local rx=cf(vec(),vec(1,0,0),vec(0,cx,sx),vec(0,-sx,cx))
 local ry=cf(vec(),vec(cy,0,-sy),vec(0,1,0),vec(sy,0,cy))
 local rz=cf(vec(),vec(cz,sz,0),vec(-sz,cz,0),vec(0,0,1))
 return rx*ry*rz
end
CFrame.fromEulerAnglesXYZ=CFrame.Angles
function CFrame.fromMatrix(p,r,u,b) return cf(p,r,u,b or r:Cross(u)) end
local function enum(path)
 return setmetatable({_path=path},{__index=function(t,k) local n=enum(path.."."..k);rawset(t,k,n);return n end,__tostring=function(t)return t._path end})
end
local Enum=enum("Enum")
local I={}; local Imt={}
function Imt.__index(a,k)
 if I[k] then return I[k] end
 if k=="Position" then return a._props.CFrame.Position end
 if k=="Orientation" then return vec() end
 local p=a._props[k]; if p~=nil then return p end
 for _, child in ipairs(a._children) do if child.Name==k then return child end end
 return nil
end
function Imt.__newindex(a,k,v)
 if k=="Size" and (a:IsA("BasePart")) then
  for _,n in ipairs({v.X,v.Y,v.Z}) do
   assert(type(n)=="number" and n==n and n>0 and n<=2048,"BasePart.Size axis must be finite positive and <=2048: "..a.Name)
  end
 end
 if k=="Parent" then
  local old=a._props.Parent
  if old then for n,c in ipairs(old._children) do if c==a then table.remove(old._children,n);break end end end
  a._props.Parent=v; if v then table.insert(v._children,a) end
 elseif k=="Position" then a._props.CFrame=cf(v,a.CFrame.r,a.CFrame.u,a.CFrame.b)
 else a._props[k]=v end
end
local function inst(class)
 return setmetatable({_props={ClassName=class,Name=class,CanCollide=true,CanTouch=true,CanQuery=true,Transparency=0,CFrame=CFrame.new(),Size=vec(4,1,2)},_children={},_attributes={}},Imt)
end
function I:IsA(class)
 return self.ClassName==class or (class=="BasePart" and (self.ClassName=="Part" or self.ClassName=="Seat" or self.ClassName=="WedgePart" or self.ClassName=="SpawnLocation"))
end
function I:FindFirstChild(name,recursive)
 for _,c in ipairs(self._children) do if c.Name==name then return c end end
 if recursive then for _,c in ipairs(self._children) do local found=c:FindFirstChild(name,true); if found then return found end end end
end
function I:WaitForChild(name) return assert(self:FindFirstChild(name),self.Name.." missing child "..name) end
function I:FindFirstChildOfClass(class) for _,c in ipairs(self._children) do if c.ClassName==class then return c end end end
function I:GetChildren() return table.clone(self._children) end
function I:GetDescendants()
 local out={};local function walk(p) for _,c in ipairs(p._children) do table.insert(out,c);walk(c) end end;walk(self);return out
end
function I:IsDescendantOf(parent)
 local current=self.Parent
 while current do
  if current==parent then return true end
  current=current.Parent
 end
 return false
end
function I:SetAttribute(k,v) self._attributes[k]=v end
function I:GetAttribute(k) return self._attributes[k] end
function I:GetAttributes() return table.clone(self._attributes) end
function I:Destroy() self.Parent=nil;self._children={} end
function I:PivotTo(cframe) self._props.Pivot=cframe end
function I:GetPivot() return self._props.Pivot or self.CFrame end
local Random={}
function Random.new(seed)
 local state=math.floor(seed or 1)%2147483647
 local r={}
 function r:NextNumber(low,high)
  state=(state*48271)%2147483647;local v=state/2147483647
  if low then return low+(high-low)*v end
  return v
 end
 function r:NextInteger(low,high) return math.min(high,math.floor(self:NextNumber(low,high+1))) end
 return r
end
local Color3={}
local ColorMethods={}
function ColorMethods:Lerp(other,t) return Color3.new(self.R+(other.R-self.R)*t,self.G+(other.G-self.G)*t,self.B+(other.B-self.B)*t) end
function Color3.new(r,g,b) return setmetatable({R=r,G=g,B=b},{__index=ColorMethods}) end
function Color3.fromRGB(r,g,b) return Color3.new(r/255,g/255,b/255) end
function Color3.fromHSV(h,s,v) return {H=h,S=s,V=v} end
local function constructor(...) return {...} end
local services={Workspace=inst("Workspace"),Lighting=inst("Lighting"),ReplicatedStorage=inst("ReplicatedStorage")}
local shared=inst("Folder");shared.Name="Shared";shared.Parent=services.ReplicatedStorage
local registry={}
local env=setmetatable({Vector3=Vector3,CFrame=CFrame,Color3=Color3,Enum=Enum,Instance={new=inst},Random=Random,
 UDim2={new=constructor,fromScale=constructor,fromOffset=constructor},UDim={new=constructor},Vector2={new=function(x,y)return vec(x,y,0) end},
 ColorSequence={new=constructor},NumberSequence={new=constructor},NumberRange={new=constructor},NumberSequenceKeypoint={new=constructor},
 game={GetService=function(_,name)return assert(services[name],name)end},workspace=services.Workspace,
 task={wait=function()end,spawn=function()end,defer=function()end},warn=print,
 typeof=function(v) return type(v)=="table" and (v._kind or (v.ClassName and "Instance")) or type(v) end}, {__index=getfenv()})
env.require=function(module) return assert(registry[module.Name],"missing module "..module.Name) end
local scripts=inst("Folder");scripts.Name="Services";env.script={Parent=scripts}
local mock={env=env,registry=registry,Workspace=services.Workspace,services=services,Vector3=Vector3,CFrame=CFrame,Instance={new=inst},Enum=Enum}
function mock.load(name,source,isService)
 local module=inst("ModuleScript");module.Name=name;module.Parent=isService and scripts or shared
 local fn=assert(loadstring(source,"@"..name));setfenv(fn,env)
 local result=fn();registry[name]=result;return result
end
return mock
