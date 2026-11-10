-- CrimeService (ModuleScript)
-- Caminho: ServerScriptService > Services > CrimeService
-- Marco 10.5: Ladrão x Polícia (regras PROVISÓRIAS em GameConfig.Crime).
--   * Assalto à loja de conveniência: quem é de gangue segura E no caixa e fica perto até acabar;
--     o alarme toca alguns segundos depois. Caixa eletrônico: minijogo de 3 etapas, alarme na hora.
--     O que rouba vira dinheiro sujo (data.dirty): só vale depois de entregar ao chefe da gangue.
--     Preso antes disso perde o dinheiro sujo.
--   * Procurado: cada crime dá pontos (data.wanted); 1 a 5 estrelas; sem crime por um tempo, baixa.
--     Com 3+ estrelas o nome vai para a Lista de Procurados (quadro da Base da PM e painel do policial).
--   * Polícia: chamados ao vivo (alarmes) e chamados de NPC quando não tem crime de jogador.
--     Taser (atordoa procurado) e algema (leva o procurado junto; no carro ele senta atrás).
--     Chegou na Penitenciária com o preso: ele é preso (pena pelas estrelas) e o policial ganha o
--     salário e a recompensa. Procurado derrubado a tiro pela polícia também vai preso.
-- Tudo é conferido no servidor (distância, frequência, emprego, gangue, prisão).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local SecurityService = require(script.Parent:WaitForChild("SecurityService"))
local ZoneService = require(script.Parent:WaitForChild("ZoneService"))
local PrisonService = require(script.Parent:WaitForChild("PrisonService"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))
local WeaponService = require(script.Parent:WaitForChild("WeaponService"))
local CareerService = require(script.Parent:WaitForChild("CareerService"))
local NPCKit = require(script.Parent:WaitForChild("NPCKit"))

local CrimeService = {}

local CR = GameConfig.Crime
local POLICE = "Policial"
local uiUpdate
local rng = Random.new()

local spots = {} -- spots[part] = { kind, name, closedUntil, alarm, cashier }
local robbing = {} -- robbing[player] = { part, kind, started, steps, lastStep, alarmed }
local calls = {} -- { id, kind, title, place, pos, started, npc, say, answered }
local nextCallId = 0
local lastPlayerCrime = -math.huge
local stunUntil = {} -- stunUntil[player] = os.clock()
local escort = {} -- escort[cop] = { target, weld, seat }
local cuffedBy = {} -- cuffedBy[target] = cop
local decayAt = {} -- decayAt[player] = os.clock() do próximo ponto a cair
local prisonModel

local function notice(player, text, color)
	uiUpdate:FireClient(player, "Notice", { text = text })
end

local function isPolice(player)
	return player:GetAttribute("Job") == POLICE
end

local function police()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if isPolice(p) then
			table.insert(list, p)
		end
	end
	return list
end

local function money(n)
	return "$" .. tostring(math.floor(n))
end

---------------------------------------------------------------------------
-- Procurado (estrelas) e dinheiro sujo
---------------------------------------------------------------------------

local function starsFor(points)
	local s = 0
	for i, t in ipairs(CR.StarPoints) do
		if points >= t then
			s = i
		end
	end
	return s
end

local function wantedOf(player)
	local data = PlayerDataService.get(player)
	local w = data and data.wanted
	return type(w) == "table" and tonumber(w.p) or 0
end

local refreshWantedList -- definida mais abaixo

local function setWanted(player, points)
	points = math.max(0, math.floor(points))
	PlayerDataService.set(player, "wanted", points > 0 and { p = points } or nil)
	local stars = starsFor(points)
	local before = player:GetAttribute("Procurado") or 0
	player:SetAttribute("Procurado", stars > 0 and stars or nil)
	player:SetAttribute("Recompensa", stars > 0 and stars * CR.BountyPerStar or nil)
	if stars ~= before then
		refreshWantedList()
	end
end

function CrimeService.addWanted(player, points)
	setWanted(player, wantedOf(player) + points)
	decayAt[player] = os.clock() + CR.DecayAfter
	lastPlayerCrime = os.clock()
end

local function dirtyOf(player)
	local data = PlayerDataService.get(player)
	return data and tonumber(data.dirty) or 0
end

local function setDirty(player, amount)
	amount = math.max(0, math.floor(amount))
	PlayerDataService.set(player, "dirty", amount > 0 and amount or nil)
	player:SetAttribute("DinheiroSujo", amount > 0 and amount or nil)
end

function CrimeService.getDirty(player)
	return dirtyOf(player)
end

-- O chefe da gangue "lava" o dinheiro sujo (GangService chama)
function CrimeService.deliverDirty(player)
	local amount = dirtyOf(player)
	if amount <= 0 then
		return 0
	end
	if EconomyService.add(player, amount, "Dinheiro do assalto entregue ao chefe") then
		setDirty(player, 0)
		return amount
	end
	return 0
end

---------------------------------------------------------------------------
-- Chamados da polícia
---------------------------------------------------------------------------

local function callsPayload()
	local now = os.clock()
	local list = {}
	for _, c in ipairs(calls) do
		table.insert(list, { id = c.id, kind = c.kind, title = c.title, place = c.place, pos = c.pos, age = math.floor(now - c.started), npc = c.npc ~= nil })
	end
	return list
