-- JewelryService (ModuleScript)
-- Caminho: ServerScriptService > Services > JewelryService
-- Marco 10.8: assalto à joalheria do Bairro Horizonte (regras em GameConfig.Jewelry; prédio no
-- JewelryBuilder). Marco 10.9: assalto bem mais difícil e com mais etapas:
--   1. Reconhecimento (obrigatório para o plano silencioso): 3 câmeras, leitor de cartão, quadro de
--      energia e duto do telhado. Vale para a gangue toda.
--   2. SILENCIOSO (gás no duto): funcionários dormem por GasDuration s. Medidor de ALERTA (0 a 100):
--      sobe com vidro quebrado, erro no minigame, câmera vendo a gangue, porta arrombada. Cheio, ou
--      os funcionários acordando = alarme.
--      BARULHENTO (arma + "Anunciar o assalto"): alarme na hora; renda o segurança mirando nele em
--      até GuardReact s, senão ele aperta o botão de pânico (porta de aço fecha mais cedo).
--   3. Vitrines, caixas e gavetas: minigame de mira (o servidor abre a sessão, confere distância,
--      ritmo e erros). Bolsa com espaço limitado e peso (anda mais devagar).
--   4. Área restrita: cartão do gerente (dormindo ou rendido) ou arrombar a porta. Código do cofre na
--      gaveta do escritório ou hackeando o terminal (que também desliga câmeras e lasers por HackTime s
--      e segura a trava da saída). Sem código: furadeira (alarme na hora). Lasers piscando no cofre.
--   5. Alarme: chamado da PM. Lockdown s depois fecham a porta de aço E a trava da saída de
--      emergência (forçar = ExitForceTime s e a PM é avisada).
--   6. Fuga: se o alarme tocou, a bolsa tem rastreador por TrackerTime s depois de sair da loja (a PM
--      vê no mapa). Vender ao chefe da própria gangue (receptador): sem rastreador e sem polícia perto.
--      Preso ou morto: perde a bolsa.
--   7. A loja fecha (perícia) por Cooldown segundos e depois volta inteira.
-- Tudo conferido no servidor (gangue, polícia, distância, tempo, estado da loja).

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local SecurityService = require(script.Parent:WaitForChild("SecurityService"))
local CrimeService = require(script.Parent:WaitForChild("CrimeService"))
local DownedService = require(script.Parent:WaitForChild("DownedService"))
local CareerService = require(script.Parent:WaitForChild("CareerService"))
local NPCKit = require(script.Parent:WaitForChild("NPCKit"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local GangService = require(script.Parent:WaitForChild("GangService"))
local HeistEvents = require(script.Parent:WaitForChild("HeistEvents")) -- Marco 10.20: eventos
local WeaponService = require(script.Parent:WaitForChild("WeaponService"))

local JewelryService = {}

local J = GameConfig.Jewelry
local MG = J.Minigame
local ALVOS = { "cam1", "cam2", "cam3", "leitor", "quadro", "duto" }
local ALVO_NOMES = {
	cam1 = "Câmera da entrada",
	cam2 = "Câmera do fundo (direita)",
	cam3 = "Câmera do fundo (esquerda)",
	leitor = "Leitor de cartão (porta dos funcionários)",
	quadro = "Quadro de energia (beco)",
	duto = "Duto do telhado",
}
local CASE_ACTION = {
	vitrine = "Quebrar vitrine",
	blindada = "Quebrar vidro blindado",
	gaveta = "Arrombar",
	colar = "Pegar o Colar Imperial",
	diamante = "Pegar o Diamante Estrela",
}
local events -- Marco 10.20: motor de eventos (HeistEvents)
local LASER_TIMING = { { 3.0, 0.62, 0 }, { 2.4, 0.55, 0.9 }, { 3.6, 0.6, 1.7 } } -- período, fração ligada, atraso
local rng = Random.new()

local uiUpdate
local store -- Model "Joalheria"
local cases = {} -- { model, glass, kind, mini, noise, zone, broken, parts = { [part] = transparência } }
local alvos = {} -- alvos[nome] = peça
local prompts = {} -- nome -> ProximityPrompt
local npcs = {} -- { npc, role, spot, asleep, surrendered, aim = { [player] = s } }
local state = "aberta" -- "aberta" | "assalto" | "fechada"
local heist -- assalto em andamento
local closedUntil = 0
local camsCut = false
local camsCutAt = 0
local reconByGang = {} -- reconByGang[gangId] = os.time() até quando vale
local reconActive = {} -- reconActive[player] = { started, found = {}, last }
local bags = {} -- bags[player] = { value, slots, count, left, trackerEnds, speed }
local pending = {} -- pending[player] = { drop, accept } (Marco 10.26: troca oferecida)
local sessions = {} -- sessions[player] = minigame aberto
local sessionId = 0
local parts = {} -- peças fixas da loja (portas, painéis, lasers...)
local vaultParts = {} -- { part, home }
local lasers = {} -- lasers[i] = { beams = {}, box, on }
local lasersShown = true

local function send(player, kind, data)
	if player and player.Parent then
		uiUpdate:FireClient(player, kind, data or {})
	end
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

local function inShowroom(pos)
	return inBox(parts.area, pos)
end

local function inRestricted(pos)
	return inBox(parts.restrita, pos)
end

local function inStore(pos)
	return inShowroom(pos) or inRestricted(pos)
end

local function rootOf(player)
	local _, _, root = SecurityService.getLivingCharacter(player)
	return root
end

local function hasGun(player)
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	return tool ~= nil and tool:GetAttribute("Use") == "gun"
end

local function canCrime(player)
	if not player:GetAttribute("Gang") then
		return false, "Só quem é de gangue assalta. Procure o chefe numa favela."
	end
	if CrimeService.isPolice(player) then
		return false, "Policial não assalta."
	end
	if player:GetAttribute("Preso") or CrimeService.isCuffed(player) then
		return false, "Agora não dá."
	end
	return true
end

local function playSound(parent, id, volume, length)
	if not id or id == 0 or not parent then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. tostring(id)
	s.Volume = volume or 0.6
	s.RollOffMaxDistance = 120
	s.Parent = parent
	s:Play()
	Debris:AddItem(s, length or 8)
end

local function casesLeft()
	local n = 0
	for _, c in ipairs(cases) do
		if not c.broken then
			n += 1
		end
	end
	return n
end

local function setText(part, str, color)
	local gui = part and part:FindFirstChild("Tela")
	local label = gui and gui:FindFirstChild("Texto")
	if label then
		label.Text = str
		if color then
			label.TextColor3 = color
		end
	end
end

local function setLed(part, on, colorOn, colorOff)
	if part then
		part.Color = on and colorOn or colorOff
	end
end

---------------------------------------------------------------------------
-- NPCs da loja
---------------------------------------------------------------------------

local function clearNpcs()
	for _, info in ipairs(npcs) do
		if info.npc and info.npc.Parent then
			info.npc:Destroy()
		end
	end
	npcs = {}
end

local function npcRoot(info)
	return info.npc and info.npc.Parent and info.npc:FindFirstChild("HumanoidRootPart")
end

local refreshPrompts -- (declarada mais abaixo)

local function stopAnims(npc)
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
			t:Stop(0.2)
		end
	end
end

local takeCard -- (declarada mais abaixo)

local function spawnNpcs()
	clearNpcs()
	local list = {
		{ spot = "PontoFuncionario1", role = "gerente", name = "Gerente Rui", outfit = "gerente", shirt = Color3.fromRGB(30, 30, 40), pants = Color3.fromRGB(20, 20, 24) },
		{ spot = "PontoFuncionario2", role = "funcionario", name = "Vendedora Lia", outfit = "vendedora", shirt = Color3.fromRGB(20, 20, 24), pants = Color3.fromRGB(20, 20, 24) },
		{ spot = "PontoSeguranca", role = "seguranca", name = "Segurança Neto", outfit = "seguranca", shirt = Color3.fromRGB(30, 34, 44), pants = Color3.fromRGB(25, 25, 30) },
		{ spot = "PontoCliente", role = "cliente", name = "Cliente" },
	}
	for _, def in ipairs(list) do
		local spot = store:FindFirstChild(def.spot)
		if spot then
			local npc = NPCKit.spawn(spot.CFrame, { name = def.name, anchored = true, important = true, shirt = def.shirt, pants = def.pants, outfit = def.outfit })
			if npc then
				local info = { npc = npc, role = def.role, spot = spot, aim = {}, home = npc:GetPivot() }
				table.insert(npcs, info)
				if def.role == "gerente" then
					local root = npc:FindFirstChild("HumanoidRootPart")
					if root then
						local prompt = Instance.new("ProximityPrompt")
						prompt.Name = "JoiaPrompt"
						prompt.ActionText = "Pegar o cartão"
						prompt.ObjectText = "Crachá do gerente"
						prompt.KeyboardKeyCode = Enum.KeyCode.E
						prompt.HoldDuration = J.CardTime
						prompt.MaxActivationDistance = 7
						prompt.RequiresLineOfSight = false
						prompt.Enabled = false
						prompt:SetAttribute("Ativo", false)
						prompt.Parent = root
						prompts.cartao = prompt
						prompt.Triggered:Connect(function(player)
							if SecurityService.checkRate(player, "JoiaPrompt", 0.4) then
								takeCard(player, info)
							end
						end)
					end
				end
			end
		end
	end
end

local function sleepNpcs()
	for _, info in ipairs(npcs) do
		local npc = info.npc
		if npc and npc.Parent and not info.asleep then
			info.asleep = true
			task.delay(rng:NextNumber(1.5, 3.5), function()
				if npc.Parent and info.asleep then
					stopAnims(npc)
					NPCKit.react(npc, "💤")
					npc:PivotTo(info.spot.CFrame * CFrame.new(rng:NextNumber(-0.5, 0.5), 0.55, 0) * CFrame.Angles(math.rad(-90), math.rad(rng:NextNumber(-40, 40)), 0))
				end
			end)
		end
	end
end

local function wakeNpcs()
	for _, info in ipairs(npcs) do
		if info.npc and info.npc.Parent and info.asleep then
			info.asleep = false
			info.npc:PivotTo(info.home)
			NPCKit.react(info.npc, "😠")
		end
	end
end

local SCARED = { "Calma! Pode levar tudo!", "Não atira, por favor!", "Tá bom, tá bom!", "Ai meu Deus!" }
local function handsUp()
	for _, info in ipairs(npcs) do
		if info.npc and info.npc.Parent and not info.asleep and info.surrendered then
			NPCKit.emote(info.npc, "cheer")
			if rng:NextNumber() < 0.25 then
				NPCKit.say(info.npc, SCARED[rng:NextInteger(1, #SCARED)], 3)
			end
		end
	end
end

local VIP_SCARED = { "Você sabe com quem está falando?!", "Meu advogado vai saber disso!", "Leva, leva! Tenho outros em casa!", "Isso nunca aconteceu em Paris!" }
local function surrender(info)
	if info.surrendered then
		return
	end
	info.surrendered = true
	NPCKit.emote(info.npc, "cheer")
	if info.role == "seguranca" then
		NPCKit.say(info.npc, "Tá bom! Não aperto nada! Não atira!", 4)
		if heist then
			heist.guard = "rendido"
		end
	elseif info.role == "gerente" then
		NPCKit.say(info.npc, "Leva o crachá, mas não machuca ninguém!", 4)
	elseif info.role == "leiloeiro" then
		NPCKit.say(info.npc, "Calma! O controle da redoma tá aqui no bolso!", 4)
	elseif info.role == "vip" then
		NPCKit.say(info.npc, VIP_SCARED[rng:NextInteger(1, #VIP_SCARED)], 3)
	elseif info.role == "noivo" then
		NPCKit.say(info.npc, "Logo hoje?! Leva tudo, mas não a aliança...", 4)
	elseif info.role == "influencer" then
		NPCKit.say(info.npc, "Tá, tá! Encerrei a live! Não atira!", 4)
	else
		NPCKit.say(info.npc, SCARED[rng:NextInteger(1, #SCARED)], 3)
	end
end

---------------------------------------------------------------------------
-- Partes da loja (vitrines, câmeras, grade, portas, cofre, lasers)
---------------------------------------------------------------------------

local function hacked()
	return heist ~= nil and heist.hackedUntil ~= nil and os.clock() < heist.hackedUntil
end

-- Marco 10.20: evento "Queda de energia" apaga câmeras e lasers por um tempo
local function blackout()
	return heist ~= nil and heist.blackoutUntil ~= nil and os.clock() < heist.blackoutUntil
end

local function camsOff()
	return camsCut or hacked() or blackout()
end

local camsShown
local function showCameras()
	local on = not camsOff()
	if camsShown == on then
		return
	end
	camsShown = on
	for _, d in ipairs(store:GetDescendants()) do
		if d:IsA("BasePart") then
			if d:GetAttribute("CameraLed") then
				d.Color = on and Color3.fromRGB(255, 30, 30) or Color3.fromRGB(40, 40, 40)
				d.Material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
			elseif d.Name == "Monitor" then
				local cam = d:GetAttribute("Cam") or 0
				setText(d, on and ("CAM %d\nAO VIVO"):format(cam) or ("CAM %d\nSEM SINAL"):format(cam), on and Color3.fromRGB(150, 255, 170) or Color3.fromRGB(255, 110, 110))
			end
		end
	end
	store:SetAttribute("CamerasCortadas", (not on) or nil)
end

local function setCameras(on)
	camsCut = not on
	camsCutAt = os.clock()
	showCameras()
end

-- Marco 10.11: a vitrine fica "quebrada" na hora (ninguém mais pega), mas o vidro só estoura no
-- golpe da animação (GrabAnim.SmashAt) e as joias somem quando a mão pega (GrabAnim.GrabAt).
local function breakGlass(c)
	c.broken = true
	c.breakId = (c.breakId or 0) + 1
	local myBreak = c.breakId
	c.model:SetAttribute("Quebrada", true)
	local glass = c.glass
	local prompt = glass:FindFirstChild("JoiaPrompt")
	if prompt then
		prompt:SetAttribute("Ativo", false)
	end
	local GA = J.GrabAnim or {}
	local function still()
		return c.broken and c.breakId == myBreak
	end
	task.delay(GA.GrabAt or 0, function()
		if still() then
			for part in pairs(c.parts) do
				part.Transparency = 1
			end
		end
	end)
	task.wait(GA.SmashAt or 0)
	if not still() then
		return
	end
	glass.Transparency = 1
	glass.CanCollide = false
	if c.noShards then
		return
	end
	-- cacos voando
	for _ = 1, 6 do
		local shard = Instance.new("Part")
		shard.Name = "Caco"
		shard.Size = Vector3.new(rng:NextNumber(0.2, 0.6), 0.05, rng:NextNumber(0.2, 0.6))
		shard.Color = Color3.fromRGB(210, 225, 235)
		shard.Material = Enum.Material.Glass
		shard.Transparency = 0.4
		shard.CanCollide = true
		shard.CanQuery = false
		shard.CastShadow = false
		shard.CFrame = glass.CFrame * CFrame.new(rng:NextNumber(-1, 1) * glass.Size.X / 2, glass.Size.Y / 2, rng:NextNumber(-1, 1) * glass.Size.Z / 2) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0)
		shard.AssemblyLinearVelocity = Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(4, 12), rng:NextNumber(-8, 8))
		shard.Parent = store
		Debris:AddItem(shard, 3)
	end
	local fx = Instance.new("ParticleEmitter")
	fx.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	fx.Color = ColorSequence.new(Color3.fromRGB(220, 240, 255))
	fx.Size = NumberSequence.new(0.35, 0)
	fx.Lifetime = NumberRange.new(0.4, 0.8)
	fx.Speed = NumberRange.new(6, 12)
	fx.SpreadAngle = Vector2.new(180, 180)
	fx.LightEmission = 1
	fx.Rate = 0
	fx.Parent = glass
	fx:Emit(40)
	Debris:AddItem(fx, 2)
	playSound(glass, J.Sounds.Glass, 0.8)
end

local function restoreCases()
	for _, c in ipairs(cases) do
		c.broken = false
		c.model:SetAttribute("Quebrada", nil)
		c.glass.Transparency = c.glassT
		c.glass.CanCollide = true
		for part, t in pairs(c.parts) do
			part.Transparency = t
		end
	end
end

local function setGrade(closed, instant)
	local grade = parts.grade
	if not grade then
		return
	end
	local top, bottom = grade:GetAttribute("Top"), grade:GetAttribute("Bottom")
	local h = closed and (top - bottom) or 0.3
	local base = grade.CFrame
	local y = closed and (top + bottom) / 2 or (top - 0.15)
	-- a grade fica no mesmo X/Z: muda só a altura do centro e o tamanho (enrola em cima)
	local goal = { Size = Vector3.new(grade.Size.X, h, grade.Size.Z), CFrame = CFrame.new(base.Position.X, y, base.Position.Z) * base.Rotation }
	grade.CanCollide = closed
	if instant then
		grade.Size, grade.CFrame = goal.Size, goal.CFrame
	else
		TweenService:Create(grade, TweenInfo.new(closed and 5 or 3, Enum.EasingStyle.Linear), goal):Play()
	end
	store:SetAttribute("Grade", closed or nil)
end

local doorBusy = false
local function openEmergency(seconds)
	local door = parts.saida
	if not door or doorBusy then
		return
	end
	doorBusy = true
	local closed = door:GetAttribute("Closed")
	-- gira 80 graus para fora (dobradiça na ponta de trás da porta)
	local hinge = closed * CFrame.new(0, 0, door.Size.Z / 2)
	local open = hinge * CFrame.Angles(0, math.rad(-80), 0) * CFrame.new(0, 0, -door.Size.Z / 2)
	door.CanCollide = false
	TweenService:Create(door, TweenInfo.new(0.4), { CFrame = open }):Play()
	task.delay(seconds or 6, function()
		if door.Parent then
			TweenService:Create(door, TweenInfo.new(0.6), { CFrame = closed }):Play()
			task.wait(0.6)
			door.CanCollide = true
		end
		doorBusy = false
	end)
end

-- estado da trava da saída: "livre" | "destravada" (hack segurando) | "trancada" | "forcada"
local function exitState()
	if not heist or not heist.locked then
		return "livre"
	end
	if heist.exitForced then
		return "forcada"
	end
	if heist.hackedAt and os.clock() < heist.lockAt + J.ExitOverride then
		return "destravada"
	end
	return "trancada"
end

local exitShown
local function showExit()
	local st = exitState()
	if st == exitShown then
		return
	end
	exitShown = st
	local led = parts.ledTrava
	if led then
		led.Color = st == "trancada" and Color3.fromRGB(255, 40, 40) or (st == "destravada" and Color3.fromRGB(255, 190, 40) or Color3.fromRGB(60, 255, 120))
	end
	local prompt = prompts.saida
	if prompt then
		if st == "trancada" then
			prompt.ActionText = "Forçar a trava"
			prompt.ObjectText = "Saída trancada!"
			prompt.HoldDuration = J.ExitForceTime
		else
			prompt.ActionText = "Abrir saída"
			prompt.ObjectText = "Saída de emergência"
			prompt.HoldDuration = 0.3
		end
	end
end

local function setStaffDoor(open, instant)
	local door = parts.portaFunc
	if not door then
		return
	end
	local goal = open and door:GetAttribute("Open") or door:GetAttribute("Closed")
	if instant then
		door.CFrame = goal
	else
		TweenService:Create(door, TweenInfo.new(1.2, Enum.EasingStyle.Quad), { CFrame = goal }):Play()
	end
	door.CanCollide = not open
	setLed(parts.ledLeitor, open, Color3.fromRGB(60, 255, 120), Color3.fromRGB(255, 40, 40))
end

local function setVault(open, instant)
	if not open then
		for _, v in ipairs(vaultParts) do
			v.part.CFrame = v.home
		end
		setText(parts.painelCofre, "🔢\n- - - -", Color3.fromRGB(255, 90, 90))
		return
	end
	local main = parts.portaCofre
	if not main then
		return
	end
	-- a porta (do lado de dentro) recua e desliza para o leste do lote
	local back = -main.CFrame.RightVector * 1.2
	local side = -main.CFrame.LookVector * 7.2
	for _, v in ipairs(vaultParts) do
		if instant then
			v.part.CFrame = v.home + back + side
		else
			TweenService:Create(v.part, TweenInfo.new(1.5, Enum.EasingStyle.Quad), { CFrame = v.home + back }):Play()
		end
	end
	if not instant then
		task.delay(1.6, function()
			for _, v in ipairs(vaultParts) do
				TweenService:Create(v.part, TweenInfo.new(3, Enum.EasingStyle.Quad), { CFrame = v.home + back + side }):Play()
			end
		end)
	end
end

local function showLasers(on)
	if lasersShown == on then
		return
	end
	lasersShown = on
	for _, l in ipairs(lasers) do
		for _, b in ipairs(l.beams) do
			b.Transparency = on and 0.15 or 1
		end
		l.on = on
	end
end

local function setClosedSign(on)
	local sign = parts.placaFechado
	local gui = sign and sign:FindFirstChildOfClass("SurfaceGui")
	if gui then
		gui.Enabled = on
	end
	store:SetAttribute("Fechada", on or nil)
	store:SetAttribute("AbreEm", on and closedUntil or nil)
end

-- O servidor não mexe no Enabled dos botões "JoiaPrompt" (o cliente esconde de quem não é de
-- gangue): marca o atributo "Ativo" e o cliente junta as duas coisas.
local function setActive(prompt, on)
	if prompt then
		prompt:SetAttribute("Ativo", on == true)
	end
end

local function caseOpen(c)
	if state ~= "assalto" or c.broken or not heist then
		return false
	end
	if c.zone == "cofre" then
		return heist.vault == "aberto"
	end
	return c.zone == "salao" or heist.staffOpen == true
end

refreshPrompts = function()
	local open = state == "aberta"
	local h = state == "assalto" and heist
	setActive(prompts.recon, open)
	setActive(prompts.anuncio, open)
	setActive(prompts.duto, open)
	setActive(prompts.quadro, state ~= "fechada" and not camsCut)
	local manager
	for _, info in ipairs(npcs) do
		if info.role == "gerente" then
			manager = info
		end
	end
	setActive(prompts.cartao, h and not h.cardTaken and manager ~= nil and (manager.asleep or manager.surrendered))
	setActive(prompts.leitor, h and not h.staffOpen)
	setActive(prompts.forcarPorta, h and not h.staffOpen)
	setActive(prompts.gaveta, h and h.staffOpen and not h.codeKnown)
	setActive(prompts.terminal, h and h.staffOpen and not h.hackedAt)
	setActive(prompts.codigo, h and h.codeKnown and h.vault == "fechado")
	setActive(prompts.furar, h and h.staffOpen and h.vault == "fechado")
	for _, c in ipairs(cases) do
		setActive(c.glass:FindFirstChild("JoiaPrompt"), caseOpen(c))
	end
	store:SetAttribute("Estado", state)
end

---------------------------------------------------------------------------
-- Assalto
---------------------------------------------------------------------------

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

local function statusPayload(player)
	local now = os.clock()
	local h = heist
	local p = {
		state = state,
		left = casesLeft(),
		total = #cases,
		cams = not camsOff(),
	}
	if not h then
		return p
	end
	p.approach = h.approach
	p.alarm = h.alarmed or false
	p.lockIn = h.lockAt and not h.locked and math.max(0, h.lockAt - now) or nil
	p.locked = h.locked or false
	p.noise = (h.approach == "silencioso" and not h.alarmed) and math.floor(h.noise) or nil
	p.gasIn = (h.gasEnds and not h.alarmed) and math.max(0, h.gasEnds - now) or nil
	p.guard = h.guard
	p.guardIn = (h.guard == "alerta" and h.guardDeadline) and math.max(0, h.guardDeadline - now) or nil
	p.card = h.staffOpen and "aberta" or (h.cardTaken and (player and player:GetAttribute("CartaoJoalheria") and "seu" or "pego") or "gerente")
	p.code = h.codeKnown and h.code or nil
	p.hackIn = hacked() and math.max(0, h.hackedUntil - now) or nil
	p.hackedAt = h.hackedAt ~= nil
	p.vault = h.vault
	p.drillIn = h.vault == "furando" and math.max(0, h.drillEnds - now) or nil
	p.exit = exitState()
	p.exitIn = p.exit == "destravada" and math.max(0, h.lockAt + J.ExitOverride - now) or nil
	p.events = events and events:list() or nil
	return p
end

local function sendStatus(extra)
	for _, p in ipairs(crewList()) do
		send(p, "JoiaStatus", statusPayload(p))
	end
	for _, p in ipairs(extra or {}) do
		send(p, "JoiaStatus", statusPayload(p))
	end
end

local function crewNotice(text, color)
	for _, p in ipairs(crewList()) do
		send(p, "JoiaAviso", { text = text, color = color })
	end
end

local function bagPayload(player)
	local b = bags[player]
	local now = os.clock()
	NPCKit.wearBag(player.Character, b and b.slots / J.BagSlots or 0) -- Marco 10.26: mochila nas costas
	return {
		value = b and b.value or 0,
		slots = b and b.slots or 0,
		max = J.BagSlots,
		count = b and b.count or 0,
		items = b and NPCKit.bagItems(b) or {},
		trackerIn = b and b.trackerEnds and math.max(0, b.trackerEnds - now) or nil,
		tracked = b and b.trackerEnds ~= nil and now < b.trackerEnds or false,
	}
end

local function points(n)
	return camsOff() and math.ceil(n / 2) or n
end

local function joinCrew(player)
	if heist and not heist.crew[player] then
		heist.crew[player] = true
		if heist.alarmed then
			CrimeService.addWanted(player, points(J.StartPoints))
		end
	end
end

local function startTracker(player, b)
	if b.trackerEnds then
		return
	end
	b.trackerEnds = os.clock() + J.TrackerTime
	player:SetAttribute("RastreadorJoias", true)
	send(player, "JoiaAviso", { text = ("📡 A bolsa tem RASTREADOR! A polícia vê você no mapa por %d s. Fuja e se esconda."):format(J.TrackerTime), color = "red" })
	send(player, "JoiaBolsa", bagPayload(player))
end

local function triggerAlarm(why)
	if not heist or heist.alarmed then
		return
	end
	heist.alarmed = true
	heist.lockAt = os.clock() + J.Lockdown
	local pos = store:GetPivot().Position
	CrimeService.alert("💎 Assalto à joalheria", J.Name, pos)
	for _, part in ipairs(store:GetChildren()) do
		if part.Name == "LuzAlarme" then
			CrimeService.blink(part)
		end
	end
	playSound(parts.anuncio, J.Sounds.Alarm, 0.7)
	for _, p in ipairs(crewList()) do
		CrimeService.addWanted(p, points(J.StartPoints))
		send(p, "JoiaAviso", { text = ("🚨 %s A polícia foi chamada. Porta de aço e saída trancam em %d s!"):format(why or "O alarme tocou!", J.Lockdown), color = "red" })
		-- quem já saiu com joias: a loja descobriu, o rastreador liga
		local b = bags[p]
		if b and b.left then
			startTracker(p, b)
		end
	end
	store:SetAttribute("Alarme", true)
	print("[JewelryService] Alarme da joalheria tocou: " .. tostring(why))
end

local function addNoise(amount)
	if not heist or heist.alarmed or heist.approach ~= "silencioso" then
		return
	end
	heist.noise = math.clamp(heist.noise + amount, 0, 100)
	if heist.noise >= 100 then
		triggerAlarm("Alguém ouviu o barulho! O alarme tocou.")
	end
end

local function startHeist(player, approach)
	if state ~= "aberta" then
		return
	end
	state = "assalto"
	heist = {
		approach = approach,
		started = os.clock(),
		crew = {},
		gang = player:GetAttribute("Gang"),
		lastCrewInside = os.clock(),
		noise = 0,
		code = ("%04d"):format(rng:NextInteger(0, 9999)),
		vault = "fechado",
	}
	heist.crew[player] = true
	if approach == "barulhento" then
		heist.guard = "alerta"
		heist.guardDeadline = os.clock() + J.GuardReact
		triggerAlarm("Assalto anunciado!")
		for _, info in ipairs(npcs) do
			if info.role ~= "seguranca" then
				surrender(info)
			elseif info.npc and info.npc.Parent then
				NPCKit.say(info.npc, "Ninguém se mexe!", 3)
				NPCKit.emote(info.npc, "point")
			end
		end
		send(player, "JoiaAviso", { text = ("🔫 MIRE NO SEGURANÇA para render ele (%d s), senão ele aperta o botão de pânico!"):format(J.GuardReact), color = "red" })
	else
		heist.guard = "dormindo"
		heist.gasEnds = os.clock() + J.GasDuration
		local smoke = parts.gas and parts.gas:FindFirstChild("Fumaca")
		if smoke then
			smoke.Enabled = true
			task.delay(9, function()
				smoke.Enabled = false
			end)
		end
		playSound(parts.gas, J.Sounds.Gas, 0.6)
		sleepNpcs()
	end
	if events then
		events:reset()
		events:roll("assalto")
	end
	refreshPrompts()
	sendStatus()
	print(("[JewelryService] %s começou o assalto à joalheria (%s)."):format(player.Name, approach))
end

local function clearCards()
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("CartaoJoalheria") then
			p:SetAttribute("CartaoJoalheria", nil)
		end
	end
end

local function finishSession(player, ok, why)
	local s = sessions[player]
	if not s then
		return
	end
	sessions[player] = nil
	if s.tool then
		s.tool:Destroy()
	end
	send(player, "JoiaMinigameFim", { id = s.id, ok = ok == true, why = why })
	if ok and s.onDone then
		s.onDone()
	end
end

local function closeStore(reason)
	if state == "fechada" then
		return
	end
	local crew = crewList()
	if events then
		events:reset()
	end
	state = "fechada"
	closedUntil = os.time() + J.Cooldown
	if not (heist and heist.locked) then
		setGrade(true)
	end
	setClosedSign(true)
	heist = nil
	for p in pairs(sessions) do
		finishSession(p, false)
	end
	clearCards()
	showLasers(false)
	refreshPrompts()
	showCameras()
	showExit()
	for _, p in ipairs(crew) do
		send(p, "JoiaStatus", statusPayload(p))
		if reason then
			send(p, "JoiaAviso", { text = reason })
		end
	end
	print("[JewelryService] Joalheria fechada para perícia.")
end

local function reopenStore()
	state = "aberta"
	heist = nil
	restoreCases()
	setGrade(false, true)
	setStaffDoor(false, true)
	setVault(false, true)
	showLasers(true)
	setText(parts.terminal, "🔒 SISTEMA\nOpala Sec 3.1", Color3.fromRGB(120, 200, 255))
	setCameras(true)
	setClosedSign(false)
	showExit()
	store:SetAttribute("Alarme", nil)
	spawnNpcs()
	refreshPrompts()
	print("[JewelryService] Joalheria aberta de novo.")
end

local function weightSpeed(b)
	return math.max(8, GameConfig.WalkSpeed - (b and b.slots or 0) * J.SlowPerSlot)
end

local function applyWeight(player, b)
	local _, humanoid = SecurityService.getLivingCharacter(player)
	if not humanoid or humanoid.SeatPart then
		return
	end
	local target = b and weightSpeed(b) or GameConfig.WalkSpeed
	local current = humanoid.WalkSpeed
	-- só mexe na velocidade normal (ou na que a bolsa colocou): bike e outros sistemas ficam como estão
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

local takeLoot
takeLoot = function(player, c)
	if not caseOpen(c) then
		return
	end
	local loot = J.Loot[c.kind] or J.Loot.aneis
	local slots = loot.Slots or 1
	local bag = bags[player] or { value = 0, slots = 0, count = 0 }
	-- Marco 10.26: abriu e não cabe? mostra o que achou e oferece trocar pelo que vale menos
	c.rolled = c.rolled or rng:NextInteger(loot.Value[1], loot.Value[2])
	if bag.slots + slots > J.BagSlots then
		local drop, dropValue = NPCKit.bagCheapest(bag, slots, J.BagSlots)
		if drop then
			local names = {}
			for _, it in ipairs(drop) do
				table.insert(names, it.name)
			end
			pending[player] = { drop = drop, accept = function()
				takeLoot(player, c)
			end }
			return send(player, "JoiaAchado", { name = loot.Name, value = c.fake and math.floor(c.rolled * 0.1) or c.rolled, slots = slots, drop = names, dropValue = dropValue })
		end
		return send(player, "JoiaAviso", { text = "🎒 Sua bolsa está cheia! Deixe o resto para a sua gangue." })
	end
	joinCrew(player)
	task.spawn(breakGlass, c)
	addNoise(c.noise)
	local value = c.rolled
	c.rolled = nil
	local lootName = loot.Name
	if c.fake then -- Marco 10.21: evento "Joia falsa"
		value = math.max(50, math.floor(value * ((J.Events.JoiaFalsa and J.Events.JoiaFalsa.Factor) or 0.08)))
		lootName = "Réplica (falsa)"
		send(player, "JoiaAviso", { text = "😬 Eram RÉPLICAS de vidro! Quase não valem nada. Deviam ter usado a lupa...", color = "red" })
	end
	NPCKit.bagItems(bag)
	table.insert(bag.items, { name = lootName, value = value, slots = slots })
	bag.value += value
	bag.slots += slots
	bag.count += 1
	bags[player] = bag
	player:SetAttribute("JoiasNaBolsa", bag.value)
	applyWeight(player, bag)
	CrimeService.addWanted(player, points(J.CasePoints))
	send(player, "JoiaBolsa", bagPayload(player))
	NPCKit.pose(player.Character, "pegar", (J.GrabAnim or {}).Length or 3.5) -- Marco 10.31: todo mundo vê
	send(player, "JoiaPegou", { name = lootName, value = value, diamond = c.kind == "diamante" and not c.fake, big = (loot.Slots or 1) >= 2, at = c.glass.Position })
	sendStatus()
	if casesLeft() == 0 then
		crewNotice("💎 Limparam a loja! Agora FUJAM!")
	end
end

-- Marco 10.20: peça de evento (tiara, maleta) direto na bolsa. Devolve false se não coube.
local function addBagItem(player, name, value, slots, at, big)
	local bag = bags[player] or { value = 0, slots = 0, count = 0 }
	if bag.slots + slots > J.BagSlots then
		send(player, "JoiaAviso", { text = ("🎒 Não cabe! %s ocupa %d espaço(s)."):format(name, slots) })
		return false
	end
	joinCrew(player)
	NPCKit.bagItems(bag)
	table.insert(bag.items, { name = name, value = value, slots = slots })
	bag.value += value
	bag.slots += slots
	bag.count += 1
	bags[player] = bag
	player:SetAttribute("JoiasNaBolsa", bag.value)
	applyWeight(player, bag)
	CrimeService.addWanted(player, points(J.CasePoints))
	send(player, "JoiaBolsa", bagPayload(player))
	NPCKit.pose(player.Character, "pegar", (J.GrabAnim or {}).Length or 3.5) -- Marco 10.31: todo mundo vê
	send(player, "JoiaPegou", { name = name, value = value, diamond = false, big = big or slots >= 2, at = at })
	sendStatus()
	return true
end

-- Minigame: o servidor abre a sessão; o cliente manda cada aperto (acertou ou não). O servidor
-- confere o ritmo, a distância, o número de erros e um tempo mínimo.
local function startMinigame(player, key, part, title, extraHits, onDone, onMiss)
	if sessions[player] then
		return
	end
	-- Marco 10.20: key pode ser a própria regra ({ Hits, Zone, Speed }): banco e eventos usam assim
	local def = type(key) == "table" and key or MG[key]
	if not def then
		return
	end
	if type(key) == "table" then
		key = "externo"
	end
	sessionId += 1
	local s = {
		id = sessionId,
		key = key,
		part = part,
		hits = def.Hits + (extraHits or 0),
		done = 0,
		miss = 0,
		started = os.clock(),
		last = 0,
		onDone = onDone,
		onMiss = onMiss,
	}
	sessions[player] = s
	if def.Drill and player.Character then -- Marco 10.21: parafusadeira na mão enquanto arromba
		local ok, tool = pcall(NPCKit.drillInHand, player.Character)
		s.tool = ok and tool or nil
	end
	send(player, "JoiaMinigame", { id = s.id, title = title, hits = s.hits, zone = def.Zone, speed = def.Speed, maxMiss = MG.MaxMiss, key = key, type = def.Type, len = def.Len, time = def.Time })
end

local function miniHit(player, arg)
	local s = sessions[player]
	if not s or type(arg) ~= "table" or arg.id ~= s.id then
		return
	end
	local now = os.clock()
	if now - s.last < 0.15 then
		return
	end
	s.last = now
	local root = rootOf(player)
	if not root or not s.part.Parent or (root.Position - s.part.Position).Magnitude > 11 then
		return finishSession(player, false, "Você se afastou.")
	end
	if arg.hit == true then
		s.done += 1
		if s.done >= s.hits then
			if now - s.started < s.hits * 0.3 then
				return finishSession(player, false, "Rápido demais.")
			end
			finishSession(player, true)
		end
	else
		s.miss += 1
		if s.onMiss then
			pcall(s.onMiss, s.miss)
		elseif s.key == "terminal" then
			addNoise(J.Noise.Miss * 0.5)
		else
			addNoise(J.Noise.Miss)
		end
		if s.miss >= MG.MaxMiss then
			if s.key == "terminal" then
				addNoise(J.Noise.HackFail)
				send(player, "JoiaAviso", { text = "💻 O sistema bloqueou a senha! Tente de novo (o alerta subiu).", color = "red" })
			end
			finishSession(player, false, "Errou demais!")
		end
	end
end

local function smash(player, c)
	if not caseOpen(c) then
		return
	end
	local ok, why = canCrime(player)
	if not ok then
		return CrimeService.notice(player, why)
	end
	local root = rootOf(player)
	if not root or (root.Position - c.glass.Position).Magnitude > 9 then
		return
	end
	if c.zone == "cofre" and not inBox(parts.cofre, root.Position, 1) then
		return
	end
	if c.zone == "restrita" and not inRestricted(root.Position) then
		return
	end
	local loot = J.Loot[c.kind] or J.Loot.aneis
	-- Marco 10.26: mesmo com a bolsa cheia dá para abrir: se valer a pena, troca (takeLoot oferece)
	joinCrew(player)
	local extra = (c.mini == "vitrine" and not hasGun(player)) and MG.NoGunHits or 0
	startMinigame(player, c.mini, c.glass, (CASE_ACTION[c.mini] or "Quebrar") .. " • " .. loot.Name, extra, function()
		takeLoot(player, c)
	end)
end

-- Marco 10.26: largar uma peça da mochila. Fica no chão e qualquer um pega de novo (a PM recolhe).
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
	if b.slots <= 0 then
		bags[player] = nil
	end
	player:SetAttribute("JoiasNaBolsa", b.slots > 0 and b.value or nil)
	applyWeight(player, bags[player])
	send(player, "JoiaBolsa", bagPayload(player))
	sendStatus()
	local gem = Instance.new("Part")
	gem.Name = "JoiaNoChao"
	gem.Shape = Enum.PartType.Ball
	gem.Size = Vector3.new(1.2, 1.2, 1.2)
	gem.Color = Color3.fromRGB(150, 220, 255)
	gem.Material = Enum.Material.Neon
	gem.Anchored = true
	gem.CanCollide = false
	gem.Position = root.Position + root.CFrame.LookVector * 3 - Vector3.new(0, 2, 0)
	gem.Parent = store
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "JoiaSolta"
	prompt.ActionText = "Pegar " .. it.name
	prompt.ObjectText = money(it.value)
	prompt.HoldDuration = 0.5
	prompt.RequiresLineOfSight = false
	prompt.Parent = gem
	prompt.Triggered:Connect(function(who)
		if not gem.Parent then
			return
		end
		if CrimeService.isPolice(who) then
			gem:Destroy()
		elseif canCrime(who) and addBagItem(who, it.name, it.value, it.slots, gem.Position) then
			gem:Destroy()
		end
	end)
	task.delay(J.DropLife or 120, function()
		if gem.Parent then
			gem:Destroy()
		end
	end)
end

local function loseBag(player, text)
	local b = bags[player]
	if not b then
		return
	end
	bags[player] = nil
	player:SetAttribute("JoiasNaBolsa", nil)
	player:SetAttribute("RastreadorJoias", nil)
	applyWeight(player, nil)
	send(player, "JoiaBolsa", bagPayload(player))
	if text then
		send(player, "JoiaAviso", { text = text, color = "red" })
	end
end

---------------------------------------------------------------------------
-- Área restrita: cartão, porta, código, terminal, cofre
---------------------------------------------------------------------------

local function insideRestrictedOrDoor(player, part, dist)
	local root = rootOf(player)
	return root ~= nil and part ~= nil and (root.Position - part.Position).Magnitude <= (dist or 10)
end

takeCard = function(player, info)
	local h = heist
	if state ~= "assalto" or not h or h.cardTaken then
		return
	end
	local ok, why = canCrime(player)
	if not ok then
		return CrimeService.notice(player, why)
	end
	if not (info.asleep or info.surrendered) then
		return send(player, "JoiaAviso", { text = "O gerente precisa estar dormindo ou rendido." })
	end
	local root, nroot = rootOf(player), npcRoot(info)
	if not root or not nroot or (root.Position - nroot.Position).Magnitude > 9 then
		return
	end
	joinCrew(player)
	h.cardTaken = true
	player:SetAttribute("CartaoJoalheria", true)
	send(player, "JoiaAviso", { text = "🔑 Você pegou o cartão do gerente! Passe no leitor da porta dos funcionários (parede do lado esquerdo do salão)." })
	refreshPrompts()
	sendStatus()
end

local function openStaffDoor(player, how)
	local h = heist
	if not h or h.staffOpen then
		return
	end
	joinCrew(player)
	h.staffOpen = true
	setStaffDoor(true)
	crewNotice(how == "cartao" and "🚪 Porta dos funcionários aberta. Lá dentro: escritório, sala de segurança, estoque e o COFRE." or "🚪 Vocês arrombaram a porta dos funcionários!")
	refreshPrompts()
	sendStatus()
end

local function openVault(player, how)
	local h = heist
	if not h or h.vault == "aberto" then
		return
	end
	h.vault = "aberto"
	setVault(true)
	setText(parts.painelCofre, "✅\n" .. h.code, Color3.fromRGB(90, 255, 140))
	crewNotice(how == "furadeira" and "🏦 A furadeira abriu o cofre!" or "🏦 Código certo: o cofre está abrindo! Cuidado com os LASERS (pisca-pisca).")
	if player then
		joinCrew(player)
	end
	refreshPrompts()
	sendStatus()
end

local function hackDone(player)
	local h = heist
	if not h or h.hackedAt then
		return
	end
	h.hackedAt = os.clock()
	h.hackedUntil = os.clock() + J.HackTime
	h.codeKnown = true
	showCameras()
	setText(parts.terminal, "✅ ACESSO LIBERADO\nCâmeras/lasers OFF", Color3.fromRGB(90, 255, 140))
	for _, p in ipairs(crewList()) do
		send(p, "JoiaAviso", { text = ("💻 Hackeado! Código do cofre: %s. Câmeras e lasers desligados por %d s, e a saída de emergência fica destravada %d s depois do lockdown."):format(h.code, J.HackTime, J.ExitOverride) })
	end
	refreshPrompts()
	sendStatus()
end

---------------------------------------------------------------------------
-- Reconhecimento
---------------------------------------------------------------------------

local function startRecon(player)
	local ok, why = canCrime(player)
	if not ok then
		return CrimeService.notice(player, why)
	end
	if state ~= "aberta" then
		return CrimeService.notice(player, "A loja não está aberta.")
	end
	local gang = player:GetAttribute("Gang")
	if reconByGang[gang] and os.time() < reconByGang[gang] then
		return send(player, "JoiaAviso", { text = ("✅ Sua gangue já fez o reconhecimento. O plano silencioso vale por mais %d min."):format(math.ceil((reconByGang[gang] - os.time()) / 60)) })
	end
	reconActive[player] = { started = os.clock(), found = {}, last = 0 }
	local list = {}
	for _, name in ipairs(ALVOS) do
		table.insert(list, { id = name, name = ALVO_NOMES[name] })
	end
	send(player, "JoiaRecon", { alvos = list, time = J.ReconTime })
end

local function spot(player, alvo)
	local r = reconActive[player]
	local part = type(alvo) == "string" and alvos[alvo]
	if not r or not part or r.found[alvo] then
		return
	end
	if os.clock() - r.last < 0.6 then
		return
	end
	local root = rootOf(player)
	if not root or (root.Position - part.Position).Magnitude > 75 then
		return
	end
	r.last = os.clock()
	r.found[alvo] = true
	local n = 0
	for _ in pairs(r.found) do
		n += 1
	end
	send(player, "JoiaReconAchou", { id = alvo, name = ALVO_NOMES[alvo], n = n, total = #ALVOS })
	if n >= #ALVOS then
		reconActive[player] = nil
		local gang = player:GetAttribute("Gang")
		if gang then
			reconByGang[gang] = os.time() + J.ReconValid
			for _, p in ipairs(Players:GetPlayers()) do
				if p:GetAttribute("Gang") == gang then
					send(p, "JoiaReconFim", { ok = true, by = player.DisplayName, minutes = math.floor(J.ReconValid / 60) })
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Receptador (chefe da gangue compra as joias)
---------------------------------------------------------------------------

local function copNear(pos)
	for _, p in ipairs(Players:GetPlayers()) do
		if CrimeService.isPolice(p) then
			local r = rootOf(p)
			if r and (r.Position - pos).Magnitude <= J.EscapePoliceRadius then
				return true
			end
		end
	end
	return false
end

local function sell(player, gangId, chief)
	local b = bags[player]
	if not b then
		return CrimeService.notice(player, "Você não tem joias para vender.")
	end
	if player:GetAttribute("Gang") ~= gangId then
		return CrimeService.notice(player, "Esse chefe só compra joias da gangue dele.")
	end
	local root = rootOf(player)
	if not root or not chief.root or (root.Position - chief.root.Position).Magnitude > J.SellDistance then
		return
	end
	if CrimeService.isCuffed(player) or player:GetAttribute("Preso") then
		return
	end
	if b.trackerEnds and os.clock() < b.trackerEnds then
		NPCKit.say(chief.npc, "Tá maluco? Essa bolsa tem rastreador! Some daqui até ele apagar!", 4)
		return send(player, "JoiaAviso", { text = ("📡 O chefe não compra com o rastreador ligado (faltam %d s)."):format(math.ceil(b.trackerEnds - os.clock())), color = "red" })
	end
	if copNear(root.Position) then
		NPCKit.say(chief.npc, "Tem polícia na cola! Despista primeiro!", 4)
		return
	end
	bags[player] = nil
	player:SetAttribute("JoiasNaBolsa", nil)
	player:SetAttribute("RastreadorJoias", nil)
	applyWeight(player, nil)
	if not EconomyService.add(player, b.value, "Joias vendidas ao receptador") then
		-- não deu para pagar: devolve a bolsa
		bags[player] = b
		player:SetAttribute("JoiasNaBolsa", b.value)
		applyWeight(player, b)
		return
	end
	NPCKit.emote(chief.npc, "cheer")
	NPCKit.say(chief.npc, "Peças de primeira! Negócio fechado, " .. player.DisplayName .. ".", 4)
	send(player, "JoiaBolsa", bagPayload(player))
	send(player, "JoiaFuga", { value = b.value, count = b.count })
	print(("[JewelryService] %s vendeu %s em joias ao receptador."):format(player.Name, money(b.value)))
end

local function ensureFences()
	for gangId, chief in pairs(GangService.getChiefs()) do
		local root = chief.root
		if root and root.Parent and not root:FindFirstChild("JoiaReceptador") then
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "JoiaReceptador"
			prompt.ActionText = "Vender as joias"
			prompt.ObjectText = "Receptador"
			prompt.KeyboardKeyCode = Enum.KeyCode.F
			prompt.HoldDuration = 1.5
			prompt.MaxActivationDistance = 10
			prompt.RequiresLineOfSight = false
			prompt.UIOffset = Vector2.new(0, 70)
			prompt.Enabled = false -- o cliente liga para quem é da gangue e tem joias
			prompt:SetAttribute("Gang", gangId)
			prompt.Parent = root
			CollectionService:AddTag(prompt, "JoiaReceptador")
			prompt.Triggered:Connect(function(player)
				if SecurityService.checkRate(player, "JoiaVender", 1) then
					sell(player, gangId, chief)
				end
			end)
		end
	end
end

---------------------------------------------------------------------------
-- Botões (ProximityPrompt). "JoiaPrompt" só aparece para quem é de gangue (o cliente esconde);
-- "JoiaSaida" para todo mundo; "JoiaPolicia" só para a PM.
---------------------------------------------------------------------------

local function makePrompt(part, name, action, object, hold, dist, fn)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = action
	prompt.ObjectText = object or J.Name
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = hold or 0
	prompt.MaxActivationDistance = dist or 8
	prompt.RequiresLineOfSight = false
	if name == "JoiaPrompt" then
		prompt:SetAttribute("Ativo", false)
		prompt.Enabled = false -- o cliente liga para quem pode usar
	end
	prompt.Parent = part
	prompt.Triggered:Connect(function(player)
		if SecurityService.checkRate(player, "JoiaPrompt", 0.4) then
			fn(player)
		end
	end)
	return prompt
end

-- confere o básico das ações do assalto
local function heistAction(player, part, dist)
	if state ~= "assalto" or not heist then
		return false
	end
	local ok, why = canCrime(player)
	if not ok then
		CrimeService.notice(player, why)
		return false
	end
	return insideRestrictedOrDoor(player, part, dist)
end

local function setupPrompts()
	local recon = store:FindFirstChild("PontoReconhecimento")
	if recon then
		prompts.recon = makePrompt(recon, "JoiaPrompt", "Fazer reconhecimento", "Catálogo", 1, 7, startRecon)
	end
	local announce = parts.anuncio
	if announce then
		prompts.anuncio = makePrompt(announce, "JoiaPrompt", "Anunciar o assalto", "Arma na mão!", 1, 14, function(player)
			local ok, why = canCrime(player)
			if not ok then
				return CrimeService.notice(player, why)
			end
			if state ~= "aberta" then
				return
			end
			if not hasGun(player) then
				return send(player, "JoiaAviso", { text = "🔫 Pegue uma arma na mão para anunciar o assalto." })
			end
			if CrimeService.policeCount() < J.MinPolice then
				return send(player, "JoiaAviso", { text = ("Precisa de pelo menos %d policial(is) no servidor."):format(J.MinPolice) })
			end
			local root = rootOf(player)
			if root and inShowroom(root.Position) then
				startHeist(player, "barulhento")
			end
		end)
	end
	local duct = store:FindFirstChild("Duto")
	if duct then
		prompts.duto = makePrompt(duct, "JoiaPrompt", "Soltar gás do sono", "Duto de ventilação", J.GasTime, 7, function(player)
			local ok, why = canCrime(player)
			if not ok then
				return CrimeService.notice(player, why)
			end
			if state ~= "aberta" then
				return
			end
			local gang = player:GetAttribute("Gang")
			if not (reconByGang[gang] and os.time() < reconByGang[gang]) then
				return send(player, "JoiaAviso", { text = "📋 Sem reconhecimento não dá: faça o reconhecimento da loja antes (catálogo da entrada)." })
			end
			if CrimeService.policeCount() < J.MinPolice then
				return send(player, "JoiaAviso", { text = ("Precisa de pelo menos %d policial(is) no servidor."):format(J.MinPolice) })
			end
			local root = rootOf(player)
			if root and (root.Position - duct.Position).Magnitude <= 10 then
				startHeist(player, "silencioso")
				send(player, "JoiaAviso", { text = ("💨 Gás solto! Os funcionários dormem por %d s. Rápido e sem barulho!"):format(J.GasDuration) })
			end
		end)
	end
	local fuse = store:FindFirstChild("QuadroEnergia")
	if fuse then
		prompts.quadro = makePrompt(fuse, "JoiaPrompt", "Cortar as câmeras", "Quadro de energia", J.FuseTime, 7, function(player)
			local ok, why = canCrime(player)
			if not ok then
				return CrimeService.notice(player, why)
			end
			if state == "fechada" or camsCut then
				return
			end
			local root = rootOf(player)
			if root and (root.Position - fuse.Position).Magnitude <= 10 then
				setCameras(false)
				joinCrew(player)
				refreshPrompts()
				send(player, "JoiaAviso", { text = "📷 Câmeras desligadas: o alerta não sobe por câmera e são menos estrelas de procurado." })
				sendStatus({ player })
			end
		end)
	end
	-- área restrita
	if parts.leitor then
		prompts.leitor = makePrompt(parts.leitor, "JoiaPrompt", "Passar o cartão", "Porta dos funcionários", 0.5, 7, function(player)
			if not heistAction(player, parts.leitor, 9) then
				return
			end
			if not player:GetAttribute("CartaoJoalheria") then
				return send(player, "JoiaAviso", { text = "🔑 Precisa do cartão do gerente (pegue com ele dormindo ou rendido), ou arrombe a porta." })
			end
			openStaffDoor(player, "cartao")
		end)
	end
	if parts.portaFunc then
		prompts.forcarPorta = makePrompt(parts.portaFunc, "JoiaPrompt", "Arrombar a porta (barulho!)", "Porta dos funcionários", J.DoorForceTime, 7, function(player)
			if not heistAction(player, parts.portaFunc, 9) then
				return
			end
			addNoise(J.Noise.ForcePerSec * J.DoorForceTime)
			openStaffDoor(player, "forca")
		end)
	end
	if parts.portaFunc then
		-- Marco 10.15: a PM abre a porta dos funcionários normalmente (sem barulho, sem arrombar)
		makePrompt(parts.portaFunc, "JoiaPolicia", "Abrir (acesso da PM)", "Porta dos funcionários", J.PoliceDoorTime or 0.6, 7, function(player)
			local h = heist
			if not CrimeService.isPolice(player) or not h or h.staffOpen then
				return
			end
			local root = rootOf(player)
			if not root or (root.Position - parts.portaFunc.Position).Magnitude > 10 then
				return
			end
			h.staffOpen = true
			setStaffDoor(true)
			crewNotice("🚔 A polícia abriu a porta dos funcionários!")
			refreshPrompts()
			sendStatus()
		end)
	end
	if parts.gaveta then
		prompts.gaveta = makePrompt(parts.gaveta, "JoiaPrompt", "Procurar o código do cofre", "Gaveta do gerente", J.OfficeTime, 6, function(player)
			if not heistAction(player, parts.gaveta, 8) or not heist.staffOpen or heist.codeKnown then
				return
			end
			joinCrew(player)
			heist.codeKnown = true
			crewNotice(("📝 Achou um papelzinho na gaveta: código do cofre %s!"):format(heist.code))
			refreshPrompts()
			sendStatus()
		end)
	end
	if parts.terminal then
		prompts.terminal = makePrompt(parts.terminal, "JoiaPrompt", "Hackear o sistema", "Terminal da segurança", 0.4, 7, function(player)
			if not heistAction(player, parts.terminal, 9) or not heist.staffOpen or heist.hackedAt then
				return
			end
			joinCrew(player)
			startMinigame(player, "terminal", parts.terminal, "Hackear o sistema • acerte a senha", 0, function()
				hackDone(player)
			end)
		end)
	end
	if parts.painelCofre then
		prompts.codigo = makePrompt(parts.painelCofre, "JoiaPrompt", "Digitar o código", "Cofre", J.VaultOpenTime, 7, function(player)
			if not heistAction(player, parts.painelCofre, 9) or not heist.codeKnown or heist.vault ~= "fechado" then
				return
			end
			openVault(player, "codigo")
		end)
	end
	if parts.portaCofre then
		prompts.furar = makePrompt(parts.portaCofre, "JoiaPrompt", "Furar o cofre (alarme!)", "Furadeira", 3, 8, function(player)
			if not heistAction(player, parts.portaCofre, 10) or heist.vault ~= "fechado" or not heist.staffOpen then
				return
			end
			joinCrew(player)
			heist.vault = "furando"
			heist.drillEnds = os.clock() + J.VaultDrill
			triggerAlarm("A furadeira disparou o alarme do cofre!")
			local fx = Instance.new("ParticleEmitter")
			fx.Name = "Faiscas"
			fx.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			fx.Color = ColorSequence.new(Color3.fromRGB(255, 200, 80))
			fx.Size = NumberSequence.new(0.3, 0)
			fx.Speed = NumberRange.new(8, 14)
			fx.Lifetime = NumberRange.new(0.2, 0.4)
			fx.SpreadAngle = Vector2.new(40, 40)
			fx.Rate = 60
			fx.LightEmission = 1
			fx.Parent = parts.volante or parts.portaCofre
			Debris:AddItem(fx, J.VaultDrill)
			playSound(parts.portaCofre, J.Sounds.Drill, 0.8, J.VaultDrill)
			refreshPrompts()
			sendStatus()
		end)
	end
	for _, c in ipairs(cases) do
		local loot = J.Loot[c.kind] or {}
		local action = CASE_ACTION[c.mini] or "Quebrar"
		if c.mini == "gaveta" then
			action = c.kind == "ouro" and "Arrombar a gaveta" or "Abrir a caixa"
		end
		local prompt = makePrompt(c.glass, "JoiaPrompt", action, loot.Name, 0.3, 6, function(player)
			smash(player, c)
		end)
		prompt:SetAttribute("Vitrine", c.kind)
	end
	local bar = parts.barra
	if bar then
		prompts.saida = makePrompt(bar, "JoiaSaida", "Abrir saída", "Saída de emergência", 0.3, 6, function(player)
			local root = rootOf(player)
			if not root or not inShowroom(root.Position) then
				return
			end
			if exitState() == "trancada" then
				-- só chega aqui depois de segurar ExitForceTime s
				heist.exitForced = true
				if not heist.exitAlerted then
					heist.exitAlerted = true
					CrimeService.alert("🚪 Saída da joalheria forçada", J.Name, bar.Position)
				end
				crewNotice("🚪 A trava da saída de emergência cedeu!")
				showExit()
			end
			openEmergency(6)
		end)
	end
	local outside = store:FindFirstChild("PortaFora")
	if outside then
		-- Marco 10.15 (pedido do Luís): policial não arromba, entra pela porta com o acesso da PM.
		-- Arrombar é coisa de bandido.
		makePrompt(outside, "JoiaPolicia", "Entrar (acesso da PM)", "Saída de emergência", J.PoliceDoorTime or 0.6, 7, function(player)
			if not CrimeService.isPolice(player) then
				return
			end
			local root = rootOf(player)
			if root and (root.Position - outside.Position).Magnitude <= 10 then
				openEmergency(8)
			end
		end)
	end
end

---------------------------------------------------------------------------
-- Relógio rápido (0,1 s): lasers e mira nos funcionários
---------------------------------------------------------------------------

local function laserStep(now)
	local h = heist
	local active = state == "assalto" and h and h.vault == "aberto" and not hacked() and not blackout()
	if not active then
		showLasers(state ~= "fechada" and not hacked() and not blackout())
		return
	end
	lasersShown = nil
	for i, l in ipairs(lasers) do
		local t = LASER_TIMING[((i - 1) % #LASER_TIMING) + 1]
		local on = ((now + t[3]) % t[1]) < t[1] * t[2]
		if on ~= l.on then
			l.on = on
			for _, b in ipairs(l.beams) do
				b.Transparency = on and 0.15 or 1
			end
		end
		if on and not h.alarmed then
			for _, p in ipairs(Players:GetPlayers()) do
				local root = not CrimeService.isPolice(p) and rootOf(p)
				if root and inBox(l.box, root.Position, 0.15) then
					joinCrew(p)
					triggerAlarm("Alguém encostou no LASER do cofre!")
					break
				end
			end
		end
	end
end

-- Marco 10.24: tiro na direção de um NPC também o faz se render na hora
local function shotAtNpc(player, from, dir)
	if state ~= "assalto" or not heist or not canCrime(player) or not inStore(from) then
		return
	end
	for _, info in ipairs(npcs) do
		local nroot = not info.surrendered and not info.asleep and npcRoot(info)
		if nroot then
			local to = nroot.Position - from
			if to.Magnitude < 30 and dir:Dot(to.Unit) > 0.97 then
				joinCrew(player)
				surrender(info)
				refreshPrompts()
				sendStatus()
			end
		end
	end
end

local function aimStep(dt)
	local h = heist
	if state ~= "assalto" or not h then
		return
	end
	for _, p in ipairs(Players:GetPlayers()) do
		local root = hasGun(p) and canCrime(p) and rootOf(p)
		local best = 0
		if root and inStore(root.Position) then
			for _, info in ipairs(npcs) do
				local nroot = not info.surrendered and not info.asleep and npcRoot(info)
				if nroot then
					local d = (nroot.Position - root.Position).Magnitude
					-- Marco 10.24: a mira de verdade, não para onde o corpo está virado
					if d < 30 and WeaponService.isAimingAt(p, root, nroot.Position) then
						info.aim[p] = (info.aim[p] or 0) + dt
						best = math.max(best, info.aim[p] / J.AimTime)
						if info.aim[p] >= J.AimTime then
							joinCrew(p)
							surrender(info)
							refreshPrompts()
							sendStatus()
						end
					else
						info.aim[p] = 0
					end
				end
			end
		end
		p:SetAttribute("Rendendo", best > 0 and best < 1 and math.floor(best * 10) * 10 or nil)
	end
	-- segurança não rendido a tempo: botão de pânico
	if h.guard == "alerta" and h.guardDeadline and os.clock() >= h.guardDeadline then
		h.guard = "panico"
		for _, info in ipairs(npcs) do
			if info.role == "seguranca" and info.npc and info.npc.Parent then
				NPCKit.say(info.npc, "BOTÃO DE PÂNICO!", 3)
				NPCKit.emote(info.npc, "point")
			end
		end
		h.lockAt = math.min(h.lockAt or math.huge, os.clock() + J.PanicLockdown)
		for _, p in ipairs(crewList()) do
			CrimeService.addWanted(p, J.PanicPoints)
			send(p, "JoiaAviso", { text = ("🚨 O segurança apertou o BOTÃO DE PÂNICO! Tudo tranca em %d s!"):format(J.PanicLockdown), color = "red" })
		end
		sendStatus()
	end
end

---------------------------------------------------------------------------
-- Relógio (a cada 0,5 s)
---------------------------------------------------------------------------

local lastStatus = 0
local lastFence = 0
local function tick(dt)
	local now = os.clock()
	-- reconhecimento vencido
	for player, r in pairs(reconActive) do
		if not player.Parent then
			reconActive[player] = nil
		elseif now - r.started > J.ReconTime then
			reconActive[player] = nil
			send(player, "JoiaReconFim", { ok = false })
		end
	end
	-- minigames esquecidos
	for player, s in pairs(sessions) do
		if not player.Parent then
			if s.tool then
				s.tool:Destroy()
			end
			sessions[player] = nil
		elseif now - s.started > 60 then -- Marco 10.27: memória e fios com erro levam mais que a barra
			finishSession(player, false, "Demorou demais.")
		end
	end
	-- câmeras voltam sozinhas se ninguém assaltar
	if camsCut and state == "aberta" and now - camsCutAt > 360 then
		setCameras(true)
		refreshPrompts()
	end
	showCameras()
	showExit()
	if state == "assalto" and heist then
		local h = heist
		-- gás acabou: funcionários acordam
		if h.gasEnds and not h.alarmed and now >= h.gasEnds then
			wakeNpcs()
			h.guard = "acordado"
			triggerAlarm("Os funcionários ACORDARAM e chamaram a polícia!")
			refreshPrompts()
		end
		-- furadeira
		if h.vault == "furando" and now >= h.drillEnds then
			openVault(nil, "furadeira")
		end
		-- hack acabou
		if h.hackedUntil and not h.hackOver and now >= h.hackedUntil then
			h.hackOver = true
			setText(parts.terminal, "⚠️ SISTEMA\nreiniciado", Color3.fromRGB(255, 200, 80))
			crewNotice("💻 O sistema reiniciou: câmeras e lasers LIGADOS de novo!", "red")
		end
		-- lockdown: porta de aço e trava da saída
		if h.alarmed and not h.locked and h.lockAt and now >= h.lockAt then
			h.locked = true
			setGrade(true)
			local st = exitState()
			crewNotice(st == "destravada" and ("🔒 A porta de aço fechou! A saída de emergência ainda está destravada (hack) por %d s. CORRE!"):format(J.ExitOverride) or ("🔒 LOCKDOWN! A porta de aço fechou e a saída de emergência TRANCOU. Segure E nela por %d s para forçar."):format(J.ExitForceTime), "red")
		end
		if events then
			events:step(dt)
		end
		if h.approach == "barulhento" and now - (h.lastHands or 0) > 2.6 then
			h.lastHands = now
			handsUp()
		end
		-- quem está lá dentro + câmeras vendo (alerta)
		local inside = false
		for _, p in ipairs(crewList()) do
			local root = rootOf(p)
			if root and inStore(root.Position) then
				inside = true
				if not camsOff() and inShowroom(root.Position) then
					addNoise(J.Noise.CamPerSec * dt)
				end
			end
		end
		h.noise = math.max(0, h.noise - J.Noise.Decay * dt)
		if inside then
			h.lastCrewInside = now
		end
		local idle = now - h.lastCrewInside
		if casesLeft() == 0 and idle > 5 then
			closeStore("A loja fechou para a perícia.")
		elseif h.locked and now - h.lockAt > 120 then
			closeStore("A polícia isolou a loja.")
		elseif idle > 150 then
			closeStore("Vocês abandonaram o assalto: a loja fechou.")
		end
		if heist and now - lastStatus > 1 then
			lastStatus = now
			sendStatus()
		end
	elseif state == "fechada" and os.time() >= closedUntil then
		reopenStore()
	end
	-- fuga de quem está com joias na bolsa
	for player, b in pairs(bags) do
		if not player.Parent then
			bags[player] = nil
		elseif player:GetAttribute("Preso") then
			loseBag(player, "A polícia recuperou as joias.")
		else
			local root = rootOf(player)
			if not root then
				loseBag(player, "Você caiu e as joias se espalharam pelo chão.")
			else
				if not b.left and not inStore(root.Position) then
					b.left = true
					if heist and heist.alarmed and heist.crew[player] then
						startTracker(player, b)
					elseif heist and heist.crew[player] then
						send(player, "JoiaAviso", { text = "🤫 Ninguém viu nada (ainda)! Corra vender ao chefe da gangue ANTES do alarme tocar: se tocar, a bolsa liga o rastreador." })
					end
				end
				if b.trackerEnds and not b.trackerOff and now >= b.trackerEnds then
					b.trackerOff = true
					player:SetAttribute("RastreadorJoias", nil)
					send(player, "JoiaAviso", { text = "📡 O rastreador apagou! Leve as joias ao chefe da sua gangue (favela) e venda (F)." })
					send(player, "JoiaBolsa", bagPayload(player))
				end
				applyWeight(player, b)
				local near = copNear(root.Position)
				if b.copNear ~= near then
					b.copNear = near
					send(player, "JoiaPolicia", { near = near })
				end
			end
		end
	end
	if now - lastFence > 3 then
		lastFence = now
		ensureFences()
	end
end

---------------------------------------------------------------------------
-- Marco 10.20: EVENTOS da joalheria (motor HeistEvents; Chance/Cooldown em GameConfig.Jewelry.Events).
-- Todos funcionam com 1 jogador ou com a gangue.
---------------------------------------------------------------------------

local JE = J.Events or {}

local function eventNpc(cf, name, shirt, pants, role, outfit, title)
	local npc = NPCKit.spawn(cf, { name = name, anchored = true, important = true, shirt = shirt, pants = pants, showName = not outfit and not title, outfit = outfit, title = title })
	if not npc then
		return nil
	end
	local info = { npc = npc, role = role, aim = {}, home = npc:GetPivot(), event = true }
	table.insert(npcs, info)
	return info
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

-- anda em passinhos (para no meio se render)
local function walkTo(info, target, stopIf)
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

local function anchorPart(name, size, cf, color, material, extra)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = extra and extra.collide or false
	p.Transparency = extra and extra.transparency or 0
	p.Reflectance = extra and extra.reflectance or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = store
	return p
end

local storeLights -- luzes da loja (queda de energia)

-- Marco 10.21: ponto do chão no salão (coordenadas do lote da loja; o anúncio fica em (0, F + 3, -8))
local function floorAt(x, z, rotY)
	return parts.anuncio.CFrame * CFrame.new(x, -3, z + 8) * CFrame.Angles(0, rotY or 0, 0)
end

local function signText(part, face, str, color, bg)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = bg or Color3.new(0, 0, 0)
	label.BackgroundTransparency = bg and 0 or 1
	label.TextColor3 = color
	label.Font = Enum.Font.Garamond
	label.TextScaled = true
	label.Text = str
	label.Parent = gui
	return label
end

local function liveBadge(npc, text)
	local head = npc and npc:FindFirstChild("Head")
	if not head then
		return nil
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "Live"
	gui.Size = UDim2.fromOffset(170, 34)
	gui.StudsOffset = Vector3.new(0, 4.2, 0)
	gui.MaxDistance = 60
	gui.AlwaysOnTop = true
	gui.Parent = head
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(200, 30, 40)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = text
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label
	return label
end

local function removePiece(info, name)
	local folder = info and info.npc and info.npc:FindFirstChild("Uniforme")
	local piece = folder and folder:FindFirstChild(name)
	if piece then
		piece:Destroy()
	end
end

local JEWELRY_EVENTS = {
	{
		Id = "Apagao",
		Name = "Queda de energia",
		Icon = "🔌",
		Text = "A energia caiu! Câmeras e lasers apagados até o gerador ligar.",
		Phases = { assalto = true },
		Duration = JE.Apagao and JE.Apagao.Duration or 45,
		Start = function(_, ev)
			heist.blackoutUntil = ev.endsAt
			storeLights = {}
			for _, d in ipairs(store:GetDescendants()) do
				if (d:IsA("PointLight") or d:IsA("SurfaceLight") or d:IsA("SpotLight")) and d.Enabled then
					d.Enabled = false
					table.insert(storeLights, d)
				end
			end
			crewNotice(("🔌 QUEDA DE ENERGIA! Câmeras e lasers APAGADOS por %d s. Aproveita!"):format(math.floor(ev.endsAt - ev.started)), "red")
		end,
		Hint = function(_, ev)
			return ("Câmeras e lasers desligados (%d s)"):format(math.ceil(ev.endsAt - os.clock()))
		end,
		Stop = function(_, _, reason)
			for _, l in ipairs(storeLights or {}) do
				if l.Parent then
					l.Enabled = true
				end
			end
			storeLights = nil
			if heist then
				heist.blackoutUntil = nil
			end
			if reason == "tempo" then
				crewNotice("💡 O gerador ligou: câmeras e lasers de volta!", "red")
			end
		end,
	},
	{
		Id = "Tiara",
		Name = "Lançamento: Tiara Real",
		Icon = "👑",
		Text = "Peça do lançamento no meio da loja, num pedestal com SENSOR DE PESO.",
		Phases = { assalto = true },
		Requires = function()
			return parts.anuncio ~= nil
		end,
		Start = function(_, ev)
			local base = parts.anuncio.CFrame * CFrame.new(0, -3, 16.5)
			local d = ev.data
			d.ped = anchorPart("PedestalTiara", Vector3.new(2.6, 3.4, 2.6), base * CFrame.new(0, 1.7, 0), Color3.fromRGB(240, 240, 244), Enum.Material.Marble, { collide = true })
			d.plate = anchorPart("SensorPeso", Vector3.new(2.2, 0.1, 2.2), base * CFrame.new(0, 3.45, 0), Color3.fromRGB(255, 60, 60), Enum.Material.Neon)
			d.tiara = anchorPart("Tiara", Vector3.new(1.6, 0.8, 1.6), base * CFrame.new(0, 3.9, 0), Color3.fromRGB(235, 200, 110), Enum.Material.Metal, { reflectance = 0.35 })
			d.glow = Instance.new("PointLight")
			d.glow.Range = 10
			d.glow.Color = Color3.fromRGB(255, 220, 160)
			d.glow.Parent = d.tiara
			local function take(player)
				local cfg = JE.Tiara or {}
				local v = cfg.Value or { 14000, 18000 }
				if addBagItem(player, "Tiara Real", rng:NextInteger(v[1], v[2]), cfg.Slots or 2, d.tiara.Position, true) then
					d.taken = true
					d.tiara.Transparency = 1
					d.glow.Enabled = false
					ev.finished = true
				end
			end
			-- 2 jogadores: um segura o sensor, o outro pega
			d.hold = makePrompt(d.ped, "JoiaPrompt", "Segurar o sensor", "Tiara Real", 0.6, 8, function(player)
				if heistAction(player, d.ped, 9) then
					d.holder, d.holdUntil = player, os.clock() + 8
					joinCrew(player)
					send(player, "JoiaAviso", { text = "✋ Segurando o sensor por 8 s: alguém da gangue pega a tiara AGORA!" })
					crewNotice(("✋ %s está segurando o sensor da tiara (8 s)!"):format(player.DisplayName))
				end
			end)
			d.grab = makePrompt(d.tiara, "JoiaPrompt", "Pegar a Tiara Real", "Sensor seguro", 1.2, 8, function(player)
				if d.taken or not heistAction(player, d.ped, 9) then
					return
				end
				if not (d.holder and d.holder ~= player and os.clock() < d.holdUntil) then
					return send(player, "JoiaAviso", { text = "⚠️ Alguém precisa segurar o sensor antes (ou troque por um saco de areia)." })
				end
				take(player)
			end)
			-- sozinho: troca pelo saco de areia (minigame difícil)
			d.swap = makePrompt(d.ped, "JoiaPrompt", "Trocar pelo saco de areia", "Sozinho", 0.5, 8, function(player)
				if d.taken or not heistAction(player, d.ped, 9) then
					return
				end
				startMinigame(player, J.EventMinigame.sacola, d.ped, "Trocar o peso • Tiara Real", 0, function()
					take(player)
				end, function()
					addNoise(15)
					if heist and heist.alarmed then
						CrimeService.addWanted(player, 2)
					end
				end)
			end)
			d.swap.UIOffset = Vector2.new(0, 60)
			crewNotice("👑 A TIARA REAL do lançamento está no pedestal do meio! Tem SENSOR DE PESO: um segura, o outro pega (ou troque por um saco de areia).")
		end,
		Step = function(_, ev)
			local d = ev.data
			local held = d.holder and os.clock() < (d.holdUntil or 0)
			if held then
				local root = rootOf(d.holder)
				if not root or (root.Position - d.ped.Position).Magnitude > 9 then
					held = false
					d.holder = nil
				end
			end
			setActive(d.hold, not d.taken and not held)
			setActive(d.grab, not d.taken and held)
			setActive(d.swap, not d.taken)
			d.plate.Color = held and Color3.fromRGB(60, 220, 90) or Color3.fromRGB(255, 60, 60)
		end,
		Hint = function(_, ev)
			return ev.data.taken and "Pega!" or "Um segura o sensor, o outro pega (ou saco de areia)"
		end,
		Stop = function(_, ev)
			for _, k in ipairs({ "ped", "plate", "tiara" }) do
				if ev.data[k] then
					ev.data[k]:Destroy()
				end
			end
		end,
	},
	{
		Id = "Malote",
		Name = "Entregador do carro-forte",
		Icon = "💼",
		Text = "Um entregador chegou com uma maleta de diamantes. Renda ele (mire) antes que vá embora!",
		Phases = { assalto = true },
		Requires = function()
			return parts.anuncio ~= nil
		end,
		Start = function(_, ev)
			local cfg = JE.Malote or {}
			local d = ev.data
			ev.endsAt = os.clock() + (cfg.Stay or 40)
			d.info = eventNpc(parts.anuncio.CFrame * CFrame.new(4, -3, -4), "Entregador Valdir", nil, nil, "entregador", "carroforte")
			if not d.info then
				error("sem NPC")
			end
			NPCKit.hold(d.info.npc, "Maleta", Vector3.new(1.6, 1.2, 0.4), Color3.fromRGB(30, 30, 34), Enum.Material.Metal)
			NPCKit.say(d.info.npc, "Entrega da LLC Valores... opa.", 4)
			local root = npcRoot(d.info)
			d.prompt = makePrompt(root, "JoiaPrompt", "Pegar a maleta", "Entregador rendido", 1, 7, function(player)
				if d.taken or not heistAction(player, root, 8) then
					return
				end
				local v = cfg.Value or { 10000, 14000 }
				if addBagItem(player, "Maleta de diamantes", rng:NextInteger(v[1], v[2]), cfg.Slots or 2, root.Position, true) then
					d.taken = true
					local case = d.info.npc:FindFirstChild("Maleta")
					if case then
						case:Destroy()
					end
					ev.finished = true
				end
			end)
			crewNotice("💼 Chegou um ENTREGADOR do carro-forte com uma maleta! Mire nele para render e pegue a maleta.")
		end,
		Step = function(_, ev)
			local d = ev.data
			setActive(d.prompt, not d.taken and d.info and d.info.surrendered == true)
		end,
		Hint = function(_, ev)
			return ev.data.info and ev.data.info.surrendered and "Rendido: pegue a maleta!" or "Mire nele para render"
		end,
		Stop = function(_, ev, reason)
			local d = ev.data
			if reason == "tempo" and not d.taken and d.info and not d.info.surrendered then
				crewNotice("💼 O entregador foi embora e viu tudo!", "red")
				addNoise(35)
			end
			local info = d.info
			task.delay(reason == "concluido" and 4 or 0, function()
				dropNpc(info)
			end)
		end,
	},
	{
		Id = "Corajoso",
		Name = "Cliente corajoso",
		Icon = "🏃",
		Text = "Um cliente escondido está correndo para a porta para chamar a polícia!",
		Phases = { assalto = true },
		Duration = 30,
		Requires = function()
			return heist and heist.approach == "barulhento" and store:FindFirstChild("PontoCliente") ~= nil and parts.grade ~= nil
		end,
		Start = function(_, ev)
			local d = ev.data
			d.wait = os.clock() + rng:NextNumber(6, 12)
		end,
		Step = function(_, ev)
			local d = ev.data
			local now = os.clock()
			if not d.info then
				if now < d.wait then
					return
				end
				local spot = store:FindFirstChild("PontoCliente")
				d.info = eventNpc(spot.CFrame * CFrame.new(-3, 0, 2), "Cliente", nil, nil, "corajoso")
				if not d.info then
					return true
				end
				NPCKit.say(d.info.npc, "Vou chamar a polícia!", 3)
				walkTo(d.info, parts.grade.Position, function()
					return d.info.surrendered
				end)
				crewNotice("🏃 Um CLIENTE CORAJOSO saiu do provador e está correndo para a porta! Mire nele!", "red")
				d.deadline = now + 14
				return
			end
			if d.info.surrendered then
				if not d.stopped then
					d.stopped = true
					NPCKit.say(d.info.npc, "Tá bom, tá bom! Fico quieto!", 3)
				end
				return now > d.deadline
			end
			local root = npcRoot(d.info)
			if not root or now > d.deadline or (root.Position - parts.grade.Position).Magnitude < 6 then
				d.escaped = true
				return true
			end
		end,
		Hint = function(_, ev)
			return ev.data.stopped and "Rendido" or "Mire no cliente antes da porta!"
		end,
		Stop = function(_, ev)
			local d = ev.data
			if d.escaped and heist then
				heist.lockAt = math.max(os.clock() + 5, (heist.lockAt or os.clock() + J.Lockdown) - 15)
				crewNotice("🏃 O cliente escapou e chamou a PM: a porta de aço vai fechar 15 s mais cedo!", "red")
				for _, p in ipairs(crewList()) do
					CrimeService.addWanted(p, 5)
				end
			end
			dropNpc(d.info)
		end,
	},
	{
		Id = "Leilao",
		Name = "Leilão VIP",
		Icon = "🔨",
		Text = "Leilão fechado para milionários no salão: o Colar Imperatriz na redoma, convidados cheios de joias e a caixa dos lances.",
		Phases = { assalto = true },
		Requires = function()
			return parts.anuncio ~= nil
		end,
		Start = function(_, ev)
			local cfg = JE.Leilao or {}
			local d = ev.data
			d.parts = {}
			local function deco(name, size, cf, color, material, extra)
				local p = anchorPart(name, size, cf, color, material, extra)
				table.insert(d.parts, p)
				return p
			end
			-- tapete, púlpito com placa, mesa da caixa e cordões de veludo
			deco("TapeteLeilao", Vector3.new(14, 0.06, 17), floorAt(20, 2.5) * CFrame.new(0, 0.03, 0), Color3.fromRGB(120, 20, 34), Enum.Material.Fabric)
			local pod = deco("Pulpito", Vector3.new(3.4, 4, 1.8), floorAt(20, 9) * CFrame.new(0, 2, 0), Color3.fromRGB(70, 40, 26), Enum.Material.Wood, { collide = true })
			deco("TampoPulpito", Vector3.new(3.8, 0.3, 2.2), pod.CFrame * CFrame.new(0, 2.15, 0), Color3.fromRGB(224, 178, 80), Enum.Material.Metal)
			signText(pod, Enum.NormalId.Front, "🔨 LEILÃO VIP", Color3.fromRGB(240, 210, 130))
			local banner = deco("FaixaLeilao", Vector3.new(12, 2.6, 0.2), floorAt(20, 12) * CFrame.new(0, 11, 0), Color3.fromRGB(20, 20, 24), Enum.Material.Fabric)
			signText(banner, Enum.NormalId.Front, "LEILÃO BENEFICENTE • COLAR IMPERATRIZ", Color3.fromRGB(240, 210, 130))
			for _, x in ipairs({ 13, 27 }) do
				for _, z in ipairs({ -5, 10 }) do
					deco("PosteVeludo", Vector3.new(0.4, 3, 0.4), floorAt(x, z) * CFrame.new(0, 1.5, 0), Color3.fromRGB(224, 178, 80), Enum.Material.Metal)
				end
				deco("CordaoVeludo", Vector3.new(0.25, 0.25, 15), floorAt(x, 2.5) * CFrame.new(0, 2.6, 0), Color3.fromRGB(150, 20, 40), Enum.Material.Fabric)
			end
			local tbl = deco("MesaLances", Vector3.new(3, 3, 2), floorAt(25, 8) * CFrame.new(0, 1.5, 0), Color3.fromRGB(240, 240, 244), Enum.Material.Marble, { collide = true })
			d.cash = deco("CaixaLances", Vector3.new(1.8, 1, 1.2), tbl.CFrame * CFrame.new(0, 2, 0), Color3.fromRGB(110, 70, 40), Enum.Material.Wood)
			-- redoma com sensor e o colar
			local ped = deco("PedestalLeilao", Vector3.new(2.4, 3.4, 2.4), floorAt(15, 4) * CFrame.new(0, 1.7, 0), Color3.fromRGB(240, 240, 244), Enum.Material.Marble, { collide = true })
			d.ped = ped
			d.sensor = deco("SensorRedoma", Vector3.new(2.6, 0.12, 2.6), ped.CFrame * CFrame.new(0, 1.76, 0), Color3.fromRGB(255, 50, 50), Enum.Material.Neon)
			d.colar = deco("ColarImperatriz", Vector3.new(1.4, 0.5, 1.4), ped.CFrame * CFrame.new(0, 2.1, 0), Color3.fromRGB(235, 200, 110), Enum.Material.Metal, { reflectance = 0.35 })
			d.gem = deco("PedraColar", Vector3.new(0.6, 0.6, 0.6), ped.CFrame * CFrame.new(0, 2.6, -0.3), Color3.fromRGB(80, 200, 255), Enum.Material.Neon)
			d.dome = deco("Redoma", Vector3.new(3.2, 3.2, 3.2), ped.CFrame * CFrame.new(0, 1.8, 0), Color3.fromRGB(200, 225, 240), Enum.Material.SmoothPlastic, { transparency = 0.7, reflectance = 0.2 })
			d.dome.Shape = Enum.PartType.Ball
			local glow = Instance.new("PointLight")
			glow.Range = 12
			glow.Color = Color3.fromRGB(160, 220, 255)
			glow.Parent = d.gem
			-- leiloeiro e convidados (com taças de champanhe)
			d.lei = eventNpc(floorAt(20, 10.6), "Leiloeiro Afonso", nil, nil, "leiloeiro", "leiloeiro")
			if not d.lei then
				error("sem NPC")
			end
			NPCKit.hold(d.lei.npc, "Martelo", Vector3.new(0.3, 1.1, 0.3), Color3.fromRGB(70, 40, 26), Enum.Material.Wood)
			d.guests = {}
			for i, g in ipairs({ { 15.5, "Condessa Vera", "vipa" }, { 20, "Sr. Hugo Bastos", "vip" }, { 24.5, "Madame Lúcia", "vipa" } }) do
				local info = eventNpc(floorAt(g[1], -2.5, math.pi), g[2], nil, nil, "vip", g[3], "CONVIDADO VIP")
				if info then
					NPCKit.hold(info.npc, "Taca", Vector3.new(0.3, 0.9, 0.3), Color3.fromRGB(250, 236, 180), Enum.Material.SmoothPlastic)
					local root = npcRoot(info)
					local gd = { info = info }
					gd.prompt = makePrompt(root, "JoiaPrompt", "Pegar as joias", g[2], 1, 7, function(player)
						if gd.robbed or not info.surrendered or not heistAction(player, root, 8) then
							return
						end
						local v = cfg.Guest or { 2500, 4000 }
						if addBagItem(player, "Joias de " .. g[2], rng:NextInteger(v[1], v[2]), 1, root.Position, false) then
							gd.robbed = true
							removePiece(info, "Colar")
							NPCKit.say(info.npc, i == 2 and "Meu relógio suíço!" or "Meu colar de família!", 3)
						end
					end)
					table.insert(d.guests, gd)
				end
			end
			local leiRoot = npcRoot(d.lei)
			-- 1) render o leiloeiro e pegar o controle da redoma
			d.remotePrompt = makePrompt(leiRoot, "JoiaPrompt", "Pegar o controle da redoma", "Leiloeiro rendido", 1, 7, function(player)
				if d.remoteBy or not d.lei.surrendered or not heistAction(player, leiRoot, 8) then
					return
				end
				d.remoteBy = player
				joinCrew(player)
				send(player, "JoiaAviso", { text = "🎛️ Controle da redoma na mão! Vá até o pedestal e ABRA A REDOMA sem disparar o sensor." })
			end)
			local function openDome(loud)
				d.open = true
				d.dome.Transparency = 1
				d.dome.CanCollide = false
				d.sensor.Color = loud and Color3.fromRGB(255, 200, 40) or Color3.fromRGB(60, 220, 90)
			end
			-- 2a) abrir com o controle (silencioso)
			d.openPrompt = makePrompt(ped, "JoiaPrompt", "Abrir a redoma", "Com o controle", 1, 7, function(player)
				if d.open or player ~= d.remoteBy or not heistAction(player, ped, 8) then
					return
				end
				openDome(false)
				crewNotice("🔓 Redoma aberta pelo controle, sem disparar nada. Peguem o Colar Imperatriz!")
			end)
			-- 2b) quebrar no braço (barulho + porta tranca mais cedo)
			d.breakPrompt = makePrompt(ped, "JoiaPrompt", "Quebrar a redoma", "Dispara o sensor!", 3, 7, function(player)
				if d.open or not heistAction(player, ped, 8) then
					return
				end
				joinCrew(player)
				openDome(true)
				addNoise(cfg.BreakNoise or 45)
				if heist and heist.alarmed then
					heist.lockAt = math.max(os.clock() + 5, (heist.lockAt or os.clock() + J.Lockdown) - 10)
					crewNotice("💥 A redoma quebrou e o sensor disparou: a porta tranca 10 s mais cedo!", "red")
				else
					crewNotice("💥 A redoma quebrou! Muito barulho...", "red")
				end
			end)
			d.breakPrompt.UIOffset = Vector2.new(0, 60)
			-- 3) o colar
			d.grab = makePrompt(d.colar, "JoiaPrompt", "Pegar o Colar Imperatriz", "Peça do leilão", 1.2, 8, function(player)
				if d.taken or not d.open or not heistAction(player, ped, 9) then
					return
				end
				local v = cfg.Colar or { 16000, 22000 }
				if addBagItem(player, "Colar Imperatriz", rng:NextInteger(v[1], v[2]), 2, d.colar.Position, true) then
					d.taken = true
					d.colar.Transparency = 1
					d.gem.Transparency = 1
					glow.Enabled = false
					NPCKit.say(d.lei.npc, "Arrematado... pelo crime. Que vergonha.", 4)
				end
			end)
			-- caixa dos lances
			d.cashPrompt = makePrompt(d.cash, "JoiaPrompt", "Pegar a caixa dos lances", "Dinheiro dos lances", 1.5, 7, function(player)
				if d.cashTaken or not heistAction(player, d.cash, 8) then
					return
				end
				local v = cfg.Lances or { 6000, 9000 }
				if addBagItem(player, "Caixa dos lances", rng:NextInteger(v[1], v[2]), 1, d.cash.Position, false) then
					d.cashTaken = true
					d.cash.Transparency = 1
				end
			end)
			NPCKit.say(d.lei.npc, "Dou-lhe uma... dou-lhe duas... ISSO É UM ASSALTO?!", 4)
			crewNotice("🔨 LEILÃO VIP no salão (lado leste)! Render o LEILOEIRO dá o controle da REDOMA do Colar Imperatriz (ou quebrem na marra). Os CONVIDADOS têm joias e tem a CAIXA DOS LANCES.")
		end,
		Step = function(_, ev)
			local d = ev.data
			setActive(d.remotePrompt, not d.remoteBy and d.lei and d.lei.surrendered == true)
			setActive(d.openPrompt, not d.open and d.remoteBy ~= nil)
			setActive(d.breakPrompt, not d.open)
			setActive(d.grab, d.open and not d.taken)
			setActive(d.cashPrompt, not d.cashTaken)
			for _, gd in ipairs(d.guests or {}) do
				setActive(gd.prompt, not gd.robbed and gd.info.surrendered == true)
			end
			if d.taken and d.cashTaken then
				return true
			end
		end,
		Hint = function(_, ev)
			local d = ev.data
			if not d.open then
				return d.remoteBy and "Abra a redoma com o controle" or "Renda o leiloeiro (controle) ou quebre a redoma"
			end
			return d.taken and "Colar pego! Falta a caixa dos lances?" or "Redoma aberta: pegue o colar!"
		end,
		Stop = function(_, ev)
			local d = ev.data
			for _, p in ipairs(d.parts or {}) do
				p:Destroy()
			end
			local infos = { d.lei }
			for _, gd in ipairs(d.guests or {}) do
				table.insert(infos, gd.info)
			end
			task.delay(3, function()
				for _, info in ipairs(infos) do
					dropNpc(info)
				end
			end)
		end,
	},
	{
		Id = "JoiaFalsa",
		Name = "Joias falsas",
		Icon = "🔍",
		Text = "Dica do informante: uma das vitrines do salão só tem RÉPLICAS. Examine com a lupa antes de quebrar.",
		Phases = { assalto = true },
		Requires = function()
			local n = 0
			for _, c in ipairs(cases) do
				if c.zone == "salao" and not c.broken then
					n += 1
				end
			end
			return n >= 3
		end,
		Start = function(_, ev)
			local d = ev.data
			local pool = {}
			for _, c in ipairs(cases) do
				if c.zone == "salao" and not c.broken then
					table.insert(pool, c)
				end
			end
			d.fake = pool[rng:NextInteger(1, #pool)]
			d.fake.fake = true
			d.prompts = {}
			for _, c in ipairs(pool) do
				local pr = makePrompt(c.glass, "JoiaPrompt", "Examinar com a lupa", "Joias da vitrine", 1.2, 7, function(player)
					if c.broken or not heistAction(player, c.glass, 8) then
						return
					end
					joinCrew(player)
					if c.fake then
						d.found = true
						crewNotice(("🔍 %s olhou na lupa: essa vitrine é de RÉPLICAS! Nem percam tempo com ela."):format(player.DisplayName), "red")
					else
						send(player, "JoiaAviso", { text = "🔍 Na lupa: são VERDADEIRAS. Pode pegar!" })
					end
				end)
				pr.UIOffset = Vector2.new(0, 60)
				d.prompts[c] = pr
			end
			crewNotice("🔍 Dica do informante: UMA das vitrines do salão só tem RÉPLICAS de vidro. Examine com a lupa (segure E) antes de quebrar!")
		end,
		Step = function(_, ev)
			local d = ev.data
			for c, pr in pairs(d.prompts or {}) do
				setActive(pr, not c.broken)
			end
			if d.fake and d.fake.broken then
				return true
			end
		end,
		Hint = function(_, ev)
			return ev.data.found and "Achou a vitrine falsa!" or "Uma vitrine tem réplicas: use a lupa"
		end,
		Stop = function(_, ev)
			local d = ev.data
			for _, pr in pairs(d.prompts or {}) do
				pr:Destroy()
			end
			if d.fake then
				d.fake.fake = nil
			end
		end,
	},
	{
		Id = "Pedido",
		Name = "Pedido de casamento",
		Icon = "💍",
		Text = "Um cliente estava de joelhos pedindo a namorada em casamento quando vocês entraram.",
		Phases = { assalto = true },
		Requires = function()
			return parts.anuncio ~= nil
		end,
		Start = function(_, ev)
			local d = ev.data
			d.noivo = eventNpc(floorAt(-19, 3, math.rad(90)), "Rodrigo", Color3.fromRGB(30, 34, 60), Color3.fromRGB(26, 26, 32), "noivo", nil, "NOIVO")
			d.noiva = eventNpc(floorAt(-22.5, 3, math.rad(-90)), "Camila", Color3.fromRGB(240, 240, 250), Color3.fromRGB(240, 240, 250), "noiva", nil, "NOIVA")
			if not d.noivo or not d.noiva then
				error("sem NPC")
			end
			NPCKit.hold(d.noivo.npc, "CaixinhaAlianca", Vector3.new(0.6, 0.5, 0.6), Color3.fromRGB(150, 20, 40), Enum.Material.Fabric)
			NPCKit.emote(d.noivo.npc, "sit")
			NPCKit.say(d.noivo.npc, "Camila... você quer casar comigo?", 4)
			local root = npcRoot(d.noivo)
			d.steal = makePrompt(root, "JoiaPrompt", "Pegar a aliança", "Que maldade...", 1, 7, function(player)
				if d.decided or not d.noivo.surrendered or not heistAction(player, root, 8) then
					return
				end
				local v = (JE.Pedido and JE.Pedido.Value) or { 7000, 10000 }
				if addBagItem(player, "Aliança de diamante", rng:NextInteger(v[1], v[2]), 1, root.Position, false) then
					d.decided = "roubou"
					local box = d.noivo.npc:FindFirstChild("CaixinhaAlianca")
					if box then
						box:Destroy()
					end
					NPCKit.say(d.noiva.npc, "NÃÃÃO! Era o MEU anel!", 4)
					CrimeService.addWanted(player, 2)
					ev.finished = true
				end
			end)
			d.bless = makePrompt(root, "JoiaPrompt", "Deixar o pedido acontecer", "Ser legal", 1.5, 7, function(player)
				if d.decided or not heistAction(player, root, 8) then
					return
				end
				d.decided = "abencoou"
				joinCrew(player)
				NPCKit.emote(d.noiva.npc, "cheer")
				NPCKit.say(d.noiva.npc, "SIM! SIM! MIL VEZES SIM!", 4)
				NPCKit.say(d.noivo.npc, "Valeu, gente! A gente não viu NADA.", 4)
				local bonus = (JE.Pedido and JE.Pedido.Bonus) or 20
				if heist.alarmed then
					heist.lockAt = (heist.lockAt or os.clock()) + bonus
					crewNotice(("💍 Ela disse SIM! O casal promete não falar nada: a porta tranca %d s mais tarde."):format(bonus))
				else
					heist.noise = math.max(0, (heist.noise or 0) - 25)
					crewNotice("💍 Ela disse SIM! O casal ficou quietinho: o barulho baixou.")
				end
				ev.finished = true
			end)
			d.bless.UIOffset = Vector2.new(0, 60)
			crewNotice("💍 Um cliente estava PEDINDO A NAMORADA EM CASAMENTO! Renda o noivo e pegue a aliança de diamante... ou deixe o pedido acontecer (o casal fica do seu lado).")
		end,
		Step = function(_, ev)
			local d = ev.data
			setActive(d.steal, not d.decided and d.noivo and d.noivo.surrendered == true)
			setActive(d.bless, not d.decided)
		end,
		Hint = function(_, ev)
			return ev.data.decided and "Decidido" or "Roubar a aliança ou deixar o pedido?"
		end,
		Stop = function(_, ev, reason)
			local d = ev.data
			if reason == "tempo" and not d.decided then
				crewNotice("💍 O casal fugiu pela porta gritando por socorro!", "red")
				addNoise(20)
			end
			task.delay(reason == "concluido" and 5 or 0, function()
				dropNpc(d.noivo)
				dropNpc(d.noiva)
			end)
		end,
	},
	{
		Id = "Live",
		Name = "Influencer ao vivo",
		Icon = "📱",
		Text = "Uma influencer está fazendo LIVE dentro da loja. Quem aparecer na câmera fica mais procurado.",
		Phases = { assalto = true },
		Requires = function()
			return parts.anuncio ~= nil
		end,
		Start = function(_, ev)
			local d = ev.data
			d.info = eventNpc(floorAt(-14, -15, math.rad(160)), "Bella Brilho", Color3.fromRGB(240, 120, 190), Color3.fromRGB(240, 240, 250), "influencer", nil, "INFLUENCER")
			if not d.info then
				error("sem NPC")
			end
			NPCKit.hold(d.info.npc, "PauDeSelfie", Vector3.new(0.15, 2.6, 0.15), Color3.fromRGB(30, 30, 34), Enum.Material.Metal)
			d.viewers = 1200
			d.badge = liveBadge(d.info.npc, "🔴 AO VIVO • 1,2 mil")
			d.filmed = {}
			d.nextTick = os.clock() + 2
			NPCKit.say(d.info.npc, "GENTE! TÁ ROLANDO UM ASSALTO AO VIVO! Compartilha!", 4)
			local root = npcRoot(d.info)
			d.phone = makePrompt(root, "JoiaPrompt", "Pegar o celular", "Fim da live", 1, 7, function(player)
				if d.phoneTaken or not d.info.surrendered or not heistAction(player, root, 8) then
					return
				end
				local v = (JE.Live and JE.Live.Phone) or { 1500, 2500 }
				if addBagItem(player, "Celular da influencer", rng:NextInteger(v[1], v[2]), 1, root.Position, false) then
					d.phoneTaken = true
					local stick = d.info.npc:FindFirstChild("PauDeSelfie")
					if stick then
						stick:Destroy()
					end
					ev.finished = true
				end
			end)
			crewNotice("📱 Uma INFLUENCER está fazendo LIVE do assalto! Quem aparecer na câmera fica MAIS PROCURADO. Mire nela para encerrar a live e pegue o celular.", "red")
		end,
		Step = function(_, ev)
			local d = ev.data
			local now = os.clock()
			setActive(d.phone, not d.phoneTaken and d.info and d.info.surrendered == true)
			if d.info and d.info.surrendered then
				if d.badge and not d.ended then
					d.ended = true
					d.badge.BackgroundColor3 = Color3.fromRGB(40, 40, 44)
					d.badge.Text = "⚫ LIVE ENCERRADA"
				end
				return
			end
			if now < d.nextTick then
				return
			end
			d.nextTick = now + 2
			d.viewers += rng:NextInteger(600, 1800)
			if d.badge then
				d.badge.Text = ("🔴 AO VIVO • %.1f mil"):format(d.viewers / 1000):gsub("%.", ",")
			end
			local root = npcRoot(d.info)
			if not root then
				return
			end
			local range = (JE.Live and JE.Live.Range) or 24
			for _, p in ipairs(crewList()) do
				local r = rootOf(p)
				if r and (r.Position - root.Position).Magnitude < range and (d.filmed[p] or 0) < 6 then
					d.filmed[p] = (d.filmed[p] or 0) + 1
					CrimeService.addWanted(p, 1)
					if d.filmed[p] == 1 then
						send(p, "JoiaAviso", { text = "📱 Você apareceu na LIVE! Procurado subindo. Rende a influencer!", color = "red" })
					end
				end
			end
			addNoise(4)
		end,
		Hint = function(_, ev)
			return ev.data.ended and "Live encerrada: pegue o celular" or "Mire na influencer para parar a live!"
		end,
		Stop = function(_, ev, reason)
			local d = ev.data
			if reason == "tempo" and not d.ended and heist then
				if heist.alarmed then
					heist.lockAt = math.max(os.clock() + 5, (heist.lockAt or os.clock() + J.Lockdown) - 10)
					crewNotice("📈 A live VIRALIZOU! A PM viu tudo: a porta tranca 10 s mais cedo!", "red")
				else
					triggerAlarm("📈 A live da influencer viralizou e alguém ligou para a PM!")
				end
			end
			task.delay(reason == "concluido" and 4 or 0, function()
				dropNpc(d.info)
			end)
		end,
	},
}

---------------------------------------------------------------------------

local function onRequest(player, action, arg)
	if not SecurityService.isShortString(action, 16) then
		return
	end
	if action == "MiniHit" then
		if SecurityService.checkRate(player, "JoiaMini", 0.1) then
			miniHit(player, arg)
		end
		return
	end
	if not SecurityService.checkRate(player, "JoiaRequest", 0.2) then
		return
	end
	if action == "Spot" then
		spot(player, arg)
	elseif action == "MiniSair" then
		finishSession(player, false, "Você desistiu.")
	elseif action == "Status" then
		send(player, "JoiaStatus", statusPayload(player))
		send(player, "JoiaBolsa", bagPayload(player))
	elseif action == "Largar" and type(arg) == "number" then
		local b = bags[player]
		local it = b and NPCKit.bagItems(b)[math.floor(arg)]
		if it then
			dropItem(player, it)
		end
	elseif action == "Trocar" then
		local o = pending[player]
		pending[player] = nil
		if o then
			for _, it in ipairs(o.drop) do
				dropItem(player, it)
			end
			o.accept()
		end
	elseif action == "Deixar" then
		pending[player] = nil
	end
end

function JewelryService.init(remotes)
	uiUpdate = remotes[GameConfig.Remotes.UIUpdate]
	store = CollectionService:GetTagged("Joalheria")[1]
	if not store then
		warn("[JewelryService] Joalheria não encontrada no mapa.")
		return
	end
	remotes[GameConfig.Remotes.JewelryRequest].OnServerEvent:Connect(onRequest)
	parts = {
		area = store:FindFirstChild("Area"),
		restrita = store:FindFirstChild("AreaRestrita"),
		cofre = store:FindFirstChild("AreaCofre"),
		grade = store:FindFirstChild("Grade"),
		saida = store:FindFirstChild("SaidaEmergencia"),
		barra = store:FindFirstChild("BarraAntipanico"),
		ledTrava = store:FindFirstChild("LedTrava"),
		anuncio = store:FindFirstChild("PontoAnuncio"),
		gas = store:FindFirstChild("Gas"),
		placaFechado = store:FindFirstChild("PlacaFechado"),
		portaFunc = store:FindFirstChild("PortaFuncionarios"),
		leitor = store:FindFirstChild("LeitorCartao"),
		ledLeitor = store:FindFirstChild("LedLeitor"),
		terminal = store:FindFirstChild("Terminal"),
		gaveta = store:FindFirstChild("GavetaGerente"),
		portaCofre = store:FindFirstChild("PortaCofre"),
		volante = store:FindFirstChild("VolanteCofre"),
		painelCofre = store:FindFirstChild("PainelCofre"),
	}
	for _, d in ipairs(store:GetDescendants()) do
		if d:IsA("BasePart") then
			local alvo = d:GetAttribute("Alvo")
			if alvo then
				alvos[alvo] = d
			end
			if d:GetAttribute("PartePortaCofre") then
				table.insert(vaultParts, { part = d, home = d.CFrame })
			end
		end
	end
	-- lasers
	for _, d in ipairs(store:GetChildren()) do
		if d.Name == "CortinaLaser" then
			local i = d:GetAttribute("Index") or (#lasers + 1)
			lasers[i] = lasers[i] or { beams = {}, on = true }
			lasers[i].box = d
		end
	end
	local laserFolder = store:FindFirstChild("Lasers")
	for _, b in ipairs(laserFolder and laserFolder:GetChildren() or {}) do
		local i = b:GetAttribute("Cortina")
		if i and lasers[i] then
			table.insert(lasers[i].beams, b)
		end
	end
	-- vitrines (salão, área restrita ou cofre)
	local folder = store:FindFirstChild("Vitrines")
	for _, m in ipairs(folder and folder:GetChildren() or {}) do
		local glass = m:FindFirstChild("Vidro")
		if glass then
			local zone = "salao"
			if inBox(parts.cofre, glass.Position, 1) then
				zone = "cofre"
			elseif inBox(parts.restrita, glass.Position, 1) then
				zone = "restrita"
			end
			local c = {
				model = m,
				glass = glass,
				glassT = glass.Transparency,
				kind = m:GetAttribute("Loot") or "aneis",
				mini = m:GetAttribute("Minigame") or "vitrine",
				noise = m:GetAttribute("Barulho") or J.Noise.Glass,
				noShards = m:GetAttribute("SemCacos") == true,
				zone = zone,
				broken = false,
				parts = {},
			}
			local joias = m:FindFirstChild("Joias")
			for _, part in ipairs(joias and joias:GetDescendants() or {}) do
				if part:IsA("BasePart") then
					c.parts[part] = part.Transparency
				end
			end
			table.insert(cases, c)
		end
	end
	table.sort(cases, function(a, b)
		return (a.model:GetAttribute("Index") or 0) < (b.model:GetAttribute("Index") or 0)
	end)
	setupPrompts()
	spawnNpcs()
	-- Marco 10.20: eventos
	events = HeistEvents.new("Joia", JEWELRY_EVENTS, J.Events, {
		announce = function(ev)
			for _, p in ipairs(crewList()) do
				send(p, "JoiaEvento", { id = ev.id, name = ev.def.Name, icon = ev.def.Icon, text = ev.def.Text })
			end
		end,
	}, J.MaxEvents or 2)
	events.forceAll = J.TestAllEvents == true
	setCameras(true)
	showExit()
	refreshPrompts()
	-- diamante girando devagar
	local gem
	for _, d in ipairs(store:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("Gira") then
			gem = d
		end
	end
	CrimeService.onArrest(function(target, cop)
		local b = bags[target]
		if b and cop and cop.Parent then
			local paid = CareerService.taskPay(cop, "Policial", J.PoliceRecoverPay, "Recuperou joias roubadas", 0)
			send(cop, "CrimePaid", { amount = paid, text = ("Joias recuperadas: +%s"):format(money(paid)) })
		end
		if b then
			loseBag(target, "A polícia recuperou as joias.")
		end
		if target:GetAttribute("CartaoJoalheria") then
			target:SetAttribute("CartaoJoalheria", nil)
		end
	end)
	-- Marco 10.15: desistiu caído (ou ninguém reanimou) = perde a bolsa de joias
	DownedService.onGiveUp(function(target)
		if bags[target] then
			loseBag(target, "Você caiu e perdeu as joias.")
		end
		if target:GetAttribute("CartaoJoalheria") then
			target:SetAttribute("CartaoJoalheria", nil)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		bags[player] = nil
		reconActive[player] = nil
		sessions[player] = nil
		if heist then
			heist.crew[player] = nil
		end
		for _, info in ipairs(npcs) do
			info.aim[player] = nil
		end
	end)
	task.spawn(function()
		local acc, last = 0, os.clock()
		while true do
			task.wait(0.1)
			local now = os.clock()
			local dt = now - last
			last = now
			local ok, err = pcall(function()
				laserStep(now)
				aimStep(dt)
			end)
			if not ok then
				warn("[JewelryService] " .. tostring(err))
			end
			acc += dt
			if acc >= 0.5 then
				local okTick, errTick = pcall(tick, acc)
				acc = 0
				if not okTick then
					warn("[JewelryService] " .. tostring(errTick))
				end
				if gem and gem.Parent and gem.Transparency < 1 then
					gem.CFrame = gem.CFrame * CFrame.Angles(0, math.rad(12), 0)
				end
			end
		end
	end)
	print(("[JewelryService] %s pronta: %d vitrines/gavetas, %d cortinas de laser."):format(J.Name, #cases, #lasers))
end

-- Marco 10.20: o BankService usa o mesmo minigame (a janela "JoiaMinigame" do cliente).
-- rule = { Hits, Zone, Speed }; onMiss(miss) é chamado a cada erro.
function JewelryService.minigame(player, rule, part, title, onDone, onMiss)
	if sessions[player] then
		return false
	end
	startMinigame(player, rule, part, title, 0, onDone, onMiss)
	return sessions[player] ~= nil
end

return JewelryService
