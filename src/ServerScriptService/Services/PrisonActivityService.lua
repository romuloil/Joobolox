-- Refeitório, enfermaria, exercício, visitas, gavetas e cartões da prisão.
-- Prompts nativos apenas solicitam ações. Papel, posição, tempo e inventário
-- pertencem ao servidor; nenhum atributo de apresentação concede permissão.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Config = require(Shared:WaitForChild("PrisonActivityConfig"))
local Rules = require(Shared:WaitForChild("PrisonActivityRules"))
local Security = require(script.Parent:WaitForChild("SecurityService"))

local Service = {}
local initialized = false
local sites, hooks, ui
local cards, storedCards, cooldowns, exercises, holds, officerPrompts = {}, {}, {}, {}, {}, {}
local connections, exerciseCounts, restrictedAt = {}, {}, {}
local function now() return Workspace:GetServerTimeNow() end
local function notice(player, text)
 if player.Parent == Players then ui:FireClient(player, "Notice", {text = text}) end
end
local function positionOf(prompt)
 local parent = prompt and prompt.Parent
 if parent and parent:IsA("BasePart") then return parent.Position end
 if parent and parent:IsA("Attachment") then return parent.WorldPosition end
 return nil
end
local function living(player)
 if not player or player.Parent ~= Players then return nil end
 return Security.getLivingCharacter(player)
end
local function police(player)
 return hooks.policeService.isOnDuty(player) == true
end
local function detained(player)
 return hooks.prisonService.isDetained(player) == true
end
local function releasedToYard(player)
 if not detained(player) then return false end
 if hooks.prisonService.isCellLocked then return not hooks.prisonService.isCellLocked(player) end
 local opens = player:GetAttribute("PrisonCellOpensAt")
 return Rules.finite(opens) and now() >= opens
end
local function active(player)
 local _, humanoid, root = living(player)
 local stunned = player:GetAttribute("StunnedUntil")
 if not root or not Rules.finitePoint(root.Position)
  or (Rules.finite(stunned) and now() < stunned) then return nil end
 return humanoid, root
end
local function hasLineOfSight(player, position, extra)
 local character, _, root = living(player)
 if not root then return false end
 local params = RaycastParams.new()
 params.FilterType = Enum.RaycastFilterType.Exclude
 params.FilterDescendantsInstances = extra and {character, extra} or {character}
 params.IgnoreWater = true
 local delta = position - root.Position
 -- O último meio stud pode tocar o balcão que contém o prompt; não autoriza
 -- atravessar paredes no resto do trajeto.
 local length = delta.Magnitude
 if length < 0.01 then return true end
 return Workspace:Raycast(root.Position, delta.Unit * math.max(0, length - 0.6), params) == nil
end
local function near(player, prompt, skipVisibility)
 local humanoid, root = active(player)
 local position = positionOf(prompt)
 if not root or not Rules.finitePoint(position)
  or not Rules.inRange((root.Position - position).Magnitude, Config.InteractionDistance) then return nil end
 if not skipVisibility and not hasLineOfSight(player, position, prompt.Parent) then return nil end
 return humanoid, root
end
local function setCardState(player)
 player:SetAttribute("PrisonKeycard", cards[player] == true)
 player:SetAttribute("PrisonStoredKeycard", storedCards[player] ~= nil)
end
local function ownCell(player)
 return hooks.prisonService.getAssignedCellId(player)
end
local function recordCooldown(player, key, interval)
 local record = cooldowns[player]
 if not record then record = {}; cooldowns[player] = record end
 if not Rules.available(record[key], now(), interval) then return false end
 record[key] = now()
 return true
end
function Service.hasKeycard(player)
 return cards[player] == true and detained(player)
end
function Service.clearPlayer(player)
 cards[player], storedCards[player], exercises[player], holds[player] = nil, nil, nil, nil
 cooldowns[player] = nil
 exerciseCounts[player] = nil
 restrictedAt[player] = nil
 player:SetAttribute("PrisonExercisesCompleted", nil)
 player:SetAttribute("PrisonVisitorRegisteredAt", nil)
 setCardState(player)
 for thief, hold in pairs(holds) do if hold.officer == player then holds[thief] = nil end end
 player:SetAttribute("PrisonExerciseUntil", nil)
end