end

local function sendCalls(target)
	local payload = { calls = callsPayload() }
	if target then
		uiUpdate:FireClient(target, "CrimeCalls", payload)
		return
	end
	for _, p in ipairs(police()) do
		uiUpdate:FireClient(p, "CrimeCalls", payload)
	end
end

local function addCall(kind, title, place, pos, extra)
	nextCallId += 1
	local c = { id = nextCallId, kind = kind, title = title, place = place, pos = pos, started = os.clock() }
	for k, v in pairs(extra or {}) do
		c[k] = v
	end
	table.insert(calls, c)
	for _, p in ipairs(police()) do
		uiUpdate:FireClient(p, "CrimeNewCall", { title = title, place = place, npc = c.npc ~= nil })
	end
	sendCalls()
	return c
end

local function removeCall(c)
	local i = table.find(calls, c)
	if i then
		table.remove(calls, i)
	end
	if c.npc and c.npc.Parent then
		c.npc:Destroy()
	end
	sendCalls()
end

local function blinkAlarm(alarm)
	if not alarm or alarm:GetAttribute("Blinking") then
		return
	end
	alarm:SetAttribute("Blinking", true)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 40, 40)
	light.Range = 18
	light.Brightness = 2
	light:SetAttribute("SemLimite", true) -- Marco 10.6: o alarme pisca sozinho (fora do limite de luzes)
	light.Parent = alarm
	local old, oldMat = alarm.Color, alarm.Material
	task.spawn(function()
		local t0 = os.clock()
		local on = false
		while os.clock() - t0 < 60 and alarm.Parent do
			on = not on
			alarm.Color = on and Color3.fromRGB(255, 30, 30) or Color3.fromRGB(90, 20, 20)
			alarm.Material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
			light.Enabled = on
			task.wait(0.4)
		end
		alarm.Color, alarm.Material = old, oldMat
		light:Destroy()
		alarm:SetAttribute("Blinking", nil)
	end)
end

local function raiseAlarm(part, info)
	blinkAlarm(info.alarm)
	local title = info.kind == "loja" and "🚨 Assalto à loja" or "🚨 Caixa eletrônico violado"
	addCall("alarme", title, info.name, part.Position)
	lastPlayerCrime = os.clock()
end

---------------------------------------------------------------------------
-- Assaltos
---------------------------------------------------------------------------

local function canRob(player, info)
	if not player:GetAttribute("Gang") then
		return false, "Só quem é de gangue assalta. Procure o chefe numa favela."
	end
	if isPolice(player) then
		return false, "Policial não assalta."
	end
	if player:GetAttribute("Preso") or cuffedBy[player] then
		return false, "Agora não dá."
	end
	if robbing[player] then
		return false, "Você já está num assalto."
	end
	if info.closedUntil and os.time() < info.closedUntil then
		return false, ("Fechado: foi assaltado há pouco. Volte em %d min."):format(math.ceil((info.closedUntil - os.time()) / 60))
	end
	if ZoneService.isInside(player) then
		return false, "Aqui é zona segura."
	end
	return true
end

local function stopRobbery(player, ok, reason)
	local r = robbing[player]
	if not r then
		return
	end
	robbing[player] = nil
	local info = spots[r.part]
	if info and info.cashier and info.cashier.Parent then
		NPCKit.emote(info.cashier, "wave")
	end
	if not ok then
		uiUpdate:FireClient(player, "CrimeRobEnd", { ok = false, reason = reason })
		return
	end
	local range = r.kind == "loja" and CR.StoreReward or CR.AtmReward
	local reward = rng:NextInteger(range[1], range[2])
	setDirty(player, dirtyOf(player) + reward)
	CrimeService.addWanted(player, r.kind == "loja" and CR.StorePoints or CR.AtmPoints)
	info.closedUntil = os.time() + CR.Cooldown
	r.part:SetAttribute("ClosedUntil", info.closedUntil)
	uiUpdate:FireClient(player, "CrimeRobEnd", { ok = true, reward = reward, dirty = dirtyOf(player) })
	print(("[CrimeService] %s assaltou %s (+%d sujo)."):format(player.Name, info.name, reward))
end

local function startRobbery(player, part)
	local info = spots[part]
	local ok, why = canRob(player, info)
	if not ok then
		return notice(player, why)
	end
	local _, _, root = SecurityService.getLivingCharacter(player)
	if not root then
		return
	end
	local r = { part = part, kind = info.kind, started = os.clock(), steps = 0, lastStep = os.clock() }
	robbing[player] = r
	if info.kind == "loja" then
		if info.cashier and info.cashier.Parent then
			NPCKit.emote(info.cashier, "cheer") -- mãos para cima
			NPCKit.say(info.cashier, "Calma, calma! Pode levar!", 4)
		end
		uiUpdate:FireClient(player, "CrimeRob", { kind = "loja", place = info.name, time = CR.StoreTime, pos = part.Position, range = CR.StoreRange })
	else
		r.alarmed = true
		raiseAlarm(part, info)
		uiUpdate:FireClient(player, "CrimeRob", { kind = "atm", place = info.name, steps = CR.AtmSteps, pos = part.Position, range = CR.AtmRange, stepMin = CR.AtmStepMin })
	end
	-- acompanha o assalto: perto do lugar, vivo, sem ser preso
	task.spawn(function()
		while robbing[player] == r do
			task.wait(0.25)
			local _, _, rr = SecurityService.getLivingCharacter(player)
			local range = r.kind == "loja" and CR.StoreRange or CR.AtmRange
			if not rr or not player.Parent or (rr.Position - part.Position).Magnitude > range or cuffedBy[player] or player:GetAttribute("Preso") then
				stopRobbery(player, false, "Assalto cancelado: você saiu de perto.")
				break
			end
			local t = os.clock() - r.started
			if r.kind == "loja" then
				if not r.alarmed and t >= CR.StoreAlarmDelay then
					r.alarmed = true
					raiseAlarm(part, info)
				end
				if t >= CR.StoreTime then
					stopRobbery(player, true)
				end
			elseif t > 90 then
				stopRobbery(player, false, "Demorou demais: o caixa travou.")
			end
		end
	end)
