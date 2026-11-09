-- Concessionária do Vale: physical asset supplied by the user, Little Life interactions.
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local CarBuilder = require(script.Parent:WaitForChild("CarBuilder"))
local Builder = {}
-- Original floor frame: a single rigid transform levels the imported site, at full scale.
local SOURCE = CFrame.new(813.3833618164062,2447.85,2723.642578125,
 .8191261887550354,.01924167014658451,-.5732919573783875,
 -.015500071458518505,.9998154044151306,.011410599574446678,
 .573405921459198,-.00046042288886383176,.8192729949951172)

local function connectDoor(model)
 local panel=model:FindFirstChild("interiordoorpanel")
 local garage=model.Name=="DEALERGARAGE"
 if garage then panel=model:FindFirstChildWhichIsA("BasePart") end
 if not panel then return end
 local parts={}
 for _,p in ipairs(model:GetChildren()) do
  if p:IsA("BasePart") and (garage or p==panel or p:IsA("UnionOperation")) then
   table.insert(parts,{p=p,cf=p.CFrame})
  end
 end
 local origin=panel.CFrame
 local hinge=origin*CFrame.new(0,0,-panel.Size.Z/2)
 local openTransform=garage and CFrame.new(0,math.max(panel.Size.Y,12)+1,0)
  or hinge*CFrame.Angles(0,math.rad(95),0)*hinge:Inverse()
 -- Fixed prompt stays beside the opening even while the leaf is raised.
 local anchor=Instance.new("Part")
 anchor.Name="ComandoPorta";anchor.Size=Vector3.new(.3,.3,.3)
 anchor.CFrame=origin;anchor.Transparency=1;anchor.Anchored=true
 anchor.CanCollide=false;anchor.CanTouch=false;anchor.CanQuery=false;anchor.Parent=model
 local prompt=Instance.new("ProximityPrompt")
 prompt.Name="PortaConcessionaria";prompt.ActionText="Abrir";prompt.ObjectText=garage and "Portão da oficina" or "Porta"
 prompt.KeyboardKeyCode=Enum.KeyCode.E;prompt.MaxActivationDistance=10;prompt.RequiresLineOfSight=false;prompt.Parent=anchor
 local opened,busy=false,false
 prompt.Triggered:Connect(function(player)
  local char=player.Character;local root=char and char:FindFirstChild("HumanoidRootPart")
  local hum=char and char:FindFirstChildOfClass("Humanoid")
  if busy or not root or not hum or hum.Health<=0 or (root.Position-anchor.Position).Magnitude>12 then return end
  opened=not opened;busy=true;prompt.ActionText=opened and "Fechar" or "Abrir"
  for _,entry in ipairs(parts) do
   TweenService:Create(entry.p,TweenInfo.new(.65),{CFrame=opened and openTransform*entry.cf or entry.cf}):Play()
  end
  task.delay(.7,function()busy=false end)
 end)
end

