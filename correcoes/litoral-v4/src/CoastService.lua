-- Local server interactions; reuses the city's NPC, wallet and inventory services.
local Players=game:GetService("Players")
local Workspace=game:GetService("Workspace")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local NPCKit=require(script.Parent:WaitForChild("NPCKit"))
local Economy=require(script.Parent:WaitForChild("EconomyService"))
local Inventory=require(script.Parent:WaitForChild("InventoryService"))
local Config=require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local Service={}
local last={};local initialized=false
local FOOD={picole={name="Picolé do Litoral",price=25,heal=10,color=Color3.fromRGB(244,139,171)},agua={name="Água do Litoral",price=15,heal=5,color=Color3.fromRGB(92,193,228)}}
local function livingNear(player,point,range)
 local character=player.Character
 local root=character and character:FindFirstChild("HumanoidRootPart")
 local hum=character and character:FindFirstChildOfClass("Humanoid")
 if root and hum and hum.Health>0 and (root.Position-point.Position).Magnitude<=range then return hum end
end
local function snack(player,info)
 local tool=Instance.new("Tool");tool.Name=info.name;tool.CanBeDropped=false
 local h=Instance.new("Part");h.Name="Handle";h.Size=Vector3.new(.7,1.4,.5);h.Color=info.color
 h.Material=Enum.Material.SmoothPlastic;h.CanCollide=false;h.CanTouch=false;h.Massless=true;h.Parent=tool
 local used=false
 tool.Activated:Connect(function()
  local c=player.Character;local hum=c and c:FindFirstChildOfClass("Humanoid")
  if used or tool.Parent~=c or not hum or hum.Health<=0 then return end
  used=true;hum.Health=math.min(hum.MaxHealth,hum.Health+info.heal);tool:Destroy()
 end)
 return tool
end
function Service.init(remotes)
 if initialized then return end
 local map=Workspace:FindFirstChild("Map");local coast=map and map:FindFirstChild("Litoral")
 if not coast then return end
 initialized=true
 local ui=remotes[Config.Remotes.UIUpdate]
 local function notice(player,text)ui:FireClient(player,"Notice",{text=text})end
 Players.PlayerRemoving:Connect(function(p)last[p]=nil end)
 for _,point in ipairs(coast:GetDescendants()) do
  local food=FOOD[point:GetAttribute("FoodId")]
  if food and point:IsA("BasePart") then
   local prompt=Instance.new("ProximityPrompt");prompt.Name="ComprarLanche"
   prompt.ActionText="Comprar • $"..food.price;prompt.ObjectText=food.name
   prompt.KeyboardKeyCode=Enum.KeyCode.E;prompt.HoldDuration=.4;prompt.MaxActivationDistance=10;prompt.RequiresLineOfSight=false;prompt.Parent=point
   prompt.Triggered:Connect(function(player)
    if not livingNear(player,point,12) or player:GetAttribute("Preso") or player:GetAttribute("Caido") then return end
    local now=os.clock();if now-(last[player] or -math.huge)<1 then return end;last[player]=now
    local backpack=player:FindFirstChild("Backpack")
    if not backpack then return end
    if backpack:FindFirstChild(food.name) or player.Character:FindFirstChild(food.name) then return notice(player,"Você já tem esse lanche na mochila.") end
    if not Inventory.hasRoom(player) then return notice(player,"Abra espaço na mochila antes de comprar.") end
    if not Economy.spend(player,food.price,"Litoral: "..food.name) then return notice(player,"Saldo insuficiente para esse lanche.") end
    local tool=snack(player,food);tool.Parent=backpack
    notice(player,food.name.." na mochila. Equipe e use para consumir.")
   end)
  end
 end
 -- Only fifteen static characters: reuse NPCKit and avoid pathfinding loops.
 task.spawn(function()
  local names={"Bia","Caio","Lia","Rafa"}
  for _,point in ipairs(coast:GetDescendants()) do
   if point:IsA("BasePart") and point:GetAttribute("Tourist") then
    local style=point:GetAttribute("Style") or 1;local vendor=point:GetAttribute("Vendor")
    local npc=NPCKit.spawn(point.CFrame,{name=vendor and "Atendente da praia" or names[style],shirt=point.Color,pants=Color3.fromRGB(215,193,152),anchored=true,important=true,showName=true})
    if npc then
     npc:SetAttribute("CoastalTourist",true)
     if not vendor and style%2==0 then NPCKit.hold(npc,"CameraDePasseio",Vector3.new(.8,.6,.4),Color3.fromRGB(45,53,60),Enum.Material.SmoothPlastic) end
     local root=npc:FindFirstChild("HumanoidRootPart")
     if root then
      local prompt=Instance.new("ProximityPrompt");prompt.Name="ConversarPraia";prompt.ActionText="Conversar";prompt.ObjectText=vendor and "Atendente" or "Turista"
      prompt.KeyboardKeyCode=Enum.KeyCode.E;prompt.MaxActivationDistance=9;prompt.RequiresLineOfSight=false;prompt.Parent=root
      local nextTalk=0
      prompt.Triggered:Connect(function(player)
       if not livingNear(player,root,11) or os.clock()<nextTalk then return end
       nextTalk=os.clock()+3
       NPCKit.say(npc,vendor and "Água no quiosque e picolés no carrinho! Veja os preços nas placas." or "Que vista bonita! O mirante fica seguindo a estrada. A ponte ainda está em obras.",5)
      end)
     end
    end
    task.wait(.15)
   end
  end
 end)
end
return Service