end

local function atmStep(player)
	local r = robbing[player]
	if not r or r.kind ~= "atm" then
		return
	end
	if os.clock() - r.lastStep < CR.AtmStepMin - 0.5 then
		return -- rápido demais: o servidor não aceita
	end
	r.steps += 1
	r.lastStep = os.clock()
	if r.steps >= CR.AtmSteps then
		stopRobbery(player, true)
	end
end

local function setupSpot(part)
	if spots[part] then
		return
	end
	local kind = part:GetAttribute("Robbery")
	local info = { kind = kind, name = part:GetAttribute("PlaceName") or "Loja" }
	spots[part] = info
	local holder = part.Parent
	if kind == "loja" then
		info.alarm = holder:FindFirstChild("LuzAlarme")
		local spot = holder:FindFirstChild("CaixaSpot")
		if spot then
			info.cashier = NPCKit.spawn(spot.CFrame * CFrame.new(0, -spot.Size.Y / 2, 0), { name = "Caixa", anchored = true, important = true, outfit = "loja" })
		end
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CrimePrompt"
	prompt.ActionText = kind == "loja" and "Assaltar" or "Hackear"
	prompt.ObjectText = info.name
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 1.5
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	prompt.Triggered:Connect(function(player)
		if not SecurityService.checkRate(player, "Rob", 1) then
			return
		end
		local _, _, root = SecurityService.getLivingCharacter(player)
		if root and (root.Position - part.Position).Magnitude <= 12 then
			startRobbery(player, part)
		end
	end)
end

---------------------------------------------------------------------------
-- Lista de procurados (quadro da Base da PM + painel do policial)
---------------------------------------------------------------------------

local board, boardCards

local function wantedList()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local stars = p:GetAttribute("Procurado") or 0
		if stars >= CR.ListStars then
			table.insert(list, { userId = p.UserId, name = p.DisplayName, stars = stars, bounty = stars * CR.BountyPerStar })
		end
	end
	table.sort(list, function(a, b)
		return a.stars > b.stars
	end)
	return list
end

local function buildBoard()
	local map = Workspace:FindFirstChild("Map")
	prisonModel = map and map:FindFirstChild("Penitenciaria")
	board = prisonModel and prisonModel:FindFirstChild("QuadroProcurados", true)
	if not board then
		return
	end
	-- os cartazes de enfeite saem: o quadro mostra a lista de verdade
	for _, d in ipairs(board.Parent:GetChildren()) do
		if d:IsA("BasePart") and (d.Name == "Cartaz" or d.Name == "Rosto") then
			d.Transparency = 1
		end
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Lista"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.2
	gui.Parent = board
	local grid = Instance.new("Frame")
	grid.Size = UDim2.fromScale(1, 1)
	grid.BackgroundTransparency = 1
	grid.Parent = gui
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(1 / 3, -16, 0.5, -16)
	layout.CellPadding = UDim2.fromOffset(12, 12)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	boardCards = {}
	for i = 1, 6 do
		local card = Instance.new("Frame")
		card.BackgroundColor3 = Color3.fromRGB(245, 235, 200)
		card.LayoutOrder = i
		card.Parent = grid
		local img = Instance.new("ImageLabel")
		img.Name = "Foto"
		img.Size = UDim2.fromScale(0.42, 0.62)
		img.Position = UDim2.fromScale(0.29, 0.04)
		img.BackgroundColor3 = Color3.fromRGB(60, 60, 65)
		img.Parent = card
		local name = Instance.new("TextLabel")
		name.Name = "Nome"
		name.Size = UDim2.fromScale(0.96, 0.14)
		name.Position = UDim2.fromScale(0.02, 0.67)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.GothamBlack
		name.TextScaled = true
		name.TextColor3 = Color3.fromRGB(40, 30, 20)
		name.Parent = card
		local info = Instance.new("TextLabel")
		info.Name = "Info"
		info.Size = UDim2.fromScale(0.96, 0.15)
		info.Position = UDim2.fromScale(0.02, 0.82)
		info.BackgroundTransparency = 1
		info.Font = Enum.Font.GothamBold
		info.TextScaled = true
		info.TextColor3 = Color3.fromRGB(170, 35, 35)
		info.Parent = card
		boardCards[i] = card
	end