local function stationAccess(player, station)
 local humanoid = near(player, station.prompt)
 if not humanoid then return nil end
 if station.kind == "visitor" then
  if detained(player) then notice(player, "A recepção de visitas é uma área pública; permaneça no setor de internos."); return nil end
 else
  if not police(player) and not releasedToYard(player) then
   notice(player, "Aguarde a abertura da sua cela para usar as áreas comuns."); return nil
  end
 end
 return humanoid
end
local function useStation(player, station)
 local humanoid = stationAccess(player, station)
 if not humanoid or not Security.checkRate(player, "PrisonActivity", 0.35) then return false end
 if station.kind == "meal" or station.kind == "medical" then
  local medical = station.kind == "medical"
  local amount = medical and Config.MedicalHeal or Config.MealHeal
  local maximum = humanoid.MaxHealth
  local health = Rules.healedHealth(humanoid.Health, maximum, amount)
  if not health then return false end
  if not recordCooldown(player, station.kind, medical and Config.MedicalCooldown or Config.MealCooldown) then
   notice(player, medical and "Aguarde antes de receber outro atendimento." or "Aguarde a próxima refeição.")
   return false
  end
  humanoid.Health = health
  notice(player, medical and "Atendimento concluído. Sua saúde foi recuperada parcialmente."
   or "Refeição servida. Bom apetite! Você recuperou um pouco de saúde.")
  return true
 elseif station.kind == "exercise" then
  if exercises[player] or not recordCooldown(player, "exercise", Config.ExerciseCooldown) then
   notice(player, "Aguarde antes de iniciar outra série."); return false
  end
  local record = {station = station, character = player.Character, endsAt = now() + Config.ExerciseSeconds}
  exercises[player] = record
  player:SetAttribute("PrisonExerciseUntil", record.endsAt)
  notice(player, "Série iniciada: permaneça junto ao equipamento por quatro segundos.")
  return true
 elseif station.kind == "visitor" then
  if not recordCooldown(player, "visitor", 4) then return false end
  player:SetAttribute("PrisonVisitorRegisteredAt", now())
  notice(player, "Visita registrada. Use os bancos do pavilhão para aguardar. Os internos permanecem no setor protegido; a visita não libera portões.")
  return true
 end
 return false
end

local function useDrawer(player, drawer)
 if not releasedToYard(player) or ownCell(player) ~= drawer.id or not near(player, drawer.prompt)
  or not Security.checkRate(player, "PrisonDrawer", 0.8) then return false end
 if cards[player] then
  if storedCards[player] then notice(player, "Sua gaveta já contém um cartão."); return false end
  cards[player], storedCards[player] = nil, drawer.id
  notice(player, "Cartão guardado na gaveta da sua cela.")
 elseif storedCards[player] == drawer.id then
  storedCards[player], cards[player] = nil, true
  notice(player, "Cartão retirado da sua gaveta.")
 else
  notice(player, "Gaveta vazia. Você pode guardar um cartão de acesso durante esta pena.")
  return false
 end
 setCardState(player)
 return true
end
local function doorOccupied(door)
 for _, player in ipairs(Players:GetPlayers()) do
  local _, _, root = living(player)
  if root then
   local point = door.closed:PointToObjectSpace(root.Position)
   if math.abs(point.X) <= door.part.Size.X / 2 + 2 and math.abs(point.Y) <= door.part.Size.Y / 2 + 2
    and math.abs(point.Z) <= door.part.Size.Z / 2 + 2 then return true end
  end
 end
 return false
end
local function moveDoor(door, open)
 door.isOpen = open
 door.part:SetAttribute("Open", open)
 door.part.CFrame = open and door.open or door.closed
 door.part.CanCollide = true
end
local function autoClose(door, epoch)
 if not door.part.Parent or door.accessEpoch ~= epoch or door.part:GetAttribute("Open") ~= true then return end
 if door.busy or doorOccupied(door) then
  task.delay(0.5, function() autoClose(door, epoch) end)
  return
 end
 moveDoor(door, false)
end
local function useDoor(player, door)
 if not near(player, door.prompt) or door.busy or not Security.checkRate(player, "PrisonCardDoor", 0.6) then return false end
 if not police(player) then
  if not releasedToYard(player) or not Service.hasKeycard(player) then
   notice(player, "Porta restrita: requer policial em serviço ou cartão de acesso."); return false
  end
  if not hooks.policeService.registerPrisonOffense(player, "Área restrita") then return false end
 end
 door.accessEpoch = (door.accessEpoch or 0) + 1
 local epoch = door.accessEpoch
 moveDoor(door, true)
 task.delay(Config.DoorOpenSeconds, function() autoClose(door, epoch) end)
 notice(player, "Acesso liberado por alguns segundos. Afaste-se da folha da porta.")
 return true
