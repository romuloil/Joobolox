local f=fixture({noNpcs=true})
local m=f.mock;local V,C=m.Vector3,m.CFrame
local new=m.env.Instance.new
m.env.Instance.new=function(class)
 local p=new(class);local isA=p.IsA
 rawset(p,"IsA",function(self,kind)
  return isA(self,kind)or(kind=='BasePart'and(class=='UnionOperation'or class=='CornerWedgePart'))or(kind=='LuaSourceContainer'and(class=='Script'or class=='ModuleScript'or class=='LocalScript'))
 end)
 p.FindFirstChildWhichIsA=function(self,kind)for _,c in ipairs(self:GetChildren())do if c:IsA(kind)then return c end end end
 return p
end
local I=m.env.Instance.new
local oldNew=C.new
C.new=function(...)
 local a={...}
 if #a==12 then return C.fromMatrix(V.new(a[1],a[2],a[3]),V.new(a[4],a[7],a[10]),V.new(a[5],a[8],a[11]),V.new(a[6],a[9],a[12]))end
 return oldNew(...)
end
local imported={}
for _,n in ipairs(DEALER)do
 local p=I(n.class);p.Name=n.name;imported[n.id]=p
 if n.pos then
  local r=n.rot;p.Size=V.new(table.unpack(n.size));p.CanCollide=n.collide
  p.CFrame=C.fromMatrix(V.new(table.unpack(n.pos)),V.new(r[1][1],r[2][1],r[3][1]),V.new(r[1][2],r[2][2],r[3][2]),V.new(r[1][3],r[2][3],r[3][3]))
 end
 if n.parent>0 then p.Parent=assert(imported[n.parent])else p.Parent=m.services.ServerStorage end
end
local template=m.services.ServerStorage.DealershipTemplate
check(#template:GetDescendants()+1==8618,'full physical subtree imported with all furniture, interior, exterior and parking objects')
m.load('CarBuilder','return {}',true)
m.registry.CarBuilder.build=function(spec,cf)
 local c=I('Model');local p=I('VehicleSeat');p.Name='Driver';p.CFrame=cf;p.Parent=c
 return c
end
local H={}
H.makePart=function(parent,props)local p=I(props.ClassName or'Part');for k,v in pairs(props)do if k~='ClassName'then p[k]=v end end;p.Anchored=true;p.Parent=parent;return p end
H.addSurfaceText=function(p,text)local l=I('TextLabel');l.Text=text;l.Parent=p end
local module=m.load('DealershipBuilder',SOURCES.DealershipBuilder,true)
local plan={Origin=V.new(1600,1.33,-2600),Center=V.new(1576,0,-2595),Width=520,Depth=620}
local site
m.env.task.spawn(function()site=module.build(m.Workspace.Map,plan,H)end)
f.advance(3)
check(site and site:FindFirstChild('Dealer')and site:FindFirstChild('ParkingLot'),'actual builder includes the complete showroom and open parking')
local count,prompts,exhibitions=0,{},0
local min,max=V.new(math.huge,math.huge,math.huge),V.new(-math.huge,-math.huge,-math.huge)
local function geometry(p)
 local h=p.Size/2
 for _,x in ipairs({-1,1})do for _,y in ipairs({-1,1})do for _,z in ipairs({-1,1})do
  local c=p.CFrame*V.new(h.X*x,h.Y*y,h.Z*z)
  min=V.new(math.min(min.X,c.X),math.min(min.Y,c.Y),math.min(min.Z,c.Z))
  max=V.new(math.max(max.X,c.X),math.max(max.Y,c.Y),math.max(max.Z,c.Z))
 end end end
end
for _,p in ipairs(site:GetDescendants())do
 assert(not p:IsA('LuaSourceContainer'),'foreign source survived')
 if p:IsA('BasePart')then assert(p.Anchored,'unanchored imported geometry');count+=1 end
 if p.Name=='PortaConcessionaria'then table.insert(prompts,p)end
 if p:GetAttribute('Exhibition')then exhibitions+=1 end
end
for _,name in ipairs({'Dealer','ParkingLot'})do for _,p in ipairs(site[name]:GetDescendants())do if p:IsA('BasePart')then geometry(p)end end end
check(count>4000 and count<6012,'compact parking reduces parts while keeping the dealership anchored')
check(#prompts==16,'ten interior doors and six workshop gates have local interactions')
check(exhibitions==3,'three Little Life vehicles displayed outside without replacing reference furniture')
check(min.X>plan.Center.X-plan.Width/2 and max.X<plan.Center.X+plan.Width/2 and min.Z>plan.Center.Z-plan.Depth/2 and max.Z<plan.Center.Z+plan.Depth/2,'all transformed geometry stays inside the reserved dealership lot')
check(max.Z-min.Z<620 and max.Z-min.Z>500,'parking depth reduced from 1315 to about 590 studs')
local originalDealer=template:FindFirstChild('Dealer')
check(#originalDealer:GetDescendants()==#site.Dealer:GetDescendants()-16*2,'all original dealership interior/facade objects retained, plus door anchors and prompts')
local retail=m.Workspace.Map.Garages.ConcessionariaDoVale
local pickup=m.Workspace.Map.Garages.RetiradaConcessionaria
check(retail:GetAttribute('Dealership')and not pickup:GetAttribute('Dealership'),'sales counter and owned-car collection garage are distinct')
check((retail.Balcao.Position-(plan.Origin+V.new(-45,3,58))).Magnitude<.001,'sales prompt sits at original interior front desk')
for _,g in ipairs({retail,pickup})do
 for i=1,3 do local v=g['Vaga'..i];assert(v and not v.CanCollide and not v.CanQuery,'pickup marker blocks space')end
end
check(true,'both counters share three invisible nonblocking pickup positions')
local p=f.player(80001);local prompt=prompts[1]
p.Character.HumanoidRootPart.Position=prompt.Parent.Position+V.new(100,0,0)
prompt.Triggered:Fire(p);check(prompt.ActionText=='Abrir','door rejects a forged activation from far away')
p.Character.HumanoidRootPart.Position=prompt.Parent.Position
prompt.Triggered:Fire(p);check(prompt.ActionText=='Fechar','nearby E activation opens original door geometry')
prompt.Triggered:Fire(p);check(prompt.ActionText=='Fechar','door cooldown prevents overlapping animations')
f.advance(1);prompt.Triggered:Fire(p);check(prompt.ActionText=='Abrir','door can be closed again')
local beforeParts,afterParts={},{}
for _,v in ipairs(originalDealer:GetDescendants())do if v:IsA('BasePart')then table.insert(beforeParts,v)end end
for _,v in ipairs(site.Dealer:GetDescendants())do if v:IsA('BasePart')and v.Name~='ComandoPorta'then table.insert(afterParts,v)end end
check(#beforeParts==#afterParts,'every original building part remains present')
for i,v in ipairs(beforeParts)do assert((v.Size-afterParts[i].Size).Magnitude<.0001,'building part was resized')end
check(true,'building and interior remain at exactly original scale')
f.assertClean()
print('TOTAL DEALERSHIP',passed,'PARTS',count)