end

local thumbs = {}
local function thumb(userId)
	if thumbs[userId] == nil then
		local ok, url = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size180x180)
		end)
		thumbs[userId] = ok and url or ""
	end
	return thumbs[userId]
end

refreshWantedList = function()
	local list = wantedList()
	for _, p in ipairs(police()) do
		uiUpdate:FireClient(p, "CrimeWanted", { list = list })
	end
	if not boardCards then
		return
	end
	task.spawn(function()
		for i, card in ipairs(boardCards) do
			local w = list[i]
			card.Visible = w ~= nil or i == 1
			if w then
				card.Foto.Image = thumb(w.userId)
				card.Nome.Text = w.name
				card.Info.Text = ("%s  %s"):format(string.rep("★", w.stars), money(w.bounty))
			elseif i == 1 then
				card.Foto.Image = ""
				card.Nome.Text = "Ninguém procurado"
				card.Info.Text = "A cidade está calma"
			end
		end
	end)
end

---------------------------------------------------------------------------
-- Taser, algema e levar o preso
---------------------------------------------------------------------------

local function insidePrison(pos)
	if not prisonModel then
		return false
	end
	local p = prisonModel.WorldPivot:PointToObjectSpace(pos)
	return math.abs(p.X) <= GameConfig.Prison.Width / 2 and math.abs(p.Z) <= GameConfig.Prison.Depth / 2
end

local function setMassless(character, on)
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Massless = on
		end
	end
end

local function weldBehind(cop, target)
	local e = escort[cop]
	local _, _, cRoot = SecurityService.getLivingCharacter(cop)
	local tChar, tHum, tRoot = SecurityService.getLivingCharacter(target)
	if not e or not cRoot or not tRoot then
		return false
	end
	if e.weld then
		e.weld:Destroy()
	end
	tHum.Sit = false
	tHum.PlatformStand = true
	setMassless(tChar, true)
	ZoneService.setRiding(tChar, true) -- não esbarra em nada enquanto é levado
	tRoot.CFrame = cRoot.CFrame * CFrame.new(1.6, 0, -2.6)
	local weld = Instance.new("Weld")
	weld.Name = "Algemado"
	weld.Part0 = cRoot
	weld.Part1 = tRoot
	weld.C0 = CFrame.new(1.6, 0, -2.6)
	weld.Parent = cRoot
	e.weld = weld
	e.seat = nil
	return true
end

local function releaseTarget(cop, why, keepSentence)
	local e = escort[cop]
	if not e then
		return
	end
	escort[cop] = nil
	local target = e.target
	cuffedBy[target] = nil
	if e.weld then
		e.weld:Destroy()
	end
	if e.conn then
		for _, c in ipairs(e.conn) do
			c:Disconnect()
		end
	end
	if target.Parent then
		target:SetAttribute("Algemado", nil)
		local tChar, tHum = SecurityService.getLivingCharacter(target)
		if tChar then
			setMassless(tChar, false)
			ZoneService.setRiding(tChar, false)
			tHum.PlatformStand = false
			tHum.JumpPower = 50
			tHum.JumpHeight = 7.2
			tHum.Sit = false
		end
		if not target:GetAttribute("Preso") and not keepSentence then
			-- tira a pena "de segurança" que entrou na hora da algema
			local data = PlayerDataService.get(target)
			if data and type(data.prison) == "table" and data.prison.pending then
				PlayerDataService.set(target, "prison", nil)
			end
		end
		if why then
			notice(target, why)
		end
	end
	if cop.Parent then
		cop:SetAttribute("Escoltando", nil)
	end
end

-- Prende de verdade (chegou na prisão ou foi derrubado pela polícia)
local arrestHooks = {} -- Marco 10.8: o JewelryService fica sabendo de cada prisão
local function sendToPrison(target, cop, reason)
	for _, fn in ipairs(arrestHooks) do
		task.spawn(fn, target, cop)
	end
	local stars = target:GetAttribute("Procurado") or 0
	local sentence = CR.SentenceBase + stars * CR.SentencePerStar
	local lost = dirtyOf(target)
	setDirty(target, 0)
	setWanted(target, 0)
	InventoryService.confiscate(target)
	if robbing[target] then
		stopRobbery(target, false, "Assalto cancelado.")
	end
	PlayerDataService.set(target, "prison", nil)
	PrisonService.arrest(target, sentence)
	notice(target, ("Você foi preso (%s)! Pena: %d min.%s"):format(reason, math.ceil(sentence / 60), lost > 0 and (" Perdeu " .. money(lost) .. " do assalto.") or ""))
	if cop and cop.Parent then
		local pay = CareerService.taskPay(cop, POLICE, CR.ArrestPay + stars * CR.BountyPerStar, "Prisão de " .. target.Name, GameConfig.Career.ArrestTasks)
		uiUpdate:FireClient(cop, "CrimePaid", { amount = pay, text = ("Prendeu %s: +%s"):format(target.DisplayName, money(pay)) })
	end
	print(("[CrimeService] %s preso (%s), %d estrelas."):format(target.Name, reason, stars))
end

