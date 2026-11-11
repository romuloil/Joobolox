-- BankService (ModuleScript)
-- Caminho: ServerScriptService > Services > BankService
-- Marco 10.20: ASSALTO AO BANCO CENTRAL (prédio no BankBuilder; números em GameConfig.Bank; eventos
-- no motor HeistEvents). Usa a mesma base da joalheria: gangue, procurado, chamado da PM, bolsa com
-- peso, minigame (a janela "JoiaMinigame", via JewelryService.minigame), receptador no chefe da
-- gangue e pagamento do policial que prende.
-- Fases (o painel mostra "Fase N/6"):
--   F1 PREPARAÇÃO (antes, opcional, vale para a gangue): crachá do funcionário que fuma no beco
--      (pula o gerente) e cortar a energia no transformador (alarme chega 45 s depois na PM e
--      câmeras mudas: metade dos pontos de procurado).
--   F2 INÍCIO: "Anunciar o assalto" no salão com arma, com pelo menos MinCrew da MESMA gangue
--      perto (servidor confere). Alarme -> chamado da PM. Clientes e caixas se rendem; o SEGURANÇA
--      tem que ser rendido (mirar) em GuardReact s, senão aperta o pânico (cerco mais cedo).
--      Gavetas dos caixas (minigame). O GERENTE rendido entrega o crachá.
--   F3 INTERNO: porta de segurança (crachá ou arrombar), terminal da segurança (hack = trava de
--      tempo liberada + câmeras), CONTROLE DUPLO (2 chaves longe uma da outra giradas juntas; se só
--      sobrou 1 da equipe vale a trava temporária de 12 s), furadeira térmica na porta do cofre.
--   F4 COFRE: girar o volante: a porta redonda abre (animação + som).
--   F5 COLETA: maços de dinheiro, barras de ouro (2 espaços), cofrinhos (minigame). Bolsa pesa.
--   F6 FUGA: sair do banco, despistar, vender ao chefe da gangue (F). Dinheiro marcado = rastreador.
-- Pressão sem depender de policial de verdade: SiegeTime depois do alarme vem o CERCO (porta da
-- frente tranca, procurado sobe para quem está dentro, saída de serviço só forçando) e SiegeFinal
-- depois a polícia toma o prédio (quem está dentro perde o malote e é tirado do prédio).
-- Fim seguro (nunca trava): fugiram todos, abandonaram, cerco final ou ninguém da equipe online.
-- Queda do jogo: o malote fica no chão (a equipe pega; a PM recolhe) e quem voltar em
-- ReconnectGrace s volta para a equipe. Tudo conferido no servidor (gangue, distância, estado).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local SecurityService = require(script.Parent:WaitForChild("SecurityService"))
local CrimeService = require(script.Parent:WaitForChild("CrimeService"))
local DownedService = require(script.Parent:WaitForChild("DownedService"))
local CareerService = require(script.Parent:WaitForChild("CareerService"))
local NPCKit = require(script.Parent:WaitForChild("NPCKit"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local GangService = require(script.Parent:WaitForChild("GangService"))
local JewelryService = require(script.Parent:WaitForChild("JewelryService"))
local HeistEvents = require(script.Parent:WaitForChild("HeistEvents"))
local WeaponService = require(script.Parent:WaitForChild("WeaponService"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService")) -- Marco 10.30
local AssaltoConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AssaltoConfig"))
local FerramentasAssaltoService -- Marco 10.30 (carregado no init)
local cleanupVaultTools -- Marco 10.30 (definida mais abaixo)
local PERF = AssaltoConfig.Perfuratriz
local C4C = AssaltoConfig.C4

local BankService = {}

local B = GameConfig.Bank
local MG = B.Minigame
local rng = Random.new()
local GUARD = B.Guards or {}

local uiUpdate
local bank -- Model "Banco"
local parts = {}
local prompts = {} -- lista { prompt, cond = function() -> bool }
local namedPrompts = {}
local npcs = {} -- { npc, role, spot, aim = {}, surrendered, home }
local state = "aberto" -- "aberto" | "assalto" | "fechado"
local heist
local closedUntil = 0
local bags = {} -- bags[player] = { value, slots, count, marked, left, trackerEnds, speed, gang }
local prep = {} -- prep[gangId] = { cracha = os.clock() até, energia = os.clock() até }
local drops = {} -- malotes no chão: { part, value, slots, name, expires }
local loot = { caixas = {}, pilhas = {}, ouro = {}, cofrinhos = {} }
local doorParts = {} -- { part, home }
local doorHinge
local doorAngle = 0 -- 0 = fechada, 1 = aberta
local gateHome
local events
local storage -- pasta em ServerStorage (andaime guardado)
local reformaOn, stormOn = false, false
local sprinklerOn = false -- Marco 10.21: sprinklers molhando a furadeira (metade da velocidade)
local swat = {}
local staffGeneration = 0
local initialized = false

---------------------------------------------------------------------------
-- Básico
---------------------------------------------------------------------------

local function send(player, kind, data)
	if player and player.Parent then
		uiUpdate:FireClient(player, kind, data or {})
	end
end

-- peça do banco pelo nome (procura dentro dos sub-modelos também)
local function f(name)
	return bank and (bank:FindFirstChild(name) or bank:FindFirstChild(name, true))
end

local function money(n)
	return "$" .. tostring(math.floor(n))
end

local function inBox(box, pos, pad)
	if not box then
		return false
	end
	local p = box.CFrame:PointToObjectSpace(pos)
	local h = box.Size / 2
	pad = pad or 0
	return math.abs(p.X) <= h.X + pad and math.abs(p.Y) <= h.Y + 4 and math.abs(p.Z) <= h.Z + pad
end

local function inHall(pos)
	return inBox(parts.areaSalao, pos)
end

local function inRestricted(pos)
	return inBox(parts.areaRestrita, pos)
end

local function inVault(pos)
	return inBox(parts.areaCofre, pos)
end

local function inBuilding(pos)
	return inHall(pos) or inRestricted(pos) or inVault(pos) or inBox(parts.areaSub, pos)
end

local function inLot(pos)
	return inBox(parts.areaLote, pos, 10)
end

local function rootOf(player)
	local _, _, root = SecurityService.getLivingCharacter(player)
	return root
end

local function near(player, part, dist)
	local root = rootOf(player)
	return root ~= nil and part ~= nil and (root.Position - part.Position).Magnitude <= (dist or 10)
end

local function hasGun(player)
	local character = player.Character
	for _, tool in ipairs(character and character:GetChildren() or {}) do
		if tool:IsA("Tool") and tool:GetAttribute("Use") == "gun" then
			return true
		end
	end
	return false
end

local function canCrime(player)
	if not player:GetAttribute("Gang") then
		return false, "Só quem é de gangue assalta banco. Procure o chefe numa favela."
	end
	if CrimeService.isPolice(player) then
		return false, "Policial não assalta."
	end
	if player:GetAttribute("Preso") or CrimeService.isCuffed(player) then
		return false, "Agora não dá."
	end
	if not rootOf(player) or DownedService.isDowned(player) then
		return false, "Você precisa estar de pé para interagir com o banco."
	end
	return true
end

local function playSound(parent, id, volume, length)
	if not parent or not id or id == 0 then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. tostring(id)
	s.Volume = volume or 0.6
	s.RollOffMaxDistance = 180
	s.Parent = parent
	s:Play()
	task.delay(length or 8, function()
		s:Destroy()
	end)
end

local function setText(part, str, color)
	local gui = part and part:FindFirstChildOfClass("SurfaceGui")
	local label = gui and gui:FindFirstChildOfClass("TextLabel")
	if label then
		label.Text = str
		if color then
			label.TextColor3 = color
		end
	end
end

local function crewList()
	local list = {}
	if heist then
		for p in pairs(heist.crew) do
			if p.Parent then
				table.insert(list, p)
			end
		end
	end
	return list
end

-- da equipe, online, vivo e solto
local function activeCrew()
	local n = 0
	for _, p in ipairs(crewList()) do
		if rootOf(p) and not CrimeService.isCuffed(p) and not p:GetAttribute("Preso") and not DownedService.isDowned(p) then
			n += 1
		end
	end
	return n
end

local function crewNotice(text, color)
	for _, p in ipairs(crewList()) do
		send(p, "BancoAviso", { text = text, color = color })
	end
end

local function camsMuted()
	if not heist then
		return false
	end
	return heist.hacked or (heist.powerCut == true)
end

local function points(n)
	return camsMuted() and math.ceil(n / 2) or n
end

local function joinCrew(player)
	if heist and not heist.crew[player] and player:GetAttribute("Gang") == heist.gang then
		heist.crew[player] = true
		if heist.called then
			CrimeService.addWanted(player, points(B.StartPoints))
		end
	end
	return heist ~= nil and heist.crew[player] == true
end

---------------------------------------------------------------------------
-- Bolsa (malote)
---------------------------------------------------------------------------

local function bagPayload(player)
	local b = bags[player]
	local now = os.clock()
	return {
		value = b and b.value or 0,
		slots = b and b.slots or 0,
		max = B.BagSlots,
		count = b and b.count or 0,
		items = b and NPCKit.bagItems(b) or {},
		marked = b and b.marked or false,
		trackerIn = b and b.trackerEnds and math.max(0, b.trackerEnds - now) or nil,
		tracked = b and b.trackerEnds ~= nil and now < b.trackerEnds or false,
	}
end

local function weightSpeed(b)
	return math.max(8, GameConfig.WalkSpeed - (b and b.slots or 0) * B.SlowPerSlot)
end

local function applyWeight(player, b)
	local _, humanoid = SecurityService.getLivingCharacter(player)
	if not humanoid or humanoid.SeatPart then
		return
	end
	local target = b and weightSpeed(b) or GameConfig.WalkSpeed
	local current = humanoid.WalkSpeed
	local ours = (b and b.speed) or player:GetAttribute("BolsaVelocidade")
	if math.abs(current - GameConfig.WalkSpeed) < 0.05 or (ours and math.abs(current - ours) < 0.05) then
		if math.abs(current - target) > 0.05 then
			humanoid.WalkSpeed = target
		end
	end
	if b then
		b.speed = target
	end
	player:SetAttribute("BolsaVelocidade", b and target or nil)
end

local function setBag(player, b)
	bags[player] = b
	player:SetAttribute("MaloteBanco", b and b.value or nil)
	if not b then
		player:SetAttribute("RastreadorBanco", nil)
	end
	NPCKit.wearBag(player.Character, b and b.slots / B.BagSlots or 0)
	applyWeight(player, b)
	send(player, "BancoBolsa", bagPayload(player))
end

local sendStatus -- (mais abaixo)
local pending = {} -- pending[player] = { drop, accept } (Marco 10.26: troca oferecida)

-- põe um item na bolsa (devolve false se não coube)
local function addToBag(player, name, value, slots, at, opts)
	opts = opts or {}
	local b = bags[player] or { value = 0, slots = 0, count = 0, gang = player:GetAttribute("Gang") }
	if b.slots + slots > B.BagSlots then
		-- Marco 10.26: não coube: oferece trocar pelo que vale menos
		local drop, dropValue = NPCKit.bagCheapest(b, slots, B.BagSlots)
		if opts.offer and drop then
			local names = {}
			for _, it in ipairs(drop) do
				table.insert(names, it.name)
			end
			pending[player] = { drop = drop, accept = opts.offer, heist = heist,
				at = at, expires = os.clock() + 20, bag = b, valid = opts.valid }
			send(player, "BancoAchado", { name = name, value = value, slots = slots, drop = names, dropValue = dropValue })
		else
			send(player, "BancoAviso", { text = ("🎒 Não cabe! %s ocupa %d espaço(s) e sua bolsa tem %d livre(s)."):format(name, slots, B.BagSlots - b.slots) })
		end
		return false
	end
	joinCrew(player)
	NPCKit.bagItems(b)
	table.insert(b.items, { name = name, value = value, slots = slots })
	b.value += value
	b.slots += slots
	b.count += 1
	local moneyRoot = rootOf(player)
	if moneyRoot then
		playSound(moneyRoot, B.Sounds.Money, 0.7, 2)
	end
	if opts.marked then
		b.marked = true
	end
	setBag(player, b)
	if heist and b.slots >= 6 and not heist.rolledHeavy and events then
		heist.rolledHeavy = true
		events:roll("pesada")
	end
	if not opts.quiet then
		CrimeService.addWanted(player, points(B.LootPoints))
	end
	-- Marco 10.31: pose "pegar" pelo servidor (todo mundo vê, mesmo se a animação publicada não
	-- carregar no aparelho dos outros; quem vê a animação de verdade não vê a pose por cima)
	NPCKit.pose(player.Character, "pegar", (GameConfig.Jewelry.GrabAnim or {}).Length or 3.5)
	send(player, "BancoPegou", { name = name, value = value, at = at, big = slots >= 2 })
	if sendStatus then
		sendStatus()
	end
	return true
end

local function loseBag(player, text)
	if not bags[player] then
		return
	end
	setBag(player, nil)
	if text then
		send(player, "BancoAviso", { text = text, color = "red" })
	end
end

local makePrompt -- (mais abaixo)

-- malote no chão (caiu do jogo, desistiu caído, bolsa rasgou, avalanche)
local function makeDrop(pos, value, slots, name, life)
	local part = Instance.new("Part")
	part.Name = "MaloteNoChao"
	part.Size = Vector3.new(1.8, 1.4, 1.4)
	part.Color = Color3.fromRGB(70, 90, 140)
	part.Material = Enum.Material.Fabric
	part.Anchored = true
	part.CanCollide = false
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Workspace:FindFirstChild("Map") or bank }
	local hit = Workspace:Raycast(pos + Vector3.new(0, 3, 0), Vector3.new(0, -30, 0), params)
	local y = hit and hit.Position.Y or (pos.Y - 2.5)
	part.CFrame = CFrame.new(pos.X, y + 0.7, pos.Z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	part.Parent = bank
	local glow = Instance.new("PointLight")
	glow.Range = 6
	glow.Brightness = 0.6
	glow.Color = Color3.fromRGB(120, 160, 255)
	glow.Parent = part
	local d = { part = part, value = value, slots = slots, name = name or "Malote", expires = os.clock() + (life or B.DropLife) }
	table.insert(drops, d)
	local p = makePrompt(part, "BancoPrompt", "Pegar " .. d.name, money(value), 0.8, 8, function(player)
		if d.taken or not near(player, part, 9) then
			return
		end
		local ok, why = canCrime(player)
		if not ok then
			return CrimeService.notice(player, why)
		end
		if addToBag(player, d.name, d.value, d.slots, part.Position, { quiet = true }) then
			d.taken = true
			part:Destroy()
		end
	end, function()
		return not d.taken
	end)
	p.MaxActivationDistance = 8
	makePrompt(part, "BancoPolicia", "Recolher malote (PM)", money(value), 1, 8, function(player)
		if d.taken or not CrimeService.isPolice(player) or not near(player, part, 9) then
			return
		end
		d.taken = true
		part:Destroy()
		local paid = CareerService.taskPay(player, "Policial", B.PoliceBagPay, "Recolheu malote do banco", 0)
		send(player, "CrimePaid", { amount = paid, text = ("Malote recuperado: +%s"):format(money(paid)) })
	end, function()
		return not d.taken
	end)
	return d
end

-- Marco 10.26: largar um item da mochila no chão (dá para pegar de novo)
local function dropItem(player, it)
	local b = bags[player]
	local root = rootOf(player)
	if not b or not root then
		return
	end
	local items = NPCKit.bagItems(b)
	local at = table.find(items, it)
	if not at then
		return
	end
	table.remove(items, at)
	b.value = math.max(0, b.value - it.value)
	b.slots = math.max(0, b.slots - it.slots)
	b.count = math.max(0, (b.count or 1) - 1)
	setBag(player, b.slots > 0 and b or nil)
	makeDrop(root.Position + root.CFrame.LookVector * 3, it.value, it.slots, it.name)
	if sendStatus then
		sendStatus()
	end
end

-- larga a bolsa inteira no chão (em pedaços de até 4 espaços)
local function dropWholeBag(player, pos, text)
	local b = bags[player]
	if not b then
		return
	end
	setBag(player, nil)
	local pieces = math.max(1, math.ceil(b.slots / 4))
	for i = 1, pieces do
		local slots = (i < pieces) and 4 or (b.slots - 4 * (pieces - 1))
		local value = math.floor(b.value * slots / math.max(1, b.slots))
		local off = Vector3.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2))
		makeDrop(pos + off, value, math.max(1, slots), "Malote do banco")
	end
	if text then
		crewNotice(text, "red")
	end
end

---------------------------------------------------------------------------
-- NPCs
---------------------------------------------------------------------------

local setLasers, crewFx, stepLasers, stepTension, shout -- Marco 10.25 (definidas mais abaixo)

local function npcRoot(info)
	return info and info.npc and info.npc.Parent and info.npc:FindFirstChild("HumanoidRootPart")
end

local function clearNpcs(onlyRole)
	for i = #npcs, 1, -1 do
		local info = npcs[i]
		if not onlyRole or info.role == onlyRole then
			if info.npc and info.npc.Parent then
				info.npc:Destroy()
			end
			table.remove(npcs, i)
		end
	end
end

local function addNpc(cf, def, generation)
	local npc = NPCKit.spawn(cf, { name = def.name, anchored = def.walk ~= true, important = true, shirt = def.shirt, pants = def.pants, showName = def.showName, outfit = def.outfit, title = def.title })
	if not npc then
		return nil
	end
	if generation and (generation ~= staffGeneration or state == "fechado" or (state == "assalto" and def.role == "fumante")) then
		npc:Destroy()
		return nil
	end
	local info = { npc = npc, role = def.role, aim = {}, home = npc:GetPivot() }
	if def.role == "seguranca" or def.role == "vigia" then
		info.aimRange = GUARD.AimRange or 60
	end
	table.insert(npcs, info)
	return info
end

local function npcBy(role)
	for _, info in ipairs(npcs) do
		if info.role == role and npcRoot(info) then
			return info
		end
	end
	return nil
end

local SUIT = Color3.fromRGB(28, 30, 40)
local surrender
local function spawnStaff(generation)
	local list = {
		{ spot = "PontoSeguranca", role = "seguranca", name = "Vigilante Souza", outfit = "seguranca" },
		{ spot = "PontoSeguranca2", role = "vigia", name = "Vigilante Rocha", outfit = "seguranca" },
		{ spot = "PontoGerente", role = "gerente", name = "Gerente Marta", outfit = "gerente" },
		{ spot = "PontoCaixa1", role = "caixa", name = "Caixa Paula", outfit = "caixa" },
		{ spot = "PontoCaixa2", role = "caixa", name = "Caixa Jonas", outfit = "caixa" },
		{ spot = "PontoCliente1", role = "cliente", name = "Cliente" },
		{ spot = "PontoCliente2", role = "cliente", name = "Cliente" },
		{ spot = "PontoCliente3", role = "cliente", name = "Cliente" },
		{ spot = "PontoFumante", role = "fumante", name = "Funcionário Beto", outfit = "funcionario" },
	}
	for _, def in ipairs(list) do
		if generation ~= staffGeneration or state == "fechado" then
			return
		end
		local spot = f(def.spot)
		if spot then
			local info = addNpc(spot.CFrame * CFrame.new(0, -2.5, 0), def, generation)
			if info then
				info.spot = spot
				if state == "assalto" and (info.role == "caixa" or info.role == "cliente") then
					surrender(info)
				end
				if def.role == "fumante" then
					NPCKit.hold(info.npc, "Cafe", Vector3.new(0.4, 0.6, 0.4), Color3.fromRGB(240, 240, 240))
				end
			end
		end
	end
end

local tiePrompt -- definida depois do makePrompt (Marco 10.25)
local SCARED = { "Calma! Pode levar!", "Não atira, por favor!", "Tá bom, tá bom!", "Meu Deus do céu!", "Eu tenho família!" }
surrender = function(info)
	if info.surrendered then
		return
	end
	info.surrendered = true
	if not info.npc or not info.npc.Parent then
		return
	end
	NPCKit.pose(info.npc, (info.role == "caixa" or info.role == "cliente") and "refem" or "maos")
	-- Marco 10.25: quem é armado só fica quieto um tempo: amarre, senão ele reage
	if (info.role == "seguranca" or info.role == "vigia") and not info.tied and heist then
		info.releaseAt = os.clock() + (B.TieTime or 35)
		info.relapsed = nil
		tiePrompt(info)
	end
	if info.gun then
		info.gun:Destroy()
		info.gun = nil
	end
	if info.role == "vigia" then
		NPCKit.say(info.npc, "Tá bom! Larguei a arma!", 4)
	elseif info.role == "seguranca" then
		NPCKit.say(info.npc, info.armed and "Tá bom! Larguei a arma!" or "Tá bom! Não aperto nada!", 4)
		if heist and heist.guard == "alerta" then
			heist.guard = "rendido"
		end
	elseif info.role == "gerente" then
		NPCKit.say(info.npc, "Leva o crachá, mas não machuca ninguém!", 4)
	elseif info.role == "guardacosta" then
		NPCKit.say(info.npc, "Ok, ok! Mãos pra cima!", 3)
	elseif info.role == "rival" then
		NPCKit.say(info.npc, "Foi mal, parceiro! Já tô indo!", 3)
	else
		NPCKit.say(info.npc, SCARED[rng:NextInteger(1, #SCARED)], 3)
	end
end

local function handsUp()
	for _, info in ipairs(npcs) do
		-- Marco 10.30: o Batalhão de Choque é "surrendered" só para não poder ser rendido; não levanta as mãos
		if info.surrendered and info.npc and info.npc.Parent and info.role ~= "rival" and info.role ~= "choque" and not info.tied then
			NPCKit.pose(info.npc, (info.role == "caixa" or info.role == "cliente") and "refem" or "maos")
		end
	end
end

-- Marco 10.21: seguranças armados atiram no assaltante mais perto (de pé e à vista)
local function lineOfSight(from, to, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	return Workspace:Raycast(from, to - from, params) == nil
end

local function guardStep(now)
	local h = heist
	local ignore
	for _, info in ipairs(npcs) do
		local root = (info.role == "seguranca" or info.role == "vigia") and not info.surrendered and npcRoot(info)
		local active = false
		if root then
			if info.role == "seguranca" then
				active = h.guard == "panico" or info.relapsed == true
			else
				active = now >= h.started + (GUARD.GalleryDelay or 8)
			end
		end
		if active then
			if not info.armed then
				info.armed = true
				info.gun = NPCKit.hold(info.npc, "PistolaSeguranca", Vector3.new(0.35, 0.7, 1.3), Color3.fromRGB(30, 30, 34), Enum.Material.Metal)
				NPCKit.say(info.npc, info.role == "vigia" and "PARADOS! LARGUEM AS ARMAS!" or "Ninguém sai daqui!", 3)
				NPCKit.emote(info.npc, "point")
				info.nextShot = now + 1.2
				if not h.guardsWarned then
					h.guardsWarned = true
					crewNotice("🔫 OS SEGURANÇAS ESTÃO ATIRANDO! Mire neles para render (tem um na galeria de cima).", "red")
				end
			end
			if now >= (info.nextShot or 0) then
				info.nextShot = now + (GUARD.FireRate or 1.3)
				if not ignore then
					ignore = {}
					for _, x in ipairs(npcs) do
						if x.npc then
							table.insert(ignore, x.npc)
						end
					end
				end
				local eye = root.Position + Vector3.new(0, 1.5, 0)
				local bestD, bestRoot
				for _, p in ipairs(crewList()) do
					local r = rootOf(p)
					local hum = r and r.Parent and r.Parent:FindFirstChildOfClass("Humanoid")
					if hum and hum.Health > 0 and not p:GetAttribute("Caido") and not p:GetAttribute("Algemado") then
						local d = (r.Position - eye).Magnitude
						if d < (GUARD.Range or 60) and (not bestD or d < bestD) then
							local list = table.clone(ignore)
							table.insert(list, r.Parent)
							if lineOfSight(eye, r.Position, list) then
								bestD, bestRoot = d, r
							end
						end
					end
				end
				if bestRoot then
					local pv = info.npc:GetPivot()
					local tp = bestRoot.Position
					info.npc:PivotTo(CFrame.lookAt(pv.Position, Vector3.new(tp.X, pv.Position.Y, tp.Z)))
					local hit = rng:NextNumber() < (GUARD.Hit or 0.5)
					local to = hit and tp or tp + Vector3.new(rng:NextNumber(-4, 4), rng:NextNumber(-1, 3), rng:NextNumber(-4, 4))
					if uiUpdate then
						uiUpdate:FireAllClients("Shot", { from = info.gun and info.gun.Position or eye, to = to, by = 0 })
					end
					if hit then
						local hum = bestRoot.Parent:FindFirstChildOfClass("Humanoid")
						if hum then
							hum:TakeDamage(GUARD.Damage or 9)
						end
					end
					info.shots = (info.shots or 0) + 1
				end
			end
		end
	end
end

local function aimStep(dt)
	if state ~= "assalto" or not heist then
		return
	end
	for _, p in ipairs(Players:GetPlayers()) do
		local root = hasGun(p) and canCrime(p) and rootOf(p)
		local best = 0
		if root and inLot(root.Position) then
			for _, info in ipairs(npcs) do
				local nroot = not info.surrendered and info.role ~= "fumante" and npcRoot(info)
				if nroot then
					local d = (nroot.Position - root.Position).Magnitude
					if d < (info.aimRange or 34) and WeaponService.isAimingAt(p, root, nroot.Position) then
						info.aim[p] = (info.aim[p] or 0) + dt
						best = math.max(best, info.aim[p] / B.AimTime)
						if info.aim[p] >= B.AimTime then
							joinCrew(p)
							surrender(info)
						end
					else
						info.aim[p] = 0
					end
				end
			end
		end
		-- Marco 10.24: mostra na tela que está rendendo
		p:SetAttribute("Rendendo", best > 0 and best < 1 and math.floor(best * 10) * 10 or nil)
	end
end

-- Marco 10.24: tiro na direção de um NPC também o faz se render na hora
local function shotAtNpc(player, from, dir)
	if state ~= "assalto" or not heist or not canCrime(player) or not inLot(from) then
		return
	end
	-- Marco 10.25: tiro assusta os reféns
	if inBuilding(from) then
		heist.tension = math.max(0, (heist.tension or 0) - (B.Tension.Shot or 12))
	end
	for _, info in ipairs(npcs) do
		local nroot = not info.surrendered and info.role ~= "fumante" and npcRoot(info)
		if nroot then
			local to = nroot.Position - from
			if to.Magnitude < (info.aimRange or 34) and dir:Dot(to.Unit) > 0.97 then
				joinCrew(player)
				surrender(info)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Peças (portas, grade, cofre, monitores)
---------------------------------------------------------------------------

-- Marco 10.25: lasers do subsolo. Sobem e descem; dá para passar na hora certa, mas encostar adianta o cerco
setLasers = function(on)
	for _, l in ipairs(parts.lasers and parts.lasers:GetChildren() or {}) do
		l.Transparency = on and 0 or 1
	end
end

crewFx = function(kind)
	for _, p in ipairs(crewList()) do
		send(p, "BancoFx", { kind = kind })
	end
end

stepLasers = function(h, now)
	if not h.lasersOn or not h.gateOpen then
		return
	end
	local base = parts.lasers:GetChildren()
	for _, l in ipairs(base) do
		local i = l:GetAttribute("Index") or 1
		local home = l:GetAttribute("Home")
		if not home then
			home = l.CFrame
			l:SetAttribute("Home", home)
		end
		local cf = home * CFrame.new(0, 2.2 + math.sin(now * 1.6 + i * 2.1) * 3.1, 0)
		l.CFrame = cf
		if now >= (h.laserHitAt or 0) then
			for _, p in ipairs(crewList()) do
				local r = rootOf(p)
				-- Marco 10.30: quem está furando fica colado na porta, dentro da última cortina: não conta
				if r and p ~= h.driller then
					local rel = cf:PointToObjectSpace(r.Position)
					if math.abs(rel.Z) < 1 and math.abs(rel.Y) < 2.4 and math.abs(rel.X) < 20 then
						h.laserHitAt = now + 3
						h.siegeAt -= B.LaserPenalty
						crewFx("laser")
						crewNotice(("🔴 %s encostou no laser! O cerco chega %d s mais cedo."):format(p.DisplayName, B.LaserPenalty), "red")
						break
					end
				end
			end
		end
	end
end

-- Marco 10.25: tensão dos reféns. Sobe com o tempo (mais rápido sem ninguém no salão); gritar (G) ou
-- atirar acalma. Em 100 um refém tenta avisar a polícia.
stepTension = function(h, dt)
	local T = B.Tension
	local watched = false
	for _, p in ipairs(crewList()) do
		local r = rootOf(p)
		if r and inHall(r.Position) then
			watched = true
		end
	end
	h.tension = math.min(100, (h.tension or 0) + dt * (watched and T.Watched or T.Alone))
	if h.tension >= 100 and not h.sieged then
		h.tension = 55
		h.siegeAt -= T.Penalty
		for _, info in ipairs(npcs) do
			if info.role == "cliente" and npcRoot(info) then
				NPCKit.say(info.npc, "Socorro! Polícia!", 3)
				break
			end
		end
		crewNotice(("😱 Um refém avisou a polícia: o cerco chega %d s mais cedo! Fique de olho (G para gritar)."):format(T.Penalty), "red")
	end
end

local SHOUTS = { "Todo mundo no chão!", "Ninguém se mexe!", "É um assalto! Quietos!", "Quem se mexer, leva!" }
shout = function(player)
	local h = heist
	local root = rootOf(player)
	if state ~= "assalto" or not h or not h.crew[player] or not root or not inBuilding(root.Position) then
		return
	end
	local now = os.clock()
	if now < (h.shoutAt or 0) then
		return
	end
	h.shoutAt = now + B.Tension.ShoutCooldown
	h.tension = math.max(0, (h.tension or 0) - B.Tension.Shout)
	handsUp()
	NPCKit.pose(player.Character, "gritar", 1.2)
	if player.Character then
		pcall(function()
			game:GetService("Chat"):Chat(player.Character:FindFirstChild("Head"), SHOUTS[rng:NextInteger(1, #SHOUTS)])
		end)
	end
	sendStatus()
end

local function setFront(closed)
	local g = parts.gradeFrente
	if g then
		g.Transparency = closed and 0 or 1
		g.CanCollide = closed
		g:SetAttribute("Aberta", not closed)
	end
end

local function setSecDoor(open)
	local d = parts.portaSeg
	if d then
		local home = d:GetAttribute("Home")
		d.CFrame = open and (home * CFrame.new(5.8, 0, 0)) or home
	end
	if parts.ledLeitor then
		parts.ledLeitor.Color = open and Color3.fromRGB(60, 220, 90) or Color3.fromRGB(230, 50, 50)
	end
end

local gateToken = 0
local function setGate(open)
	local g = parts.grade
	if not g or not gateHome then
		return
	end
	gateToken += 1
	local my = gateToken
	task.spawn(function()
		local from = g:GetPivot()
		local to = open and (gateHome + Vector3.new(0, 10.5, 0)) or gateHome
		for i = 1, 20 do
			if my ~= gateToken then
				return
			end
			g:PivotTo(from:Lerp(to, i / 20))
			task.wait(0.05)
		end
	end)
end

local function setDoorAngle(t)
	doorAngle = math.clamp(t, 0, 1)
	if not doorHinge then
		return
	end
	local rot = CFrame.new(doorHinge) * CFrame.Angles(0, math.rad(-B.DoorAngle * doorAngle), 0) * CFrame.new(-doorHinge)
	for _, dp in ipairs(doorParts) do
		dp.part.CFrame = rot * dp.home
	end
	if parts.bloqueio then
		parts.bloqueio.CanCollide = doorAngle < 0.55
	end
end

local doorToken = 0
local function animateDoor(target, seconds)
	doorToken += 1
	local my = doorToken
	local from = doorAngle
	local t0 = os.clock()
	task.spawn(function()
		while my == doorToken do
			local a = math.clamp((os.clock() - t0) / seconds, 0, 1)
			local s = a * a * (3 - 2 * a)
			setDoorAngle(from + (target - from) * s)
			if a >= 1 then
				break
			end
			RunService.Heartbeat:Wait()
		end
	end)
end

local function setMonitors(on)
	for _, m in ipairs(parts.monitores or {}) do
		local cam = m:GetAttribute("Cam") or 0
		setText(m, on and ("CAM %d\n● REC"):format(cam) or ("CAM %d\nSEM SINAL"):format(cam), on and Color3.fromRGB(120, 255, 150) or Color3.fromRGB(255, 110, 110))
	end
end

local function setTimePanel(str, color)
	setText(parts.painelTempo, str, color)
end

local function setKeyLed(which, on)
	for _, d in ipairs(bank:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("Chave") == which then
			d.Color = on and Color3.fromRGB(60, 220, 90) or Color3.fromRGB(230, 50, 50)
		end
	end
end

local function setReforma(on)
	reformaOn = on
	local sc = parts.andaime
	if sc then
		sc.Parent = on and bank or storage
	end
	local jan = parts.janela
	if jan then
		for _, d in ipairs(jan:GetDescendants()) do
			if d:IsA("BasePart") then
				if d.Name == "Bloqueio" then
					d.CanCollide = not on
				elseif d.Name == "Vidro" or d.Name == "Grade" or d.Name == "Caixilho" then
					if d:GetAttribute("T0") == nil then
						d:SetAttribute("T0", d.Transparency)
					end
					d.Transparency = on and 1 or d:GetAttribute("T0")
					d.CanCollide = not on
				end
			end
		end
	end
end

local function resetLoot()
	for _, c in ipairs(loot.caixas) do
		c.taken = false
		c.part.Color = Color3.fromRGB(70, 44, 28)
	end
	for _, list in ipairs({ loot.pilhas, loot.ouro }) do
		for _, s in ipairs(list) do
			s.left = s.layers
			s.marked = false
			s.blocked = false
			s.examined = false
			for i = 1, s.layers do
				local layer = s.model:FindFirstChild("Camada" .. i)
				for _, d in ipairs(layer and layer:GetDescendants() or {}) do
					if d:IsA("BasePart") then
						d.Transparency = 0
					end
				end
			end
			local hl = s.model:FindFirstChild("Marcado")
			if hl then
				hl:Destroy()
			end
		end
	end
	for _, c in ipairs(loot.cofrinhos) do
		c.taken = false
		local open = c.part:FindFirstChild("Aberto")
		if open then
			open.Transparency = 1
		end
	end
	if parts.cofreDiretor then
		parts.cofreDiretor.Color = Color3.fromRGB(40, 44, 50)
	end
	loot.diretorTaken = false
end

---------------------------------------------------------------------------
-- Estado do assalto e painel
---------------------------------------------------------------------------

local function phaseOf(h)
	if not h then
		return 1
	end
	if h.anyLeft then
		return 7
	end
	if h.vaultLooted then
		return 6
	end
	if h.vault == "aberto" or h.vault == "abrindo" or h.drill == "pronta" then
		return 5
	end
	if h.gateOpen then
		return 4
	end
	if h.secOpen then
		return 3
	end
	return 2
end

local PHASES = { "Preparação", "Anúncio", "Área restrita", "Subsolo", "Cofre", "Coleta", "Fuga" }

-- Marco 10.24: a UMA coisa que a pessoa tem que fazer agora, com onde fica e como faz. O painel do
-- topo da tela e os marcadores no mundo mostram isto. Devolve texto, dica, marca e lugares.
local function goalNow(h, player)
	local function spot(x)
		if not x then
			return nil
		end
		return x:IsA("Model") and x:GetPivot().Position or x.Position
	end
	local function npcSpot(info)
		local r = npcRoot(info)
		return r and r.Position + Vector3.new(0, 1, 0)
	end
	local AIM = "Com a arma na mão, mire até a pessoa se render"
	local guard = npcBy("seguranca")
	if h.guard == "alerta" and guard and not guard.surrendered then
		return ("Mire no SEGURANÇA antes do pânico! %ds"):format(math.max(0, math.ceil((h.guardDeadline or 0) - os.clock()))), AIM, "MIRE AQUI", { npcSpot(guard) }
	end
	-- quem atira só vira o objetivo se a pessoa está no salão, onde ele pode acertá-la
	local root = rootOf(player)
	local atHall = root ~= nil and inHall(root.Position)
	if atHall and guard and guard.armed and not guard.surrendered then
		return "O segurança está atirando: mire nele!", AIM, "MIRE AQUI", { npcSpot(guard) }
	end
	local vigia = npcBy("vigia")
	if atHall and vigia and vigia.armed and not vigia.surrendered then
		return "O vigilante da galeria está atirando: mire nele!", AIM, "MIRE AQUI", { npcSpot(vigia) }
	end
	-- Marco 10.25: rendido perto de reagir
	for _, info in ipairs(npcs) do
		if info.surrendered and info.releaseAt and not info.tied and npcRoot(info) and info.releaseAt - os.clock() < 20 then
			return ("Amarre o vigilante antes que ele reaja! %ds"):format(math.max(0, math.ceil(info.releaseAt - os.clock()))), "Segure E perto dele", "AMARRAR", { npcSpot(info) }
		end
	end
	if (h.tension or 0) >= 75 then
		return "Os reféns estão se agitando: grite para eles ficarem no chão!", "Aperte G", "REFÉNS", { spot(parts.anuncio) }
	end
	if not h.secOpen then
		if h.cardHolder then
			return "Passe o crachá no leitor da porta de segurança", "Segure E no leitor", "LEITOR", { spot(parts.leitor) }
		end
		local boss = npcBy("gerente")
		if boss and not boss.surrendered then
			return "Renda a GERENTE para pegar o crachá", AIM, "MIRE AQUI", { npcSpot(boss) }
		elseif boss then
			return "Pegue o crachá com a gerente", "Segure E perto dela", "CRACHÁ", { npcSpot(boss) }
		end
		return "Arrombe a porta de segurança", "Segure E na porta", "PORTA", { spot(parts.portaSeg) }
	end
	if not h.hacked then
		return "Hackeie o terminal da sala de segurança (porta leste do corredor)", "Segure E no terminal", "TERMINAL", { spot(parts.terminal) }
	end
	if not h.gateOpen then
		local keys, now = {}, os.clock()
		if not (h.keyA and now - h.keyA < 30) then
			table.insert(keys, spot(parts.chaveA))
		end
		if not (h.keyB and now - h.keyB < 30) then
			table.insert(keys, spot(parts.chaveB))
		end
		return activeCrew() < 2 and "Gire as 2 chaves do corredor (sozinho: até 12 s entre elas)" or "Girem as 2 chaves do corredor JUNTOS", "Segure E na chave", "CHAVE", keys
	end
	if h.drill == "c4" then
		return "C4 PLANTADA! Saiam de perto da porta do cofre!", "Vai explodir", "C4", { spot(parts.pontoFuradeira) }
	end
	if h.drill == "furando" then
		local pct = math.floor((h.drillProgress or 0) * 100)
		if h.drillJam then
			return "A broca da perfuratriz TRAVOU: destrave!", "Segure E na porta do cofre", "PERFURATRIZ", { spot(parts.pontoFuradeira) }
		end
		if not h.driller then
			return ("Perfuração parada em %d%%: segure a perfuratriz na porta"):format(pct), "Com a Perfuratriz na mão, segure E na porta", "PERFURATRIZ", { spot(parts.pontoFuradeira) }
		end
		if h.driller == player then
			return ("Furando: %d%%. Segure o CLIQUE; solte antes de superaquecer"):format(pct), "No celular: segure o botão 🛠️", "PERFURATRIZ", { spot(parts.pontoFuradeira) }
		end
		return ("%s está furando o cofre: %d%%. Defendam!"):format(h.driller.DisplayName, pct), "Se ele cair, pegue a perfuratriz e continue", "PERFURATRIZ", { spot(parts.pontoFuradeira) }
	end
	if h.lasersOn and not h.drill and h.vault == "fechado" then
		return "Desça a escada e corte os lasers do subsolo no quadro vermelho", "Segure E no quadro, ou passe sem encostar", "LASERS", { spot(parts.quadroLaser) }
	end
	if h.drill ~= "pronta" and h.vault ~= "aberto" and h.vault ~= "abrindo" then
		return "Abra a porta do cofre: PERFURATRIZ (achada na obra) ou C4 (chefe)", "Com ela na mochila, segure E na porta do cofre", "COFRE", { spot(parts.pontoFuradeira) }
	end
	if h.vault ~= "aberto" then
		return "Gire o volante e abra o cofre", "Segure E na porta do cofre", "VOLANTE", { spot(parts.pontoFuradeira) }
	end
	local bag = bags[player]
	local full = bag and bag.slots and bag.slots >= B.BagSlots
	if not h.vaultLooted and not full then
		return "Encha o malote: dinheiro e ouro dentro do cofre", "Segure E nas pilhas e nos paletes", "COFRE", { spot(parts.areaCofre) }
	end
	if h.tunnel == "aberto" then
		return "Fuja pelo túnel e suba pelo bueiro", "Segure E na escada do bueiro", "BUEIRO", { spot(parts.saidaTunel) }
	end
	if h.sieged then
		return "Cercado! Explodam a parede do túnel na antessala, ou forcem a saída de serviço", "Segure E na parede de tijolos", "TÚNEL", { spot(parts.paredeTunel), spot(parts.saidaServico) }
	end
	return "Fuja com o malote: pela frente, ou explodindo o túnel na antessala", "Segure E na parede de tijolos ou saia pela porta", "SAÍDA", { spot(parts.saida), spot(parts.paredeTunel) }
end

local function objectives(h, player)
	local o = {}
	local function add(text, done, hot)
		table.insert(o, { t = text, d = done or nil, h = hot or nil })
	end
	if h.guard == "alerta" then
		add(("👮 MIRE NO SEGURANÇA! %ds"):format(math.max(0, math.ceil((h.guardDeadline or 0) - os.clock()))), false, true)
	elseif h.guard == "panico" then
		local g = npcBy("seguranca")
		if g and not g.surrendered then
			add("🔫 O segurança está ATIRANDO: mire nele!", false, true)
		else
			add("🚨 O segurança apertou o pânico (cerco mais cedo)", true)
		end
	else
		add("Segurança rendido", true)
	end
	local card = h.secOpen and "Porta de segurança aberta"
		or (h.cardHolder == player and "Você tem o crachá: passe no leitor")
		or (h.cardHolder and "Crachá com a equipe: passe no leitor")
		or "Crachá: renda a GERENTE (mire) ou arrombe a porta"
	add(card, h.secOpen, h.cardHolder == player)
	add(h.hacked and "Trava de tempo liberada (terminal hackeado)" or "Hackear o terminal da sala de segurança", h.hacked, h.secOpen and not h.hacked)
	local solo = activeCrew() < 2
	add(h.gateOpen and "Controle duplo: grade aberta" or (solo and "Girar as 2 chaves do corredor (12 s entre elas)" or "Girar as 2 chaves do corredor JUNTOS"), h.gateOpen, h.hacked and not h.gateOpen)
	add(h.lasersOn and "Lasers do subsolo: cortar no quadro ou passar" or "Lasers do subsolo desligados", not h.lasersOn, h.gateOpen and h.lasersOn)
	local drillText
	if h.drill == "furando" then
		drillText = h.drillJam and "🔥 Broca TRAVOU: destrave!" or ("🛠️ Perfuratriz: %d%%"):format(math.floor((h.drillProgress or 0) * 100))
	elseif h.drill == "c4" then
		drillText = "🧨 C4 plantada: vai explodir!"
	elseif h.drill == "pronta" then
		drillText = h.vault == "fechado" and "Fechadura furada: gire o volante" or "Porta do cofre aberta"
	else
		drillText = "Abrir a porta do cofre (perfuratriz ou C4)"
	end
	add(drillText, h.drill == "pronta", h.gateOpen and h.drill ~= "pronta")
	add(h.vault == "aberto" and "Cofre ABERTO: encham as bolsas" or "Girar o volante e abrir o cofre", h.vault == "aberto", h.drill == "pronta" and h.vault ~= "aberto")
	add("Fugir e vender ao chefe da gangue (F)", false, h.vaultLooted)
	return o
end

local function crewPayload()
	local list = {}
	for _, p in ipairs(crewList()) do
		local b = bags[p]
		table.insert(list, { name = p.DisplayName, value = b and b.value or 0, slots = b and b.slots or 0 })
	end
	return list
end

local function prepPayload(player)
	local g = player:GetAttribute("Gang")
	local pr = g and prep[g]
	local now = os.clock()
	return {
		cracha = pr and pr.cracha and pr.cracha > now and math.ceil(pr.cracha - now) or nil,
		energia = pr and pr.energia and pr.energia > now and math.ceil(pr.energia - now) or nil,
	}
end

local function statusPayload(player)
	local now = os.clock()
	local h = heist
	local p = {
		state = state,
		phase = phaseOf(h),
		phaseName = PHASES[phaseOf(h)],
		prep = prepPayload(player),
		reforma = reformaOn or nil,
		closedIn = state == "fechado" and math.max(0, closedUntil - now) or nil,
	}
	if events then
		p.events = events:list()
	end
	if not h then
		p.startPos = parts.anuncio and parts.anuncio.Position -- Marco 10.24: onde se anuncia o assalto
		return p
	end
	p.crew = crewPayload()
	p.member = h.crew[player] == true
	p.goals = objectives(h, player)
	p.goalText, p.goalHint, p.goalMark, p.goalPos = goalNow(h, player)
	p.tension = math.floor(h.tension or 0)
	p.alarmIn = (not h.called and h.alarmAt) and math.max(0, h.alarmAt - now) or nil
	p.called = h.called or false
	p.siegeIn = (h.siegeAt and not h.sieged) and math.max(0, h.siegeAt - now) or nil
	p.sieged = h.sieged or false
	p.takeIn = h.sieged and math.max(0, h.siegeAt + B.SiegeFinal - now) or nil
	p.drill = h.drill == "furando" and (h.drillProgress or 0) or nil
	p.c4 = (h.drill == "c4" and h.c4At) and math.max(0, h.c4At - now) or nil
	p.jam = h.drillJam or nil
	p.keys = { A = h.keyA and now - h.keyA < 30 or false, B = h.keyB and now - h.keyB < 30 or false }
	p.solo = activeCrew() < 2
	p.cams = not camsMuted()
	return p
end

sendStatus = function(extra)
	for _, p in ipairs(crewList()) do
		send(p, "BancoStatus", statusPayload(p))
	end
	for _, p in ipairs(extra or {}) do
		send(p, "BancoStatus", statusPayload(p))
	end
end

---------------------------------------------------------------------------
-- Alarme, cerco e fim
---------------------------------------------------------------------------

local function callPolice(why)
	local h = heist
	if not h or h.called then
		return
	end
	h.called = true
	crewFx("alarme")
	local pos = bank:GetPivot().Position
	CrimeService.alert("🏦 Assalto ao banco", B.Name, pos)
	for _, part in ipairs(bank:GetChildren()) do
		if part.Name == "LuzAlarme" then
			CrimeService.blink(part)
		end
	end
	playSound(parts.anuncio, B.Sounds.Alarm, 0.8, 30)
	for _, p in ipairs(crewList()) do
		CrimeService.addWanted(p, points(B.StartPoints))
	end
	crewNotice(("🚨 %s A PM foi chamada! O CERCO chega em %d:%02d."):format(why or "", math.floor((h.siegeAt - os.clock()) / 60), math.floor((h.siegeAt - os.clock()) % 60)), "red")
	bank:SetAttribute("Alarme", true)
	if events then
		events:roll("alarme")
	end
end

local function spawnSwat()
	local base = parts.saida and parts.saida.CFrame
	if not base then
		return
	end
	for i = -2, 2 do
		if i ~= 0 then
			-- Marco 10.30 (bug do Luís: o Choque flutuava na frente do banco): o marcador fica na altura
			-- do piso do banco; a fila agora fica no chão de verdade daquele ponto
			local cf = base * CFrame.new(i * 5, -2.5, -10) * CFrame.Angles(0, math.pi, 0)
			local groundY = NPCKit.groundAt(cf.Position)
			cf = cf - Vector3.new(0, cf.Position.Y - groundY, 0)
			local info = addNpc(cf, { role = "choque", name = "Choque", outfit = "choque" })
			if info then
				info.surrendered = true -- não dá para render o Choque
				table.insert(swat, info)
				NPCKit.hold(info.npc, "Escudo", Vector3.new(2.2, 3.2, 0.3), Color3.fromRGB(30, 40, 60), Enum.Material.Metal)
				if i == -2 then
					NPCKit.say(info.npc, "POLÍCIA! O PRÉDIO ESTÁ CERCADO!", 5)
				end
			end
		end
	end
end

local function exitRobbers()
	-- quem ficou dentro no fim do cerco: perde o malote e é tirado do prédio
	local out = parts.saida
	for _, p in ipairs(Players:GetPlayers()) do
		local root = rootOf(p)
		if root and inBuilding(root.Position) and not CrimeService.isPolice(p) then
			if bags[p] then
				loseBag(p, "🚔 A polícia tomou o banco e recuperou o malote.")
			end
			if heist and heist.crew[p] then
				CrimeService.addWanted(p, 20)
			end
			if out then
				p.Character:PivotTo(out.CFrame * CFrame.new(rng:NextNumber(-8, 8), 0, -12))
			end
		end
	end
end

local refreshPrompts -- (mais abaixo)

local function closeBank(reason)
	if state == "fechado" then
		return
	end
	local crew = crewList()
	if events then
		events:reset()
	end
	setReforma(false)
	pcall(cleanupVaultTools, heist) -- Marco 10.30
	state = "fechado"
	staffGeneration += 1
	table.clear(pending)
	if heist and heist.drillPart then
		heist.drillPart:Destroy()
	end
	closedUntil = os.clock() + B.Cooldown
	heist = nil
	setFront(true)
	setGate(false)
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("CrachaBanco") then
			p:SetAttribute("CrachaBanco", nil)
		end
	end
	bank:SetAttribute("Alarme", nil)
	bank:SetAttribute("Estado", state)
	for _, p in ipairs(crew) do
		send(p, "BancoStatus", statusPayload(p))
		if reason then
			send(p, "BancoAviso", { text = reason })
		end
	end
	task.delay(25, function()
		if state == "fechado" then
			for _, info in ipairs(swat) do
				if info.npc and info.npc.Parent then
					info.npc:Destroy()
				end
			end
			swat = {}
		end
	end)
	refreshPrompts()
	print("[BankService] Banco fechado: " .. tostring(reason))
end

local function reopenBank()
	setLasers(false) -- Marco 10.25: o subsolo volta ao normal
	if parts.paredeTunel then
		parts.paredeTunel.Transparency = 0
		parts.paredeTunel.CanCollide = true
	end
	state = "aberto"
	heist = nil
	for _, d in ipairs(bank:GetChildren()) do -- Marco 10.30: marcas do corte e da explosão
		if d.Name == "MarcaCorte" or d.Name == "CorteBrasa" or d.Name == "Queimado" or d.Name == "C4Plantada" then
			d:Destroy()
		end
	end
	resetLoot()
	setFront(false)
	setSecDoor(false)
	setGate(false)
	doorToken += 1
	setDoorAngle(0)
	setMonitors(true)
	setKeyLed("ChaveA", false)
	setKeyLed("ChaveB", false)
	setTimePanel("TRAVA DE TEMPO\n🔒 ATIVA", Color3.fromRGB(255, 80, 80))
	setText(parts.terminal, "🔒 SISTEMA\nVÉRTICE SEC 5", Color3.fromRGB(120, 200, 255))
	setText(parts.retro, "C:\\>_", Color3.fromRGB(80, 255, 120))
	clearNpcs()
	swat = {}
	staffGeneration += 1
	-- Avatares podem demorar para carregar; os botões não dependem desse pedido de rede.
	task.defer(spawnStaff, staffGeneration)
	bank:SetAttribute("Estado", state)
	if events then
		events:reset()
		events:roll("aberto")
	end
	refreshPrompts()
	print("[BankService] Banco Central aberto.")
end

---------------------------------------------------------------------------
-- Início
---------------------------------------------------------------------------

local function gangNear(player)
	local gang = player:GetAttribute("Gang")
	local list = {}
	local center = parts.anuncio.Position
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("Gang") == gang and canCrime(p) then
			local r = rootOf(p)
			if r and not DownedService.isDowned(p) and ((r.Position - center).Magnitude <= B.StartRadius or inHall(r.Position)) then
				table.insert(list, p)
			end
		end
	end
	return list
end

local function startHeist(player)
	if state ~= "aberto" then
		return
	end
	local root = rootOf(player)
	if not root or not inHall(root.Position) or not near(player, parts.anuncio, 19) then
		return send(player, "BancoAviso", { text = "Entre no salão e aproxime-se do ponto de anúncio." })
	end
	local ok, why = canCrime(player)
	if not ok then
		return CrimeService.notice(player, why)
	end
	if not hasGun(player) then
		return send(player, "BancoAviso", { text = "🔫 Pegue uma arma na mão para anunciar o assalto." })
	end
	if CrimeService.policeCount() < B.MinPolice then
		return send(player, "BancoAviso", { text = ("Precisa de pelo menos %d policial(is) no servidor."):format(B.MinPolice) })
	end
	local crew = gangNear(player)
	if #crew < B.MinCrew then
		return send(player, "BancoAviso", { text = ("👥 Banco é trabalho de equipe: precisa de pelo menos %d da SUA gangue aqui dentro do salão (tem %d)."):format(B.MinCrew, #crew), color = "red" })
	end
	-- Marco 10.30: sem perfuratriz nem C4 a porta do cofre não abre
	local hasTool = false
	for _, p in ipairs(crew) do
		if InventoryService.has(p, "Perfuratriz") or InventoryService.has(p, "C4") then
			hasTool = true
		end
	end
	if not hasTool then
		return send(player, "BancoAviso", { text = "🛠️ Para abrir o cofre a equipe precisa de uma PERFURATRIZ (escondida na obra do Residencial Vale Alto, Estrada do Vale) ou de uma C4 (chefe da gangue). Ninguém aqui tem.", color = "red" })
	end
	local now = os.clock()
	local gang = player:GetAttribute("Gang")
	local pr = prep[gang] or {}
	state = "assalto"
	heist = {
		gang = gang,
		crew = {},
		away = {},
		started = now,
		lastInside = now,
		guard = "alerta",
		guardDeadline = now + B.GuardReact,
		powerCut = pr.energia ~= nil and pr.energia > now,
		vault = "fechado",
		drillProgress = 0,
		tension = B.Tension.Start,
		lasersOn = true,
	}
	setLasers(true)
	for _, p in ipairs(crew) do
		heist.crew[p] = true
	end
	local delay = heist.powerCut and B.PowerAlarmDelay or 0
	heist.alarmAt = now + delay
	heist.siegeAt = now + delay + B.SiegeTime
	if pr.cracha and pr.cracha > now then
		heist.cardHolder = player
		player:SetAttribute("CrachaBanco", true)
	end
	-- todo mundo se rende, menos o segurança (e a gerente, que precisa de mira para dar o crachá)
	for _, info in ipairs(npcs) do
		if info.role == "caixa" or info.role == "cliente" then
			surrender(info)
		elseif info.role == "seguranca" and info.npc and info.npc.Parent then
			NPCKit.say(info.npc, "Ninguém se mexe!", 3)
			NPCKit.emote(info.npc, "point")
		elseif info.role == "gerente" and info.npc and info.npc.Parent then
			NPCKit.say(info.npc, "Socorro! Isso é um assalto!", 3)
		elseif info.role == "fumante" and info.npc and info.npc.Parent then
			info.npc:Destroy()
		end
	end
	if heist.powerCut then
		setMonitors(false)
	end
	if events then
		events:reset({ Reforma = true })
		events:roll("inicio")
	end
	if delay == 0 then
		callPolice("Assalto anunciado!")
	else
		crewNotice(("⚡ A energia está cortada: o alarme só chega na PM em %d s. RÁPIDO!"):format(delay))
	end
	for _, p in ipairs(crew) do
		send(p, "BancoEvento", { id = "inicio", icon = "🏦", name = "ASSALTO AO BANCO", text = ("Equipe de %d. MIRE NO SEGURANÇA (%d s), no VIGILANTE da galeria (ele atira!) e na GERENTE (crachá). O cerco chega em %d min."):format(#crew, B.GuardReact, math.floor((heist.siegeAt - now) / 60)) })
	end
	refreshPrompts()
	sendStatus()
	print(("[BankService] %s anunciou o assalto ao banco com %d da gangue %s."):format(player.Name, #crew, tostring(gang)))
end

---------------------------------------------------------------------------
-- Ações
---------------------------------------------------------------------------

-- confere o básico de uma ação do assalto
local function heistAction(player, part, dist)
	if state ~= "assalto" or not heist then
		return false
	end
	local ok, why = canCrime(player)
	if not ok then
		CrimeService.notice(player, why)
		return false
	end
	if player:GetAttribute("Gang") ~= heist.gang then
		send(player, "BancoAviso", { text = "Esse assalto é de outra gangue." })
		return false
	end
	if not near(player, part, dist or 10) then
		return false
	end
	joinCrew(player)
	return true
end

local function minigame(player, rule, part, title, onDone, onMiss)
	local session = heist
	local character = player.Character
	local function valid()
		return session ~= nil and heist == session and player.Character == character
			and part.Parent ~= nil and heistAction(player, part, 12)
	end
	NPCKit.pose(player.Character, "digitar", 6)
	local ok = JewelryService.minigame(player, rule, part, title, function(...)
		if valid() then onDone(...) end
	end, function(...)
		if valid() and onMiss then onMiss(...) end
	end)
	if not ok then
		send(player, "BancoAviso", { text = "Termine o que você está fazendo antes." })
	end
end

local function openSecDoor(player, how)
	local h = heist
	if not h or h.secOpen then
		return
	end
	h.secOpen = true
	setSecDoor(true)
	crewNotice(how == "forca" and "🚪 Arrombaram a porta de segurança! Hackeiem o terminal da segurança (leste)." or ("🪪 %s passou o crachá: porta de segurança aberta! Agora o terminal da segurança (leste)."):format(player and player.DisplayName or "Alguém"))
	if events then
		events:roll("interno")
	end
	refreshPrompts()
	sendStatus()
end

local function turnKey(player, which)
	local h = heist
	if not h or h.gateOpen then
		return
	end
	if not h.hacked then
		return send(player, "BancoAviso", { text = "⏳ A TRAVA DE TEMPO está ativa: hackeie o terminal da sala de segurança antes.", color = "red" })
	end
	local now = os.clock()
	if which == "A" then
		h.keyA, h.keyAby = now, player
	else
		h.keyB, h.keyBby = now, player
	end
	setKeyLed("Chave" .. which, true)
	local other
	if which == "A" then
		other = h.keyB
	else
		other = h.keyA
	end
	local solo = activeCrew() < 2
	local window = solo and B.SoloDualWindow or B.DualWindow
	if other and now - other <= window and (solo or h.keyAby ~= h.keyBby) then
		h.gateOpen = true
		setGate(true)
		setTimePanel("TRAVA DE TEMPO\n🔓 LIBERADA", Color3.fromRGB(90, 255, 120))
		crewNotice("🔑 CONTROLE DUPLO ACEITO! A grade subiu: desçam a escada até o SUBSOLO. Cuidado com os lasers!")
		refreshPrompts()
		sendStatus()
		return
	end
	if solo then
		send(player, "BancoAviso", { text = ("🔑 Trava temporária: você tem %d s para girar a OUTRA chave!"):format(B.SoloDualWindow) })
	else
		crewNotice(("🔑 %s girou a CHAVE %s. A outra tem que girar em até %.1f s!"):format(player.DisplayName, which == "A" and "1" or "2", B.DualWindow))
	end
	task.delay(window + 0.2, function()
		if heist == h and not h.gateOpen then
			local t = which == "A" and h.keyA or h.keyB
			if t == now then
				if which == "A" then
					h.keyA, h.keyAby = nil, nil
				else
					h.keyB, h.keyBby = nil, nil
				end
				setKeyLed("Chave" .. which, false)
				send(player, "BancoAviso", { text = "❌ A chave voltou: girem as duas JUNTAS.", color = "red" })
			end
		end
	end)
	sendStatus()
end

local function drillRate()
	local r = 1 / B.DrillTime
	if reformaOn then
		r *= 1.25
	end
	if stormOn then
		r *= 1.15
	end
	if sprinklerOn then
		r *= 0.5
	end
	return r
end

local function openVault(player, opts)
	opts = opts or {}
	local h = heist
	if not h or h.vault == "aberto" or h.vault == "abrindo" then
		return
	end
	h.vault = "abrindo"
	local openTime = opts.blast and 0.5 or B.DoorOpenTime -- Marco 10.30: C4 arranca a porta na hora
	if not opts.blast then
		playSound(parts.pontoFuradeira, B.Sounds.VaultDoor, 0.9, 10)
		for _, p in ipairs(crewList()) do
			if p == player then
				NPCKit.pose(p.Character, "girar", 3)
			end
		end
		crewNotice(("🌀 %s girou o volante: a PORTA DO COFRE está abrindo!"):format(player and player.DisplayName or "Alguém"))
	end
	animateDoor(1, openTime)
	task.delay(openTime, function()
		if heist == h then
			h.vault = "aberto"
			h.vaultOpened = true
			if events and not h.rolledCofre then
				h.rolledCofre = true
				events:roll("cofre")
			end
			refreshPrompts()
			sendStatus()
		end
	end)
	refreshPrompts()
	sendStatus()
end


local function vaultLoot(player)
	local h = heist
	if h and not h.vaultLooted then
		h.vaultLooted = true
		if events then
			events:roll("coleta")
		end
	end
end

local grabStack
grabStack = function(player, s, kind)
	local h = heist
	if not h or h.vault ~= "aberto" or s.left <= 0 or s.blocked
		or not heistAction(player, s.model:FindFirstChild("Botao"), 8) then
		return
	end
	local L = B.Loot[kind]
	local value = rng:NextInteger(L.Value[1], L.Value[2])
	if not addToBag(player, L.Name, value, L.Slots, s.model:GetPivot().Position, { marked = s.marked, offer = function()
		grabStack(player, s, kind)
	end, valid = function() return heist == h and h.vault == "aberto" and s.left > 0 and not s.blocked end }) then
		return
	end
	local layer = s.model:FindFirstChild("Camada" .. s.left)
	for _, d in ipairs(layer and layer:GetDescendants() or {}) do
		if d:IsA("BasePart") then
			d.Transparency = 1
		end
	end
	s.left -= 1
	if s.marked then
		local root = rootOf(player)
		if root then
			local smoke = Instance.new("ParticleEmitter")
			smoke.Color = ColorSequence.new(Color3.fromRGB(40, 90, 255))
			smoke.Size = NumberSequence.new(1.5, 4)
			smoke.Rate = 60
			smoke.Lifetime = NumberRange.new(1, 1.6)
			smoke.Speed = NumberRange.new(2, 5)
			smoke.Parent = root
			task.delay(4, function()
				smoke:Destroy()
			end)
		end
		send(player, "BancoAviso", { text = "💥 TINTA AZUL! Esse dinheiro era MARCADO: a bolsa liga o rastreador quando você sair do banco.", color = "red" })
	end
	vaultLoot(player)
	refreshPrompts()
end

---------------------------------------------------------------------------
-- Eventos do banco (motor HeistEvents; Chance/Cooldown em GameConfig.Bank.Events)
---------------------------------------------------------------------------

local function walkNpc(info, target, stopIf)
	task.spawn(function()
		local root = npcRoot(info)
		if not root then
			return
		end
		local from = root.Position
		local flat = Vector3.new(target.X, from.Y, target.Z)
		local steps = math.max(1, math.ceil((flat - from).Magnitude / 3))
		local pts = {}
		for i = 1, steps do
			table.insert(pts, from:Lerp(flat, i / steps))
		end
		NPCKit.walk(info.npc, pts, nil, function()
			return info.npc.Parent ~= nil and not (stopIf and stopIf())
		end)
	end)
end

local function dropNpc(info)
	if not info then
		return
	end
	for i, x in ipairs(npcs) do
		if x == info then
			table.remove(npcs, i)
			break
		end
	end
	if info.npc and info.npc.Parent then
		info.npc:Destroy()
	end
end

local function newPart(name, size, cf, color, material, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color or Color3.fromRGB(163, 162, 165) -- Marco 10.30: peças invisíveis (efeitos) vêm sem cor
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent or bank
	return p
end

-- Marco 10.21: ponto do lote (y = altura acima do piso do banco), a partir do PontoAnuncio (0, F + 3, -52)
local function lotAt(x, y, z)
	return parts.anuncio.CFrame * CFrame.new(x, y - 3, z + 52)
end

---------------------------------------------------------------------------
-- Marco 10.30: PERFURATRIZ (segurada na mão) e C4 na porta do cofre
---------------------------------------------------------------------------

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local BEEP = "rbxasset://sounds/electronicpingshort.wav" -- som que já vem no Roblox (o Luís pode trocar)

local drillSpot -- { cut, normal, into, stand } (calculado uma vez)
local function getDrillSpot()
	if drillSpot then
		return drillSpot
	end
	local pf = parts.pontoFuradeira
	local into = -pf.CFrame.LookVector -- da antecâmara para a porta
	local right = pf.CFrame.RightVector
	-- fura do lado das trancas (contrário da dobradiça), um pouco abaixo do centro
	local hingeSide = doorHinge and ((doorHinge - pf.Position):Dot(right) >= 0 and 1 or -1) or 1
	local origin = pf.Position - right * hingeSide * 2 - Vector3.new(0, 1.6, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { parts.portaCofre }
	local hit = Workspace:Raycast(origin - into * 5, into * 14, params)
	local cut = hit and hit.Position or (origin + into * 1)
	-- (a porta é reta: o normal do ponto que o raio acertou pode ser de um rebite inclinado)
	local normal = -into
	-- onde a pessoa fica (3,6 studs para trás, no chão)
	local standXZ = cut - into * 3.6
	params.FilterDescendantsInstances = { bank }
	local floor = Workspace:Raycast(Vector3.new(standXZ.X, cut.Y + 1, standXZ.Z), Vector3.new(0, -14, 0), params)
	local floorY = floor and floor.Position.Y or (cut.Y - 5)
	drillSpot = { cut = cut, normal = normal, into = into, standXZ = Vector3.new(standXZ.X, floorY, standXZ.Z) }
	return drillSpot
end

local function vaultFx(h)
	if h.drillFx and h.drillFx.root.Parent then
		return h.drillFx
	end
	local sp = getDrillSpot()
	local root = newPart("PerfuracaoFx", Vector3.new(0.2, 0.2, 0.2), CFrame.lookAt(sp.cut, sp.cut + sp.normal))
	root.Transparency = 1
	root.CanTouch = false
	local att = Instance.new("Attachment")
	att.Parent = root
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "Faiscas"
	sparks.EmissionDirection = Enum.NormalId.Front
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 240, 180), Color3.fromRGB(255, 120, 30))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0.02) })
	sparks.Rate = 90
	sparks.Lifetime = NumberRange.new(0.25, 0.7)
	sparks.Speed = NumberRange.new(14, 26)
	sparks.SpreadAngle = Vector2.new(65, 65)
	sparks.Acceleration = Vector3.new(0, -60, 0)
	sparks.Drag = 2
	sparks.Enabled = false
	sparks.Parent = att
	local chips = Instance.new("ParticleEmitter")
	chips.Name = "Lascas"
	chips.EmissionDirection = Enum.NormalId.Front
	chips.Color = ColorSequence.new(Color3.fromRGB(150, 150, 156))
	chips.Size = NumberSequence.new(0.08)
	chips.Rate = 25
	chips.Lifetime = NumberRange.new(0.6, 1.2)
	chips.Speed = NumberRange.new(4, 9)
	chips.SpreadAngle = Vector2.new(40, 40)
	chips.Acceleration = Vector3.new(0, -50, 0)
	chips.RotSpeed = NumberRange.new(-300, 300)
	chips.Enabled = false
	chips.Parent = att
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "Fumaca"
	smoke.EmissionDirection = Enum.NormalId.Front
	smoke.Color = ColorSequence.new(Color3.fromRGB(90, 90, 90), Color3.fromRGB(160, 160, 160))
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 3.5) })
	smoke.Rate = 18
	smoke.Lifetime = NumberRange.new(1.5, 2.5)
	smoke.Speed = NumberRange.new(1.5, 3)
	smoke.Acceleration = Vector3.new(0, 3, 0)
	smoke.Enabled = false
	smoke.Parent = att
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 160, 60)
	light.Range = 14
	light.Brightness = 0
	light.Parent = root
	-- marca do corte na porta: um círculo em brasa que cresce com o progresso
	local glow = newPart("CorteBrasa", Vector3.new(0.05, 0.3, 0.3), CFrame.lookAt(sp.cut + sp.normal * 0.03, sp.cut + sp.normal * 2) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(255, 150, 50), Enum.Material.Neon)
	glow.Shape = Enum.PartType.Cylinder
	glow.CanTouch = false
	local sound
	if B.Sounds.Drill and B.Sounds.Drill ~= 0 then
		sound = Instance.new("Sound")
		sound.SoundId = "rbxassetid://" .. tostring(B.Sounds.Drill)
		sound.Looped = true
		sound.Volume = 0.7
		sound.RollOffMaxDistance = 160
		sound.Parent = root
	end
	h.drillFx = { root = root, sparks = sparks, chips = chips, smoke = smoke, light = light, glow = glow, sound = sound }
	return h.drillFx
end

local function clearVaultFx(h)
	if h and h.drillFx then
		local fx = h.drillFx
		h.drillFx = nil
		if fx.sound then
			fx.sound:Stop()
		end
		for _, e in ipairs({ fx.sparks, fx.chips }) do
			e.Enabled = false
		end
		fx.smoke.Enabled = false
		Debris:AddItem(fx.root, 3)
		-- a marca do corte esfria e fica (escura) até o banco reabrir
		fx.glow.Material = Enum.Material.Metal
		fx.glow.Color = Color3.fromRGB(60, 40, 30)
		fx.glow.Name = "MarcaCorte"
	end
end

local function setDrillerAttrs(player, on)
	local character = player and player.Character
	if not character then
		return
	end
	character:SetAttribute("Perfurando", on or nil)
	character:SetAttribute("Empurrando", nil)
	character:SetAttribute("AlvoFuro", on and getDrillSpot().cut or nil)
end

local function stopDrilling(h, why, done)
	local d = h and h.driller
	if not d then
		return
	end
	h.driller = nil
	h.drillPush = false
	setDrillerAttrs(d, false)
	send(d, "BancoFuro", { on = false, done = done == true })
	if h.drillFx then
		local fx = h.drillFx
		fx.sparks.Enabled = false
		fx.chips.Enabled = false
		fx.light.Brightness = 0
		if fx.sound then
			fx.sound:Pause()
		end
	end
	if why then
		crewNotice(why, "red")
	end
	refreshPrompts()
end

local function drillerOk(h, p)
	if not p or not p.Parent or not h.crew[p] then
		return false
	end
	if DownedService.isDowned(p) or CrimeService.isCuffed(p) or p:GetAttribute("Preso") then
		return false
	end
	local root = rootOf(p)
	if not root then
		return false
	end
	local sp = getDrillSpot()
	if (root.Position - sp.standXZ).Magnitude > PERF.Range + 3 then
		return false
	end
	if InventoryService.toolInHand(p, "Perfuratriz") then
		h.drillNoTool = nil
		return true
	end
	-- quando o servidor põe a perfuratriz na mão, a barra de itens do cliente pisca a ferramenta por
	-- uns 0,3 s (testado no Studio): só para se ficar sem ela na mão por 1 s
	h.drillNoTool = h.drillNoTool or os.clock()
	return os.clock() - h.drillNoTool < 1
end

local function startDrilling(player)
	local h = heist
	if not h or h.driller or not (h.drill == nil or h.drill == "furando") then
		return
	end
	if not InventoryService.has(player, "Perfuratriz") then
		return send(player, "BancoAviso", { text = "🛠️ Você não tem a PERFURATRIZ. Ela aparece na obra do Residencial Vale Alto (Estrada do Vale). Ou use C4.", color = "red" })
	end
	local tool = InventoryService.equip(player, "Perfuratriz")
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not tool or not humanoid or not root then
		return
	end
	local sp = getDrillSpot()
	-- encosta na porta: de frente para o ponto do corte
	local flat = Vector3.new(sp.into.X, 0, sp.into.Z).Unit
	local y = sp.standXZ.Y + humanoid.HipHeight + root.Size.Y / 2
	character:PivotTo(CFrame.lookAt(Vector3.new(sp.standXZ.X, y, sp.standXZ.Z), Vector3.new(sp.standXZ.X, y, sp.standXZ.Z) + flat))
	local first = h.drill == nil
	h.drill = "furando"
	h.driller = player
	h.drillHeat = h.drillHeat or 0
	h.drillLock = 0
	h.drillPush = false
	h.drillNoTool = nil
	vaultFx(h)
	setDrillerAttrs(player, true)
	send(player, "BancoFuro", { on = true, p = h.drillProgress or 0, heat = h.drillHeat })
	if first then
		CrimeService.addWanted(player, points(PERF.Points))
		crewNotice(("🛠️ %s encostou a PERFURATRIZ na porta do cofre! Segurando o clique ela fura (%d s). Defendam!"):format(player.DisplayName, PERF.Time))
		if events then
			events:roll("furando")
		end
	else
		crewNotice(("🛠️ %s voltou a furar o cofre."):format(player.DisplayName))
	end
	refreshPrompts()
	sendStatus()
end

local function drillDone(h)
	local d = h.driller
	h.drill = "pronta"
	h.drillProgress = 1
	stopDrilling(h, nil, true)
	clearVaultFx(h)
	setTimePanel("FECHADURA\nROMPIDA", Color3.fromRGB(90, 255, 120))
	crewNotice("🔓 A fechadura do cofre cedeu! GIREM O VOLANTE (segure E na porta).")
	if d and FerramentasAssaltoService then
		FerramentasAssaltoService.consume(d)
	end
	refreshPrompts()
	sendStatus()
end

local lastFuroSend = 0
local function stepDrill(dt)
	local h = heist
	if state ~= "assalto" or not h or h.drill ~= "furando" then
		return
	end
	local d = h.driller
	if not d then
		return
	end
	if not drillerOk(h, d) then
		local why = ("🛠️ A perfuratriz PAROU em %d%%: alguém com ela na mão segure E na porta do cofre."):format(math.floor((h.drillProgress or 0) * 100))
		stopDrilling(h, why)
		return
	end
	local now = os.clock()
	local fx = vaultFx(h)
	local locked = now < (h.drillLock or 0)
	local pushing = h.drillPush and now - (h.drillPushAt or 0) < 1.2
	local working = pushing and not locked and not h.drillJam
	if working then
		local mult = drillRate() * B.DrillTime -- obra (+25%), tempestade (+15%), sprinklers (metade)
		h.drillProgress = math.min(1, (h.drillProgress or 0) + dt / PERF.Time * mult)
		h.drillHeat = (h.drillHeat or 0) + dt * PERF.HeatUp
		if h.drillHeat >= 1 then
			h.drillHeat = 0.55
			h.drillLock = now + PERF.OverheatLock
			fx.smoke:Emit(25)
			send(d, "BancoAviso", { text = "🔥 SUPERAQUECEU! Solte e espere a perfuratriz esfriar.", color = "red" })
		end
	else
		h.drillHeat = math.max(0, (h.drillHeat or 0) - dt * PERF.CoolDown)
	end
	local character = d.Character
	if character and character:GetAttribute("Empurrando") ~= (working or nil) then
		character:SetAttribute("Empurrando", working or nil)
	end
	fx.sparks.Enabled = working
	fx.chips.Enabled = working
	fx.smoke.Enabled = locked or (h.drillHeat or 0) > 0.75
	fx.light.Brightness = working and (2.5 + math.random() * 1.5) or 0
	local r = 0.35 + (h.drillProgress or 0) * 1.5
	fx.glow.Size = Vector3.new(0.05, r, r)
	local heat01 = math.clamp((h.drillHeat or 0) + (working and 0.3 or 0), 0, 1)
	fx.glow.Color = Color3.fromRGB(150, 60, 30):Lerp(Color3.fromRGB(255, 220, 140), heat01)
	if fx.sound then
		if working and not fx.sound.IsPlaying then
			fx.sound:Resume()
			if not fx.sound.IsPlaying then
				fx.sound:Play()
			end
		elseif not working and fx.sound.IsPlaying then
			fx.sound:Pause()
		end
		fx.sound.PlaybackSpeed = 0.9 + (h.drillHeat or 0) * 0.35
	end
	if now - lastFuroSend > 0.12 then
		lastFuroSend = now
		send(d, "BancoFuro", { on = true, p = h.drillProgress, heat = h.drillHeat, lock = locked and (h.drillLock - now) or nil, jam = h.drillJam or nil, push = working })
		setTimePanel(("FURANDO\n%d%%"):format(math.floor(h.drillProgress * 100)), Color3.fromRGB(255, 190, 60))
	end
	if h.drillProgress >= 1 then
		drillDone(h)
	end
end

-- explosão (C4 da porta, C4 do túnel): efeito no servidor + câmera/empurrão no cliente
local function explosionFx(pos, normal, opts)
	opts = opts or {}
	local radius = opts.radius or 14
	local boom = Instance.new("Explosion")
	boom.Position = pos + normal * 0.5
	boom.BlastRadius = radius
	boom.BlastPressure = 0
	boom.DestroyJointRadiusPercent = 0
	boom.ExplosionType = Enum.ExplosionType.NoCraters
	boom.Parent = Workspace
	local soundAt = newPart("SomExplosao", Vector3.new(0.2, 0.2, 0.2), CFrame.new(pos))
	soundAt.Transparency = 1
	playSound(soundAt, B.Sounds.Explosion, 1, 6)
	Debris:AddItem(soundAt, 7)
	-- bola de fogo que cresce e some
	local ball = newPart("BolaDeFogo", Vector3.new(1, 1, 1), CFrame.new(pos + normal * 1.5), Color3.fromRGB(255, 190, 80), Enum.Material.Neon)
	ball.Shape = Enum.PartType.Ball
	ball.Transparency = 0.05
	ball.CastShadow = false
	TweenService:Create(ball, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(radius, radius, radius), Transparency = 1, Color = Color3.fromRGB(255, 80, 20) }):Play()
	Debris:AddItem(ball, 0.6)
	local flash = Instance.new("PointLight")
	flash.Color = Color3.fromRGB(255, 170, 80)
	flash.Range = 40
	flash.Brightness = 12
	flash.Parent = ball
	-- fumaça, fogo e brasas
	local holder = newPart("FumacaExplosao", Vector3.new(0.2, 0.2, 0.2), CFrame.lookAt(pos + normal * 0.8, pos + normal * 3))
	holder.Transparency = 1
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Color3.fromRGB(40, 40, 40), Color3.fromRGB(120, 120, 120))
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 9) })
	smoke.Lifetime = NumberRange.new(3, 5)
	smoke.Speed = NumberRange.new(4, 10)
	smoke.SpreadAngle = Vector2.new(70, 70)
	smoke.Acceleration = Vector3.new(0, 4, 0)
	smoke.Drag = 1.5
	smoke.EmissionDirection = Enum.NormalId.Front
	smoke.Rate = 6
	smoke.Parent = holder
	smoke:Emit(40)
	local embers = Instance.new("ParticleEmitter")
	embers.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 90, 20))
	embers.LightEmission = 1
	embers.Size = NumberSequence.new(0.25, 0.05)
	embers.Lifetime = NumberRange.new(0.6, 1.6)
	embers.Speed = NumberRange.new(20, 45)
	embers.SpreadAngle = Vector2.new(80, 80)
	embers.Acceleration = Vector3.new(0, -40, 0)
	embers.EmissionDirection = Enum.NormalId.Front
	embers.Rate = 0
	embers.Parent = holder
	embers:Emit(120)
	local fire = Instance.new("Fire")
	fire.Size = 6
	fire.Heat = 12
	fire.Parent = holder
	task.delay(5, function()
		smoke.Enabled = false
		fire.Enabled = false
	end)
	Debris:AddItem(holder, 10)
	-- pedaços de metal voando
	for i = 1, opts.debris or 12 do
		local chunk = Instance.new("Part")
		chunk.Name = "Estilhaco"
		chunk.Size = Vector3.new(math.random() * 0.6 + 0.2, math.random() * 0.4 + 0.15, math.random() * 0.6 + 0.2)
		chunk.Color = i % 3 == 0 and Color3.fromRGB(255, 150, 60) or Color3.fromRGB(90, 92, 98)
		chunk.Material = i % 3 == 0 and Enum.Material.Neon or Enum.Material.Metal
		chunk.CFrame = CFrame.new(pos + normal * 1.2) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		chunk.CanTouch = false
		chunk.CanQuery = false
		chunk.Parent = Workspace
		local dir = (normal + Vector3.new(math.random() - 0.5, math.random() * 0.8, math.random() - 0.5) * 1.6).Unit
		chunk.AssemblyLinearVelocity = dir * (30 + math.random() * 40)
		chunk.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 30
		Debris:AddItem(chunk, 6)
	end
	-- marca preta na parede/porta
	if opts.scorch ~= false then
		local mark = newPart("Queimado", Vector3.new(0.05, radius * 0.45, radius * 0.45), CFrame.lookAt(pos + normal * 0.04, pos + normal * 2) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(25, 22, 20), Enum.Material.Slate)
		mark.Shape = Enum.PartType.Cylinder
		mark.Transparency = 0.15
	end
	-- dano em quem estava perto (de longe menos) e câmera/empurrão no cliente de cada um
	for _, p in ipairs(Players:GetPlayers()) do
		local character = p.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid then
			local dist = (root.Position - pos).Magnitude
			if dist < 220 then
				send(p, "BancoExplosao", { pos = pos, r = radius, big = opts.big == true })
			end
			if dist < radius and humanoid.Health > 0 and (opts.damage or 0) > 0 then
				humanoid:TakeDamage(opts.damage * (1 - dist / radius))
			end
		end
	end
end

local function c4Model(cf)
	local folder = ServerStorage:FindFirstChild("WeaponModels")
	local src = folder and folder:FindFirstChild("C4")
	local m = Instance.new("Model")
	m.Name = "C4Plantada"
	local led
	if src then
		local c = src:Clone()
		local grip, muzzle, frente = c:FindFirstChild("Grip", true), c:FindFirstChild("Muzzle", true), c:FindFirstChild("Frente", true)
		local _, size = c:GetBoundingBox()
		local long = math.max(size.X, size.Y, size.Z)
		if long > 0 and c:IsA("Model") then
			c:ScaleTo(c:GetScale() * 1.1 / long)
		end
		local parts0 = {}
		for _, d in ipairs(c:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(parts0, d)
			end
		end
		if grip and muzzle and frente and grip:IsA("BasePart") then
			-- eixo comprido = Grip -> Muzzle (fica em pé), frente (celular) = para fora da porta
			local center = (grip.Position + muzzle.Position) / 2
			local up = (muzzle.Position - grip.Position).Unit
			local out = frente.Position - center
			out = (out - up * out:Dot(up)).Unit
			local from = CFrame.fromMatrix(center, up:Cross(out), up, out)
			local to = cf -- (cf: Y = em pé na porta, Z = para fora)
			local move = to * from:Inverse()
			for _, d in ipairs(parts0) do
				d.CFrame = move * d.CFrame
			end
		end
		for _, d in ipairs(parts0) do
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			if d.Name == "Grip" or d.Name == "Muzzle" or d.Name == "Frente" then
				d.Transparency = 1
			end
			local hex = d.Name:match("^Cor_(%x%x%x%x%x%x)")
			if hex then
				d.Color = Color3.fromHex(hex)
				d.Material = Enum.Material.SmoothPlastic
				if d:IsA("MeshPart") then
					d.TextureID = ""
				end
			end
			d.Parent = m
		end
		c:Destroy()
	else
		newPart("Explosivo", Vector3.new(0.6, 1.1, 0.25), cf, Color3.fromRGB(96, 92, 52), Enum.Material.SmoothPlastic, m)
		newPart("Celular", Vector3.new(0.4, 0.8, 0.12), cf * CFrame.new(0, 0, 0.18), Color3.fromRGB(40, 70, 120), Enum.Material.SmoothPlastic, m)
		newPart("Fita", Vector3.new(0.66, 0.16, 0.3), cf, Color3.fromRGB(130, 120, 90), Enum.Material.Fabric, m)
	end
	led = newPart("LedC4", Vector3.new(0.12, 0.12, 0.12), cf * CFrame.new(0.12, 0.42, 0.22), Color3.fromRGB(255, 30, 30), Enum.Material.Neon, m)
	led.Shape = Enum.PartType.Ball
	local l = Instance.new("PointLight")
	l.Color = Color3.fromRGB(255, 40, 40)
	l.Range = 5
	l.Brightness = 2
	l.Parent = led
	m.Parent = bank
	return m, led
end

local function plantC4(player)
	local h = heist
	if not h or h.drill == "pronta" or h.drill == "c4" or h.vault ~= "fechado" then
		return
	end
	if not InventoryService.removeOne(player, "C4") then
		return send(player, "BancoAviso", { text = "🧨 Você não tem C4. O chefe da gangue vende.", color = "red" })
	end
	local sp = getDrillSpot()
	if h.driller then
		stopDrilling(h)
	end
	clearVaultFx(h)
	h.drill = "c4"
	h.c4At = os.clock() + C4C.Fuse
	local cf = CFrame.fromMatrix(sp.cut + sp.normal * 0.14, Vector3.yAxis:Cross(sp.normal), Vector3.yAxis, sp.normal)
	local model, led = c4Model(cf)
	h.c4Model = model
	local bill = Instance.new("BillboardGui")
	bill.Size = UDim2.fromOffset(110, 44)
	bill.StudsOffsetWorldSpace = Vector3.new(0, 1.3, 0)
	bill.AlwaysOnTop = true
	bill.MaxDistance = 90
	bill.Parent = led
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
	label.BackgroundTransparency = 0.25
	label.TextColor3 = Color3.fromRGB(255, 60, 60)
	label.Font = Enum.Font.Code
	label.TextScaled = true
	label.Text = ("00:%02d"):format(C4C.Fuse)
	label.Parent = bill
	Instance.new("UICorner").Parent = label
	local beep = Instance.new("Sound")
	beep.SoundId = BEEP
	beep.Volume = 0.8
	beep.RollOffMaxDistance = 90
	beep.Parent = led
	CrimeService.addWanted(player, points(C4C.Points))
	crewNotice(("🧨 %s PLANTOU A C4 na porta do cofre! SAIAM DE PERTO: %d s!"):format(player.DisplayName, C4C.Fuse), "red")
	refreshPrompts()
	sendStatus()
	task.spawn(function()
		local nextBeep = 0
		while heist == h and h.drill == "c4" do
			local left = h.c4At - os.clock()
			if left <= 0 then
				break
			end
			label.Text = ("00:%02d"):format(math.ceil(left))
			if os.clock() >= nextBeep then
				beep:Play()
				led.Color = Color3.fromRGB(255, 255, 255)
				task.delay(0.08, function()
					if led.Parent then
						led.Color = Color3.fromRGB(255, 30, 30)
					end
				end)
				nextBeep = os.clock() + math.clamp(left / C4C.Fuse, 0.12, 1)
			end
			task.wait(0.05)
		end
		if heist ~= h or h.drill ~= "c4" then
			if model.Parent then
				model:Destroy()
			end
			return
		end
		model:Destroy()
		h.c4Model = nil
		explosionFx(sp.cut, sp.normal, { radius = C4C.Radius, damage = C4C.Damage, big = true, debris = 18 })
		h.drill = "pronta"
		h.drillProgress = 1
		setTimePanel("PORTA\nEXPLODIDA", Color3.fromRGB(255, 120, 60))
		if not h.called then
			callPolice("O estrondo da explosão chegou na PM!")
		end
		h.siegeAt -= C4C.SiegeSooner
		crewNotice(("💥 BOOM! A porta do cofre foi ARRANCADA! O barulho trouxe a polícia %d s mais cedo."):format(C4C.SiegeSooner), "red")
		openVault(player, { blast = true })
	end)
end

-- limpa o que sobrou (fim do assalto)
cleanupVaultTools = function(h)
	if not h then
		return
	end
	stopDrilling(h)
	clearVaultFx(h)
	if h.c4Model and h.c4Model.Parent then
		h.c4Model:Destroy()
	end
	h.c4Model = nil
end

local function isCovered(root)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { root.Parent }
	return Workspace:Raycast(root.Position, Vector3.new(0, 80, 0), params) ~= nil
end

local E = B.Events or {}
local BANK_EVENTS
BANK_EVENTS = {
	{
		Id = "Reforma",
		Name = "Reforma no prédio",
		Icon = "🚧",
		Text = "Andaime no lado OESTE: a janela da diretoria está aberta e o barulho da obra abafa a perfuratriz (+25%).",
		Phases = { aberto = true },
		Start = function()
			setReforma(true)
		end,
		Hint = function()
			return "Andaime a oeste: entrada pela janela da diretoria"
		end,
		Stop = function()
			setReforma(false)
		end,
	},
	{
		Id = "Tempestade",
		Name = "Tempestade",
		Icon = "⛈️",
		Text = "Chuva forte: o telefone falha (o alarme demora mais) e o trovão abafa a perfuratriz.",
		Phases = { inicio = true },
		Duration = 240,
		Start = function(_, ev)
			stormOn = true
			local d = ev.data
			local center = bank:GetPivot().Position
			d.cloud = newPart("Chuva", Vector3.new(260, 1, 260), CFrame.new(center + Vector3.new(0, 70, 0)), Color3.fromRGB(80, 90, 100))
			d.cloud.Transparency = 1
			local rain = Instance.new("ParticleEmitter")
			rain.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			rain.Color = ColorSequence.new(Color3.fromRGB(180, 200, 230))
			rain.Size = NumberSequence.new(0.15)
			rain.Rate = 900
			rain.Lifetime = NumberRange.new(1.2, 1.6)
			rain.Speed = NumberRange.new(70, 90)
			rain.EmissionDirection = Enum.NormalId.Bottom
			rain.Transparency = NumberSequence.new(0.3)
			rain.Parent = d.cloud
			d.flash = Instance.new("PointLight")
			d.flash.Range = 60
			d.flash.Brightness = 0
			d.flash.Color = Color3.fromRGB(220, 230, 255)
			d.flash.Parent = d.cloud
			d.next = os.clock() + 3
			if heist and not heist.called and heist.alarmAt then
				heist.alarmAt += 15
				heist.siegeAt += 15
			end
		end,
		Step = function(_, ev)
			local d = ev.data
			if os.clock() >= d.next then
				d.next = os.clock() + rng:NextNumber(8, 15)
				d.flash.Brightness = 8
				playSound(d.cloud, B.Sounds.Thunder, 0.7, 6)
				task.delay(0.15, function()
					if d.flash.Parent then
						d.flash.Brightness = 0
					end
				end)
			end
		end,
		Stop = function(_, ev)
			stormOn = false
			if ev.data.cloud then
				ev.data.cloud:Destroy()
			end
		end,
	},
	{
		Id = "VIP",
		Name = "Visita da Gerência Regional",
		Icon = "🕴️",
		Text = "O diretor regional está no salão com um GUARDA-COSTAS e uma maleta executiva. Renda os dois!",
		Phases = { inicio = true },
		Requires = function()
			return f("PontoVIP") ~= nil
		end,
		Start = function(_, ev)
			local d = ev.data
			d.vip = addNpc(f("PontoVIP").CFrame * CFrame.new(0, -2.5, 0), { role = "vip", name = "Dr. Augusto", outfit = "diretor" })
			d.guard = addNpc(f("PontoGuardaCosta").CFrame * CFrame.new(0, -2.5, 0), { role = "guardacosta", name = "Guarda-costas", outfit = "guardacostas" })
			if not d.vip then
				error("sem NPC")
			end
			NPCKit.hold(d.vip.npc, "Maleta", Vector3.new(1.6, 1.2, 0.4), Color3.fromRGB(60, 40, 24), Enum.Material.Leather)
			d.deadline = os.clock() + B.GuardReact + 4
			local root = npcRoot(d.vip)
			d.prompt = makePrompt(root, "BancoPrompt", "Pegar a maleta executiva", "Diretor rendido", 1, 7, function(player)
				if d.taken or not heistAction(player, root, 8) then
					return
				end
				local L = B.Loot.maleta
				if addToBag(player, L.Name, rng:NextInteger(L.Value[1], L.Value[2]), L.Slots, root.Position) then
					d.taken = true
					local m = d.vip.npc:FindFirstChild("Maleta")
					if m then
						m:Destroy()
					end
				end
			end, function()
				return not d.taken and d.vip.surrendered == true
			end)
		end,
		Step = function(_, ev)
			local d = ev.data
			if d.guard and not d.guard.surrendered and not d.called and os.clock() > d.deadline then
				d.called = true
				if d.guard.npc and d.guard.npc.Parent then
					NPCKit.say(d.guard.npc, "Central! Reforço no Banco Central!", 4)
				end
				if heist then
					heist.siegeAt -= 60
					for _, p in ipairs(crewList()) do
						CrimeService.addWanted(p, 8)
					end
				end
				crewNotice("📻 O guarda-costas chamou REFORÇO: o cerco chega 1 min mais cedo!", "red")
			end
			return d.taken and (d.called or (d.guard == nil) or d.guard.surrendered)
		end,
		Hint = function(_, ev)
			local d = ev.data
			if d.taken then
				return "Maleta na bolsa!"
			end
			if d.guard and not d.guard.surrendered and not d.called then
				return ("Mire no guarda-costas (%ds)"):format(math.max(0, math.ceil(d.deadline - os.clock())))
			end
			return d.vip and d.vip.surrendered and "Pegue a maleta do diretor" or "Mire no diretor"
		end,
		Stop = function(_, ev)
			local d = ev.data
			task.delay(5, function()
				dropNpc(d.vip)
				dropNpc(d.guard)
			end)
		end,
	},
	{
		Id = "Corajoso",
		Name = "Cliente corajoso",
		Icon = "🏃",
		Text = "Um cliente que estava no banheiro corre para a porta para chamar a polícia!",
		Phases = { inicio = true, interno = true },
		Duration = 45,
		Requires = function()
			return heist ~= nil and not heist.sieged
		end,
		Start = function(_, ev)
			ev.data.wait = os.clock() + rng:NextNumber(8, 16)
		end,
		Step = function(_, ev)
			local d = ev.data
			local now = os.clock()
			if not d.info then
				if now < d.wait then
					return
				end
				local spot = f("PontoCliente2")
				d.info = spot and addNpc(spot.CFrame * CFrame.new(0, -2.5, 4), { role = "corajoso", name = "Cliente", walk = true, showName = true })
				if not d.info then
					return true
				end
				NPCKit.say(d.info.npc, "Vou chamar a polícia!", 3)
				walkNpc(d.info, parts.saida.Position, function()
					return d.info.surrendered
				end)
				crewNotice("🏃 Um CLIENTE CORAJOSO está correndo para a porta! Mire nele!", "red")
				d.deadline = now + 16
				return
			end
			if d.info.surrendered then
				return now > d.deadline
			end
			local root = npcRoot(d.info)
			if not root or now > d.deadline or (root.Position - parts.saida.Position).Magnitude < 8 then
				d.escaped = true
				return true
			end
		end,
		Hint = function(_, ev)
			return ev.data.info and (ev.data.info.surrendered and "Rendido" or "Mire nele antes da porta!") or "Alguém está escondido..."
		end,
		Stop = function(_, ev)
			local d = ev.data
			if d.escaped and heist then
				heist.siegeAt -= 60
				for _, p in ipairs(crewList()) do
					CrimeService.addWanted(p, 6)
				end
				crewNotice("🏃 O cliente fugiu e contou tudo: o cerco chega 1 min mais cedo!", "red")
			end
			dropNpc(d.info)
		end,
	},
	{
		Id = "Retro",
		Name = "Terminal Nostálgico",
		Icon = "💾",
		Text = "Um computador velho da diretoria ligou sozinho. Quem decifrar abre o COFRE DO DIRETOR.",
		Phases = { interno = true },
		Requires = function()
			return parts.retro ~= nil and parts.cofreDiretor ~= nil
		end,
		Start = function(_, ev)
			local d = ev.data
			setText(parts.retro, "C:\\> COFRE.EXE\nSENHA: ____", Color3.fromRGB(80, 255, 120))
			d.prompt = makePrompt(parts.retro, "BancoPrompt", "Usar o terminal antigo", "C:\\>", 0.5, 7, function(player)
				if d.solved or not heistAction(player, parts.retro, 8) then
					return
				end
				minigame(player, MG.retro, parts.retro, "C:\\> COFRE.EXE • decifre a senha", function()
					d.solved = true
					setText(parts.retro, "C:\\> ACESSO OK\nCOFRE DIRETOR: ABERTO", Color3.fromRGB(80, 255, 120))
					crewNotice("💾 Senha decifrada! O COFRE DO DIRETOR (diretoria, canto) destravou.")
					refreshPrompts()
				end)
			end, function()
				return not d.solved
			end)
			d.safe = makePrompt(parts.cofreDiretor, "BancoPrompt", "Abrir o cofre do diretor", "Cofre do Diretor", 3, 7, function(player)
				if not d.solved or loot.diretorTaken or not heistAction(player, parts.cofreDiretor, 8) then
					return
				end
				local L = B.Loot.diretor
				if addToBag(player, L.Name, rng:NextInteger(L.Value[1], L.Value[2]), L.Slots, parts.cofreDiretor.Position) then
					loot.diretorTaken = true
					parts.cofreDiretor.Color = Color3.fromRGB(20, 20, 22)
				end
			end, function()
				return d.solved and not loot.diretorTaken
			end)
		end,
		Step = function()
			return loot.diretorTaken
		end,
		Hint = function(_, ev)
			return ev.data.solved and "Cofre do diretor destravado!" or "Diretoria (oeste): decifre o terminal"
		end,
	},
	{
		Id = "Furadeira",
		Name = "Broca travada",
		Icon = "🔥",
		Text = "A broca da perfuratriz vai travar no meio do caminho!",
		Phases = { furando = true },
		Start = function(_, ev)
			ev.data.at = rng:NextNumber(0.3, 0.7)
			ev.data.prompt = makePrompt(parts.pontoFuradeira, "BancoPrompt", "Destravar a broca", "Perfuratriz travada", 0.5, 9, function(player)
				if not heist or not heist.drillJam or not heistAction(player, parts.pontoFuradeira, 10) then
					return
				end
				minigame(player, MG.furadeira, parts.pontoFuradeira, "Destravar a broca da perfuratriz", function()
					if heist then
						heist.drillJam = false
						crewNotice("🔧 Broca destravada! Pode voltar a furar.")
						ev.finished = true
					end
				end)
			end, function()
				return heist ~= nil and heist.drillJam == true
			end)
		end,
		Step = function(_, ev)
			local h = heist
			if not h or h.drill ~= "furando" then
				return h == nil or h.drill == "pronta"
			end
			if not h.drillJam and not ev.data.jammed and h.drillProgress >= ev.data.at then
				ev.data.jammed = true
				h.drillJam = true
				crewNotice("🔥 A FURADEIRA TRAVOU (superaquecida)! Alguém destrava ela (minigame).", "red")
				sendStatus()
			end
		end,
		Hint = function()
			return heist and heist.drillJam and "Destrave a broca!" or "Fique de olho na broca"
		end,
		Stop = function()
			if heist then
				heist.drillJam = false
			end
		end,
	},
	{
		Id = "Isca",
		Name = "Cofre-Isca",
		Icon = "🎯",
		Text = "Duas pilhas de dinheiro são ISCA (tinta + rastreador). Examinem antes de pegar!",
		Phases = { cofre = true },
		Requires = function()
			return #loot.pilhas >= 2
		end,
		Start = function(_, ev)
			local idx = {}
			for i = 1, #loot.pilhas do
				idx[i] = i
			end
			for i = #idx, 2, -1 do
				local j = rng:NextInteger(1, i)
				idx[i], idx[j] = idx[j], idx[i]
			end
			for k = 1, 2 do
				loot.pilhas[idx[k]].marked = true
			end
			ev.data.prompts = {}
			for _, s in ipairs(loot.pilhas) do
				local btn = s.model:FindFirstChild("Botao")
				if btn then
					local p = makePrompt(btn, "BancoPrompt", "Examinar as cédulas", "Pode ser isca", 2, 7, function(player)
						if s.examined or not heistAction(player, btn, 8) then
							return
						end
						s.examined = true
						if s.marked then
							local hl = Instance.new("Highlight")
							hl.Name = "Marcado"
							hl.FillColor = Color3.fromRGB(40, 90, 255)
							hl.OutlineColor = Color3.fromRGB(120, 170, 255)
							hl.FillTransparency = 0.5
							hl.Parent = s.model
							crewNotice("🎯 Essa pilha é ISCA (pacote de tinta + rastreador)! Não peguem.", "red")
						else
							send(player, "BancoAviso", { text = "✅ Cédulas limpas: pode levar." })
						end
					end, function()
						return not s.examined and s.left > 0 and heist ~= nil and heist.vault == "aberto"
					end)
					p.UIOffset = Vector2.new(0, 60)
					table.insert(ev.data.prompts, p)
				end
			end
		end,
		Hint = function()
			return "2 pilhas têm tinta: examine antes (segure E)"
		end,
	},
	{
		Id = "Teimosa",
		Name = "Porta que não para de fechar",
		Icon = "🚪",
		Text = "O mecanismo da porta do cofre enlouqueceu e ela está FECHANDO! Segurem a porta ou calcem ela.",
		Phases = { coleta = true },
		Duration = 45,
		Requires = function()
			return heist ~= nil and heist.vault == "aberto" and doorAngle > 0.95
		end,
		Start = function(_, ev)
			local d = ev.data
			local pf = parts.pontoFuradeira
			d.hold = makePrompt(pf, "BancoPrompt", "Segurar a porta", "Porta do cofre", 0.4, 10, function(player)
				if heistAction(player, pf, 11) then
					d.holder, d.holdUntil = player, os.clock() + 6
				end
			end, function()
				return not d.closed
			end)
			d.wedge = makePrompt(pf, "BancoPrompt", "Calçar a porta", "Sozinho: trava 30 s", 4, 10, function(player)
				if heistAction(player, pf, 11) then
					d.wedgeUntil = os.clock() + 30
					crewNotice("🧱 Porta CALÇADA por 30 s.")
				end
			end, function()
				return not d.closed
			end)
			d.wedge.UIOffset = Vector2.new(0, 60)
			doorToken += 1
		end,
		Step = function(_, ev, dt)
			local d = ev.data
			local h = heist
			if not h or d.closed then
				return true
			end
			local now = os.clock()
			local held = d.holder and now < (d.holdUntil or 0) and near(d.holder, parts.pontoFuradeira, 11)
			local wedged = d.wedgeUntil and now < d.wedgeUntil
			if held or wedged then
				setDoorAngle(math.min(1, doorAngle + dt * 0.25))
			else
				setDoorAngle(doorAngle - dt / 25)
				if doorAngle <= 0 then
					d.closed = true
					h.vault = "fechado"
					crewNotice("🚪 A PORTA DO COFRE FECHOU! Quem ficou dentro: alavanca de EMERGÊNCIA (vermelha). Fora: girar o volante.", "red")
					refreshPrompts()
					return true
				end
			end
		end,
		Hint = function(_, ev)
			local d = ev.data
			if d.closed then
				return "Fechou! Alavanca ou volante"
			end
			return ("Porta %d%% aberta: segure ou calce!"):format(math.floor(doorAngle * 100))
		end,
		Stop = function(_, ev, reason)
			local d = ev.data
			if not d.closed and heist and heist.vault == "aberto" then
				animateDoor(1, 2)
				if reason == "tempo" then
					crewNotice("🚪 O mecanismo esfriou: a porta ficou aberta.")
				end
			end
		end,
	},
	{
		Id = "Avalanche",
		Name = "Avalanche de malotes",
		Icon = "📦",
		Text = "A prateleira de malotes desabou em cima do ouro! Peguem os malotes do chão e levantem a prateleira.",
		Phases = { coleta = true },
		Requires = function()
			return parts.prateleira ~= nil and loot.ouro[1] ~= nil and loot.ouro[1].left > 0
		end,
		Start = function(_, ev)
			local d = ev.data
			local rack = parts.prateleira
			local frame = rack:FindFirstChild("Estrutura")
			d.homes = {}
			for _, p in ipairs(rack:GetDescendants()) do
				if p:IsA("BasePart") then
					d.homes[p] = p.CFrame
				end
			end
			local edge = frame.CFrame * CFrame.new(0, -frame.Size.Y / 2, -frame.Size.Z / 2)
			local fall = edge * CFrame.Angles(math.rad(-80), 0, 0) * edge:Inverse()
			for p, home in pairs(d.homes) do
				p.CFrame = fall * home
			end
			loot.ouro[1].blocked = true
			local L = B.Loot.malote
			for i = 1, 8 do
				local pos = (edge * CFrame.new(rng:NextNumber(-7, 7), 0.5, -rng:NextNumber(4, 11))).Position
				makeDrop(pos, rng:NextInteger(L.Value[1], L.Value[2]), L.Slots, L.Name, 50)
			end
			playSound(frame, B.Sounds.Bell, 0.6, 4)
			-- levantar: 2 pessoas juntas (uma em cada ponta) ou 1 arrastando devagar
			d.ends = {}
			for k, x in ipairs({ -6, 6 }) do
				local m = newPart("PontaPrateleira", Vector3.new(1, 1, 1), edge * CFrame.new(x, 1, -4.5), Color3.new(1, 1, 1))
				m.Transparency = 1
				d.ends[k] = m
				makePrompt(m, "BancoPrompt", "Levantar (ponta " .. k .. ")", "Os 2 juntos", 1.5, 7, function(player)
					if d.cleared or not heistAction(player, m, 8) then
						return
					end
					d["lift" .. k] = os.clock()
					local other = d["lift" .. (3 - k)]
					if other and os.clock() - other <= B.DualWindow then
						d.cleared = true
					else
						send(player, "BancoAviso", { text = "💪 Segurando! A outra ponta tem que levantar junto." })
					end
				end, function()
					return not d.cleared
				end)
			end
			makePrompt(d.ends[1], "BancoPrompt", "Arrastar sozinho", "Devagar", 8, 7, function(player)
				if not d.cleared and heistAction(player, d.ends[1], 8) then
					d.cleared = true
				end
			end, function()
				return not d.cleared
			end).UIOffset = Vector2.new(0, 60)
		end,
		Step = function(_, ev)
			if ev.data.cleared then
				crewNotice("💪 Prateleira levantada: o ouro está livre!")
				return true
			end
		end,
		Hint = function(_, ev)
			return ev.data.cleared and "Liberado" or "Levantem a prateleira (2 juntos) • malotes no chão"
		end,
		Stop = function(_, ev)
			local d = ev.data
			for p, home in pairs(d.homes or {}) do
				if p.Parent then
					p.CFrame = home
				end
			end
			for _, m in ipairs(d.ends or {}) do
				m:Destroy()
			end
			if loot.ouro[1] then
				loot.ouro[1].blocked = false
			end
			refreshPrompts()
		end,
	},
	{
		Id = "Rompe",
		Name = "Malote se rompe",
		Icon = "🧵",
		Text = "Uma bolsa rasgou e o dinheiro está caindo! Recolham e remendem.",
		Phases = { pesada = true, fuga = true }, -- "pesada" = a 1ª vez que uma bolsa passa de 6 espaços
		Duration = 30,
		Requires = function()
			for _, p in ipairs(crewList()) do
				if bags[p] and bags[p].slots >= 4 then
					return true
				end
			end
			return false
		end,
		Start = function(_, ev)
			local d = ev.data
			for _, p in ipairs(crewList()) do
				if bags[p] and bags[p].slots >= 4 and (not d.victim or bags[p].slots > bags[d.victim].slots) then
					d.victim = p
				end
			end
			local function leak(n)
				local b = bags[d.victim]
				local root = rootOf(d.victim)
				if not b or not root or b.slots <= 1 then
					return
				end
				for _ = 1, n do
					if b.slots <= 1 then
						break
					end
					local value = math.floor(b.value / b.slots)
					b.value -= value
					b.slots -= 1
					makeDrop(root.Position + Vector3.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3)), value, 1, "Maços espalhados", 60)
				end
				setBag(d.victim, b)
			end
			d.leak = leak
			leak(2)
			d.next = os.clock() + 7
			local root = rootOf(d.victim)
			d.prompt = root and makePrompt(root, "BancoPrompt", "Remendar a bolsa", d.victim.DisplayName, 2.5, 7, function(player)
				if heist and heist.crew[player] and near(player, root, 8) then
					d.fixed = true
					crewNotice(("🧵 %s remendou a bolsa de %s."):format(player.DisplayName, d.victim.DisplayName))
				end
			end, function()
				return not d.fixed
			end)
			send(d.victim, "BancoAviso", { text = "🧵 SUA BOLSA RASGOU! Notas caindo: alguém remenda (ou você mesmo, parado) e recolham o que caiu.", color = "red" })
			crewNotice(("🧵 A bolsa de %s rasgou! Remendem e recolham os maços do chão."):format(d.victim.DisplayName), "red")
		end,
		Step = function(_, ev)
			local d = ev.data
			if d.fixed or not d.victim.Parent then
				return true
			end
			if os.clock() >= d.next then
				d.next = os.clock() + 7
				d.leak(1)
			end
		end,
		Hint = function(_, ev)
			return ev.data.fixed and "Remendada" or ("Remendem a bolsa de " .. tostring(ev.data.victim and ev.data.victim.DisplayName or "?"))
		end,
		Stop = function(_, ev)
			if ev.data.prompt then
				ev.data.prompt:Destroy()
			end
		end,
	},
	{
		Id = "AoVivo",
		Name = "Transmissão ao vivo",
		Icon = "📺",
		Text = "Um helicóptero da TV está filmando! Ao ar livre perto do banco o procurado sobe rápido: fiquem embaixo de teto.",
		Phases = { coleta = true, fuga = true },
		Duration = 90,
		Requires = function()
			return heist ~= nil and heist.called
		end,
		Start = function(_, ev)
			local d = ev.data
			local center = bank:GetPivot().Position
			d.center = center
			local m = Instance.new("Model")
			m.Name = "HelicopteroTV"
			local body = newPart("Corpo", Vector3.new(5, 4, 10), CFrame.new(center + Vector3.new(60, 80, 0)), Color3.fromRGB(230, 230, 236), Enum.Material.SmoothPlastic, m)
			newPart("Cauda", Vector3.new(1, 1.2, 9), body.CFrame * CFrame.new(0, 0.6, 9), Color3.fromRGB(230, 230, 236), nil, m)
			newPart("Rotor", Vector3.new(16, 0.2, 0.8), body.CFrame * CFrame.new(0, 2.3, 0), Color3.fromRGB(30, 30, 34), nil, m)
			local tv = newPart("Logo", Vector3.new(0.1, 1.6, 4), body.CFrame * CFrame.new(2.55, 0, 0), Color3.fromRGB(200, 30, 40), Enum.Material.Neon, m)
			tv.Transparency = 0
			local spot = Instance.new("SpotLight")
			spot.Face = Enum.NormalId.Bottom
			spot.Range = 120
			spot.Angle = 25
			spot.Brightness = 6
			spot.Parent = body
			m.PrimaryPart = body
			m.Parent = bank
			d.heli = m
			playSound(body, B.Sounds.Helicopter, 0.5, 90)
			d.t = 0
			d.conn = RunService.Heartbeat:Connect(function(step)
				d.t += step * 0.22
				local pos = center + Vector3.new(math.cos(d.t) * 70, 80, math.sin(d.t) * 70)
				local ahead = center + Vector3.new(math.cos(d.t + 0.1) * 70, 80, math.sin(d.t + 0.1) * 70)
				if m.Parent then
					m:PivotTo(CFrame.lookAt(pos, ahead) * CFrame.Angles(math.rad(-8), 0, 0))
				end
			end)
			d.next = os.clock() + 3
			for _, p in ipairs(Players:GetPlayers()) do
				send(p, "BancoAviso", { text = "📺 AO VIVO: assalto ao " .. B.Name .. "! Helicóptero da TV no local." })
			end
		end,
		Step = function(_, ev)
			local d = ev.data
			if os.clock() < d.next then
				return
			end
			d.next = os.clock() + 3
			for _, p in ipairs(crewList()) do
				local root = rootOf(p)
				if root and (root.Position - d.center).Magnitude < 300 and not isCovered(root) then
					CrimeService.addWanted(p, 1)
					if not d.warned then
						d.warned = true
						send(p, "BancoAviso", { text = "📺 A câmera da TV pegou você! Procure um teto (embaixo de algo)." })
					end
				end
			end
		end,
		Hint = function()
			return "Ao ar livre o procurado sobe: fique embaixo de teto"
		end,
		Stop = function(_, ev)
			local d = ev.data
			if d.conn then
				d.conn:Disconnect()
			end
			if d.heli then
				d.heli:Destroy()
			end
		end,
	},
	{
		Id = "Rival",
		Name = "Equipe rival oportunista",
		Icon = "🦊",
		Text = "Dois da gangue rival querem roubar os malotes de vocês na saída! Mirem neles para espantar.",
		Phases = { fuga = true },
		Duration = 60,
		Requires = function()
			return f("PontoRival") ~= nil
		end,
		Start = function(_, ev)
			local d = ev.data
			d.rivals = {}
			-- chegam correndo de um beco perto de quem saiu com malote (ou dos fundos do banco)
			local base = f("PontoRival").CFrame
			for _, p in ipairs(crewList()) do
				local r = bags[p] and rootOf(p)
				if r and not inBuilding(r.Position) then
					local side = r.CFrame.RightVector * (rng:NextNumber() < 0.5 and -1 or 1)
					local at = r.Position + side * 40 + r.CFrame.LookVector * 10
					base = CFrame.lookAt(at, r.Position)
					break
				end
			end
			for i = 1, 2 do
				local info = addNpc(base * CFrame.new(i * 4 - 6, -2.5, 0), { role = "rival", name = "Rival", walk = true, showName = true, shirt = Color3.fromRGB(150, 110, 20), pants = Color3.fromRGB(30, 30, 30) })
				if info then
					local humanoid = info.npc:FindFirstChildOfClass("Humanoid")
					if humanoid then
						humanoid.WalkSpeed = 15
					end
					info.token = 0
					table.insert(d.rivals, info)
				end
			end
			if #d.rivals == 0 then
				error("sem NPC")
			end
			d.next = 0
		end,
		Step = function(_, ev)
			local d = ev.data
			local now = os.clock()
			local alive = 0
			for _, info in ipairs(d.rivals) do
				local root = npcRoot(info)
				if root and not info.gone then
					if info.surrendered then
						info.gone = true
						task.delay(2.5, function()
							dropNpc(info)
						end)
					else
						alive += 1
						local best, bestD
						for _, p in ipairs(crewList()) do
							local r = bags[p] and rootOf(p)
							if r then
								local dd = (r.Position - root.Position).Magnitude
								if dd < 220 and (not bestD or dd < bestD) then
									best, bestD = p, dd
								end
							end
						end
						if best and bestD < 5.5 then
							local b = bags[best]
							local stolen = math.floor(b.value * 0.3)
							local slots = math.min(b.slots - 1, math.max(1, math.floor(b.slots * 0.3)))
							if slots >= 1 and stolen > 0 then
								b.value -= stolen
								b.slots -= slots
								setBag(best, b)
								send(best, "BancoAviso", { text = ("🦊 O rival puxou parte do seu malote: -%s!"):format(money(stolen)), color = "red" })
							end
							NPCKit.say(info.npc, "Valeu pelo presente!", 3)
							-- um puxão só por evento: o outro também foge
							for _, other in ipairs(d.rivals) do
								if other ~= info and not other.gone then
									other.gone = true
									task.delay(2, function()
										dropNpc(other)
									end)
								end
							end
							info.gone = true
							task.delay(2, function()
								dropNpc(info)
							end)
						elseif best and now >= (info.retarget or 0) then
							info.retarget = now + 1.5
							info.token += 1
							local my = info.token
							local target = rootOf(best)
							if target then
								walkNpc(info, target.Position, function()
									return info.token ~= my or info.surrendered or info.gone
								end)
							end
						end
					end
				end
			end
			return alive == 0
		end,
		Hint = function()
			return "Mire nos rivais antes que encostem!"
		end,
		Stop = function(_, ev)
			for _, info in ipairs(ev.data.rivals or {}) do
				dropNpc(info)
			end
		end,
	},
	-- Marco 10.21 -----------------------------------------------------------------
	{
		Id = "Negociador",
		Name = "Telefone do negociador",
		Icon = "📞",
		Text = "O Major Tavares, negociador da PM, está ligando para a gerência. Atenda e enrole ele para ganhar tempo.",
		Phases = { alarme = true },
		Requires = function()
			return heist ~= nil and not heist.sieged and parts.anuncio ~= nil
		end,
		Start = function(_, ev)
			local cfg = E.Negociador or {}
			local d = ev.data
			d.deadline = os.clock() + (cfg.Ring or 25)
			d.phone = newPart("TelefoneNegociador", Vector3.new(1.4, 0.6, 1), lotAt(53, 3.3, -32.2), Color3.fromRGB(170, 20, 30), Enum.Material.SmoothPlastic)
			d.light = Instance.new("PointLight")
			d.light.Color = Color3.fromRGB(255, 60, 60)
			d.light.Range = 10
			d.light.Parent = d.phone
			d.prompt = makePrompt(d.phone, "BancoPrompt", "Atender o negociador", "📞 Tocando!", 0.5, 8, function(player)
				if d.answered or not heistAction(player, d.phone, 9) then
					return
				end
				d.answered = true
				d.light.Enabled = false
				send(player, "BancoAviso", { text = "📞 \"Aqui é o Major Tavares. Vamos conversar...\" Enrole ele (minigame)!" })
				minigame(player, MG.negociador or MG.retro, d.phone, "Enrolar o negociador", function()
					if heist then
						heist.siegeAt += cfg.Bonus or 60
						crewNotice(("📞 %s enrolou o Major Tavares: o cerco atrasou %d s!"):format(player.DisplayName, cfg.Bonus or 60))
					end
					ev.finished = true
				end, function()
					if heist then
						heist.siegeAt -= cfg.Penalty or 20
						crewNotice(("📞 O negociador percebeu a enrolação: o cerco vem %d s mais cedo!"):format(cfg.Penalty or 20), "red")
					end
					ev.finished = true
				end)
			end, function()
				return heist ~= nil and not d.answered
			end)
			crewNotice("📞 O TELEFONE DA GERÊNCIA está tocando: é o NEGOCIADOR da PM! Atenda e enrole ele para atrasar o cerco.")
		end,
		Step = function(_, ev)
			local d = ev.data
			if not d.answered then
				d.blink = not d.blink
				d.phone.Color = d.blink and Color3.fromRGB(255, 60, 60) or Color3.fromRGB(150, 20, 30)
				if os.clock() > d.deadline then
					d.missed = true
					return true
				end
			end
		end,
		Hint = function(_, ev)
			return ev.data.answered and "Na linha com o Major Tavares" or "Atenda o telefone da gerência (leste)"
		end,
		Stop = function(_, ev)
			local d = ev.data
			if d.missed and heist and not heist.sieged then
				local p = (E.Negociador and E.Negociador.Ignore) or 30
				heist.siegeAt -= p
				crewNotice(("📞 Ninguém atendeu o negociador: a PM acha que tem refém em perigo. Cerco %d s mais cedo!"):format(p), "red")
			end
			if d.phone then
				d.phone:Destroy()
			end
		end,
	},
	{
		Id = "CarroForte",
		Name = "Carro-forte na doca",
		Icon = "🚚",
		Text = "Um carro-forte parou na DOCA (fundos do banco) para descarregar malotes. Renda os 2 vigilantes!",
		Phases = { interno = true },
		Requires = function()
			return parts.anuncio ~= nil
		end,
		Start = function(_, ev)
			local cfg = E.CarroForte or {}
			local d = ev.data
			ev.endsAt = os.clock() + (cfg.Stay or 90)
			d.parts = {}
			local function piece(name, size, x, y, z, color, material, shape)
				local p = newPart(name, size, lotAt(x, y, z), color, material)
				p.CanCollide = true
				if shape then
					p.Shape = shape
				end
				table.insert(d.parts, p)
				return p
			end
			local GREEN, DARK = Color3.fromRGB(60, 90, 66), Color3.fromRGB(30, 32, 36)
			piece("BauCarroForte", Vector3.new(14, 7, 7.4), 12, -4 + 4.4, 113, GREEN, Enum.Material.Metal)
			piece("CabineCarroForte", Vector3.new(5, 5.6, 7.4), 21.6, -4 + 3.7, 113, GREEN, Enum.Material.Metal)
			piece("ParabrisaCarroForte", Vector3.new(0.2, 2.4, 6.6), 24.15, -4 + 5, 113, Color3.fromRGB(40, 50, 60), Enum.Material.SmoothPlastic)
			for _, w in ipairs({ { 7, 109.6 }, { 7, 116.4 }, { 20, 109.6 }, { 20, 116.4 } }) do
				local wheel = piece("RodaCarroForte", Vector3.new(1.2, 3, 3), w[1], -4 + 1.5, w[2], DARK, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
				wheel.CFrame = wheel.CFrame * CFrame.Angles(0, math.rad(90), 0)
			end
			local logo = piece("LogoCarroForte", Vector3.new(8, 2, 0.1), 12, -4 + 5, 109.25, Color3.fromRGB(240, 240, 240), Enum.Material.SmoothPlastic)
			logo.CanCollide = false
			d.door = piece("PortaCarroForte", Vector3.new(0.4, 6, 6.6), 4.8, -4 + 4.4, 113, Color3.fromRGB(80, 110, 86), Enum.Material.DiamondPlate)
			for i = 1, 3 do
				piece("MaloteCarroForte", Vector3.new(1.6, 1.4, 1.2), 3.2, -4 + 0.7, 110.5 + i * 1.6, Color3.fromRGB(70, 60, 50), Enum.Material.Fabric)
			end
			d.guards = {}
			for i, p in ipairs({ { 2, 109 }, { 2, 118 } }) do
				local info = addNpc(lotAt(p[1], -4 - 2.5 + 3, p[2]) * CFrame.Angles(0, math.rad(90), 0), { role = "carroforte", name = i == 1 and "Vigilante Ramos" or "Vigilante Dias", outfit = "carroforte" })
				if info then
					NPCKit.hold(info.npc, "Escopeta", Vector3.new(0.3, 0.5, 2.6), Color3.fromRGB(30, 30, 34), Enum.Material.Metal)
					table.insert(d.guards, info)
				end
			end
			d.radioAt = os.clock() + (cfg.Radio or 25)
			d.prompt = makePrompt(d.door, "BancoPrompt", "Pegar os malotes do carro-forte", "Vigilantes rendidos", 2, 9, function(player)
				if d.taken or not heistAction(player, d.door, 10) then
					return
				end
				for _, g in ipairs(d.guards) do
					if not g.surrendered then
						return send(player, "BancoAviso", { text = "🔫 Renda os 2 vigilantes do carro-forte antes!" })
					end
				end
				local v = cfg.Value or { 9000, 13000 }
				if addToBag(player, "Malotes do carro-forte", rng:NextInteger(v[1], v[2]), cfg.Slots or 2, d.door.Position) then
					d.taken = true
					for _, p in ipairs(d.parts) do
						if p.Name == "MaloteCarroForte" then
							p.Transparency = 1
						end
					end
					ev.finished = true
				end
			end, function()
				return heist ~= nil and not d.taken
			end)
			crewNotice("🚚 Um CARRO-FORTE parou na DOCA (fundos do banco)! Renda os 2 vigilantes e pegue os malotes antes que ele vá embora.")
		end,
		Step = function(_, ev)
			local d = ev.data
			if not d.radioed and os.clock() > d.radioAt then
				for _, g in ipairs(d.guards) do
					if not g.surrendered and g.npc and g.npc.Parent then
						d.radioed = true
						NPCKit.say(g.npc, "Central, central! Movimento estranho no banco!", 4)
						if heist then
							heist.siegeAt -= (E.CarroForte and E.CarroForte.RadioPenalty) or 30
							crewNotice("📻 O vigilante do carro-forte chamou a central: o cerco vem 30 s mais cedo!", "red")
						end
						break
					end
				end
			end
		end,
		Hint = function(_, ev)
			return ev.data.taken and "Malotes pegos!" or "Doca (fundos): renda os vigilantes"
		end,
		Stop = function(_, ev, reason)
			local d = ev.data
			if reason == "tempo" and not d.taken then
				crewNotice("🚚 O carro-forte foi embora.", "red")
			end
			for _, info in ipairs(d.guards or {}) do
				dropNpc(info)
			end
			for _, p in ipairs(d.parts or {}) do
				p:Destroy()
			end
		end,
	},
	{
		Id = "AlarmeSilencioso",
		Name = "Alarme silencioso",
		Icon = "🤫",
		Text = "Uma caixa está com o pé no ALARME SILENCIOSO embaixo do balcão!",
		Phases = { inicio = true },
		Requires = function()
			return npcBy("caixa") ~= nil
		end,
		Start = function(_, ev)
			local cfg = E.AlarmeSilencioso or {}
			local d = ev.data
			d.info = npcBy("caixa")
			d.deadline = os.clock() + (cfg.Time or 15)
			local root = npcRoot(d.info)
			d.led = newPart("BotaoSilencioso", Vector3.new(0.5, 0.3, 0.5), root.CFrame * CFrame.new(0, -2.2, -1), Color3.fromRGB(255, 40, 40), Enum.Material.Neon)
			d.prompt = makePrompt(root, "BancoPrompt", "Afastar do botão", "Alarme silencioso!", 1, 8, function(player)
				if d.stopped or not heistAction(player, root, 9) then
					return
				end
				d.stopped = true
				NPCKit.say(d.info.npc, "Desculpa! Desculpa! Não apertei, juro!", 3)
				crewNotice(("🤫 %s pegou a caixa no flagra: o alarme silencioso NÃO foi."):format(player.DisplayName))
				ev.finished = true
			end, function()
				return heist ~= nil and not d.stopped
			end)
			crewNotice(("🤫 A %s está com o pé no ALARME SILENCIOSO! Afaste ela do botão em %d s (segure E nela)."):format(d.info.npc.Name, cfg.Time or 15), "red")
		end,
		Step = function(_, ev)
			local d = ev.data
			d.blink = not d.blink
			if d.led then
				d.led.Transparency = d.blink and 0 or 0.7
			end
			if not d.stopped and os.clock() > d.deadline then
				d.pressed = true
				return true
			end
		end,
		Hint = function(_, ev)
			return ev.data.stopped and "Pego no flagra!" or "Segure E na caixa: afaste do botão!"
		end,
		Stop = function(_, ev)
			local d = ev.data
			if d.pressed and heist then
				local p = (E.AlarmeSilencioso and E.AlarmeSilencioso.Penalty) or 45
				heist.siegeAt -= p
				heist.alarmAt = math.min(heist.alarmAt or os.clock(), os.clock())
				crewNotice(("🤫 O ALARME SILENCIOSO foi! A PM já sabe: cerco %d s mais cedo."):format(p), "red")
			end
			if d.led then
				d.led:Destroy()
			end
		end,
	},
	{
		Id = "Sprinkler",
		Name = "Sprinklers",
		Icon = "💦",
		Text = "O calor da perfuratriz vai disparar os SPRINKLERS da antecâmara!",
		Phases = { furando = true },
		Start = function(_, ev)
			ev.data.at = rng:NextNumber(0.25, 0.5)
		end,
		Step = function(_, ev)
			local h = heist
			local d = ev.data
			if not h or h.drill ~= "furando" then
				return h == nil or h.drill == "pronta"
			end
			if not d.on and not d.done and h.drillProgress >= d.at then
				d.on = true
				sprinklerOn = true
				d.rain = newPart("Sprinklers", Vector3.new(36, 0.4, 18), lotAt(0, -6.5, 32), Color3.fromRGB(200, 220, 240), Enum.Material.SmoothPlastic)
				d.rain.Transparency = 1
				local w = Instance.new("ParticleEmitter")
				w.Texture = "rbxasset://textures/particles/sparkles_main.dds"
				w.Color = ColorSequence.new(Color3.fromRGB(170, 210, 255))
				w.Size = NumberSequence.new(0.2)
				w.Rate = 500
				w.Lifetime = NumberRange.new(0.6, 0.9)
				w.Speed = NumberRange.new(20, 26)
				w.EmissionDirection = Enum.NormalId.Bottom
				w.Parent = d.rain
				d.valve = newPart("RegistroSprinkler", Vector3.new(0.4, 1.6, 1.6), lotAt(19.6, -17.5, 39) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(200, 30, 30), Enum.Material.Metal)
				d.valve.Shape = Enum.PartType.Cylinder
				d.valve.CFrame = lotAt(19.6, -17.5, 39)
				d.prompt = makePrompt(d.valve, "BancoPrompt", "Fechar o registro", "Sprinklers", 3, 8, function(player)
					if not d.on or not heistAction(player, d.valve, 9) then
						return
					end
					d.on = false
					d.done = true
					sprinklerOn = false
					if d.rain then
						d.rain:Destroy()
						d.rain = nil
					end
					crewNotice(("💧 %s fechou o registro: a perfuratriz voltou à velocidade normal."):format(player.DisplayName))
					ev.finished = true
				end, function()
					return heist ~= nil and d.on == true
				end)
				crewNotice("💦 OS SPRINKLERS DISPARARAM! A perfuratriz está a METADE da velocidade. Fechem o REGISTRO vermelho (parede leste da antecâmara).", "red")
				sendStatus()
			end
		end,
		Hint = function(_, ev)
			return ev.data.on and "Feche o registro vermelho (antecâmara)" or "Cuidado com o calor da perfuratriz"
		end,
		Stop = function(_, ev)
			local d = ev.data
			sprinklerOn = false
			for _, k in ipairs({ "rain", "valve" }) do
				if d[k] then
					d[k]:Destroy()
				end
			end
		end,
	},
	{
		Id = "Gas",
		Name = "Gás lacrimogêneo",
		Icon = "💨",
		Text = "O Choque jogou GÁS LACRIMOGÊNEO no prédio! Peguem as máscaras no armário da sala de segurança.",
		Phases = { cerco = true },
		Requires = function()
			return f("Armario") ~= nil and f("AreaSalao") ~= nil
		end,
		Start = function(_, ev)
			local cfg = E.Gas or {}
			local d = ev.data
			ev.endsAt = os.clock() + (cfg.Duration or 70)
			d.nextHurt = os.clock() + 3
			local area = f("AreaSalao")
			d.cloud = newPart("GasLacrimogeneo", Vector3.new(area.Size.X - 4, 2, area.Size.Z - 4), area.CFrame * CFrame.new(0, -area.Size.Y / 2 + 4, 0), Color3.fromRGB(230, 230, 220), Enum.Material.SmoothPlastic)
			d.cloud.Transparency = 1
			local smoke = Instance.new("ParticleEmitter")
			smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
			smoke.Color = ColorSequence.new(Color3.fromRGB(235, 235, 220))
			smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.5), NumberSequenceKeypoint.new(1, 1) })
			smoke.Size = NumberSequence.new(8, 16)
			smoke.Lifetime = NumberRange.new(5, 7)
			smoke.Speed = NumberRange.new(1, 3)
			smoke.SpreadAngle = Vector2.new(180, 180)
			smoke.Rate = 80
			smoke.Parent = d.cloud
			d.masked = {}
			local locker = f("Armario")
			d.prompt = makePrompt(locker, "BancoPrompt", "Pegar máscara de gás", "Armário dos vigilantes", 0.8, 8, function(player)
				if d.masked[player] or not heistAction(player, locker, 9) then
					return
				end
				d.masked[player] = true
				player:SetAttribute("MascaraGas", true)
				local char = player.Character
				local head = char and char:FindFirstChild("Head")
				if head then
					local mask = Instance.new("Part")
					mask.Name = "MascaraGas"
					mask.Size = Vector3.new(1.3, 0.9, 0.5)
					mask.Color = Color3.fromRGB(40, 44, 40)
					mask.Material = Enum.Material.SmoothPlastic
					mask.CanCollide = false
					mask.CanQuery = false
					mask.Massless = true
					mask.CFrame = head.CFrame * CFrame.new(0, -0.25, -0.55)
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = head
					weld.Part1 = mask
					weld.Parent = mask
					mask.Parent = char
				end
				send(player, "BancoAviso", { text = "😷 Máscara de gás no rosto: o gás não te pega mais." })
			end, function()
				return heist ~= nil
			end)
			crewNotice("💨 GÁS LACRIMOGÊNEO! Quem estiver no prédio sem máscara perde vida. As MÁSCARAS estão no armário da SALA DE SEGURANÇA.", "red")
		end,
		Step = function(_, ev)
			local d = ev.data
			local now = os.clock()
			if now < d.nextHurt then
				return
			end
			d.nextHurt = now + 2
			for _, p in ipairs(crewList()) do
				local r = rootOf(p)
				if r and not d.masked[p] and inBuilding(r.Position) and not DownedService.isDowned(p) then
					local hum = r.Parent and r.Parent:FindFirstChildOfClass("Humanoid")
					if hum and hum.Health > 0 then
						hum:TakeDamage((E.Gas and E.Gas.Damage) or 4)
						if not d.warned then
							d.warned = true
							send(p, "BancoAviso", { text = "😵 O gás está te sufocando! Máscara no armário da sala de segurança!", color = "red" })
						end
					end
				end
			end
		end,
		Hint = function()
			return "Máscaras: armário da sala de segurança"
		end,
		Stop = function(_, ev)
			local d = ev.data
			if d.cloud then
				d.cloud:Destroy()
			end
			for p in pairs(d.masked or {}) do
				p:SetAttribute("MascaraGas", nil)
				local m = p.Character and p.Character:FindFirstChild("MascaraGas")
				if m then
					m:Destroy()
				end
			end
		end,
	},
}

---------------------------------------------------------------------------
-- Botões (ProximityPrompt). "BancoPrompt" só aparece para quem é de gangue (o cliente esconde);
-- "BancoPolicia" só para a PM. Cada um tem uma condição: o relógio liga/desliga (atributo Ativo).
---------------------------------------------------------------------------

-- Marco 10.26: a animação de cada botão (o cliente liga enquanto segura o E)
local PROMPT_POSE = {
	Amarrar = "amarrar", Hackear = "digitar", ["Cortar os"] = "digitar", ["Passar o"] = "digitar", ["Girar a chave"] = "digitar",
	Montar = "agachar", Plantar = "agachar", Destravar = "agachar", ["Girar o volante"] = "girar",
	Pegar = "pegar", Esvaziar = "pegar", Abrir = "pegar", Arrombar = "forca", Puxar = "forca",
}
makePrompt = function(part, name, action, object, hold, dist, fn, cond)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = action
	prompt.ObjectText = object or B.Short
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = hold or 0
	prompt.MaxActivationDistance = dist or 8
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	for key, pose in pairs(PROMPT_POSE) do
		if action:find(key, 1, true) then
			prompt:SetAttribute("Pose", pose)
		end
	end
	local function available()
		if not cond then return true end
		local ok, on = pcall(cond)
		return ok and on == true
	end
	local function allowed(player)
		if not prompt.Parent or not available() or not near(player, part, prompt.MaxActivationDistance + 1)
			or DownedService.isDowned(player) or player:GetAttribute("Preso") or CrimeService.isCuffed(player) then
			return false
		end
		if name == "BancoPolicia" then return CrimeService.isPolice(player) end
		return canCrime(player)
	end
	local on = available()
	prompt.Enabled = on
	prompt:SetAttribute("Ativo", on)
	prompt.Parent = part
	prompt:SetAttribute("BancoAcao", action)
	local holds = setmetatable({}, { __mode = "k" })
	prompt.PromptButtonHoldBegan:Connect(function(player)
		if allowed(player) then
			holds[player] = { at = os.clock(), state = state, heist = heist, character = player.Character }
		end
	end)
	prompt.PromptButtonHoldEnded:Connect(function(player)
		local entry = holds[player]
		if entry then entry.ended = os.clock() end
	end)
	prompt.Triggered:Connect(function(player)
		if not allowed(player) then
			if near(player, part, prompt.MaxActivationDistance + 1) and name ~= "BancoPolicia" then
				local ok, why = canCrime(player)
				if not ok and SecurityService.checkRate(player, "BancoAviso", 1) then CrimeService.notice(player, why) end
			end
			return
		end
		local entry = holds[player]
		holds[player] = nil
		if prompt.HoldDuration > 0 and (not entry or entry.state ~= state or entry.heist ~= heist
			or entry.character ~= player.Character or os.clock() - entry.at < prompt.HoldDuration - 0.15
			or (entry.ended and (entry.ended - entry.at < prompt.HoldDuration - 0.15 or os.clock() - entry.ended > 1))) then
			return
		end
		if SecurityService.checkRate(player, "BancoPrompt", 0.4) then
			local ok, err = pcall(fn, player)
			if not ok then
				warn("[BankService] " .. tostring(err))
			end
			-- Marco 10.25: a tela responde na hora, sem esperar o próximo segundo
			refreshPrompts()
			sendStatus({ player })
		end
	end)
	local scope = heist and part.Name ~= "MaloteNoChao" and name ~= "BancoReceptador" and heist or nil
	table.insert(prompts, { prompt = prompt, cond = cond, scope = scope })
	return prompt
end

refreshPrompts = function()
	for i = #prompts, 1, -1 do
		local e = prompts[i]
		if e.scope and e.scope ~= heist then
			e.prompt:Destroy()
			table.remove(prompts, i)
		elseif not e.prompt.Parent then
			table.remove(prompts, i)
		else
			local on = true
			if e.cond then
				local ok, r = pcall(e.cond)
				on = ok and r == true
			end
			if e.prompt:GetAttribute("Ativo") ~= on then
				e.prompt.Enabled = on
				e.prompt:SetAttribute("Ativo", on)
			end
		end
	end
	if bank then
		bank:SetAttribute("Estado", state)
	end
end

local function H()
	return state == "assalto" and heist or nil
end

-- Marco 10.25: amarrar o vigilante rendido
tiePrompt = function(info)
	local root = npcRoot(info)
	if info.tiePrompt or not root then
		return
	end
	info.tiePrompt = makePrompt(root, "BancoPrompt", "Amarrar", "Rendido: amarre antes que ele reaja", 0.7, 8, function(player)
		if info.tied or not info.surrendered or not heistAction(player, root, 9) then
			return
		end
		info.tied = true
		info.releaseAt = nil
		NPCKit.pose(info.npc, "amarrado")
		NPCKit.rope(info.npc)
		NPCKit.say(info.npc, "Tá apertado!", 2)
		crewNotice(("🪢 %s amarrou um vigilante."):format(player.DisplayName))
	end, function()
		return H() ~= nil and info.surrendered == true and not info.tied
	end)
	refreshPrompts()
end

local function setupPrompts()
	-- F1: preparação
	local trafo = f("PainelTransformador") or f("Transformador")
	if trafo then
		makePrompt(trafo, "BancoPrompt", "Cortar a energia", "Transformador", B.PowerTime, 8, function(player)
			local ok, why = canCrime(player)
			if not ok then
				return CrimeService.notice(player, why)
			end
			if state ~= "aberto" or not near(player, trafo, 9) then
				return
			end
			local g = player:GetAttribute("Gang")
			prep[g] = prep[g] or {}
			if prep[g].energia and prep[g].energia > os.clock() then
				return send(player, "BancoAviso", { text = "Sua gangue já cortou a energia. Anuncie o assalto antes que ela volte." })
			end
			prep[g].energia = os.clock() + B.PrepValid
			setMonitors(false)
			send(player, "BancoEvento", { id = "energia", icon = "⚡", name = "ENERGIA CORTADA", text = ("Câmeras mudas e telefone fora: se anunciarem em %d min, o alarme demora %d s para chegar na PM."):format(math.floor(B.PrepValid / 60), B.PowerAlarmDelay) })
			CrimeService.addWanted(player, 2)
		end, function()
			return state == "aberto"
		end)
	end
	-- crachá do funcionário que fuma (o prompt vai no NPC quando ele nasce)
	-- F2: anúncio
	parts.anuncio.Parent = bank
	namedPrompts.anuncio = makePrompt(parts.anuncio, "BancoPrompt", "Anunciar o assalto", "Arma na mão • equipe junta", 1, 18, startHeist, function()
		return state == "aberto"
	end)
	-- gavetas dos caixas
	for _, c in ipairs(loot.caixas) do
		makePrompt(c.part, "BancoPrompt", "Esvaziar a gaveta", "Caixa " .. tostring(c.part:GetAttribute("Index") or ""), 0.4, 6, function(player)
			local session = heist
			if c.taken or not heistAction(player, c.part, 7) then
				return
			end
			minigame(player, MG.gaveta, c.part, "Gaveta do caixa", function()
				if c.taken then
					return
				end
				local L = B.Loot.caixa
				local value = rng:NextInteger(L.Value[1], L.Value[2])
				local function take()
					if heist == session and not c.taken and heistAction(player, c.part, 7)
						and addToBag(player, L.Name, value, L.Slots, c.part.Position, { offer = take,
							valid = function() return heist == session and not c.taken end }) then
						c.taken = true
						c.part.Color = Color3.fromRGB(20, 20, 22)
						refreshPrompts()
					end
				end
				take()
			end)
		end, function()
			return H() ~= nil and not c.taken
		end)
	end
	-- F3: porta de segurança
	makePrompt(parts.leitor, "BancoPrompt", "Passar o crachá", "Leitor da porta de segurança", 0.6, 7, function(player)
		local h = H()
		if not h or h.secOpen or not heistAction(player, parts.leitor, 8) then
			return
		end
		if h.cardHolder ~= player then
			return send(player, "BancoAviso", { text = h.cardHolder and ("🪪 Quem está com o crachá é %s."):format(h.cardHolder.DisplayName) or "🪪 Sem crachá: renda a GERENTE (mire nela) e pegue o crachá, ou arrombe a porta." })
		end
		openSecDoor(player, "cracha")
	end, function()
		local h = H()
		return h ~= nil and not h.secOpen
	end)
	makePrompt(parts.portaSeg, "BancoPrompt", "Arrombar a porta", "Porta de segurança", B.DoorForceTime, 8, function(player)
		local h = H()
		if not h or h.secOpen or not heistAction(player, parts.portaSeg, 9) then
			return
		end
		CrimeService.addWanted(player, points(4))
		openSecDoor(player, "forca")
	end, function()
		local h = H()
		return h ~= nil and not h.secOpen
	end).UIOffset = Vector2.new(0, 60)
	-- abrir por dentro (quem entrou pela janela da reforma)
	makePrompt(parts.portaSeg, "BancoPrompt", "Abrir por dentro", "Porta de segurança", 1, 7, function(player)
		local h = H()
		local root = rootOf(player)
		if not h or h.secOpen or not root or not inRestricted(root.Position) or not heistAction(player, parts.portaSeg, 8) then
			return
		end
		openSecDoor(player, "dentro")
	end, function()
		local h = H()
		return h ~= nil and not h.secOpen
	end).UIOffset = Vector2.new(0, 120)
	-- terminal da segurança (hack)
	makePrompt(parts.terminal, "BancoPrompt", "Hackear o sistema", "Terminal da segurança", 0.5, 7, function(player)
		local h = H()
		if not h or h.hacked or not heistAction(player, parts.terminal, 8) then
			return
		end
		minigame(player, MG.terminal, parts.terminal, "Hackear • trava de tempo e câmeras", function()
			if heist ~= h or h.hacked then
				return
			end
			h.hacked = true
			setMonitors(false)
			setText(parts.terminal, "🔓 ACESSO\nLIBERADO", Color3.fromRGB(90, 255, 120))
			setTimePanel("TRAVA DE TEMPO\n⚠️ CONTROLE DUPLO", Color3.fromRGB(255, 210, 80))
			crewNotice("💻 SISTEMA HACKEADO: câmeras mudas e trava de tempo desligada. Agora as 2 CHAVES da antecâmara, JUNTAS!")
			refreshPrompts()
			sendStatus()
		end, function()
			CrimeService.addWanted(player, 1)
		end)
	end, function()
		local h = H()
		return h ~= nil and h.secOpen and not h.hacked
	end)
	-- controle duplo
	for _, k in ipairs({ "A", "B" }) do
		local part = k == "A" and parts.chaveA or parts.chaveB
		makePrompt(part, "BancoPrompt", "Girar a chave " .. (k == "A" and "1" or "2"), "Controle duplo", B.KeyTime, 7, function(player)
			local h = H()
			if not h or h.gateOpen or not heistAction(player, part, 8) then
				return
			end
			turnKey(player, k)
		end, function()
			local h = H()
			return h ~= nil and h.secOpen and not h.gateOpen
		end)
	end
	-- Marco 10.25: quadro dos lasers e túnel
	makePrompt(parts.quadroLaser, "BancoPrompt", "Cortar os lasers", "Quadro do subsolo", 0.5, 8, function(player)
		local h = H()
		if not h or not h.lasersOn or not heistAction(player, parts.quadroLaser, 9) then
			return
		end
		minigame(player, MG.laser, parts.quadroLaser, "Cortar os lasers", function()
			if heist ~= h or not h.lasersOn then
				return
			end
			h.lasersOn = false
			setLasers(false)
			crewNotice("✂️ Lasers desligados: o caminho até a porta do cofre está livre!")
			refreshPrompts()
			sendStatus()
		end, function()
			if heist == h then
				h.siegeAt -= 5
				crewNotice("⚡ O quadro deu choque: o cerco chega 5 s mais cedo.", "red")
			end
		end)
	end, function()
		local h = H()
		return h ~= nil and h.gateOpen == true and h.lasersOn == true
	end)
	makePrompt(parts.paredeTunel, "BancoPrompt", "Plantar o C4", "Parede frágil: túnel do esgoto", 2, 8, function(player)
		local h = H()
		if not h or h.tunnel or not h.vaultOpened or not heistAction(player, parts.paredeTunel, 9) then
			return
		end
		h.tunnel = "armando"
		local planterRoot = rootOf(player)
		local away = planterRoot and (planterRoot.Position - parts.paredeTunel.Position) * Vector3.new(1, 0, 1) or Vector3.new(0, 0, 1)
		h.tunnelNormal = away.Magnitude > 0.1 and away.Unit or Vector3.new(0, 0, 1)
		crewNotice(("🧨 %s plantou o C4! Afastem-se: %d s!"):format(player.DisplayName, B.TunnelFuse), "red")
		CrimeService.addWanted(player, points(4))
		task.delay(B.TunnelFuse, function()
			if heist ~= h then
				return
			end
			h.tunnel = "aberto"
			local wallPart = parts.paredeTunel
			-- Marco 10.30: mesma explosão da C4 da porta (fogo, fumaça, estilhaços, câmera tremendo)
			explosionFx(wallPart.Position, h.tunnelNormal or Vector3.new(0, 0, 1), { radius = 12, damage = 30, debris = 10, scorch = false })
			wallPart.Transparency = 1
			wallPart.CanCollide = false
			crewFx("explosao")
			crewNotice("💥 A parede caiu! O túnel leva até o bueiro no gramado oeste.")
			refreshPrompts()
			sendStatus()
		end)
	end, function()
		local h = H()
		return h ~= nil and h.vaultOpened == true and not h.tunnel
	end)
	makePrompt(parts.saidaTunel, "BancoPrompt", "Subir pelo bueiro", "Saída do túnel", 1, 9, function(player)
		local h = H()
		if not h or h.tunnel ~= "aberto" or not heistAction(player, parts.saidaTunel, 10) then
			return
		end
		local character = player.Character
		if character then
			character:PivotTo(parts.bueiro.CFrame)
		end
	end, function()
		local h = H()
		return h ~= nil and h.tunnel == "aberto"
	end)
	-- furadeira e volante
	local pf = parts.pontoFuradeira
	-- Marco 10.30: a porta do cofre abre com a PERFURATRIZ (segurada na mão) ou com C4
	local drillPrompt = makePrompt(pf, "BancoPrompt", "Encostar a perfuratriz", "Porta do cofre", 1, 9, function(player)
		local h = H()
		if not h or not h.gateOpen or h.driller or not (h.drill == nil or h.drill == "furando") or not heistAction(player, pf, 10) then
			return
		end
		startDrilling(player)
	end, function()
		local h = H()
		return h ~= nil and h.gateOpen == true and h.driller == nil and (h.drill == nil or h.drill == "furando") and h.vault == "fechado"
	end)
	drillPrompt:SetAttribute("Precisa", "Perfuratriz") -- o cliente só mostra para quem tem
	local c4Prompt = makePrompt(pf, "BancoPrompt", "Plantar a C4", "Porta do cofre: explode!", C4C.PlantTime, 9, function(player)
		local h = H()
		if not h or not h.gateOpen or h.drill == "pronta" or h.drill == "c4" or not heistAction(player, pf, 10) then
			return
		end
		plantC4(player)
	end, function()
		local h = H()
		return h ~= nil and h.gateOpen == true and h.drill ~= "pronta" and h.drill ~= "c4" and h.vault == "fechado"
	end)
	c4Prompt:SetAttribute("Precisa", "C4")
	c4Prompt.UIOffset = Vector2.new(0, 60)
	-- (as duas no E: o cliente mostra só uma; com as duas na mochila, vale a que está na mão)
	makePrompt(pf, "BancoPrompt", "Girar o volante", "Abrir o cofre", B.WheelTime, 9, function(player)
		local h = H()
		if not h or h.drill ~= "pronta" or h.vault == "aberto" or h.vault == "abrindo" or not heistAction(player, pf, 10) then
			return
		end
		openVault(player)
	end, function()
		local h = H()
		return h ~= nil and h.drill == "pronta" and (h.vault == "fechado")
	end)
	-- alavanca de emergência (por dentro)
	makePrompt(parts.alavanca, "BancoPrompt", "Puxar a alavanca", "Emergência: abre a porta", 2, 7, function(player)
		local h = H()
		if not h or h.vault ~= "fechado" or not h.vaultOpened or not heistAction(player, parts.alavanca, 8) then
			return
		end
		openVault(player)
	end, function()
		local h = H()
		return h ~= nil and h.vault == "fechado" and h.vaultOpened == true
	end)
	-- dinheiro e ouro
	for _, s in ipairs(loot.pilhas) do
		local btn = s.model:FindFirstChild("Botao")
		makePrompt(btn, "BancoPrompt", "Pegar maços de dinheiro", "1 espaço", 1.2, 7, function(player)
			if heistAction(player, btn, 8) then
				grabStack(player, s, "dinheiro")
			end
		end, function()
			local h = H()
			return h ~= nil and h.vault == "aberto" and s.left > 0
		end)
	end
	for _, s in ipairs(loot.ouro) do
		local btn = s.model:FindFirstChild("Botao")
		makePrompt(btn, "BancoPrompt", "Pegar barras de ouro", "2 espaços • pesado", 2, 7, function(player)
			if s.blocked then
				return send(player, "BancoAviso", { text = "📦 A prateleira caiu em cima do ouro: levantem ela primeiro." })
			end
			if heistAction(player, btn, 8) then
				grabStack(player, s, "ouro")
			end
		end, function()
			local h = H()
			return h ~= nil and h.vault == "aberto" and s.left > 0 and not s.blocked
		end)
	end
	-- cofrinhos
	for _, c in ipairs(loot.cofrinhos) do
		makePrompt(c.part, "BancoPrompt", "Abrir cofrinho", "Cofrinho de aluguel", 0.4, 6, function(player)
			local h = H()
			if not h or h.vault ~= "aberto" or c.taken or not heistAction(player, c.part, 7) then
				return
			end
			minigame(player, MG.cofrinho, c.part, "Abrir o cofrinho", function()
				if c.taken then
					return
				end
				local L = B.Loot.cofrinho
				local name, value = L.Name, rng:NextInteger(L.Value[1], L.Value[2])
				if L.Rare and rng:NextNumber() < L.Rare.Chance then
					name, value = L.Rare.Name, rng:NextInteger(L.Rare.Value[1], L.Rare.Value[2])
				end
				-- Marco 10.26: achou algo melhor com a bolsa cheia? pode trocar
				local function take()
					if heist ~= h or h.vault ~= "aberto" or c.taken or not heistAction(player, c.part, 7) then
						return
					end
					if addToBag(player, name, value, L.Slots, c.part.Position, { offer = take,
						valid = function() return heist == h and h.vault == "aberto" and not c.taken end }) then
						c.taken = true
						local open = c.part:FindFirstChild("Aberto")
						if open then
							open.Transparency = 0
						end
						vaultLoot(player)
						refreshPrompts()
					end
				end
				take()
			end)
		end, function()
			local h = H()
			return h ~= nil and h.vault == "aberto" and not c.taken
		end)
	end
	-- saída de serviço: abre por dentro; no cerco precisa forçar
	local exit = parts.saidaServico
	local exitToken = 0
	local function openExit(seconds)
		exitToken += 1
		local token = exitToken
		exit.Transparency = 0.8
		exit.CanCollide = false
		task.delay(seconds, function()
			-- Nunca feche a folha em cima de alguém atravessando.
			while token == exitToken and exit.Parent do
				local occupied = false
				for _, p in ipairs(Players:GetPlayers()) do
					local root = rootOf(p)
					if root and inBox(exit, root.Position, 2) then occupied = true; break end
				end
				if not occupied then break end
				task.wait(0.25)
			end
			if token == exitToken and exit.Parent then
				exit.Transparency = 0
				exit.CanCollide = true
			end
		end)
	end
	makePrompt(exit, "BancoPrompt", "Abrir a saída de serviço", "Saída", 0.8, 8, function(player)
		local h = H()
		if not h or h.sieged or not heistAction(player, exit, 9) then
			return
		end
		openExit(6)
	end, function()
		local h = H()
		return h ~= nil and not h.sieged
	end)
	makePrompt(exit, "BancoPrompt", "Forçar a saída (cerco)", "Trava magnética", B.ExitForceTime, 8, function(player)
		local h = H()
		if not h or not h.sieged or not heistAction(player, exit, 9) then
			return
		end
		CrimeService.addWanted(player, 4)
		crewNotice(("🚪 %s forçou a saída de serviço!"):format(player.DisplayName))
		openExit(8)
	end, function()
		local h = H()
		return h ~= nil and h.sieged == true
	end)
	-- PM: abre a porta da frente e a de segurança com a chave da polícia
	makePrompt(parts.gradeFrente, "BancoPolicia", "Abrir (chave da PM)", "Porta de aço", 1, 10, function(player)
		if not CrimeService.isPolice(player) or not near(player, parts.gradeFrente, 12) then
			return
		end
		setFront(false)
		task.delay(8, function()
			if state ~= "aberto" then
				setFront(true)
			end
		end)
	end, function()
		return state ~= "aberto"
	end)
	makePrompt(parts.portaSeg, "BancoPolicia", "Abrir (acesso da PM)", "Porta de segurança", 0.6, 8, function(player)
		if CrimeService.isPolice(player) and near(player, parts.portaSeg, 9) then
			setSecDoor(true)
			task.delay(8, function()
				if not (heist and heist.secOpen) then
					setSecDoor(false)
				end
			end)
		end
	end, function()
		return state == "assalto"
	end)
	makePrompt(exit, "BancoPolicia", "Abrir (acesso da PM)", "Saída de serviço", 0.6, 8, function(player)
		if CrimeService.isPolice(player) and near(player, exit, 9) then
			openExit(6)
		end
	end, function()
		return true
	end)
end

-- crachá do funcionário que fuma no beco (preparação) e da gerente (assalto)
local function setupNpcPrompts()
	-- Os marcadores sobrevivem à recriação dos NPCs e ao carregamento tardio dos avatares.
	local sroot = f("PontoFumante")
	if sroot then
		makePrompt(sroot, "BancoPrompt", "Pegar o crachá emprestado", "Funcionário distraído", B.BadgeTime, 6, function(player)
			local ok, why = canCrime(player)
			if not ok then
				return CrimeService.notice(player, why)
			end
			if state ~= "aberto" or not near(player, sroot, 7) then
				return
			end
			local g = player:GetAttribute("Gang")
			prep[g] = prep[g] or {}
			if prep[g].cracha and prep[g].cracha > os.clock() then
				return send(player, "BancoAviso", { text = "Sua gangue já tem o crachá." })
			end
			prep[g].cracha = os.clock() + B.PrepValid
			local smoker = npcBy("fumante")
			if smoker then NPCKit.say(smoker.npc, "Ué... cadê meu crachá?", 4) end
			send(player, "BancoEvento", { id = "cracha", icon = "🪪", name = "CRACHÁ NA MÃO", text = ("Quem anunciar o assalto nos próximos %d min já entra com o crachá (não precisa da gerente)."):format(math.floor(B.PrepValid / 60)) })
		end, function()
			return state == "aberto"
		end)
	end
	local mroot = f("PontoGerente")
	if mroot then
		makePrompt(mroot, "BancoPrompt", "Pegar o crachá", "Gerente rendida", B.CardTime, 7, function(player)
			local h = H()
			local manager = npcBy("gerente")
			if not h or h.cardHolder or h.secOpen or not manager or not manager.surrendered or not heistAction(player, mroot, 8) then
				return
			end
			h.cardHolder = player
			player:SetAttribute("CrachaBanco", true)
			crewNotice(("🪪 %s pegou o crachá da gerente: passe no leitor da porta de segurança (fundo do salão)."):format(player.DisplayName))
			sendStatus()
		end, function()
			local h = H()
			local manager = npcBy("gerente")
			return h ~= nil and not h.cardHolder and not h.secOpen and manager ~= nil and manager.surrendered == true
		end)
	end
end

---------------------------------------------------------------------------
-- Receptador (o chefe da gangue compra o malote)
---------------------------------------------------------------------------

local function copNear(pos)
	for _, p in ipairs(Players:GetPlayers()) do
		if CrimeService.isPolice(p) then
			local r = rootOf(p)
			if r and (r.Position - pos).Magnitude <= B.EscapePoliceRadius then
				return true
			end
		end
	end
	return false
end

local function sell(player, gangId, chief)
	local b = bags[player]
	if not b then
		return CrimeService.notice(player, "Você não tem malote do banco.")
	end
	if player:GetAttribute("Gang") ~= gangId or b.gang ~= gangId then
		return CrimeService.notice(player, "Esse chefe só compra da gangue dele.")
	end
	local root = rootOf(player)
	if not root or not chief.root or (root.Position - chief.root.Position).Magnitude > B.SellDistance then
		return
	end
	if CrimeService.isCuffed(player) or player:GetAttribute("Preso") or DownedService.isDowned(player) then
		return
	end
	if inBuilding(root.Position) then return end
	if b.trackerEnds and os.clock() < b.trackerEnds then
		NPCKit.say(chief.npc, "Esse dinheiro tá marcado e com rastreador! Some daqui!", 4)
		return send(player, "BancoAviso", { text = ("📡 O chefe não compra com o rastreador ligado (faltam %d s)."):format(math.ceil(b.trackerEnds - os.clock())), color = "red" })
	end
	if copNear(root.Position) then
		NPCKit.say(chief.npc, "Tem polícia na cola! Despista primeiro!", 4)
		return
	end
	setBag(player, nil)
	if not EconomyService.add(player, b.value, "Malote do banco vendido ao receptador") then
		setBag(player, b)
		return
	end
	NPCKit.emote(chief.npc, "cheer")
	NPCKit.say(chief.npc, "Serviço de banco! Respeito, " .. player.DisplayName .. ".", 4)
	send(player, "BancoFuga", { value = b.value, count = b.count })
	print(("[BankService] %s vendeu %s do banco ao receptador."):format(player.Name, money(b.value)))
end

local function ensureFences()
	for gangId, chief in pairs(GangService.getChiefs()) do
		local root = chief.root
		if root and root.Parent and not root:FindFirstChild("BancoReceptador") then
			local prompt = makePrompt(root, "BancoReceptador", "Vender o malote do banco", "Receptador", 1.5, 10, function(player)
				sell(player, gangId, chief)
			end)
			prompt.KeyboardKeyCode = Enum.KeyCode.F
			prompt.UIOffset = Vector2.new(0, 140)
			prompt:SetAttribute("Gang", gangId)
			CollectionService:AddTag(prompt, "BancoReceptador")
		end
	end
end

---------------------------------------------------------------------------
-- Relógio (a cada 0,5 s)
---------------------------------------------------------------------------

local lastStatus = 0
local lastFence = 0
local lastSiegeTick = 0
local lastNear = 0

local function tick(dt)
	local now = os.clock()
	if state == "assalto" and heist then
		local h = heist
		if events then
			events:step(dt)
		end
		-- segurança não rendido a tempo: botão de pânico
		if h.guard == "alerta" and now >= h.guardDeadline then
			h.guard = "panico"
			local g = npcBy("seguranca")
			if g then
				NPCKit.say(g.npc, "BOTÃO DE PÂNICO!", 3)
				NPCKit.emote(g.npc, "point")
			end
			h.siegeAt -= B.PanicSiege
			h.alarmAt = math.min(h.alarmAt, now)
			for _, p in ipairs(crewList()) do
				CrimeService.addWanted(p, 15)
			end
			crewNotice(("🚨 O SEGURANÇA APERTOU O PÂNICO! O cerco chega %d s mais cedo."):format(B.PanicSiege), "red")
		end
		guardStep(now)
		stepTension(h, dt)
		stepLasers(h, now)
		-- Marco 10.25: rendido que ninguém amarrou volta a reagir
		for _, info in ipairs(npcs) do
			if info.surrendered and info.releaseAt and not info.tied and now >= info.releaseAt and npcRoot(info) then
				info.surrendered = false
				info.relapsed = true
				info.releaseAt = nil
				info.armed = false
				info.aim = {}
				NPCKit.pose(info.npc, nil)
				NPCKit.say(info.npc, "Agora é a minha vez!", 3)
				crewNotice("🔫 Um vigilante que ninguém amarrou pegou outra arma! Mire nele de novo.", "red")
			end
		end
		-- alarme chega na PM (com a energia cortada, atrasado)
		if not h.called and now >= h.alarmAt then
			callPolice(h.powerCut and "O telefone voltou e o alarme chegou na PM." or nil)
		end
		-- (Marco 10.30: a perfuratriz anda no stepDrill, a cada 0,1 s)
		-- cerco
		if not h.sieged and now >= h.siegeAt then
			h.sieged = true
			if not h.called then
				callPolice()
			end
			setFront(true)
			crewFx("cerco")
			spawnSwat()
			if events then
				events:roll("cerco")
			end
			crewNotice(("🚔 CERCO! O Batalhão de Choque fechou a porta da frente. Só sai forçando a saída de serviço (leste). Em %d s a polícia toma o prédio!"):format(B.SiegeFinal), "red")
			refreshPrompts()
		end
		if h.sieged and now - lastSiegeTick >= 10 then
			lastSiegeTick = now
			for _, p in ipairs(crewList()) do
				local r = rootOf(p)
				if r and inBuilding(r.Position) then
					CrimeService.addWanted(p, B.SiegePoints)
				end
			end
		end
		if h.guard ~= "alerta" and now - (h.lastHands or 0) > 3 then
			h.lastHands = now
			handsUp()
		end
		-- quem está no banco
		local inside = false
		for _, p in ipairs(crewList()) do
			local r = rootOf(p)
			if r and inLot(r.Position) then
				inside = true
			end
		end
		if inside then
			h.lastInside = now
		end
		local idle = now - h.lastInside
		local online = #crewList()
		local graceOpen = false
		for _, t in pairs(h.away) do
			if now - t < B.ReconnectGrace then
				graceOpen = true
			end
		end
		if h.sieged and now >= h.siegeAt + B.SiegeFinal then
			exitRobbers()
			closeBank("🚔 A polícia tomou o banco. O assalto acabou.")
		elseif online == 0 and not graceOpen then
			closeBank("O assalto acabou: ninguém da equipe ficou.")
		elseif h.vaultOpened and idle > 30 then
			closeBank("🏦 A equipe fugiu: o banco fechou para a perícia.")
		elseif not h.vaultOpened and idle > B.AbandonTime then
			closeBank("Vocês abandonaram o assalto: o banco fechou.")
		end
		if heist and now - lastStatus > 1 then
			lastStatus = now
			sendStatus()
		end
	elseif state == "fechado" and now >= closedUntil then
		reopenBank()
	elseif state == "aberto" and events then
		events:step(dt)
	end
	-- status da preparação para quem é de gangue e está no terreno do banco
	if now - lastNear > 2 then
		lastNear = now
		for _, p in ipairs(Players:GetPlayers()) do
			local r = (not heist or not heist.crew[p]) and p:GetAttribute("Gang") and rootOf(p)
			if r and inLot(r.Position) then
				send(p, "BancoStatus", statusPayload(p))
			end
		end
	end
	-- fuga de quem está com malote
	for player, b in pairs(bags) do
		if not player.Parent then
			bags[player] = nil
		elseif player:GetAttribute("Preso") then
			loseBag(player, "A polícia recuperou o malote do banco.")
		else
			local root = rootOf(player)
			if root then
				if not b.left and not inBuilding(root.Position) then
					b.left = true
					if heist and heist.crew[player] then heist.anyLeft = true end
					if b.marked and not b.trackerEnds then
						b.trackerEnds = now + B.TrackerTime
						player:SetAttribute("RastreadorBanco", true)
						send(player, "BancoAviso", { text = ("📡 Dinheiro MARCADO: rastreador ligado por %d s! A PM vê você no mapa."):format(B.TrackerTime), color = "red" })
						send(player, "BancoBolsa", bagPayload(player))
					end
					if events and heist and heist.crew[player] and not heist.rolledFuga then
						heist.rolledFuga = true
						events:roll("fuga")
					end
				end
				if b.trackerEnds and not b.trackerOff and now >= b.trackerEnds then
					b.trackerOff = true
					player:SetAttribute("RastreadorBanco", nil)
					send(player, "BancoAviso", { text = "📡 O rastreador apagou! Leve o malote ao chefe da sua gangue (F)." })
					send(player, "BancoBolsa", bagPayload(player))
				end
				applyWeight(player, b)
				local cn = copNear(root.Position)
				if b.copNear ~= cn then
					b.copNear = cn
					send(player, "BancoPolicia", { near = cn })
				end
			end
		end
	end
	-- malotes no chão vencidos
	for i = #drops, 1, -1 do
		local d = drops[i]
		if d.taken or not d.part.Parent then
			table.remove(drops, i)
		elseif now >= d.expires then
			d.part:Destroy()
			table.remove(drops, i)
		end
	end
	refreshPrompts()
	if now - lastFence > 3 then
		lastFence = now
		ensureFences()
	end
end

---------------------------------------------------------------------------

local VALID_POSE = { amarrar = true, digitar = true, agachar = true, girar = true, pegar = true, forca = true }

local function onRequest(player, action, arg)
	if not SecurityService.isShortString(action, 16) then
		return
	end
	if action == "Pose" then -- segurando o E: todo mundo vê
		if player.Character and (arg == nil or VALID_POSE[arg]) and SecurityService.checkRate(player, "BancoPose", 0.1) then
			NPCKit.pose(player.Character, arg, arg and 8 or nil)
		end
		return
	end
	if action == "Perfurar" then -- Marco 10.30: segurando o clique com a perfuratriz na porta
		if SecurityService.checkRate(player, "BancoFuro", 0.08) and heist and heist.driller == player then
			heist.drillPush = arg == true
			heist.drillPushAt = os.clock()
		end
		return
	end
	if action == "Soltar" then -- largou a perfuratriz (pulou ou apertou X)
		if heist and heist.driller == player then
			stopDrilling(heist, ("🛠️ %s largou a perfuratriz em %d%%."):format(player.DisplayName, math.floor((heist.drillProgress or 0) * 100)))
		end
		return
	end
	if not SecurityService.checkRate(player, "BancoRequest", 0.3) then
		return
	end
	if action == "Status" then
		send(player, "BancoStatus", statusPayload(player))
		send(player, "BancoBolsa", bagPayload(player))
	elseif action == "Gritar" then
		shout(player)
	elseif action == "Largar" and type(arg) == "number" then
		local b = bags[player]
		local it = b and NPCKit.bagItems(b)[math.floor(arg)]
		if it then
			dropItem(player, it)
		end
	elseif action == "Trocar" then
		local o = pending[player]
		pending[player] = nil
		local root = rootOf(player)
		if o and o.heist and heist == o.heist and canCrime(player) and player:GetAttribute("Gang") == heist.gang
			and bags[player] == o.bag and os.clock() <= o.expires and root and (root.Position - o.at).Magnitude <= 12
			and (not o.valid or o.valid()) then
			for _, it in ipairs(o.drop) do
				dropItem(player, it)
			end
			o.accept()
		end
	elseif action == "Deixar" then
		pending[player] = nil
	end
end

local function findParts()
	parts = {
		areaSalao = f("AreaSalao"),
		areaRestrita = f("AreaRestrita"),
		areaCofre = f("AreaCofre"),
		areaLote = f("AreaLote"),
		anuncio = f("PontoAnuncio"),
		gradeFrente = f("GradeFrente"),
		portaSeg = f("PortaSeguranca"),
		leitor = f("LeitorCartao"),
		ledLeitor = f("LedLeitor"),
		terminal = f("TerminalSeguranca"),
		retro = f("TerminalRetro"),
		cofreDiretor = f("CofreDiretor"),
		chaveA = f("ChaveA"),
		chaveB = f("ChaveB"),
		painelTempo = f("PainelTempo"),
		grade = f("GradeAntecamara"),
		portaCofre = f("PortaCofre"),
		pivot = f("PivotCofre"),
		bloqueio = f("BloqueioCofre"),
		pontoFuradeira = f("PontoFuradeira"),
		alavanca = f("AlavancaEmergencia"),
		saidaServico = f("SaidaServico"),
		saida = f("PontoSaida"),
		areaSub = f("AreaSubsolo"),
		quadroLaser = f("QuadroLaser"),
		paredeTunel = f("ParedeTunel"),
		saidaTunel = f("SaidaTunel"),
		bueiro = f("PontoBueiro"),
		lasers = f("Lasers"),
		prateleira = f("PrateleiraMalotes"),
		andaime = f("Andaime"),
		janela = f("JanelaReforma"),
		monitores = {},
	}
	for _, d in ipairs(bank:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "Monitor" and d:GetAttribute("Cam") then
			table.insert(parts.monitores, d)
		end
	end
	local missing = {}
	for _, key in ipairs({ "areaSalao", "areaRestrita", "areaCofre", "areaLote", "anuncio", "gradeFrente", "portaSeg", "leitor", "terminal", "chaveA", "chaveB", "grade", "portaCofre", "pivot", "pontoFuradeira", "alavanca", "saidaServico", "saida", "areaSub", "quadroLaser", "paredeTunel", "saidaTunel", "bueiro", "lasers" }) do
		if not parts[key] then
			table.insert(missing, key)
		end
	end
	return missing
end

function BankService.init(remotes)
	if initialized then return end
	uiUpdate = remotes[GameConfig.Remotes.UIUpdate]
	bank = CollectionService:GetTagged("Banco")[1]
	if not bank then
		warn("[BankService] Banco não encontrado no mapa.")
		return
	end
	remotes[GameConfig.Remotes.BankRequest].OnServerEvent:Connect(onRequest)
	WeaponService.onShot(shotAtNpc)
	local okF, mod = pcall(require, script.Parent:WaitForChild("FerramentasAssaltoService", 5))
	FerramentasAssaltoService = okF and mod or nil
	local missing = findParts()
	if #missing > 0 then
		warn("[BankService] Faltam peças no banco: " .. table.concat(missing, ", "))
		return
	end
	initialized = true
	-- Marco 10.21: parafusadeira de enfeite na mesa da sala de segurança
	if NPCKit.drill then
		pcall(NPCKit.drill, bank, lotAt(52, 3.6, 12) * CFrame.Angles(0, math.rad(30), 0))
	end
	storage = ServerStorage:FindFirstChild("BancoGuardado") or Instance.new("Folder")
	storage.Name = "BancoGuardado"
	storage.Parent = ServerStorage
	-- porta do cofre
	doorHinge = parts.pivot.Position
	for _, d in ipairs(parts.portaCofre:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(doorParts, { part = d, home = d.CFrame })
		end
	end
	gateHome = parts.grade:GetPivot()
	-- saque
	for _, c in ipairs(f("Caixas"):GetChildren()) do
		table.insert(loot.caixas, { part = c, taken = false })
	end
	for _, m in ipairs(f("Pilhas"):GetChildren()) do
		local n = m:GetAttribute("Camadas") or B.MoneyGrabs
		table.insert(loot.pilhas, { model = m, layers = n, left = n })
	end
	for _, m in ipairs(f("Ouro"):GetChildren()) do
		local n = m:GetAttribute("Camadas") or B.GoldGrabs
		table.insert(loot.ouro, { model = m, layers = n, left = n })
	end
	table.sort(loot.ouro, function(a, b)
		return (a.model:GetAttribute("Index") or 0) < (b.model:GetAttribute("Index") or 0)
	end)
	for _, c in ipairs(f("Cofrinhos"):GetChildren()) do
		table.insert(loot.cofrinhos, { part = c, taken = false })
	end
	setReforma(false)
	setLasers(false)
	events = HeistEvents.new("Banco", BANK_EVENTS, B.Events, {
		announce = function(ev)
			local list = ev.id == "Reforma" and {} or crewList()
			for _, p in ipairs(list) do
				send(p, "BancoEvento", { id = ev.id, name = ev.def.Name, icon = ev.def.Icon, text = ev.def.Text })
			end
		end,
	}, B.MaxEvents)
	events.forceAll = B.TestAllEvents == true
	setupPrompts()
	setupNpcPrompts()
	reopenBank()
	CrimeService.onArrest(function(target, cop)
		local b = bags[target]
		if b and cop and cop.Parent then
			local paid = CareerService.taskPay(cop, "Policial", B.PoliceRecoverPay, "Recuperou malote do banco", 0)
			send(cop, "CrimePaid", { amount = paid, text = ("Malote do banco recuperado: +%s"):format(money(paid)) })
		end
		if b then
			loseBag(target, "A polícia recuperou o malote do banco.")
		end
		if target:GetAttribute("CrachaBanco") then
			target:SetAttribute("CrachaBanco", nil)
			if heist and heist.cardHolder == target then
				heist.cardHolder = nil
			end
		end
	end)
	DownedService.onGiveUp(function(target)
		local root = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
		if bags[target] and root then
			dropWholeBag(target, root.Position, ("💸 %s caiu e o malote ficou no chão! Peguem antes da PM."):format(target.DisplayName))
		elseif bags[target] then
			loseBag(target, "Você caiu e perdeu o malote.")
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if bags[player] and root then
			dropWholeBag(player, root.Position, ("📴 %s caiu do jogo: o malote dele ficou no chão!"):format(player.DisplayName))
		end
		bags[player] = nil
		if heist and heist.crew[player] then
			heist.crew[player] = nil
			heist.away[player.UserId] = os.clock()
			if heist.cardHolder == player then
				heist.cardHolder = nil
			end
			crewNotice(("📴 %s caiu do jogo. Se voltar em %d s, volta para a equipe."):format(player.DisplayName, B.ReconnectGrace))
		end
		for _, info in ipairs(npcs) do
			info.aim[player] = nil
		end
	end)
	Players.PlayerAdded:Connect(function(player)
		local h = heist
		local t = h and h.away[player.UserId]
		if t and os.clock() - t <= B.ReconnectGrace and player:GetAttribute("Gang") == h.gang then
			h.away[player.UserId] = nil
			h.crew[player] = true
			task.delay(4, function()
				send(player, "BancoAviso", { text = "🏦 Você voltou para a equipe do assalto ao banco!" })
				crewNotice(("📲 %s voltou para o assalto!"):format(player.DisplayName))
			end)
		end
	end)
	task.spawn(function()
		local acc, last = 0, os.clock()
		while true do
			task.wait(0.1)
			local now = os.clock()
			local dt = now - last
			last = now
			local ok, err = pcall(aimStep, dt)
			if not ok then
				warn("[BankService] " .. tostring(err))
			end
			local okDrill, errDrill = pcall(stepDrill, dt) -- Marco 10.30
			if not okDrill then
				warn("[BankService] " .. tostring(errDrill))
			end
			acc += dt
			if acc >= 0.5 then
				local okTick, errTick = pcall(tick, acc)
				acc = 0
				if not okTick then
					warn("[BankService] " .. tostring(errTick))
				end
			end
		end
	end)
	print(("[BankService] %s pronto: %d caixas, %d pilhas, %d paletes de ouro, %d cofrinhos, %d eventos."):format(B.Name, #loot.caixas, #loot.pilhas, #loot.ouro, #loot.cofrinhos, #BANK_EVENTS))
end

return BankService
