-- Interface do taxista. Apenas apresenta o despacho e envia intenções ao servidor.
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Workspace=game:GetService("Workspace")
local GameConfig=require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local UIScaler=require(script.Parent:WaitForChild("UIScaler"))
local MapController=require(script.Parent:WaitForChild("MapController"))
local TaxiController={}
local player=Players.LocalPlayer
local initialized=false
local request,card,title,route,instruction,actionButton,panel,panelTitle,panelInfo,panelAction
local state={onDuty=false,stage="idle",count=0,slots=2}
local prompts={}
local panelKind="duty"
local BLUE=Color3.fromRGB(24,76,147)
local YELLOW=Color3.fromRGB(245,195,49)
local INK=Color3.fromRGB(35,44,58)
local function corner(parent,radius)local c=Instance.new("UICorner");c.CornerRadius=UDim.new(0,radius);c.Parent=parent end
local function text(parent,value,pos,size,pixels,bold)
 local t=Instance.new("TextLabel");t.BackgroundTransparency=1;t.Position=pos;t.Size=size
 t.Font=bold and Enum.Font.GothamBold or Enum.Font.GothamMedium;t.TextSize=pixels or 14
 t.TextColor3=INK;t.TextXAlignment=Enum.TextXAlignment.Left;t.TextYAlignment=Enum.TextYAlignment.Center;t.TextWrapped=true;t.Text=value;t.Parent=parent;return t
end
local function button(parent,value,pos,size,callback)
 local b=Instance.new("TextButton");b.Text=value;b.Position=pos;b.Size=size;b.BackgroundColor3=BLUE
 b.BorderSizePixel=0;b.Font=Enum.Font.GothamBold;b.TextSize=13;b.TextColor3=Color3.new(1,1,1);b.Parent=parent;corner(b,8);b.Activated:Connect(callback);return b
end
local function send(action,payload)if request then request:FireServer(action,payload)end end
local function refreshPrompts()
 for prompt in pairs(prompts)do
  if not prompt.Parent then prompts[prompt]=nil
  else prompt.Enabled=state.onDuty and prompt:GetAttribute("TaxiOwnerUserId")==player.UserId
   and prompt:GetAttribute("TaxiTripId")==state.tripId and prompt:GetAttribute("TaxiStage")==state.stage end
 end
end
local function watchPrompt(item)
 if item:IsA("ProximityPrompt")and(item.Name=="TaxiPickupPrompt"or item.Name=="TaxiDropoffPrompt")then
  prompts[item]=true
  for _,attr in ipairs({"TaxiOwnerUserId","TaxiTripId","TaxiStage"})do item:GetAttributeChangedSignal(attr):Connect(refreshPrompts)end
  refreshPrompts()
 end
end
local function refreshPanel()
 if not panel or not panel.Visible then return end
 if panelKind=="dispatch"then
  panelTitle.Text="Despacho LXR Táxis"
  panelInfo.Text=state.stage=="idle" and "Retire seu uniforme e o táxi da empresa. O despacho enviará o ponto de embarque e o destino do passageiro.\n\nA corrida será paga ao chegar ao destino, com o táxi parado e você ao volante."
   or "Você já tem uma corrida em andamento. Confira o destino no mapa. Para receber outra, conclua ou cancele a atual."
  panelAction.Text=state.stage=="idle"and"Receber uma corrida"or"Cancelar corrida atual"
 else
  panelTitle.Text="LXR Táxis · Central de serviço"
  panelInfo.Text=("Vagas de taxista: %d/%d\n\nEntre em serviço, retire o uniforme no vestiário e o carro na garagem da LXR. Uniforme e táxi ficam vinculados a este emprego."):format(state.count,state.slots)
  panelAction.Text=state.onDuty and"Encerrar meu turno"or"Entrar como taxista"
 end
end
local function refresh()
 if not card then return end
 card.Visible=state.onDuty
 title.Text=("LXR TÁXIS · %d/%d em serviço"):format(state.count,state.slots)
 if state.stage=="pickup"then
  route.Text="BUSCAR · "..tostring(state.pickupName or"Passageiro")
  instruction.Text="Siga o marcador no mapa. Pare perto do passageiro e fique ao volante."
  actionButton.Visible=true;actionButton.Text="Embarcar passageiro"
 elseif state.stage=="dropoff"then
  route.Text="DESTINO · "..tostring(state.destinationName or"Destino da corrida")
  instruction.Text="Leve o passageiro com segurança. Pare no destino para concluir."
  actionButton.Visible=true;actionButton.Text="Concluir corrida"
 else
  route.Text="AGUARDANDO DESPACHO"
  instruction.Text="Retire seu uniforme e táxi na LXR. Busque uma corrida no balcão de despacho."
  actionButton.Visible=false
 end
 if state.onDuty then MapController.setTarget("LXR Táxis",typeof(state.target)=="Vector3"and state.target or nil)
 elseif state.hadDuty then MapController.setTarget(nil,nil)end
 state.hadDuty=state.onDuty
 refreshPrompts();refreshPanel()