local function taser(cop, target)
	if not isPolice(cop) or typeof(target) ~= "Instance" or not target:IsA("Player") or target == cop then
		return
	end
	if not SecurityService.checkRate(cop, "Taser", CR.TaserCooldown) then
		return
	end
	local _, _, cRoot = SecurityService.getLivingCharacter(cop)
	local _, tHum, tRoot = SecurityService.getLivingCharacter(target)
	if not cRoot or not tRoot then
		return
	end
	if (cRoot.Position - tRoot.Position).Magnitude > CR.TaserRange then
		return notice(cop, "Muito longe para o taser.")
	end
	if (target:GetAttribute("Procurado") or 0) < 1 then
		return notice(cop, target.DisplayName .. " não é procurado.")
	end
	if tHum.SeatPart then
		return notice(cop, "Ele está num veículo.")
	end
	if ZoneService.isInside(target) then
		return notice(cop, "Zona segura.")
	end
	uiUpdate:FireAllClients("CrimeZap", { from = cRoot.Position, to = tRoot.Position })
	stunUntil[target] = os.clock() + CR.TaserStun
	target:SetAttribute("Atordoado", true)
	if robbing[target] then
		stopRobbery(target, false, "Você levou um choque do taser!")
	end
	if not cuffedBy[target] then
		tHum.PlatformStand = true
	end
	notice(target, "Você levou um choque do taser!")
	task.delay(CR.TaserStun, function()
		if os.clock() >= (stunUntil[target] or 0) - 0.05 then
			target:SetAttribute("Atordoado", nil)
			local _, h = SecurityService.getLivingCharacter(target)
			if h and not cuffedBy[target] then
				h.PlatformStand = false
			end
		end
	end)
end

local function onCopSeated(cop, active, seat)
	local e = escort[cop]
	if not e then
		return
	end
	local target = e.target
	local _, tHum = SecurityService.getLivingCharacter(target)
	if not tHum then
		return
	end
	local vehicles = Workspace:FindFirstChild("Vehicles")
	if active and seat and vehicles and seat:IsDescendantOf(vehicles) then
		local car = seat.Parent
		while car and car.Parent ~= vehicles do
			car = car.Parent
		end
		local free
		for _, name in ipairs({ "RearSeat", "PassengerSeat" }) do
			for _, s in ipairs(car and car:GetDescendants() or {}) do
				if not free and s:IsA("Seat") and s.Name == name and not s.Occupant then
					free = s
				end
			end
		end
		if not free then
			return notice(cop, "Não tem banco livre para o preso.")
		end
		if e.weld then
			e.weld:Destroy()
			e.weld = nil
		end
		tHum.PlatformStand = false
		e.seat = free
		task.wait(0.1)
		free:Sit(tHum)
	elseif not active and e.seat then
		e.seat = nil
		tHum.Sit = false
		task.wait(0.2)
		if escort[cop] == e then
			weldBehind(cop, target)
		end
	end
end

local function cuff(cop, target)
	if not isPolice(cop) or not SecurityService.checkRate(cop, "Cuff", 1) then
		return
	end
	if escort[cop] then
		-- algema de novo = solta
		releaseTarget(cop, "O policial te soltou.")
		return notice(cop, "Você soltou o suspeito.")
	end
	if typeof(target) ~= "Instance" or not target:IsA("Player") or target == cop then
		return
	end
	local _, _, cRoot = SecurityService.getLivingCharacter(cop)
	local _, tHum, tRoot = SecurityService.getLivingCharacter(target)
	if not cRoot or not tRoot or cuffedBy[target] then
		return
	end
	if (cRoot.Position - tRoot.Position).Magnitude > CR.CuffRange then
		return notice(cop, "Chegue mais perto para algemar.")
	end
	if not target:GetAttribute("Atordoado") then
		return notice(cop, "Use o taser antes de algemar.")
	end
	escort[cop] = { target = target }
	cuffedBy[target] = cop
	target:SetAttribute("Algemado", cop.UserId)
	cop:SetAttribute("Escoltando", target.UserId)
	tHum.JumpPower = 0
	tHum.JumpHeight = 0
	if robbing[target] then
		stopRobbery(target, false, "Você foi algemado!")
	end
	-- sair do jogo algemado não escapa: a pena já fica salva (vira prisão ao voltar)
	local stars = target:GetAttribute("Procurado") or 0
	PlayerDataService.set(target, "prison", { left = CR.SentenceBase + stars * CR.SentencePerStar, tasks = 0, need = 3, pending = true })
	weldBehind(cop, target)
	local e = escort[cop]
	local _, cHum = SecurityService.getLivingCharacter(cop)
	e.conn = {
		cHum.Seated:Connect(function(active, seat)
			task.spawn(onCopSeated, cop, active, seat)
		end),
		tHum.Seated:Connect(function(active)
			-- o preso tentou sair do banco: volta a sentar
			if not active and e.seat and escort[cop] == e then
				task.wait(0.15)
				if e.seat and escort[cop] == e then
					e.seat:Sit(tHum)
				end
			end
		end),
	}
	notice(cop, ("Você algemou %s. Leve até a Penitenciária (pode ir de viatura)."):format(target.DisplayName))
	notice(target, "Você foi algemado! O policial vai te levar para a prisão.")
end

---------------------------------------------------------------------------
-- Chamados de NPC (só quando não tem crime de jogador)
---------------------------------------------------------------------------

