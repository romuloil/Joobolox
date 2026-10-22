-- Polícia: equipamento, registros, abordagem, custódia e fiscalização no servidor.
-- Captura depende de suspeita criada por outro serviço NO SERVIDOR e imobilização.
-- Não há remoto que crie suspeitos, altere dinheiro ou prenda um civil livremente.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("PoliceConfig"))
local Rules = require(Shared:WaitForChild("PoliceRules"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Security = require(script.Parent:WaitForChild("SecurityService"))
local WorkRoleService = require(script.Parent:WaitForChild("WorkRoleService"))

local PoliceService = {}
local initialized = false
local sites, hooks, ui
local duty, suspects, stuns, training = {}, {}, {}, {}
local reports, reportId = {}, 0
local doors, count = {}, 0
local pending, strips, misconduct = {}, {}, {}
local cancelCustody, finishCustody
local function removeStrip(player)
	local strip = strips[player]
	strips[player] = nil
	if strip and strip.model then strip.model:Destroy() end
end

local function now() return Workspace:GetServerTimeNow() end
local function notice(player, message)
	if player.Parent == Players then ui:FireClient(player, "Notice", { text = message }) end
end
local function rootOf(player)
	local _, _, root = Security.getLivingCharacter(player)
	return root
end
local function positionOf(prompt)
	local parent = prompt and prompt.Parent
	if parent and parent:IsA("BasePart") then return parent.Position end
	if parent and parent:IsA("Attachment") then return parent.WorldPosition end
end
local function near(player, prompt, reach)
	local root, target = rootOf(player), positionOf(prompt)
	return root and target and Rules.point(root.Position) and (root.Position - target).Magnitude <= (reach or Config.InteractionDistance)
end
local function nearAny(player, prompts)
	for _, prompt in ipairs(prompts or {}) do if near(player, prompt) then return true end end
	return false
end
local function onDuty(player)
	return duty[player] ~= nil and WorkRoleService.hasRole(player, "Policial")
		and not player:GetAttribute("Detained") and rootOf(player) ~= nil
end
local function equipped(player, id)
	local character = player.Character
	if not character then return nil end
	for _, item in ipairs(character:GetChildren()) do
		if item:IsA("Tool") and item:GetAttribute("PoliceIssued") and item:GetAttribute("PoliceTool") == id then return item end
	end
	return nil
end
local function doorList()
	local list = {}
	for id, door in pairs(doors) do
		table.insert(list, { id = id, name = door.name or id, open = door.isOpen == true })
	end
	if hooks and hooks.prisonService and hooks.prisonService.getCellControls then
		for _, cell in ipairs(hooks.prisonService.getCellControls()) do
			table.insert(list,{id="Cell:"..tostring(cell.id),name=("CELA %s · %s"):format(tostring(cell.name or cell.id),cell.occupied and "OCUPADA" or "LIVRE"),
				open=cell.open==true,occupied=cell.occupied==true,lockedUntil=cell.lockedUntil})
		end
	end
	table.sort(list, function(a,b) return a.id < b.id end)
	return list
end
local function sendState(player)
	if player.Parent ~= Players then return end
	local record = duty[player]
	ui:FireClient(player, "PoliceState", {
		onDuty = record ~= nil, count = count, slots = Config.Slots,
		equipped = record and record.equipped == true or false,
		patrolStep = record and record.patrol or 0, patrolTotal = #(sites.patrolPrompts or {}),
		training = training[player] ~= nil,
	})
end
local function broadcastState()
	for _, player in ipairs(Players:GetPlayers()) do sendState(player) end
end
local function teamReports()
	for player in pairs(duty) do
		if player.Parent == Players then ui:FireClient(player, "PoliceReports", { reports = reports }) end
	end
end
local function addReport(player, category, text, location)
	reportId += 1
	table.insert(reports, 1, {
		id = reportId, at = os.time(), officer = player.DisplayName or player.Name,
		category = category, text = text, location = location or "Centro de Reintegração Kinder",
	})
	while #reports > Config.MaxReports do table.remove(reports) end
	teamReports()
end
local function stripGear(player)
	local containers = {}
	if player.Character then table.insert(containers,player.Character) end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then table.insert(containers,backpack) end
	for _, container in ipairs(containers) do
		if container then
			for _, item in ipairs(container:GetChildren()) do
				if item:IsA("Tool") and item:GetAttribute("PoliceIssued") then item:Destroy() end
			end
		end
	end
end
local function removeTraining(player)
	local record = training[player]
	training[player] = nil
	if record and record.model then record.model:Destroy() end
end

function PoliceService.join(player)
	if not initialized or player.Parent ~= Players then return false end
	if duty[player] then sendState(player); return true end
	if suspects[player] or pending[player] then notice(player,"Resolva sua ocorrência antes de entrar em serviço.");return false end
	if not nearAny(player, sites.dutyPrompts) then notice(player, "Entre em serviço no balcão policial."); return false end
	if not Rules.canJoin(rootOf(player) ~= nil, player:GetAttribute("Detained"), count, Config.Slots) then
		notice(player, count >= Config.Slots and "As três vagas policiais estão ocupadas." or "Você não pode entrar em serviço agora.")
		return false
	end
	-- Reserva a vaga antes de qualquer função externa que possa ceder execução.
	duty[player] = { patrol = 0, equipped = false }
	count += 1
	player:SetAttribute("PoliceDuty", true)
	if hooks.beforeDuty then
		local ok, err = pcall(hooks.beforeDuty, player)
		if not ok then
			PoliceService.leave(player)
			warn("[PoliceService] Falha ao iniciar serviço: " .. tostring(err))
			return false
		end
	end
	if not duty[player] or player.Parent ~= Players then return false end
	local assigned = WorkRoleService.assign(player, "Policial")
	if not assigned then
		PoliceService.leave(player)
		notice(player, "Encerre seu outro emprego antes de iniciar o plantão.")
		return false
	end
	-- O uniforme é retirado no vestiário e devolvido pelo WorkRoleService.

	broadcastState()
	notice(player, "Em serviço. Retire os equipamentos no arsenal e consulte os terminais.")
	return true
end

function PoliceService.leave(player, silent)
	local record = duty[player]
	if not record then return false end
	duty[player] = nil
	removeStrip(player)
	for target, record in pairs(pending) do
		if record.officer == player then cancelCustody(target, "O agente encerrou o plantão; custódia cancelada.") end
	end
	WorkRoleService.clear(player, "Policial")
	count = math.max(0, count - 1)
	player:SetAttribute("PoliceDuty", false)
	stripGear(player)
	removeTraining(player)
	local vest = player.Character and player.Character:FindFirstChild("ColetePolicial")
	if vest then vest:Destroy() end
	if player.Parent == Players and not silent then
		sendState(player); notice(player, "Serviço policial encerrado. Equipamentos devolvidos.")
	end
	broadcastState()
	return true
end

local function decorativePart(tool, handle, name, size, offset, color, shape)
	local p = Instance.new("Part")
	p.Name, p.Size, p.Color = name, size, color
	p.CFrame = handle.CFrame * offset
	p.CanCollide, p.CanTouch, p.Massless = false, false, true
	if shape then p.Shape = shape end
	p.Parent = tool
	local weld = Instance.new("WeldConstraint"); weld.Part0, weld.Part1, weld.Parent = handle, p, p
	return p
end
local function makeTool(definition)
	local tool = Instance.new("Tool")
	tool.Name, tool.CanBeDropped, tool.RequiresHandle = definition.name, false, true
	tool:SetAttribute("PoliceIssued", true)
	tool:SetAttribute("PoliceTool", definition.id)
	local handle = Instance.new("Part")
	handle.Name, handle.Size, handle.Color = "Handle", Vector3.new(0.45, 1.1, 0.5), definition.color
	handle.CanCollide, handle.CanTouch, handle.Massless = false, false, true
	handle.Parent = tool
	if definition.id == "Pistol" or definition.id == "Taser" then
		tool.Grip = CFrame.new(0, -0.15, 0.1)
		decorativePart(tool, handle, "Corpo", Vector3.new(0.6,0.55,1.45), CFrame.new(0,0.55,-0.35), definition.color)
		decorativePart(tool, handle, "Cano", Vector3.new(0.3,0.3,0.4), CFrame.new(0,0.55,-1.2), Color3.fromRGB(22,27,36))
		decorativePart(tool, handle, "Mira", Vector3.new(0.15,0.12,0.15), CFrame.new(0,0.9,-0.6), Color3.fromRGB(110,190,220))
	elseif definition.id == "Spike" then
		handle.Size = Vector3.new(1.4,0.65,0.8)
		for x=-1,1 do decorativePart(tool,handle,"Haste",Vector3.new(0.15,0.7,0.15),CFrame.new(x*0.45,0.5,0),Color3.fromRGB(195,205,210)) end
	elseif definition.id == "Spray" then
		tool.Grip = CFrame.new(0, -0.15, 0.1)
		decorativePart(tool, handle, "ReservatórioÁgua", Vector3.new(0.9, 0.8, 1.8), CFrame.new(0, 0.45, -0.45), Color3.fromRGB(35, 150, 220))
		decorativePart(tool, handle, "Bico", Vector3.new(0.5, 0.5, 1.1), CFrame.new(0, 0.45, -1.6), Color3.fromRGB(255, 175, 55))
	elseif definition.id == "Cuff" then
		handle.Size = Vector3.new(0.2, 0.45, 0.4)
		for _, side in ipairs({-1,1}) do
			local ring = decorativePart(tool, handle, "Aro", Vector3.new(0.14,0.85,0.85), CFrame.new(side * 0.45,0.2,0) * CFrame.Angles(0,0,math.pi/2), definition.color, Enum.PartType.Cylinder)
			ring.Material = Enum.Material.Metal
		end
	elseif definition.id == "Flashlight" then
		local head = decorativePart(tool, handle, "Lente", Vector3.new(0.65,0.65,0.2), CFrame.new(0,0.35,-0.4), Color3.fromRGB(245,238,195))
		local light = Instance.new("SpotLight")
		light.Name, light.Face, light.Range, light.Angle = "PoliceLight", Enum.NormalId.Front, 40, 65
		light.Brightness, light.Enabled, light.Parent = 2.5, false, head
	elseif definition.id == "Radio" then
		decorativePart(tool, handle, "Antena", Vector3.new(0.12,0.9,0.12), CFrame.new(0.12,0.95,0), Color3.fromRGB(15,20,28))
		decorativePart(tool, handle, "Tela", Vector3.new(0.32,0.4,0.06), CFrame.new(0,0.15,-0.28), Color3.fromRGB(110,220,180))
	end
	return tool
end
function PoliceService.requestGear(player)
	if not onDuty(player) or not nearAny(player, sites.armoryPrompts) then return false end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then return false end
	stripGear(player)
	for _, definition in ipairs(Config.Gear) do makeTool(definition).Parent = backpack end
	duty[player].equipped = true
	sendState(player)
	notice(player, "Kit recebido: pistola, taser, algemas, barreira, água, lanterna e rádio.")
	return true
end

function PoliceService.clearSuspect(player)
	suspects[player] = nil
	player:SetAttribute("Wanted", false)
	player:SetAttribute("WantedReason", nil)
	player:SetAttribute("Bounty", nil)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local prompt = root and root:FindFirstChild("PoliceCuffPrompt")
	if prompt then prompt:Destroy() end
end
local function cuffPrompt(root, action)
	local p = Instance.new("ProximityPrompt")
	p.Name, p.ActionText, p.ObjectText = "PoliceCuffPrompt", "Algemar", "Suspeito imobilizado"
	p.KeyboardKeyCode, p.HoldDuration, p.MaxActivationDistance = Enum.KeyCode.E, 0.8, 7
	-- O root fica dentro do torso; o servidor faz o raycast de visibilidade.
	p.RequiresLineOfSight, p.Parent = false, root
	p.Triggered:Connect(action)
	return p
end
local function publishSuspect(player, record)
	player:SetAttribute("Wanted", true)
	player:SetAttribute("WantedReason", record.reason)
	player:SetAttribute("Bounty", record.bounty or 0)
	local root = rootOf(player)
	if root and not root:FindFirstChild("PoliceCuffPrompt") then
		cuffPrompt(root, function(officer) PoliceService.capture(officer, player.UserId) end)
	end
end
local function setSuspect(player, reason, duration, prisonOffense, reward)
	if not initialized or player.Parent ~= Players or not rootOf(player) or duty[player]
		or player:GetAttribute("InWorkZone") or (player:GetAttribute("Detained") and not prisonOffense) then return false end
	duration = Rules.finite(duration) and math.clamp(duration,5,Config.SuspectSeconds) or Config.SuspectSeconds
	local previous = suspects[player]
	local record = previous or { bounty = 0, offenses = {} }
	record.untilAt = now()+duration
	record.reason = type(reason)=="string" and reason:sub(1,100) or "Ocorrência validada pelo servidor"
	record.prisonOffense = prisonOffense == true
	if reward and Config.Bounty[reason] and not record.offenses[reason] then
		record.offenses[reason] = true
		record.bounty = math.min(Config.MaxBounty,record.bounty+Config.Bounty[reason])
	end
	suspects[player] = record
	publishSuspect(player,record)
	if not previous then
		for officer in pairs(duty) do notice(officer,"Ocorrência registrada. Imobilize com água/taser e use algemas de perto.") end
	end
	return true
end
function PoliceService.markSuspect(player, reason, duration)
	-- API de integração: não cria recompensa a partir de texto arbitrário ou teste.
	return setSuspect(player,reason,duration,false,false)
end
function PoliceService.registerPrisonOffense(player, reason)
	if not hooks or not hooks.prisonService.isDetained or not hooks.prisonService.isDetained(player)
		or (reason~="Furto de cartão" and reason~="Área restrita") then return false end
	local testing = hooks.prisonService.getDetentionReason
		and hooks.prisonService.getDetentionReason(player) == "studio_test"
	return setSuspect(player,reason,Config.SuspectSeconds,true,not testing)
end
function PoliceService.isOnDuty(player) return onDuty(player) end
function PoliceService.isWanted(player)
	local record=suspects[player]
	return record~=nil and now()<record.untilAt
end
function PoliceService.handlePrisonRelease(player, escaped, reason)
	if pending[player] then cancelCustody(player) end
	if escaped then
		return setSuspect(player,"Fuga da prisão",Config.SuspectSeconds,false,reason~="studio_test")
	end
	PoliceService.clearSuspect(player)
	return true
end

local function clearStun(player)
	local state = stuns[player]
	stuns[player] = nil
	player:SetAttribute("StunnedUntil", nil)
	if state and state.humanoid and state.humanoid.Parent then
		state.humanoid.JumpPower, state.humanoid.JumpHeight = state.jumpPower, state.jumpHeight
		if not player:GetAttribute("Detained") then state.humanoid.WalkSpeed = state.speed end
	end
end
local function stunPlayer(player, seconds)
	if hooks.beforeStun then
		local ok,err=pcall(hooks.beforeStun,player)
		if not ok then warn("[PoliceService] Falha ao preparar imobilização: "..tostring(err));return false end
	end
	local _, humanoid = Security.getLivingCharacter(player)
	if not humanoid then return false end
	local state = stuns[player]
	if not state or state.humanoid ~= humanoid then
		state = { humanoid = humanoid, speed = humanoid.WalkSpeed, jumpPower = humanoid.JumpPower, jumpHeight = humanoid.JumpHeight }
	end
	state.untilAt = now() + (seconds or Config.StunSeconds)
	stuns[player] = state
	humanoid.WalkSpeed, humanoid.JumpPower, humanoid.JumpHeight = 0, 0, 0
	player:SetAttribute("StunnedUntil", state.untilAt)
	notice(player, "Você está imobilizado por alguns segundos.")
	return true
end
local function misconductAttempt(officer)
	if not Security.checkRate(officer,"PoliceMisconduct",2) then return end
	misconduct[officer]=(misconduct[officer] or 0)+1
	local economy=hooks.economyService
	local balance=economy and economy.getMoney(officer)
	local paid=0
	if Rules.finite(balance) then
		local amount=math.min(Config.InnocentFine,math.max(0,math.floor(balance)))
		if amount>0 and economy.spend(officer,amount,"police_innocent_misuse") then paid=amount end
	end
	notice(officer,("Pessoa inocente: abordagem indevida. Multa $%d · advertência %d/%d."):format(paid,misconduct[officer],Config.MisconductLimit))
	if misconduct[officer]>=Config.MisconductLimit then
		misconduct[officer]=0
		PoliceService.leave(officer,true)
		hooks.prisonService.detain(officer,"police_misconduct")
		notice(officer,"Plantão encerrado por abordagens indevidas repetidas.")
	end
end
cancelCustody = function(target, message)
	local record=pending[target]
	if not record then return false end
	pending[target]=nil
	target:SetAttribute("CuffedUntil",nil)
	clearStun(target)
	if message then notice(target,message) end
	return true
end
local function payBounty(officer, target, record)
	local amount=record.bounty or 0
	record.bounty=0 -- remove antes de chamar economia: nunca paga duas vezes
	local economy=hooks.economyService
	if amount>0 and economy and economy.add(officer,amount,"police_bounty") then
		local message=("%s capturou %s e recebeu $%d de recompensa."):format(officer.DisplayName or officer.Name,target.DisplayName or target.Name,amount)
		for _, recipient in ipairs(Players:GetPlayers()) do notice(recipient,message) end
	end
end
finishCustody = function(target, record)
	if pending[target]~=record then return end
	if target.Parent~=Players or not onDuty(record.officer) or not rootOf(target)
		or target.Character~=record.character or record.officer.Character~=record.officerCharacter then
		cancelCustody(target,"Custódia interrompida.");return
	end
	pending[target]=nil
	target:SetAttribute("CuffedUntil",nil)
	local suspect=suspects[target]
	local accepted
	if target:GetAttribute("Detained") then
		accepted=hooks.prisonService.returnToCell and hooks.prisonService.returnToCell(target)
	else
		accepted=hooks.prisonService.detain(target,"police_capture")
	end
	clearStun(target)
	if not accepted then
		notice(record.officer,"A prisão não recebeu a custódia. A pessoa foi desalgemada.")
		return
	end
	PoliceService.clearSuspect(target)
	misconduct[record.officer]=0
	addReport(record.officer,"Captura","Custódia validada e encaminhada à cela.","Ocorrência em patrulha")
	-- Retorno de quem já cumpre pena não rende recompensa: impede repetir furto/captura.
	if not record.wasDetained and suspect then payBounty(record.officer,target,suspect) end
end

local function waterVisual(a, b)
	if (b-a).Magnitude < 0.01 then return end
	local p = Instance.new("Part")
	p.Name, p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = "JatoDeÁgua", true, false, false, false
	p.Size, p.CFrame = Vector3.new(0.2,0.2,math.max(0.1,(b-a).Magnitude)), CFrame.lookAt((a+b)/2,b)
	p.Material, p.Color, p.Transparency = Enum.Material.Neon, Color3.fromRGB(95,200,245), 0.3
	p.Parent = Workspace
	Debris:AddItem(p, 0.15)
end
local function fireWeapon(player, payload, kind)
	local range=kind=="Pistol" and Config.PistolRange or kind=="Taser" and Config.TaserRange or Config.SprayRange
	local cooldown=kind=="Pistol" and Config.PistolCooldown or kind=="Taser" and Config.TaserCooldown or Config.SprayCooldown
	if not onDuty(player) or not equipped(player,kind) or type(payload) ~= "table"
		or not Rules.validDirection(payload.direction) or not Security.checkRate(player,"PoliceWeapon",cooldown) then return false end
	local character, _, root = Security.getLivingCharacter(player)
	local head = character:FindFirstChild("Head")
	local origin = head and head.Position or root.Position + Vector3.new(0,1.5,0)
	local direction = payload.direction.Unit
	local params = RaycastParams.new(); params.FilterType = Enum.RaycastFilterType.Exclude; params.FilterDescendantsInstances = {character}; params.IgnoreWater = true
	local hit = Workspace:Raycast(origin, direction * range, params)
	local hitPosition = hit and hit.Position or origin + direction * range
	waterVisual(origin,hitPosition)
	if not hit then return true end
	local ancestor = hit.Instance
	while ancestor and ancestor ~= Workspace do
		if ancestor:IsA("Model") then
			local targetPlayer = Players:GetPlayerFromCharacter(ancestor)
			if targetPlayer then
				local suspect = suspects[targetPlayer]
				if targetPlayer==player or pending[targetPlayer] then return true end
				if suspect and now()<suspect.untilAt and (not targetPlayer:GetAttribute("Detained") or suspect.prisonOffense)
					and not targetPlayer:GetAttribute("InWorkZone") then
					if kind=="Pistol" then
						local _,humanoid=Security.getLivingCharacter(targetPlayer)
						if humanoid then humanoid:TakeDamage(Config.PistolDamage) end
					else stunPlayer(targetPlayer) end
				elseif kind~="Spray" then misconductAttempt(player) end
				return true
			end
			local record = training[player]
			if record and ancestor == record.model then
				if kind=="Pistol" then notice(player,"No treino de abordagem, use água ou taser.");return true end
				record.stunnedUntil = now() + Config.StunSeconds
				record.model:SetAttribute("StunnedUntil",record.stunnedUntil)
				notice(player,"Alvo de treino imobilizado. Aproxime-se e equipe as algemas.")
				return true
			end
		end
		ancestor = ancestor.Parent
	end
	return true
end

function PoliceService.spray(player,payload) return fireWeapon(player,payload,"Spray") end
function PoliceService.taser(player,payload) return fireWeapon(player,payload,"Taser") end
function PoliceService.pistol(player,payload) return fireWeapon(player,payload,"Pistol") end

function PoliceService.deploySpike(player)
	if not onDuty(player) or not equipped(player,"Spike") or not hooks.vehicleService
		or not hooks.vehicleService.applyPoliceSlow or not Security.checkRate(player,"PoliceSpike",Config.SpikeCooldown) then return false end
	local character,humanoid,root=Security.getLivingCharacter(player)
	if humanoid.SeatPart or not Rules.point(root.Position) then return false end
	local target=root.Position+root.CFrame.LookVector*6
	local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances={character}
	if Workspace:Raycast(root.Position,target-root.Position,params) then return false end
	local ground=Workspace:Raycast(target+Vector3.new(0,3,0),Vector3.new(0,-12,0),params)
	if not ground or ground.Normal.Y<0.8 then return false end
	removeStrip(player)
	local model=Instance.new("Model");model.Name="BarreiraPolicial";model:SetAttribute("PoliceOwner",player.UserId)
	local frame=CFrame.new(ground.Position+Vector3.new(0,0.25,0))*root.CFrame.Rotation
	local base=Instance.new("Part");base.Name="Base";base.Size=Vector3.new(13,0.25,2)
	base.CFrame=frame;base.Anchored=true;base.CanCollide=false;base.CanTouch=false;base.Color=Color3.fromRGB(40,47,55);base.Parent=model
	for i=-5,5 do
		local spike=Instance.new("Part");spike.Name="Haste";spike.Size=Vector3.new(0.18,0.5,0.18);spike.CFrame=frame*CFrame.new(i,0.35,0)
		spike.Anchored=true;spike.CanCollide=false;spike.CanTouch=false;spike.CanQuery=false;spike.Color=Color3.fromRGB(210,215,220);spike.Parent=model
	end
	model.Parent=Workspace
	strips[player]={model=model,frame=frame,untilAt=now()+Config.SpikeSeconds,hit={}}
	notice(player,"Barreira posicionada por 40 s: reduz a velocidade de veículos de procurados.")
	return true
end

local function targetPlayer(id)
	if type(id) ~= "number" or not Rules.finite(id) or id % 1 ~= 0 then return nil end
	return Players:GetPlayerByUserId(id)
end
function PoliceService.capture(officer, targetId)
	if not onDuty(officer) or not equipped(officer,"Cuff") or not Security.checkRate(officer,"PoliceCuff",0.5) then return false end
	local officerRoot = rootOf(officer)
	if targetId == "Training" then
		local record = training[officer]
		if not record or not record.model.Parent then return false end
		local targetRoot = record.model.PrimaryPart
		if not Rules.canCapture(true,true,(officerRoot.Position-targetRoot.Position).Magnitude,now(),record.stunnedUntil,true,false,false) then return false end
		local visibility=RaycastParams.new();visibility.FilterType=Enum.RaycastFilterType.Exclude;visibility.FilterDescendantsInstances={officer.Character,record.model}
		if Workspace:Raycast(officerRoot.Position,targetRoot.Position-officerRoot.Position,visibility) then return false end
		removeTraining(officer)
		addReport(officer,"Treinamento","Treinamento de abordagem concluído: água e algemas, sem dano.","Área de treinamento")
		sendState(officer)
		notice(officer,"Treinamento concluído. O registro foi enviado ao rádio da equipe.")
		return true
	end
	local target = targetPlayer(targetId)
	local targetRoot = target and rootOf(target)
	if not targetRoot or target==officer or pending[target] then return false end
	local distance=(officerRoot.Position-targetRoot.Position).Magnitude
	if not Rules.finite(distance) or distance>Config.CuffDistance then return false end
	local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances={officer.Character,target.Character}
	if Workspace:Raycast(officerRoot.Position,targetRoot.Position-officerRoot.Position,params) then return false end
	local suspect,stun=suspects[target],stuns[target]
	if not suspect or now()>=suspect.untilAt then misconductAttempt(officer);return false end
	if target:GetAttribute("InWorkZone") then return false end
	local _,humanoid=Security.getLivingCharacter(target)
	if humanoid.SeatPart then
		if hooks.vehicleService and hooks.vehicleService.ejectFromVehicle and hooks.vehicleService.ejectFromVehicle(target) then
			notice(officer,"Procurado retirado do veículo. Imobilize para algemar.");return true
		end
		return false
	end
	if not Rules.canCapture(true,true,distance,now(),stun and stun.untilAt,true,
		target:GetAttribute("Detained"),false,suspect.prisonOffense) then return false end
	local record={officer=officer,character=target.Character,officerCharacter=officer.Character,
		wasDetained=target:GetAttribute("Detained")==true,untilAt=now()+Config.CustodySeconds}
	pending[target]=record
	stun.untilAt=record.untilAt
	target:SetAttribute("StunnedUntil",record.untilAt)
	target:SetAttribute("CuffedUntil",record.untilAt)
	notice(target,"Algemado: transferência para a cela em 10 segundos.")
	notice(officer,"Custódia iniciada. Transferência em 10 segundos.")
	task.delay(Config.CustodySeconds,function() finishCustody(target,record) end)
	return true
end

function PoliceService.submitReport(player, payload)
	if not onDuty(player) or not nearAny(player,sites.reportPrompts) or type(payload) ~= "table"
		or not Rules.validReport(payload.category) or not Security.checkRate(player,"PoliceReport",Config.ReportCooldown) then return false end
	addReport(player,payload.category,Config.ReportCategories[payload.category],"Terminal de ocorrências")
	notice(player,"Informe registrado e compartilhado com os policiais em serviço.")
	return true
end
local function doorwayOccupied(door)
	for _, player in ipairs(Players:GetPlayers()) do
		local root = rootOf(player)
		if root then
			local localPos = door.closed:PointToObjectSpace(root.Position)
			if math.abs(localPos.X) <= door.part.Size.X/2+2 and math.abs(localPos.Y) <= door.part.Size.Y/2+2
				and math.abs(localPos.Z) <= door.part.Size.Z/2+3 then return true end
		end
	end
	return false
end
function PoliceService.toggleDoor(player, id)
	if type(id)=="string" and #id<=64 and id:sub(1,5)=="Cell:" then
		if not onDuty(player) or not nearAny(player,sites.controlPrompts)
			or not hooks.prisonService.getCellControls or not hooks.prisonService.setCellDoor then return false end
		local cellId=id:sub(6)
		for _, cell in ipairs(hooks.prisonService.getCellControls()) do
			if tostring(cell.id)==cellId then
				local accepted,reason=hooks.prisonService.setCellDoor(cellId,not cell.open)
				if not accepted then
					notice(player,reason=="locked" and "A cela permanece lacrada nos primeiros 5 segundos da pena."
						or reason=="blocked" and "Afaste-se da porta antes de fechar a cela." or "Não foi possível operar essa cela agora.")
				end
				ui:FireClient(player,"PolicePanel",{panel="control",doors=doorList()})
				return accepted
			end
		end
		return false
	end
	local door = type(id) == "string" and #id <= 64 and doors[id]
	if not door or not onDuty(player) or door.busy then return false end
	if not near(player,door.prompt) and not nearAny(player,sites.controlPrompts) then return false end
	if door.isOpen and doorwayOccupied(door) then notice(player,"Passagem ocupada. Aguarde antes de fechar."); return false end
	door.busy = true
	door.accessEpoch=(door.accessEpoch or 0)+1
	door.isOpen = not door.isOpen
	door.part:SetAttribute("Open",door.isOpen)
	local tween = TweenService:Create(door.part,TweenInfo.new(Config.DoorSeconds),{CFrame=door.isOpen and door.open or door.closed})
	tween:Play()
	task.delay(Config.DoorSeconds,function() door.busy=false end)
	ui:FireClient(player,"PolicePanel",{panel="control",doors=doorList()})
	return true
end

local function trainingModel(player, spawn)
	local model = Instance.new("Model"); model.Name = "Simulador de Abordagem"
	model:SetAttribute("PoliceTrainingOwner",player.UserId)
	local pieces = {
		{"HumanoidRootPart",Vector3.new(2,2,1),Vector3.zero,1},
		{"Torso",Vector3.new(2,2,1),Vector3.zero,0},
		{"Head",Vector3.new(1.6,1.2,1.2),Vector3.new(0,1.6,0),0},
		{"BraçoEsquerdo",Vector3.new(0.8,2,0.8),Vector3.new(-1.4,0,0),0},
		{"BraçoDireito",Vector3.new(0.8,2,0.8),Vector3.new(1.4,0,0),0},
		{"PernaEsquerda",Vector3.new(0.8,2,0.8),Vector3.new(-0.55,-2,0),0},
		{"PernaDireita",Vector3.new(0.8,2,0.8),Vector3.new(0.55,-2,0),0},
	}
	for _, data in ipairs(pieces) do
		local p=Instance.new("Part");p.Name,p.Size,p.CFrame=data[1],data[2],spawn*CFrame.new(data[3])
		p.Anchored,p.CanCollide,p.CanTouch,p.Transparency=true,false,false,data[4]
		p.CanQuery=data[4]==0;p.Color=Color3.fromRGB(235,163,65);p.Material=Enum.Material.SmoothPlastic;p.Parent=model
		if data[1]=="HumanoidRootPart" then model.PrimaryPart=p end
	end
	local humanoid=Instance.new("Humanoid");humanoid.DisplayName="Alvo de treinamento";humanoid.RequiresNeck=false;humanoid.BreakJointsOnDeath=false;humanoid.Parent=model
	model.Parent=Workspace
	cuffPrompt(model.PrimaryPart,function(officer) if officer==player then PoliceService.capture(officer,"Training") end end)
	return model
end
function PoliceService.startTraining(player)
	if not onDuty(player) or not near(player,sites.trainingPrompt) or not sites.trainingSpawn then return false end
	if not Security.checkRate(player,"PoliceTraining",Config.TrainingCooldown) then return false end
	if training[player] then notice(player,"Seu alvo já está na área de treinamento.");return false end
	local spawn=sites.trainingSpawn.CFrame
	-- Faixas individuais evitam um policial imobilizar o alvo de outro.
	local used={};for _,record in pairs(training) do used[record.lane]=true end
	local lane=0;while used[lane] do lane+=1 end
	spawn=spawn*CFrame.new(lane*5,0,0)
	local model=trainingModel(player,spawn)
	training[player]={model=model,base=spawn,lane=lane,untilAt=now()+Config.TrainingSeconds,stunnedUntil=0,startAt=now()}
	sendState(player);notice(player,"Treino iniciado: equipe água, acerte o alvo e use algemas de perto.")
	return true
end

local function showPanel(player, panel)
	if panel~="duty" and not onDuty(player) then notice(player,"Entre em serviço no balcão policial.");return end
	ui:FireClient(player,"PolicePanel",{panel=panel,count=count,slots=Config.Slots,onDuty=duty[player]~=nil,doors=doorList(),reports=reports,
		readOnly=panel=="reports" and not nearAny(player,sites.reportPrompts) or false})
end
local function onRequest(player, action, payload)
	if not Security.isShortString(action,16) or not Security.checkRate(player,"PoliceRequest",0.12) then return end
	if action=="Duty" then
		if payload==false then PoliceService.leave(player) elseif payload==true then PoliceService.join(player) end
	elseif action=="Gear" then PoliceService.requestGear(player)
	elseif action=="Spray" then PoliceService.spray(player,payload)
	elseif action=="Taser" then PoliceService.taser(player,payload)
	elseif action=="Pistol" then PoliceService.pistol(player,payload)
	elseif action=="Spike" then PoliceService.deploySpike(player)
	elseif action=="Cuff" then PoliceService.capture(player,payload)
	elseif action=="Report" then PoliceService.submitReport(player,payload)
	elseif action=="Door" then PoliceService.toggleDoor(player,payload)
	elseif action=="Training" then PoliceService.startTraining(player)
	elseif action=="Radio" and onDuty(player) and equipped(player,"Radio") then showPanel(player,"reports")
	elseif action=="Flashlight" and onDuty(player) then
		local tool=equipped(player,"Flashlight")
		local light=tool and tool:FindFirstChild("PoliceLight",true)
		if light then light.Enabled=not light.Enabled end
	end
end

local function registerPromptList(prompts, callback)
	for _, prompt in ipairs(prompts or {}) do
		prompt.Enabled=true
		prompt.Triggered:Connect(function(player)
			if near(player,prompt) and Security.checkRate(player,"PolicePrompt",0.35) then callback(player,prompt) end
		end)
	end
end
function PoliceService.init(remotes,civicSites,options)
	if initialized then return end
	assert(civicSites and civicSites.police,"Pontos policiais ausentes")
	sites=civicSites.police;hooks=options or {};ui=assert(remotes[GameConfig.Remotes.UIUpdate],"UIUpdate ausente")
	assert(hooks.prisonService,"PrisonService ausente")
	initialized=true
	for _, door in ipairs(sites.doors or {}) do
		doors[door.id]=door;door.isOpen=false;door.busy=false;door.part:SetAttribute("Open",false)
		if door.prompt and not door.keycard then registerPromptList({door.prompt},function(player) PoliceService.toggleDoor(player,door.id) end) end
	end
	registerPromptList(sites.dutyPrompts,function(player) showPanel(player,"duty") end)
	registerPromptList(sites.armoryPrompts,function(player) showPanel(player,"armory") end)
	registerPromptList(sites.reportPrompts,function(player) showPanel(player,"reports") end)
	registerPromptList(sites.controlPrompts,function(player) showPanel(player,"control") end)
	for index,prompt in ipairs(sites.patrolPrompts or {}) do
		registerPromptList({prompt},function(player)
			local record=duty[player]
			if not onDuty(player) or index~=(record.patrol or 0)+1 then return end
			record.patrol=index
			if index==#sites.patrolPrompts then
				addReport(player,"Patrulha","Ronda interna concluída com todos os pontos verificados.","Perímetro da prisão")
				record.patrol=0;notice(player,"Ronda concluída e registrada. Nenhuma ocorrência.")
			else notice(player,("Ponto %d/%d verificado."):format(index,#sites.patrolPrompts)) end
			sendState(player)
		end)
	end
	if sites.trainingPrompt then registerPromptList({sites.trainingPrompt},PoliceService.startTraining) end
	if sites.suspectTestPrompt then
		sites.suspectTestPrompt.Enabled=RunService:IsStudio()
		sites.suspectTestPrompt.Triggered:Connect(function(player)
			if RunService:IsStudio() and near(player,sites.suspectTestPrompt) and Security.checkRate(player,"PoliceSuspectTest",2) then
				if PoliceService.markSuspect(player,"Simulação voluntária no Studio",90) then notice(player,"Simulação iniciada. Outro jogador policial pode testar água e algemas por 90 segundos.") end
			end
		end)
	end
	assert(remotes[GameConfig.Remotes.PoliceRequest],"PoliceRequest ausente").OnServerEvent:Connect(onRequest)
	local function watchPlayer(player)
		player.CharacterAdded:Connect(function(character)
			-- Reset devolve o kit e cancela custódia, mas não apaga ocorrência pendente.
			PoliceService.leave(player,true);cancelCustody(player);clearStun(player)
			task.spawn(function()
				character:WaitForChild("HumanoidRootPart",10)
				if player.Parent==Players and player.Character==character then
					local record=suspects[player]
					if record and now()<record.untilAt then publishSuspect(player,record) end
					sendState(player)
				end
			end)
		end)
		player:GetAttributeChangedSignal("Detained"):Connect(function()
			if player:GetAttribute("Detained") then PoliceService.leave(player,true) end
		end)
		task.defer(function() if player.Parent==Players then sendState(player) end end)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in ipairs(Players:GetPlayers()) do watchPlayer(player) end
	Players.PlayerRemoving:Connect(function(player)
		PoliceService.leave(player,true);cancelCustody(player);PoliceService.clearSuspect(player);clearStun(player);removeTraining(player);misconduct[player]=nil
	end)
	task.spawn(function()
		while true do
			local time=now()
			for player,suspect in pairs(suspects) do if time>=suspect.untilAt and not pending[player] then PoliceService.clearSuspect(player) end end
			for target,record in pairs(pending) do
				if not rootOf(target) or not onDuty(record.officer) then cancelCustody(target,"Custódia interrompida.") end
			end
			for officer,strip in pairs(strips) do
				if time>=strip.untilAt or not onDuty(officer) then removeStrip(officer)
				else
					for target in pairs(suspects) do
						local root=rootOf(target)
						if root and PoliceService.isWanted(target) and not strip.hit[target] then
							local point=strip.frame:PointToObjectSpace(root.Position)
							if math.abs(point.X)<=9 and math.abs(point.Y)<=7 and math.abs(point.Z)<=5 then
								if hooks.vehicleService.applyPoliceSlow(target,Config.SpikeSlowSeconds) then strip.hit[target]=true end
							end
						end
					end
				end
			end
			for player,stun in pairs(stuns) do
				if time>=stun.untilAt or not rootOf(player) then clearStun(player)
				else stun.humanoid.WalkSpeed=0;stun.humanoid.JumpPower=0;stun.humanoid.JumpHeight=0 end
			end
			for player,record in pairs(training) do
				if not duty[player] or time>=record.untilAt or not record.model.Parent then removeTraining(player);if player.Parent==Players then sendState(player) end
				elseif time>=record.stunnedUntil then record.model:PivotTo(record.base*CFrame.new(math.sin((time-record.startAt)*1.2)*4,0,0)) end
			end
			task.wait(0.15)
		end
	end)
end
return PoliceService