end
function TaxiController.handle(kind,data)
 if type(data)~="table"then return end
 if kind=="TaxiState"then
  state.onDuty=data.onDuty==true;state.stage=type(data.stage)=="string"and data.stage or"idle"
  state.tripId=data.tripId;state.target=data.target;state.pickupName=data.pickupName;state.destinationName=data.destinationName
  if type(data.count)=="number"then state.count=math.max(0,math.floor(data.count))end
  if type(data.slots)=="number"then state.slots=math.max(1,math.floor(data.slots))end
  if not state.onDuty and panel then panel.Visible=false end
  refresh()
 elseif kind=="TaxiPanel"and panel then
  panelKind=data.panel=="dispatch"and"dispatch"or"duty"
  if type(data.onDuty)=="boolean"then state.onDuty=data.onDuty end
  if type(data.stage)=="string"then state.stage=data.stage end
  if type(data.count)=="number"then state.count=data.count end
  if type(data.slots)=="number"then state.slots=data.slots end
  panel.Visible=true;refreshPanel()
 end
end
local function readAttributes()
 state.onDuty=player:GetAttribute("TaxiDuty")==true
 state.stage=player:GetAttribute("TaxiStage")or"idle";state.tripId=player:GetAttribute("TaxiTripId")
 state.target=player:GetAttribute("TaxiTargetPosition");state.pickupName=player:GetAttribute("TaxiPickupName")
 state.destinationName=player:GetAttribute("TaxiDestinationName")
 refresh()
end
function TaxiController.init()
 if initialized then return end
 initialized=true
 request=ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(GameConfig.Remotes.TaxiRequest or"TaxiRequest")
 local gui=Instance.new("ScreenGui");gui.Name="TaxiUI";gui.ResetOnSpawn=false;gui.DisplayOrder=6;gui.Parent=player:WaitForChild("PlayerGui")
 card=Instance.new("Frame");card.Name="LXRTripCard";card.Size=UDim2.fromOffset(350,154);card.Position=UDim2.fromOffset(16,112)
 card.BackgroundColor3=Color3.fromRGB(255,246,209);card.BorderSizePixel=0;card.Visible=false;card.Parent=gui;corner(card,12);UIScaler.attach(card)
 local stripe=Instance.new("Frame");stripe.Size=UDim2.new(1,0,0,7);stripe.BackgroundColor3=YELLOW;stripe.BorderSizePixel=0;stripe.Parent=card;corner(stripe,6)
 title=text(card,"",UDim2.fromOffset(12,14),UDim2.fromOffset(262,20),12,true);title.TextColor3=BLUE
 button(card,"Sair",UDim2.fromOffset(286,13),UDim2.fromOffset(52,25),function()send("Duty",false)end)
 route=text(card,"",UDim2.fromOffset(12,42),UDim2.fromOffset(326,29),14,true)
 instruction=text(card,"",UDim2.fromOffset(12,72),UDim2.fromOffset(326,37),12,false)
 actionButton=button(card,"",UDim2.fromOffset(12,115),UDim2.fromOffset(326,29),function()
  if state.stage=="pickup"then send("Pickup")elseif state.stage=="dropoff"then send("Dropoff")end
 end)
 panel=Instance.new("Frame");panel.Name="LXRDispatchPanel";panel.AnchorPoint=Vector2.new(0.5,0.5);panel.Position=UDim2.fromScale(0.5,0.5)
 panel.Size=UDim2.fromOffset(390,300);panel.BackgroundColor3=Color3.fromRGB(255,248,220);panel.BorderSizePixel=0;panel.Visible=false;panel.Parent=gui;corner(panel,14);UIScaler.attach(panel)
 panelTitle=text(panel,"",UDim2.fromOffset(18,14),UDim2.fromOffset(315,35),20,true);panelTitle.TextColor3=BLUE
 button(panel,"×",UDim2.new(1,-45,0,14),UDim2.fromOffset(30,30),function()panel.Visible=false end)
 panelInfo=text(panel,"",UDim2.fromOffset(18,58),UDim2.new(1,-36,0,159),14,false)
 panelAction=button(panel,"",UDim2.fromOffset(18,236),UDim2.new(1,-36,0,44),function()
  if panelKind=="dispatch"then send(state.stage=="idle"and"Accept"or"Cancel")else send("Duty",not state.onDuty)end
  panel.Visible=false
 end)
 for _,attr in ipairs({"TaxiDuty","TaxiStage","TaxiTargetPosition","TaxiPickupName","TaxiDestinationName","TaxiTripId"})do
  player:GetAttributeChangedSignal(attr):Connect(readAttributes)
 end
 Workspace.DescendantAdded:Connect(watchPrompt)
 for _,item in ipairs(Workspace:GetDescendants())do watchPrompt(item)end
 readAttributes()
end
return TaxiController