local function npcCallSpot()
	local map = Workspace:FindFirstChild("Map")
	local houses = map and map:FindFirstChild("Houses")
	local list = houses and houses:GetChildren() or {}
	for _ = 1, 20 do
		local h = list[rng:NextInteger(1, math.max(1, #list))]
		local curb = h and h:GetAttribute("Curb")
		if typeof(curb) == "CFrame" and not h:GetAttribute("Remote") then
			return curb
		end
	end
	return nil
end

local function spawnNpcCall()
	local curb = npcCallSpot()
	if not curb then
		return
	end
	local kind = CR.NpcCalls[rng:NextInteger(1, #CR.NpcCalls)]
	local ground = NPCKit.groundAt(curb.Position) or curb.Position
	local npc = NPCKit.spawn(CFrame.new(ground) * curb.Rotation, { name = "Suspeito", shirt = Color3.fromRGB(150, 40, 40), anchored = true, important = true })
	if not npc then
		return
	end
	local c = addCall("npc", "📻 " .. kind.title, "Chamado da central", ground, { npc = npc, say = kind.say })
	local root = npc:FindFirstChild("HumanoidRootPart")
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "AbordarPrompt" -- o cliente só mostra para o Policial
	prompt.ActionText = "Abordar"
	prompt.ObjectText = "Suspeito"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 1.5
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	prompt.Triggered:Connect(function(cop)
		if not isPolice(cop) or c.answered or not SecurityService.checkRate(cop, "Abordar", 1) then
			return
		end
		c.answered = true
		prompt.Enabled = false
		NPCKit.emote(npc, "cheer")
		NPCKit.say(npc, c.say, 4)
		local pay = CareerService.taskPay(cop, POLICE, rng:NextInteger(CR.NpcPay[1], CR.NpcPay[2]), "Chamado de NPC")
		uiUpdate:FireClient(cop, "CrimePaid", { amount = pay, text = ("Chamado resolvido: +%s"):format(money(pay)) })
		task.delay(4, function()
			removeCall(c)
		end)
	end)
end

---------------------------------------------------------------------------
-- Laço principal (1 vez por segundo)
---------------------------------------------------------------------------

local npcTick = 0
local function tick()
	local now = os.clock()
	-- estrelas baixam sozinhas
	for _, p in ipairs(Players:GetPlayers()) do
		local pts = wantedOf(p)
		if pts > 0 and not cuffedBy[p] then
			decayAt[p] = decayAt[p] or (now + CR.DecayAfter)
			if now >= decayAt[p] then
				decayAt[p] = now + CR.DecayEvery
				setWanted(p, pts - 1)
			end
		end
	end
	-- chamados: velhos somem; alarme atendido quando um policial chega
	local changed = false
	for i = #calls, 1, -1 do
		local c = calls[i]
		if now - c.started > CR.CallLife then
			removeCall(c)
			changed = false
		elseif c.kind == "alarme" and not c.answered then
			for _, cop in ipairs(police()) do
				local _, _, root = SecurityService.getLivingCharacter(cop)
				if root and (root.Position - c.pos).Magnitude <= CR.CallArrive then
					c.answered = true
					local paid = CareerService.taskPay(cop, POLICE, CR.CallPay, "Atendeu alarme")
					uiUpdate:FireClient(cop, "CrimePaid", { amount = paid, text = ("Chegou no chamado: +%s"):format(money(paid)) })
					table.remove(calls, i)
					changed = true
					break
				end
			end
		end
	end
	if changed then
		sendCalls()
	end
	-- preso algemado chegou na prisão
	for cop, e in pairs(escort) do
		local target = e.target
		local _, _, cRoot = SecurityService.getLivingCharacter(cop)
		if not cop.Parent or not target.Parent or not isPolice(cop) or not cRoot or not SecurityService.getLivingCharacter(target) then
			releaseTarget(cop, "Você se soltou da algema!")
		elseif insidePrison(cRoot.Position) then
			releaseTarget(cop)
			sendToPrison(target, cop, "levado pela polícia")
		end
	end
	-- chamados de NPC
	npcTick += 1
	if npcTick >= 15 then
		npcTick = 0
		local cops = #police()
		local active = 0
		for _, c in ipairs(calls) do
			if c.npc then
				active += 1
			end
		end
		if cops > 0 and now - lastPlayerCrime > CR.NpcQuiet and active < math.max(1, math.ceil(cops / 2)) then
			pcall(spawnNpcCall)
		end
	end
end

---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Revista (Marco 10.6): o policial segura G perto da pessoa. Leva de 7 a 10 s; se alguém se
-- afastar ou cair, cancela. No fim, o policial vê a mochila, a munição e o dinheiro sujo e pode
-- apreender o que é proibido (painel do CrimeController).
---------------------------------------------------------------------------

local frisking = {} -- frisking[cop] = { target, t0, dur }
local friskOpen = {} -- friskOpen[cop] = { target, untilT }

local function closeTo(a, b, range)
	local _, ha, ra = SecurityService.getLivingCharacter(a)
	local _, hb, rb = SecurityService.getLivingCharacter(b)
	return ra and rb and ha.Health > 0 and hb.Health > 0 and (ra.Position - rb.Position).Magnitude <= range
end

local function friskPayload(target)
	local ammo = {}
	for kind in pairs(GameConfig.Weapons.Ammo) do
		ammo[kind] = WeaponService.ammoOf(target, kind)
	end
	return {
		user = target.UserId,
		name = target.DisplayName,
		items = InventoryService.listItems(target),
		dirty = dirtyOf(target),
		ammo = ammo,
		stars = target:GetAttribute("Procurado") or 0,
	}
end

local function frisk(cop, target)
	if not isPolice(cop) or typeof(target) ~= "Instance" or not target:IsA("Player") or target == cop or not target.Parent then
		return
	end
	if frisking[cop] then
		return notice(cop, "Você já está revistando alguém.")
	end
	if target:GetAttribute("Preso") then
		return notice(cop, "Essa pessoa já está presa.")
	end
	if not closeTo(cop, target, CR.FriskRange + 2) then
		return notice(cop, "Chegue mais perto para revistar.")
	end
	local session = { target = target, t0 = os.clock(), dur = rng:NextNumber(CR.FriskTime[1], CR.FriskTime[2]) }
	frisking[cop] = session
	uiUpdate:FireClient(cop, "CrimeFrisk", { name = target.DisplayName, dur = session.dur, cop = true })
	uiUpdate:FireClient(target, "CrimeFrisk", { name = cop.DisplayName, dur = session.dur })
	task.spawn(function()
		while os.clock() - session.t0 < session.dur do
			task.wait(0.25)
			if frisking[cop] ~= session then
				return
			end
			if not cop.Parent or not target.Parent or not isPolice(cop) or not closeTo(cop, target, CR.FriskRange + 4) then
				frisking[cop] = nil
				for _, p in ipairs({ cop, target }) do
					if p.Parent then
						uiUpdate:FireClient(p, "CrimeFriskEnd", { reason = "Revista cancelada: ficaram longe." })
					end
				end
				return
			end
		end
		frisking[cop] = nil
		friskOpen[cop] = { target = target, untilT = os.clock() + CR.FriskOpen }
		uiUpdate:FireClient(target, "CrimeFriskEnd", { reason = cop.DisplayName .. " terminou a revista." })
		uiUpdate:FireClient(cop, "CrimeFriskResult", friskPayload(target))
	end)
end

local function seize(cop, what)
	local open = friskOpen[cop]
	if not open or os.clock() > open.untilT or not isPolice(cop) then
		return notice(cop, "Revista vencida. Revista de novo.")
	end
	local target = open.target
	if not target.Parent then
		friskOpen[cop] = nil
		return
	end
	if not closeTo(cop, target, CR.FriskRange + 6) then
		return notice(cop, "A pessoa está longe. Chegue perto para apreender.")
	end
	local text
	if what == "dirty" then
		local amount = dirtyOf(target)
		if amount > 0 then
			setDirty(target, 0)
			text = money(amount) .. " de dinheiro sujo"
		end
	elseif type(what) == "string" and what:sub(1, 5) == "ammo_" and GameConfig.Weapons.Ammo[what:sub(6)] then
		local n = WeaponService.takeAmmo(target, what:sub(6))
		if n > 0 then
			text = ("%d balas de %s"):format(n, what:sub(6))
		end
	elseif type(what) == "number" then
		text = InventoryService.seize(target, what)
	end
	if text then
		notice(target, ("A polícia apreendeu: %s."):format(text))
		notice(cop, ("Apreendido: %s."):format(text))
	end
	uiUpdate:FireClient(cop, "CrimeFriskResult", friskPayload(target))
end

-- Botão "Revistar" (G) em cada pessoa. Só a PM vê (o CrimeController liga/desliga no cliente).
local function addFriskPrompt(player, character)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RevistarPrompt"
	prompt.ActionText = "Revistar"
	prompt.ObjectText = player.DisplayName
	prompt.KeyboardKeyCode = Enum.KeyCode.G
	prompt.MaxActivationDistance = CR.FriskRange
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0.4
	prompt.Enabled = false
	prompt.Parent = root
	prompt.Triggered:Connect(function(cop)
		if SecurityService.checkRate(cop, "Frisk", 1) then
			frisk(cop, player)
		end
	end)
end

local function onRequest(player, action, arg)
	if not SecurityService.checkRate(player, "CrimeRequest", 0.2) or not SecurityService.isShortString(action, 16) then
		return
	end
	if action == "AtmStep" then
		atmStep(player)
	elseif action == "Taser" then
		taser(player, arg)
	elseif action == "Cuff" then
		cuff(player, arg)
	elseif action == "Calls" and isPolice(player) then
		sendCalls(player)
		uiUpdate:FireClient(player, "CrimeWanted", { list = wantedList() })
	elseif action == "Seize" then
		seize(player, arg)
	elseif action == "FriskClose" then
		friskOpen[player] = nil
	elseif action == "CancelRob" then
		stopRobbery(player, false, "Você desistiu do assalto.")
	end
end

-- Morte por tiro (WeaponService avisa quem atirou por último)
local function onKill(killer, victim)
	if not killer or killer == victim then
		return
	end
	if isPolice(killer) and (victim:GetAttribute("Procurado") or 0) > 0 then
		sendToPrison(victim, killer, "derrubado pela polícia")
	elseif not isPolice(killer) then
		CrimeService.addWanted(killer, CR.KillPoints)
		if isPolice(victim) then
			CrimeService.addWanted(killer, CR.KillPoints) -- matar policial: o dobro
		end
	end
end

-- Marco 10.8: o que o JewelryService (assalto à joalheria) usa daqui
function CrimeService.alert(title, place, pos)
	lastPlayerCrime = os.clock()
	return addCall("alarme", title, place, pos)
end
function CrimeService.blink(part)
	blinkAlarm(part)
end
-- Marco 10.15: desistiu caído = perde o dinheiro sujo; devolve quanto perdeu
function CrimeService.clearDirty(player)
	local lost = dirtyOf(player)
	setDirty(player, 0)
	if robbing[player] then
		stopRobbery(player, false, "Assalto cancelado.")
	end
	return lost
end

function CrimeService.addDirty(player, amount)
	setDirty(player, dirtyOf(player) + amount)
	return dirtyOf(player)
end
function CrimeService.isPolice(player)
	return isPolice(player)
end
function CrimeService.policeCount()
	return #police()
end
function CrimeService.isCuffed(player)
	return cuffedBy[player] ~= nil
end
function CrimeService.onArrest(fn)
	table.insert(arrestHooks, fn)
end
function CrimeService.notice(player, text)
	notice(player, text)
end

function CrimeService.init(remotes)
	uiUpdate = remotes[GameConfig.Remotes.UIUpdate]
	remotes[GameConfig.Remotes.CrimeRequest].OnServerEvent:Connect(onRequest)

	for _, part in ipairs(CollectionService:GetTagged("CrimeSpot")) do
		setupSpot(part)
	end
	CollectionService:GetInstanceAddedSignal("CrimeSpot"):Connect(setupSpot)
	buildBoard()

	-- equipamento do Policial (taser, algema e pistola) enquanto tiver o emprego
	local function watch(player)
		local function job()
			InventoryService.setJobItems(player, isPolice(player) and { "Taser", "Algema", table.unpack(GameConfig.Weapons.PoliceKit) } or {})
			if not isPolice(player) and escort[player] then
				releaseTarget(player, "O policial te soltou.")
			end
			if isPolice(player) then
				task.defer(function()
					sendCalls(player)
					uiUpdate:FireClient(player, "CrimeWanted", { list = wantedList() })
				end)
			end
		end
		player:GetAttributeChangedSignal("Job"):Connect(job)
		job()
		if player.Character then
			task.spawn(addFriskPrompt, player, player.Character)
		end
		player.CharacterAdded:Connect(function(character)
			task.spawn(addFriskPrompt, player, character)
			stunUntil[player] = nil
			player:SetAttribute("Atordoado", nil)
			if escort[player] then
				releaseTarget(player, "O policial caiu: você se soltou!")
			end
			local cop = cuffedBy[player]
			if cop then
				releaseTarget(cop)
			end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, p in ipairs(Players:GetPlayers()) do
		watch(p)
	end
	PlayerDataService.onLoaded(function(player, data)
		if type(data.prison) == "table" and data.prison.pending then
			-- saiu do jogo algemado: volta preso (PrisonService) e perde estrelas e dinheiro sujo
			data.prison.pending = nil
			data.wanted, data.dirty = nil, nil
		end
		local w = type(data.wanted) == "table" and tonumber(data.wanted.p) or 0
		setWanted(player, w)
		setDirty(player, tonumber(data.dirty) or 0)
	end)
	Players.PlayerRemoving:Connect(function(player)
		robbing[player] = nil
		frisking[player], friskOpen[player] = nil, nil
		if escort[player] then
			releaseTarget(player)
		end
		local cop = cuffedBy[player]
		if cop then
			releaseTarget(cop, nil, true) -- a pena "pendente" fica salva: volta preso
			if cop.Parent then
				notice(cop, player.DisplayName .. " saiu do jogo algemado: vai voltar preso.")
			end
		end
		decayAt[player] = nil
		stunUntil[player] = nil
		task.defer(refreshWantedList)
	end)

	-- fuzil da PM no rack do arsenal
	local rack = prisonModel and prisonModel:FindFirstChild("RackArmas", true)
	if rack then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Pegar fuzil"
		prompt.ObjectText = "Arsenal da PM"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.MaxActivationDistance = 8
		prompt.RequiresLineOfSight = false
		prompt.Parent = rack
		prompt.Triggered:Connect(function(player)
			if not SecurityService.checkRate(player, "Rifle", 1) then
				return
			end
			if not isPolice(player) then
				return notice(player, "Só policial pega arma no arsenal.")
			end
			InventoryService.addJobItem(player, GameConfig.Weapons.PoliceRifle)
		end)
	end

	WeaponService.onKill(onKill)
	refreshWantedList()
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(tick)
			if not ok then
				warn("[CrimeService] " .. tostring(err))
			end
		end
	end)
	-- idade dos chamados no painel do policial
	task.spawn(function()
		while true do
			task.wait(5)
			if #calls > 0 then
				sendCalls()
			end
		end
	end)
	print(("[CrimeService] %d lugares para assaltar."):format(#CollectionService:GetTagged("CrimeSpot")))
end

return CrimeService