end

local function canPickpocket(thief, officer)
 if thief == officer or not releasedToYard(thief) or not police(officer)
  or cards[thief] or storedCards[thief] then return false end
 local _, thiefRoot = active(thief)
 local _, officerRoot = active(officer)
 if not thiefRoot or not officerRoot then return false end
 local delta = thiefRoot.Position - officerRoot.Position
 local horizontal = Vector3.new(delta.X, 0, delta.Z)
 local distance = delta.Magnitude
 if horizontal.Magnitude < 0.1 then return false end
 local behind = (-officerRoot.CFrame.LookVector):Dot(horizontal.Unit)
 local facing = thiefRoot.CFrame.LookVector:Dot(-horizontal.Unit)
 if not Rules.canPickpocket(distance, behind, facing, Config) then return false end
 return hasLineOfSight(thief, officerRoot.Position, officer.Character)
end
local function beginPickpocket(thief, officer)
 if not canPickpocket(thief, officer) or not Security.checkRate(thief, "PrisonPickHold", 0.3) then return end
 local record = cooldowns[thief]
 if not Rules.available(record and record.pickpocket, now(), Config.PickpocketCooldown) then return end
 holds[thief] = {officer = officer, startedAt = now(), character = thief.Character, officerCharacter = officer.Character}
end
local function endPickpocket(thief, officer)
 local hold = holds[thief]
 if not hold or hold.officer ~= officer then return end
 -- Triggered e HoldEnded podem chegar no mesmo frame em ordens diferentes.
 hold.endedAt = now()
 task.delay(0.3, function() if holds[thief] == hold then holds[thief] = nil end end)
end
local function finishPickpocket(thief, officer)
 local hold = holds[thief]
 holds[thief] = nil -- consome antes de callbacks; nunca duplica o cartão
 if not hold or hold.officer ~= officer or hold.character ~= thief.Character
  or hold.officerCharacter ~= officer.Character or now() - hold.startedAt < Config.PickpocketSeconds - 0.05
  or (hold.endedAt and now() - hold.endedAt > 0.3) or not canPickpocket(thief, officer) then return false end
 if not recordCooldown(thief, "pickpocket", Config.PickpocketCooldown) then return false end
 if not hooks.policeService.registerPrisonOffense(thief, "Furto de cartão") then return false end
 cards[thief] = true
 setCardState(thief)
 notice(thief, "Você pegou um cartão de acesso. O furto foi registrado como infração.")
 task.delay(1, function()
  if police(officer) then notice(officer, "Furto detectado: " .. thief.DisplayName .. " pegou um cartão de acesso.") end
 end)
 return true
end
local function removeOfficerPrompt(player)
 local prompt = officerPrompts[player]
 officerPrompts[player] = nil
 if prompt then prompt:Destroy() end
 for thief, hold in pairs(holds) do if hold.officer == player then holds[thief] = nil end end
end
local function refreshOfficerPrompt(player)
 removeOfficerPrompt(player)
 if not police(player) then return end
 local _, _, root = living(player)
 if not root then return end
 local prompt = Instance.new("ProximityPrompt")
 prompt.Name = "PrisonPickpocketPrompt"
 prompt.ActionText, prompt.ObjectText = "Pegar cartão discretamente", "Cartão policial"
 prompt.KeyboardKeyCode, prompt.HoldDuration = Enum.KeyCode.E, Config.PickpocketSeconds
 prompt.MaxActivationDistance, prompt.RequiresLineOfSight = Config.PickpocketDistance, false
 prompt:SetAttribute("PrisonPickpocket", true)
 prompt.Parent = root
 officerPrompts[player] = prompt
 prompt.PromptButtonHoldBegan:Connect(function(thief) beginPickpocket(thief, player) end)
 prompt.PromptButtonHoldEnded:Connect(function(thief) endPickpocket(thief, player) end)
 prompt.Triggered:Connect(function(thief) finishPickpocket(thief, player) end)
end
local function watchCharacter(player, character)
 if connections[player] then connections[player]:Disconnect(); connections[player] = nil end
 task.spawn(function()
  local humanoid = character:WaitForChild("Humanoid", 10)
  if not humanoid or player.Character ~= character or player.Parent ~= Players then return end
  connections[player] = humanoid.Died:Connect(function() Service.clearPlayer(player); removeOfficerPrompt(player) end)
 end)
