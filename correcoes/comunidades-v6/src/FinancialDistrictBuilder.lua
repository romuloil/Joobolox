-- Restauração seletiva do distrito: preserva banco, obra, litoral e concessionária atuais.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local CityRoads = require(Shared:WaitForChild("CityRoads"))
local B = GameConfig.Bank
local WHITE = Color3.new(1, 1, 1)
local FinancialDistrictBuilder = {}
-- Prédios, comércio e jardins; reaproveita os construtores do mapa.
function FinancialDistrictBuilder.plan(map, helpers)
 local D = CityRoads.FinancialDistrict
 local plan = { map = map, items = {}, mountains = {}, landscaping = {}, coast = D.Coast }
 local function reserve(kind, cf, w, d, extra)
  local area = helpers.rect(cf, w + 4, d + 4)
  if not helpers.isFree(area) then return false end
  helpers.occupy(area)
  if kind == "praca" and (#plan.items + 1) % 2 == 0 then kind = "estacionamento" end
  table.insert(plan.items, { kind = kind, lot = cf, w = w, d = d, index = #plan.items + 1, street = extra })
  return true
 end
 -- Mesmo CFrame do banco original; passeios ficam fora do lote e do subsolo.
 local R=GameConfig.Rodovia
 local bankCf=helpers.lotBeside(Vector3.new(0,0,R.ExitZ),Vector3.new(R.ExitLength,0,R.ExitZ),B.Road.T,B.Road.Side,B.LotD)
 for _,strip in ipairs({{x=-134,z=0,w=20,d=226},{x=134,z=0,w=20,d=226},{x=-36,z=141,w=168,d=20}}) do
  local cf=bankCf*CFrame.new(strip.x,0,strip.z)
  local area=helpers.rect(cf,strip.w,strip.d)
  if helpers.isFree(area) then
   helpers.occupy(area)
   table.insert(plan.landscaping,{cf=cf,w=strip.w,d=strip.d})
  end
 end
 local frontA = Vector3.new(180, 0, GameConfig.Rodovia.ExitZ)
 local frontB = Vector3.new(1040, 0, GameConfig.Rodovia.ExitZ)
 for i, t in ipairs({80,190,300,510,620,730}) do
  reserve(i % 3 == 0 and "praca" or "servico", helpers.lotBeside(frontA, frontB, t, -1, 84), 80, 80, GameConfig.Rodovia.ValeName)
 end
 for row, streetIndex in ipairs({1,2,6,7}) do
  local st = D.Streets[streetIndex]
  for _, side in ipairs({-1,1}) do
   for i, t in ipairs({80,190,300,510,620,730}) do
    local kind = i % 3 == 0 and "praca" or ((i + row) % 2 == 0 and "torre" or "servico")
    reserve(kind, helpers.lotBeside(st.A, st.B, t, side, st.Kind == "boulevard" and 120 or 84), 80, 80, st.Name)
   end
  end
 end
 -- Ruas laterais e traseira: só preenche lotes realmente livres, sem invadir o parque.
 for _,idx in ipairs({8,9,10}) do
  local st=D.Streets[idx]
  for _,side in ipairs({-1,1}) do
   for t=65,(st.B-st.A).Magnitude-40,110 do
    reserve(t==65 and "torre" or "servico",helpers.lotBeside(st.A,st.B,t,side,84),80,80,st.Name)
   end
  end
 end
 -- Mantém a ordem dos lotes principais antes do preenchimento lateral.
 local originalCount=#plan.items
 for _,idx in ipairs({3,4,5,8,10,11,12,13,14}) do
  local st=D.Streets[idx]
  for _,side in ipairs({-1,1}) do
   for t=65,(st.B-st.A).Magnitude-45,94 do
    local kind=(#plan.items-originalCount)%3==0 and "servico" or "torre"
    reserve(kind,helpers.lotBeside(st.A,st.B,t,side,84),80,80,st.Name)
   end
  end
 end
 plan.originalCount=originalCount
 plan.previousLots=#plan.items
 for _,st in ipairs(CityRoads.FinancialExtension or {})do
  for _,side in ipairs({-1,1})do
   for t=65,(st.B-st.A).Magnitude-45,100 do
    local kind=(#plan.items-plan.previousLots)%9==8 and "praca" or "servico"
    if reserve(kind,helpers.lotBeside(st.A,st.B,t,side,84),80,80,st.Name)then
     plan.items[#plan.items].extension=true
    end
   end
  end
 end
 return plan
end

function FinancialDistrictBuilder.build(plan, helpers, groups)
 if not plan then return end
 local root = helpers.model("DistritoFinanceiro", plan.map)
 root:SetAttribute("PlaceName", CityRoads.FinancialDistrict.Name)
 root:SetAttribute("Revision", "Distrito restaurado • mapa atual")
 local PAV = Color3.fromRGB(196,199,198)
 local BLUE = Color3.fromRGB(25,66,112)
 local GREEN = Color3.fromRGB(74,123,76)
 local function part(parent, name, size, cf, color, material, collide, class)
  return helpers.makePart(parent, {ClassName=class,Name=name,Size=size,CFrame=cf,Color=color,Material=material or Enum.Material.Concrete,CanCollide=collide})
 end
 local function sign(parent, cf, title, width)
  local p=part(parent,"Identificacao",Vector3.new(width or 24,4,.25),cf,BLUE,Enum.Material.Metal,false)
  helpers.addSurfaceText(p,title,Color3.new(1,1,1),BLUE)
  return p
 end
 local function seat(parent, cf)
  local s=part(parent,"Assento",Vector3.new(4,1,2),cf,Color3.fromRGB(70,77,82),Enum.Material.Wood,true,"Seat")
  s.CanTouch=false
  s:SetAttribute("SeatText","Descansar no distrito")
  part(parent,"Encosto",Vector3.new(4,2,.35),cf*CFrame.new(0,1,1),BLUE)
 end
 local services={"Vértice Coworking","Central de Empresas","Café da Praça","Galeria do Vale","Imobiliária Horizonte","Centro de Negócios"}
 local towers={"Torre Vértice","Edifício Alameda","Torre Capital","Edifício Aurora","Torre do Vale","Edifício Conexões"}
 local serviceIndex,towerIndex=0,0
 helpers.withRng(Random.new(11092026),function()
  for _,item in ipairs(plan.items) do
   local cf=item.lot
   -- Passeio contínuo até a calçada e dentro do lote: nenhum degrau alto na entrada.
   part(root,"Passeio",Vector3.new(80,.25,80),cf*CFrame.new(0,.55,0),PAV)
   if item.kind=="torre" then
    towerIndex+=1
    local name=towers[(towerIndex-1)%#towers+1]
    local b=helpers.financialTower(groups,{lot=cf,number=100+towerIndex*2,cfg={Name=name,Floors=item.index<=plan.originalCount and (12+(towerIndex%5)*3) or (6+(towerIndex%4)*2),Style=towerIndex%3==0 and "sacadas" or "vidro",Wall=towerIndex%3==0 and Color3.fromRGB(225,216,197) or Color3.fromRGB(204,217,224),Accent=BLUE}},item.street)
    b:SetAttribute("District",CityRoads.FinancialDistrict.Name)
    b:SetAttribute("MixedUse",true)
   elseif item.kind=="servico" then
    serviceIndex+=1
    local name=services[(serviceIndex-1)%#services+1]
    local cfShop=cf*CFrame.new(0,0,-10)
    local b=helpers.buildShop(root,cfShop,name,Color3.fromRGB(229,232,228),BLUE)
    b:SetAttribute("District",CityRoads.FinancialDistrict.Name)
    b:SetAttribute("Curb",helpers.curbOf(cf,80))
    -- Pavimentos comerciais acima da loja; não alteram IDs das moradias já compradas.
    if item.extension then
     b:SetAttribute("ExtensionV6",true)
     local floors=4+item.index%7;local height=floors*7
     local upper=cfShop*CFrame.new(0,23+height/2,0)
     part(b,"BlocoEscritorios",Vector3.new(40,height,32),upper,Color3.fromRGB(61,92,113),Enum.Material.Glass)
     for f=0,floors do
      part(b,"LajeEscritorios",Vector3.new(41,.4,33),cfShop*CFrame.new(0,23+f*7,0),PAV,Enum.Material.Concrete)
     end
     for _,x in ipairs({-20,-10,0,10,20})do
      for _,z in ipairs({-16.2,16.2})do
       part(b,"MontanteFachada",Vector3.new(.4,height,.4),cfShop*CFrame.new(x,23+height/2,z),BLUE,Enum.Material.Metal)
      end
     end
    end
    -- Interior acessível: balcão de recepção, estações de trabalho e mesas.
    part(b,"BalcaoRecepcao",Vector3.new(10,3,3),cfShop*CFrame.new(-12,2.5,-6),Color3.fromRGB(110,78,52),Enum.Material.Wood)
    sign(b,cfShop*CFrame.new(-12,5,-4),"RECEPÇÃO",10)
    for _,x in ipairs({-10,10}) do
     part(b,"MesaTrabalho",Vector3.new(8,.35,5),cfShop*CFrame.new(x,3.5,7),Color3.fromRGB(130,99,67),Enum.Material.Wood)
     part(b,"PeMesa",Vector3.new(.6,2.4,.6),cfShop*CFrame.new(x,2.1,7),BLUE,Enum.Material.Metal)
     seat(b,cfShop*CFrame.new(x,1.7,11)*CFrame.Angles(0,math.pi,0))
     if name~="Café da Praça" then
      part(b,"Monitor",Vector3.new(3,2,.25),cfShop*CFrame.new(x,4.7,8),BLUE,Enum.Material.SmoothPlastic,false)
     end
    end
   elseif item.kind=="estacionamento" then
    local parking=helpers.model("EstacionamentoFinanceiro",root)
    parking:SetAttribute("PlaceName","Estacionamento do Vale")
    part(parking,"Asfalto",Vector3.new(78,.12,78),cf*CFrame.new(0,.73,0),Color3.fromRGB(55,59,64),Enum.Material.Asphalt)
    -- Via central livre e seis vagas, sem portão bloqueando a entrada.
    for _,side in ipairs({-1,1}) do
     for _,z in ipairs({-22,-6,10,26}) do
      part(parking,"FaixaVaga",Vector3.new(23,.04,.25),cf*CFrame.new(side*24,.82,z),WHITE,Enum.Material.SmoothPlastic,false)
     end
    end
    sign(parking,cf*CFrame.new(27,5,-35),"ESTACIONAMENTO\nLIVRE",20)
   else
    local plaza=helpers.model("PracaFinanceira",root)
    plaza:SetAttribute("PlaceName","Praça do Vale")
    local basin=helpers.flatCylinder(plaza,"EspelhoDAgua",(cf*CFrame.new(0,1.1,3)).Position,9,.6,BLUE,Enum.Material.Slate)
    local water=helpers.flatCylinder(plaza,"Agua",(cf*CFrame.new(0,1.45,3)).Position,8,.1,Color3.fromRGB(77,160,182),Enum.Material.Glass)
    water.CanCollide=false
    part(plaza,"Escultura",Vector3.new(2,12,2),cf*CFrame.new(0,7,3)*CFrame.Angles(0,0,.25),Color3.fromRGB(185,150,81),Enum.Material.Metal)
    for _,x in ipairs({-20,20}) do
     for _,z in ipairs({-14,20}) do seat(plaza,cf*CFrame.new(x,1.3,z)) end
    end
    sign(plaza,cf*CFrame.new(0,3,-32),"PRAÇA DO VALE",24)
   end
   for _,x in ipairs({-33,33}) do
    helpers.buildTree(root,(cf*CFrame.new(x,.7,26)).Position,.8)
    helpers.buildLamp(root,cf*CFrame.new(x,-.1,-32))
   end
   task.wait() -- distribui a construção sem travar um quadro inteiro
  end
 end)
 local gardens=helpers.model("EntornoDoBanco",plan.map)
 for _,strip in ipairs(plan.landscaping) do
  part(gardens,"BaseNivelada",Vector3.new(strip.w,.5,strip.d),strip.cf*CFrame.new(0,.25,0),Color3.fromRGB(110,114,105),Enum.Material.Ground)
  part(gardens,"Calcada",Vector3.new(strip.w,.3,strip.d),strip.cf*CFrame.new(0,.65,0),PAV)
  local longX=strip.w>strip.d
  local length=math.max(strip.w,strip.d)
  for t=-length/2+14,length/2-14,32 do
   local cf=strip.cf*CFrame.new(longX and t or -6,0,longX and 6 or t)
   part(gardens,"Canteiro",Vector3.new(7,1.2,7),cf*CFrame.new(0,1.2,0),Color3.fromRGB(125,130,122),Enum.Material.Concrete)
   local mound=part(gardens,"TaludeJardim",Vector3.new(6,1.1,6),cf*CFrame.new(0,1.8,0),GREEN,Enum.Material.Grass,false)
   mound.Shape=Enum.PartType.Ball
   helpers.buildTree(gardens,cf.Position+Vector3.new(0,2,0),.7)
   helpers.buildLamp(gardens,cf*CFrame.new(longX and 0 or 12,-.1,longX and -12 or 0))
  end
 end
 root:SetAttribute("Lots",#plan.items)
 root:SetAttribute("ExtensionLots",#plan.items-(plan.previousLots or #plan.items))
 root:SetAttribute("Towers",towerIndex)
 root:SetAttribute("Services",serviceIndex)
 return root
end

return FinancialDistrictBuilder