function Builder.build(map, plan, helpers)
 if not plan then return end
 local template=ServerStorage:FindFirstChild("DealershipTemplate")
 assert(template,"Estrutura da concessionária ausente no arquivo")
 local target=CFrame.new(plan.Origin)
 local transform=target*SOURCE:Inverse()
 local site=template:Clone();site.Name="ConcessionariaDoVale"
 site:SetAttribute("PlaceName","Concessionária do Vale")
 site:SetAttribute("Curb",CFrame.new(1780,.7,-2240))
 site:SetAttribute("ImportedPhysicalInstances",8618)
 local descendants=site:GetDescendants()
 local pivots={[site]=transform*site:GetPivot()}
 for _,model in ipairs(descendants) do
  if model:IsA("Model") then pivots[model]=transform*model:GetPivot() end
 end
 for i,p in ipairs(descendants) do
  if p:IsA("BasePart") then
   p.Anchored=true;p.CFrame=transform*p.CFrame
   p.AssemblyLinearVelocity=Vector3.zero;p.AssemblyAngularVelocity=Vector3.zero
  elseif p:IsA("LuaSourceContainer") or p:IsA("ProximityPrompt") or p:IsA("ClickDetector") then
   p:Destroy()
  end
  if i%600==0 then task.wait() end
 end
 for model,pivot in pairs(pivots) do model.WorldPivot=pivot end
 site.Parent=map
 local function part(name,size,cf,color,material)
  return helpers.makePart(site,{Name=name,Size=size,CFrame=cf,Color=color,Material=material or Enum.Material.Concrete})
 end
 local function board(cf,text,width)
  local p=part("Orientacao",Vector3.new(width or 22,4,.25),cf,Color3.fromRGB(22,52,93))
  helpers.addSurfaceText(p,text,Color3.new(1,1,1),Color3.fromRGB(22,52,93))
 end
 -- Thin landscaping bases do not cover the original showroom floors or furniture.
 part("AcessoAvenida",Vector3.new(26,.15,47),CFrame.new(1780,.79,-2262),Color3.fromRGB(70,73,78),Enum.Material.Asphalt)
 board(CFrame.new(1760,5,-2257),"CONCESSIONÁRIA DO VALE\nENTRADA →",32)
 board(target*CFrame.new(-45,14,98),"CONCESSIONÁRIA DO VALE",58)
 board(target*CFrame.new(-45,5,60),"CATÁLOGO • PRESSIONE E",21)
 board(target*CFrame.new(110,5,225),"RETIRADA DE VEÍCULOS",25)
 -- Guidance follows the empty aisles, avoiding the parking islands.
 for _,z in ipairs({660,580,500,400,300}) do
  board(target*CFrame.new(195,3,z),"SHOWROOM ↑",18)
 end
 local garages=map:FindFirstChild("Garages")
 if not garages then garages=Instance.new("Folder");garages.Name="Garages";garages.Parent=map end
 local function garage(name,at,retail)
  local g=Instance.new("Model");g.Name=name;g:SetAttribute("PlaceName",retail and "Concessionária do Vale" or "Retirada da concessionária")
  g:SetAttribute("Garage",true);g:SetAttribute("SalesPosition",(target*CFrame.new(at)).Position)
  g:SetAttribute("Dealership",retail);g:SetAttribute("Curb",CFrame.new(1780,.7,-2240));g.Parent=garages
  local booth=helpers.makePart(g,{Name="Balcao",Size=Vector3.new(2,.4,2),CFrame=target*CFrame.new(at),Color=Color3.fromRGB(31,102,152),Material=Enum.Material.Metal})
  booth.CanCollide=false
  -- Three open spaces checked against the imported parking geometry.
  for i,z in ipairs({190,250,290}) do
   local marker=helpers.makePart(g,{Name="Vaga"..i,Size=Vector3.new(.1,.1,.1),CFrame=target*CFrame.new(115,1,z),Transparency=1,CanCollide=false})
   marker.CanQuery=false;marker.CanTouch=false
  end
  return g
 end
 garage("ConcessionariaDoVale",Vector3.new(-45,3,58),true)
 garage("RetiradaConcessionaria",Vector3.new(100,2,230),false)
 for _,model in ipairs(descendants) do
  if model:IsA("Model") and (model.Name=="door" or model.Name=="DEALERGARAGE") then connectDoor(model) end
 end
 -- Actual Little Life cars are displayed in the open forecourt; no foreign vehicle system.
 for i,id in ipairs({"L5","R18","Coro"}) do
  local spec=GameConfig.Cars[id]
  if spec then
   local z=180+(i-1)*60
   local car=CarBuilder.build(spec,target*CFrame.new(-135,spec.Hover,z))
   car.Name="Exposicao_"..id
   for _,p in ipairs(car:GetDescendants()) do
    if p:IsA("BasePart") then p.Anchored=true;p.CanTouch=false end
    if p:IsA("Seat") or p:IsA("VehicleSeat") then p.Disabled=true end
    if p:IsA("ProximityPrompt") or p:IsA("LuaSourceContainer") then p:Destroy() end
   end
   car:SetAttribute("Exhibition",true);car.Parent=site
   board(target*CFrame.new(-135,4,z+17),spec.Name.." • veja o catálogo",26)
  end
 end
 return site
end
return Builder