end
local function watchPlayer(player)
 player:GetAttributeChangedSignal("PoliceDuty"):Connect(function() task.defer(function() refreshOfficerPrompt(player) end) end)
 player:GetAttributeChangedSignal("WorkRole"):Connect(function() refreshOfficerPrompt(player) end)
 player:GetAttributeChangedSignal("Detained"):Connect(function()
  if not detained(player) then Service.clearPlayer(player) end
 end)
 player.CharacterAdded:Connect(function(character)
  watchCharacter(player, character)
  Service.clearPlayer(player)
  removeOfficerPrompt(player)
  task.defer(function() if player.Parent == Players then refreshOfficerPrompt(player) end end)
 end)
 if player.Character then watchCharacter(player, player.Character) end
 refreshOfficerPrompt(player)
end
local function update()
 local time = now()
 for _, player in ipairs(Players:GetPlayers()) do
  if detained(player) and (not restrictedAt[player] or time - restrictedAt[player] >= 3) then
   local _, _, root = living(player)
   if root and Rules.finitePoint(root.Position) then
    for _, zone in ipairs(sites.restrictedZones or {}) do
     local point = zone.cf:PointToObjectSpace(root.Position)
     if math.abs(point.X) <= zone.half.X and math.abs(point.Y) <= zone.half.Y and math.abs(point.Z) <= zone.half.Z then
      if hooks.policeService.registerPrisonOffense(player, "Área restrita") then restrictedAt[player] = time end
      break
     end
    end
   end
  end
 end
 for thief, hold in pairs(holds) do
  if hold.character ~= thief.Character or hold.officerCharacter ~= hold.officer.Character
   or time - hold.startedAt > Config.PickpocketSeconds + 1 or not canPickpocket(thief, hold.officer) then holds[thief] = nil end
 end
 for player, record in pairs(exercises) do
  if player.Character ~= record.character or not stationAccess(player, record.station) then
   exercises[player] = nil; player:SetAttribute("PrisonExerciseUntil", nil)
   notice(player, "Série interrompida: permaneça junto ao equipamento para concluí-la.")
  elseif time >= record.endsAt then
   exercises[player] = nil; player:SetAttribute("PrisonExerciseUntil", nil)
   exerciseCounts[player] = (exerciseCounts[player] or 0) + 1
   player:SetAttribute("PrisonExercisesCompleted", exerciseCounts[player])
   notice(player, "Série concluída! Alongamento finalizado; você pode continuar sua rotina.")
  end
 end
end
function Service.init(remotes, civicSites, options)
 if initialized then return end
 hooks = options or {}
 assert(hooks.prisonService and hooks.policeService, "Serviços da prisão ausentes")
 sites = civicSites.prisonActivities or {stations = {}, drawers = {}, doors = {}}
 ui = assert(remotes[GameConfig.Remotes.UIUpdate], "UIUpdate ausente")
 initialized = true
 for _, station in ipairs(sites.stations or {}) do
  station.prompt:SetAttribute("PrisonActivityKind", station.kind)
  station.prompt:SetAttribute("PrisonActivityId", station.id)
  station.prompt.Enabled = true
  station.prompt.Triggered:Connect(function(player) useStation(player, station) end)
 end
 for _, drawer in ipairs(sites.drawers or {}) do
  drawer.prompt:SetAttribute("PrisonDrawerCell", drawer.id)
  drawer.prompt.Enabled = true
  drawer.prompt.Triggered:Connect(function(player) useDrawer(player, drawer) end)
 end
 for _, door in ipairs(sites.doors or {}) do
  door.prompt:SetAttribute("PrisonKeycardDoor", true)
  door.prompt.Enabled = true
  door.prompt.Triggered:Connect(function(player) useDoor(player, door) end)
 end
 Players.PlayerAdded:Connect(watchPlayer)
 for _, player in ipairs(Players:GetPlayers()) do watchPlayer(player) end
 Players.PlayerRemoving:Connect(function(player)
  Service.clearPlayer(player); removeOfficerPrompt(player)
  if connections[player] then connections[player]:Disconnect(); connections[player] = nil end
 end)
 task.spawn(function() while true do update(); task.wait(0.15) end end)
end
return Service
