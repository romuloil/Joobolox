-- LitoralController (ModuleScript)
-- Caminho: StarterPlayer > StarterPlayerScripts > Controllers > LitoralController
-- Marco 10.32: a parte do cliente na praia.
--   * Ondas da área de surfe (as mesmas em todo mundo: contadas pelo relógio do servidor).
--   * Surfe: com a prancha alugada, entrou no mar entre as boias = deita e rema (WASD / analógico).
--     Quando a onda chega e te levanta: ESPAÇO (pulo) = fica em pé. Em pé: desce a parede para
--     ganhar velocidade, sobe para frear, F / 🌀 = rasgada, ESPAÇO com velocidade = aéreo 360.
--     Pontos por tempo, velocidade e manobras (combo multiplica). O servidor confere e paga.
--   * Boias balançando, espirro da prancha de todo mundo que está surfando.
--   * Conversas dos banhistas e do instrutor (UIUpdate "PraiaDialog").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local SurfWaves = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SurfWaves"))
local MobileButtons = require(script.Parent:WaitForChild("MobileButtons"))
local DialogController = require(script.Parent:WaitForChild("DialogController"))

local LitoralController = {}

local S = GameConfig.Surf
local L = GameConfig.Litoral
local F, B = SurfWaves.FRONT, SurfWaves.BACK
local player = Players.LocalPlayer
local request -- RemoteEvent LitoralRequest

local CENTER = Vector3.new((S.X0 + S.X1) / 2, L.SeaLevel, (S.ZShore + S.ZOut) / 2)
local WIDTH = S.X1 - S.X0 + 20
local SPRAY_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

---------------------------------------------------------------------------
-- Ondas (só aparecem para quem está perto da área)
---------------------------------------------------------------------------

local waveFolder
local pool = {}

local function wavePart(class, name, color, transparency, parent)
	local p = Instance.new(class)
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Color = color
	p.Transparency = transparency
	p.Size = Vector3.new(WIDTH, 1, 1)
	p.Parent = parent
	return p
end

local function makeWave(i)
	local m = Instance.new("Model")
	m.Name = "Onda" .. i
	local w = {
		model = m,
		front = wavePart("WedgePart", "Frente", Color3.fromRGB(26, 118, 140), 0.12, m),
		back = wavePart("WedgePart", "Costas", Color3.fromRGB(34, 136, 156), 0.22, m),
		lip = wavePart("Part", "Crista", Color3.fromRGB(235, 248, 250), 0.25, m),
		white = wavePart("Part", "Espuma", Color3.fromRGB(240, 250, 252), 1, m),
	}
	m.Parent = waveFolder
	return w
end

local function hideWave(w)
	if w.shown then
		w.shown = false
		w.model.Parent = nil
	end
end

local function updateWaves(waves, near)
	for i = 1, 4 do
		local w = pool[i]
		local data = waves[i]
		if not near or not data or data.a < 0.08 then
			if w then
				hideWave(w)
			end
		else
			if not w then
				w = makeWave(i)
				pool[i] = w
			end
			if not w.shown then
				w.shown = true
				w.model.Parent = waveFolder
			end
			local a = data.a
			local y = L.SeaLevel + a / 2 - 0.08
			w.front.Size = Vector3.new(WIDTH, a, F)
			w.front.CFrame = CFrame.new(CENTER.X, y, data.z - F / 2)
			w.back.Size = Vector3.new(WIDTH, a, B)
			w.back.CFrame = CFrame.new(CENTER.X, y, data.z + B / 2) * CFrame.Angles(0, math.pi, 0)
			w.lip.Size = Vector3.new(WIDTH, 0.3, 1.2 + data.breaking * 2)
			w.lip.CFrame = CFrame.new(CENTER.X, L.SeaLevel + a + 0.05, data.z + 0.3)
			w.lip.Transparency = a > 1.2 and 0.55 - data.breaking * 0.45 or 0.9
			-- quebrando: espuma branca na frente
			w.white.Size = Vector3.new(WIDTH, 0.25, F + 6)
			w.white.CFrame = CFrame.new(CENTER.X, L.SeaLevel + 0.1, data.z - (F + 6) / 2)
			w.white.Transparency = 1 - math.clamp(data.breaking, 0, 1) * 0.7
		end
	end
end

---------------------------------------------------------------------------
-- HUD do surfe
---------------------------------------------------------------------------

local hud, hint, score, popup
local function ensureHud()
	if hud and hud.Parent then
		return
	end
	hud = Instance.new("ScreenGui")
	hud.Name = "SurfeHUD"
	hud.ResetOnSpawn = false
	hud.Enabled = false
	hud.Parent = player:WaitForChild("PlayerGui")
	local function label(name, pos, size, color, font)
		local t = Instance.new("TextLabel")
		t.Name = name
		t.AnchorPoint = Vector2.new(0.5, 0)
		t.Position = pos
		t.Size = size
		t.BackgroundTransparency = 1
		t.Font = font or Enum.Font.GothamBold
		t.TextScaled = true
		t.TextColor3 = color
		t.TextStrokeTransparency = 0.4
		t.Text = ""
		t.Parent = hud
		return t
	end
	hint = label("Dica", UDim2.new(0.5, 0, 0, 92), UDim2.new(0.6, 0, 0, 30), Color3.new(1, 1, 1), Enum.Font.GothamMedium)
	score = label("Pontos", UDim2.new(0.5, 0, 0, 126), UDim2.new(0.4, 0, 0, 40), Color3.fromRGB(255, 220, 80))
	popup = label("Manobra", UDim2.new(0.5, 0, 0.3, 0), UDim2.new(0.5, 0, 0, 54), Color3.fromRGB(120, 230, 255), Enum.Font.FredokaOne)
end

local popupUntil = 0
local function showPopup(text, color)
	ensureHud()
	popup.Text = text
	popup.TextColor3 = color or Color3.fromRGB(120, 230, 255)
	popupUntil = os.clock() + 1.6
end

---------------------------------------------------------------------------
-- Surfe do jogador local
---------------------------------------------------------------------------

local st = { mode = nil } -- mode: nil, "remando", "surfando", "ar", "caiu"
local lastHint = 0

local function send(kind, data)
	if request then
		request:FireServer(kind, data)
	end
end

local function myParts()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not root or hum.Health <= 0 then
		return nil
	end
	return char, hum, root
end

local function attach(root, hum)
	if st.lv and st.lv.Parent then
		return
	end
	local att = Instance.new("Attachment")
	att.Name = "SurfeAtt"
	att.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Name = "SurfeVel"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxForce = math.huge
	lv.VectorVelocity = Vector3.zero
	lv.Parent = root
	local ao = Instance.new("AlignOrientation")
	ao.Name = "SurfeGiro"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.MaxTorque = math.huge
	ao.Responsiveness = 60
	ao.CFrame = root.CFrame.Rotation
	ao.Parent = root
	st.att, st.lv, st.ao = att, lv, ao
	hum.PlatformStand = true
end

local function detach()
	for _, k in ipairs({ "lv", "ao", "att" }) do
		if st[k] then
			st[k]:Destroy()
			st[k] = nil
		end
	end
	local _, hum = myParts()
	if hum then
		hum.PlatformStand = false
	end
end

local function setMode(mode, serverState)
	st.mode = mode
	st.modeAt = os.clock()
	if serverState then
		st.sent = serverState
		st.sentAt = os.clock()
		send("Surfe", serverState)
	end
	MobileButtons.show("surfe_manobra", mode == "surfando")
end

local function ridePoints()
	return math.floor(st.points or 0)
end

local function endRide(reason)
	local pts = ridePoints()
	if reason == "caiu" then
		pts = math.floor(pts * 0.5)
	end
	if st.rideStart and pts > 0 then
		send("Onda", { pontos = pts, tempo = os.clock() - st.rideStart, manobras = st.tricks or 0 })
	end
	st.rideStart = nil
	st.points = 0
	st.tricks = 0
	st.mult = 1
	if reason == "caiu" then
		showPopup(pts > 0 and ("💦 Vacilou! %d pts"):format(pts) or "💦 Vacilou!", Color3.fromRGB(255, 140, 120))
	elseif pts > 0 then
		showPopup(("🌊 Onda: %d pontos!"):format(pts), Color3.fromRGB(255, 220, 80))
	end
end

local function startPaddle(root, hum)
	attach(root, hum)
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	st.heading = look.Magnitude > 0.1 and look.Unit or Vector3.new(0, 0, 1)
	st.vel = Vector3.zero
	setMode("remando", "remando")
end

local function stopSurf(state)
	if st.mode == "surfando" or st.mode == "ar" then
		endRide("fim")
	end
	detach()
	setMode(nil, state or "carregando")
	ensureHud()
	hud.Enabled = false
end

local function findWave(id, waves)
	for _, w in ipairs(waves) do
		if w.id == id then
			return w
		end
	end
	return nil
end

-- a onda que pode ser pega agora (o surfista está na parede da frente, e ela já está alta)
local function catchable(pos, waves)
	for _, w in ipairs(waves) do
		local d = pos.Z - w.z
		if d > -F - 2 and d < 3 and w.a >= 1.3 and w.breaking < 0.8 then
			return w
		end
	end
	return nil
end

local function startRide(root, w)
	st.waveId = w.id
	st.u = math.clamp(root.Position.Z - w.z, -F + 1, -1)
	st.x = root.Position.X
	local side = st.heading.X
	if math.abs(side) < 0.2 then
		side = root.Position.X < CENTER.X and 1 or -1
	end
	st.dir = Vector3.new(side > 0 and 1 or -1, 0, -0.35).Unit
	st.speed = S.RideSpeed * 0.75
	st.points = 0
	st.tricks = 0
	st.mult = 1
	st.lastTrick = 0
	st.lean = 0
	st.spin = 0
	st.rideStart = os.clock()
	setMode("surfando", "surfando")
	showPopup("🏄 EM PÉ!", Color3.fromRGB(140, 255, 160))
end

local function wipeout(char)
	endRide("caiu")
	detach()
	setMode("caiu", "caiu")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root then
		root.AssemblyLinearVelocity = Vector3.new(0, 6, 0)
	end
end

local function addTrick(name, points)
	local now = os.clock()
	if now - (st.lastTrick or 0) < 4 then
		st.mult = math.min((st.mult or 1) + 0.25, 2.5)
	else
		st.mult = 1
	end
	st.lastTrick = now
	st.tricks = (st.tricks or 0) + 1
	local gain = math.floor(points * st.mult)
	st.points = (st.points or 0) + gain
	showPopup(("%s +%d%s"):format(name, gain, st.mult > 1 and ("  x%.2g"):format(st.mult) or ""))
end

local function tryJump()
	local char, _, root = myParts()
	if not char then
		return
	end
	if st.mode == "remando" then
		st.jumpAt = os.clock()
	elseif st.mode == "surfando" then
		if st.speed >= 17 and os.clock() - (st.airAt or 0) > 1.2 then
			st.mode = "ar"
			st.airAt = os.clock()
			st.vy = 25
			st.y = root.Position.Y
			st.spin = 0
		end
	end
end

local function tryCutback()
	if st.mode ~= "surfando" or os.clock() - (st.cutAt or 0) < 1.3 then
		return
	end
	if st.speed < 14 then
		showPopup("Precisa de velocidade!", Color3.fromRGB(255, 200, 120))
		return
	end
	st.cutAt = os.clock()
	st.dir = Vector3.new(-st.dir.X, 0, math.abs(st.dir.Z) * 0.6 + 0.25).Unit -- vira subindo a parede
	st.speed *= 0.78
	st.burst = true
	addTrick("🌀 RASGADA!", 120)
end

local function hintText(text)
	ensureHud()
	hint.Text = text
end

local function stepSurf(dt, waves, t)
	local char, hum, root = myParts()
	if not char then
		if st.mode then
			st.mode = nil
			st.lv, st.ao, st.att = nil, nil, nil
		end
		return
	end
	local hasBoard = char:FindFirstChild("PranchaSurfe") ~= nil
	local pos = root.Position
	if not st.mode then
		if not hasBoard or hum.SeatPart then
			return
		end
		-- entrou no mar entre as boias (fundo o bastante): deita e rema
		local inWater = hum:GetState() == Enum.HumanoidStateType.Swimming or pos.Y < L.SeaLevel + 1.5
		if inWater and pos.X > S.X0 and pos.X < S.X1 and pos.Z > S.ZShore + 12 and pos.Z < S.ZOut then
			startPaddle(root, hum)
		elseif SurfWaves.inZone(pos, 60) and pos.Z < S.ZShore + 12 and os.clock() - lastHint > 8 and pos.Z > L.SeaZ - 30 then
			lastHint = os.clock()
			showPopup("🏄 Entre mais no mar (entre as boias) para remar", Color3.fromRGB(200, 240, 255))
		end
		return
	end
	if not hasBoard then
		stopSurf(nil)
		return
	end
	ensureHud()
	hud.Enabled = true
	-- o servidor não pegou a mudança (ex.: chegou antes da posição): manda de novo
	if st.sent and char:GetAttribute("Surfe") ~= st.sent and os.clock() - (st.sentAt or 0) > 1.5 then
		st.sentAt = os.clock()
		send("Surfe", st.sent)
	end
	if os.clock() > popupUntil then
		popup.Text = ""
	end
	if st.mode == "caiu" then
		hintText("💦 Caiu! Já já você sobe na prancha de novo...")
		score.Text = ""
		if os.clock() - st.modeAt > 1.8 then
			if pos.Z > S.ZShore + 4 and SurfWaves.inZone(pos, 10) then
				startPaddle(root, hum)
			else
				stopSurf("carregando")
			end
		end
		return
	end
	if not st.lv or not st.lv.Parent then
		attach(root, hum)
	end
	local move = hum.MoveDirection * Vector3.new(1, 0, 1)
	if st.mode == "remando" then
		-- saiu pela areia (raso): levanta e anda
		if pos.Z < S.ZShore + 4 then
			stopSurf("carregando")
			return
		end
		local desired = move * S.PaddleSpeed
		st.vel = st.vel:Lerp(desired, 1 - math.exp(-2.2 * dt))
		-- a onda passando empurra para a areia
		local push = 0
		for _, w in ipairs(waves) do
			local d = pos.Z - w.z
			if d > -F and d < B * 0.5 then
				push = math.max(push, w.a * (d < 0 and 2.4 or 1.2))
			end
		end
		local vel = st.vel + Vector3.new(0, 0, -push)
		-- limite das boias
		if pos.X < S.X0 + 3 then
			vel = Vector3.new(math.max(vel.X, 6), 0, vel.Z)
		elseif pos.X > S.X1 - 3 then
			vel = Vector3.new(math.min(vel.X, -6), 0, vel.Z)
		end
		if pos.Z > S.ZOut - 3 then
			vel = Vector3.new(vel.X, 0, math.min(vel.Z, -6))
		end
		if (pos.X < S.X0 + 3 or pos.X > S.X1 - 3 or pos.Z > S.ZOut - 3) and os.clock() - lastHint > 4 then
			lastHint = os.clock()
			showPopup("🟠 Limite das boias!", Color3.fromRGB(255, 170, 80))
		end
		if st.vel.Magnitude > 1.5 then
			st.heading = st.heading:Lerp(st.vel.Unit, 1 - math.exp(-4 * dt))
			if st.heading.Magnitude > 0.01 then
				st.heading = st.heading.Unit
			end
		end
		local surface = SurfWaves.height(pos.X, pos.Z, t, waves)
		local bob = math.sin(os.clock() * 2.2) * 0.12
		local vy = math.clamp((surface + 1.05 + bob - pos.Y) * 8, -25, 25)
		st.lv.VectorVelocity = Vector3.new(vel.X, vy, vel.Z)
		local h = st.heading
		st.ao.CFrame = CFrame.fromMatrix(Vector3.zero, Vector3.new(-h.Z, 0, h.X), h, Vector3.new(0, 1, 0))
		-- pegar a onda
		local w = catchable(pos, waves)
		if st.jumpAt and os.clock() - st.jumpAt < 0.5 then
			if w then
				st.jumpAt = nil
				startRide(root, w)
				return
			end
		elseif st.jumpAt then
			st.jumpAt = nil
			local soon = false
			for _, ww in ipairs(waves) do
				if ww.z > pos.Z and ww.z - pos.Z < S.WaveSpeed * 4 then
					soon = true
				end
			end
			showPopup(soon and "Quase! Espera ela chegar e te levantar" or "🌊 Sem onda aqui: ela vem do fundo", Color3.fromRGB(200, 240, 255))
		end
		if w then
			hintText("🏄 AGORA! Aperte ESPAÇO (pulo) para ficar em pé!")
		else
			local eta
			for _, ww in ipairs(waves) do
				if ww.z > pos.Z then
					local e = (ww.z - pos.Z) / S.WaveSpeed
					eta = eta and math.min(eta, e) or e
				end
			end
			hintText(eta and ("🌊 Onda chegando em %ds • fique de frente para a areia"):format(math.ceil(eta)) or "🌊 Esperando a próxima onda... reme para o fundo")
		end
		score.Text = ""
		return
	end
	-- surfando / aéreo
	local w = findWave(st.waveId, waves)
	if not w or w.a < 0.7 or w.z < S.ZBreak + 2 then
		local pts = ridePoints()
		endRide("fim")
		if pos.Z < S.ZShore + 8 then
			stopSurf("carregando")
		else
			setMode("remando", "remando")
			st.vel = Vector3.zero
			st.heading = Vector3.new(0, 0, -1)
		end
		if pts <= 0 then
			showPopup("A onda acabou!", Color3.fromRGB(200, 240, 255))
		end
		return
	end
	local slope = w.a / F
	if st.mode == "surfando" then
		-- vira para onde o jogador manda (mais devagar quando está rápido)
		if move.Magnitude > 0.2 then
			local want = move.Unit
			local turn = (2.8 - math.min(st.speed, 40) * 0.03) * dt
			local before = st.dir
			st.dir = st.dir:Lerp(want, math.clamp(turn, 0, 1))
			if st.dir.Magnitude < 0.05 then
				st.dir = before
			end
			st.dir = st.dir.Unit
			st.lean = math.clamp(before:Cross(st.dir).Y * 25, -0.55, 0.55)
		else
			st.lean *= math.exp(-4 * dt)
			-- sem comando: a prancha volta sozinha para o meio da parede (e para de subir depois da rasgada)
			st.u += (-F * 0.45 - st.u) * 1.1 * dt
			st.dir = Vector3.new(st.dir.X, 0, st.dir.Z + (-0.2 - st.dir.Z) * math.min(1, 2 * dt)).Unit
		end
		-- descer a parede acelera, subir freia
		st.speed += -st.dir.Z * slope * 30 * dt
		st.speed += (S.RideSpeed - st.speed) * 0.3 * dt
		st.speed = math.clamp(st.speed, 6, 46)
		st.u += st.dir.Z * st.speed * dt
		st.x += st.dir.X * st.speed * dt
		-- pontos: tempo + velocidade (mais no "tubo" perto da crista)
		local pocket = st.u > -F * 0.5 and 1.3 or 1
		st.points = (st.points or 0) + dt * (6 + st.speed * 0.55) * pocket * (st.mult or 1)
		if st.u > 1.2 then
			-- passou da crista: ficou para trás da onda
			endRide("fim")
			setMode("remando", "remando")
			st.vel = Vector3.zero
			showPopup("Passou da crista!", Color3.fromRGB(200, 240, 255))
			return
		elseif st.u < -F - 3 then
			if w.breaking > 0.45 then
				wipeout(char)
			else
				endRide("fim")
				setMode("remando", "remando")
				st.vel = Vector3.zero
				showPopup("Desceu demais da onda!", Color3.fromRGB(200, 240, 255))
			end
			return
		end
		if st.x < S.X0 + 4 or st.x > S.X1 - 4 then
			endRide("fim")
			setMode("remando", "remando")
			st.vel = Vector3.zero
			st.heading = Vector3.new(st.x < S.X0 + 4 and 1 or -1, 0, 0)
			showPopup("🟠 Chegou nas boias! Fim da onda", Color3.fromRGB(255, 170, 80))
			return
		end
		st.u = math.clamp(st.u, -F - 4, 2)
		local surface = SurfWaves.height(st.x, w.z + st.u, t, waves)
		local target = Vector3.new(st.x, surface + 0.2, w.z + st.u)
		local feed = Vector3.new(st.dir.X * st.speed, 0, -S.WaveSpeed + st.dir.Z * st.speed)
		local v = feed + (target - pos) * Vector3.new(6, 0, 6)
		local vy = math.clamp((surface + (hum.HipHeight + root.Size.Y / 2) + 0.35 - pos.Y) * 10, -30, 30)
		st.lv.VectorVelocity = Vector3.new(v.X, vy, v.Z)
		local travel = feed.Magnitude > 0.5 and feed.Unit or Vector3.new(1, 0, 0)
		st.ao.CFrame = CFrame.lookAt(Vector3.zero, travel) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(st.lean, 0, 0)
		hintText(MobileButtons.enabled and "Analógico: descer/subir a onda • 🌀 rasgada • pulo: aéreo" or "WASD: descer/subir a onda • F: rasgada • ESPAÇO: aéreo")
	else -- "ar"
		st.vy -= 70 * dt
		st.x += st.dir.X * st.speed * dt
		st.spin += dt * (math.pi * 2 / 0.72)
		local surface = SurfWaves.height(st.x, w.z + st.u, t, waves)
		local feet = hum.HipHeight + root.Size.Y / 2 + 0.35
		local feed = Vector3.new(st.dir.X * st.speed, 0, -S.WaveSpeed + st.dir.Z * st.speed * 0.3)
		local target = Vector3.new(st.x, pos.Y, w.z + st.u)
		local v = feed + (target - pos) * Vector3.new(6, 0, 6)
		st.lv.VectorVelocity = Vector3.new(v.X, st.vy, v.Z)
		local travel = feed.Magnitude > 0.5 and feed.Unit or Vector3.new(1, 0, 0)
		st.ao.CFrame = CFrame.lookAt(Vector3.zero, travel) * CFrame.Angles(0, math.rad(90) + math.min(st.spin, math.pi * 2), 0)
		if st.vy < 0 and pos.Y <= surface + feet + 0.3 then
			if st.u > -F - 2 and st.u < 1.5 and st.spin > math.pi * 1.5 then
				st.mode = "surfando"
				st.speed *= 0.9
				st.burst = true
				addTrick("🛫 AÉREO 360!", 250)
			else
				wipeout(char)
				return
			end
		end
	end
	score.Text = ("🏄 %d pts%s"):format(ridePoints(), (st.mult or 1) > 1 and ("   combo x%.2g"):format(st.mult) or "")
end

---------------------------------------------------------------------------
-- Espirro das pranchas (de todo mundo) e boias
---------------------------------------------------------------------------

local function sprayOf(board)
	local main = board.PrimaryPart or board:FindFirstChildWhichIsA("BasePart", true)
	if not main then
		return nil
	end
	local e = main:FindFirstChild("EspirroSurfe")
	if not e then
		e = Instance.new("ParticleEmitter")
		e.Name = "EspirroSurfe"
		e.Texture = SPRAY_TEXTURE
		e.Color = ColorSequence.new(Color3.fromRGB(245, 252, 255))
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 2.4) })
		e.Lifetime = NumberRange.new(0.4, 0.8)
		e.Speed = NumberRange.new(6, 13)
		e.SpreadAngle = Vector2.new(35, 35)
		e.Acceleration = Vector3.new(0, -32, 0)
		e.EmissionDirection = Enum.NormalId.Back
		e.Rate = 0
		e.LightInfluence = 0.4
		e.Parent = main
	end
	return e
end

local function stepSurfers()
	for _, char in ipairs(CollectionService:GetTagged("Surfista")) do
		local board = char:FindFirstChild("PranchaSurfe")
		if board then
			local state = char:GetAttribute("Surfe")
			local e = sprayOf(board)
			if e then
				e.Rate = state == "surfando" and 55 or state == "remando" and 4 or 0
				if char == player.Character and st.burst then
					st.burst = false
					e:Emit(40)
				end
			end
			-- prancha some dentro de carro/moto
			local hum = char:FindFirstChildOfClass("Humanoid")
			local hidden = hum and hum.SeatPart ~= nil
			if board:GetAttribute("Escondida") ~= hidden then
				board:SetAttribute("Escondida", hidden)
				for _, d in ipairs(board:GetDescendants()) do
					if d:IsA("BasePart") then
						d.LocalTransparencyModifier = hidden and 1 or 0
					end
				end
			end
		end
	end
end

local buoys = {}
local function stepBuoys(t, waves, camPos)
	if (camPos - CENTER).Magnitude > 900 then
		return
	end
	local now = os.clock()
	for _, b in ipairs(buoys) do
		local base = b:GetAttribute("Base")
		if b.Parent and typeof(base) == "CFrame" then
			local p = base.Position
			local y = SurfWaves.height(p.X, p.Z, t, waves) - L.SeaLevel
			b.CFrame = base + Vector3.new(0, y + math.sin(now * 1.6 + p.X * 0.05 + p.Z * 0.03) * 0.3, 0)
		end
	end
end

-- bolinhas do frescobol (vão e voltam em arco, 1,4 s por batida)
local balls = {}
local function stepFrescobol(camPos)
	local now = Workspace:GetServerTimeNow()
	for _, b in ipairs(balls) do
		local a, c = b:GetAttribute("PA"), b:GetAttribute("PB")
		if b.Parent and typeof(a) == "Vector3" and typeof(c) == "Vector3" and (camPos - a).Magnitude < 260 then
			local k = (now / 1.4) % 2
			local t = k < 1 and k or 2 - k
			local p = a:Lerp(c, t) + Vector3.new(0, math.sin(t * math.pi) * 2.6, 0)
			b.CFrame = CFrame.new(p)
		end
	end
end

-- barcos ancorados balançando
local boats = {}
local function stepBoats(camPos)
	local now = os.clock()
	for _, m in ipairs(boats) do
		local base = m:GetAttribute("Base")
		if m.Parent and typeof(base) == "CFrame" and (camPos - base.Position).Magnitude < 1400 then
			local ph = base.Position.X * 0.01
			m:PivotTo(base * CFrame.new(0, math.sin(now * 0.9 + ph) * 0.5, 0) * CFrame.Angles(math.sin(now * 0.7 + ph) * 0.05, 0, math.sin(now * 1.1 + ph) * 0.07))
		end
	end
end

-- gaivotas voando em círculos em cima da areia (só no aparelho de quem está perto)
local gulls
local function makeGull(parent)
	local m = Instance.new("Model")
	m.Name = "Gaivota"
	local function gp(name, size, color)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = m
		return p
	end
	local body = gp("Corpo", Vector3.new(0.7, 0.6, 2), Color3.fromRGB(245, 245, 245))
	local wl = gp("AsaE", Vector3.new(2.6, 0.12, 0.9), Color3.fromRGB(170, 175, 185))
	local wr = gp("AsaD", Vector3.new(2.6, 0.12, 0.9), Color3.fromRGB(170, 175, 185))
	local beak = gp("Bico", Vector3.new(0.18, 0.18, 0.5), Color3.fromRGB(250, 190, 40))
	m.Parent = parent
	return { model = m, body = body, wl = wl, wr = wr, beak = beak }
end

local function stepGulls(camPos)
	local beachNear = math.abs(camPos.Z - 3750) < 700 and math.abs(camPos.X) < L.BeachHalf + 400
	if not beachNear then
		if gulls then
			gulls.folder.Parent = nil
		end
		return
	end
	if not gulls then
		gulls = { folder = Instance.new("Folder"), list = {} }
		gulls.folder.Name = "Gaivotas"
		for i = 1, 7 do
			local g = makeGull(gulls.folder)
			g.center = Vector3.new(math.random(-L.BeachHalf + 200, L.BeachHalf - 200), math.random(28, 48), math.random(3640, 3900))
			g.radius = math.random(25, 60)
			g.speed = (math.random() < 0.5 and -1 or 1) * (0.25 + math.random() * 0.2)
			g.phase = math.random() * 6.28
			table.insert(gulls.list, g)
		end
	end
	gulls.folder.Parent = Workspace
	local now = os.clock()
	for _, g in ipairs(gulls.list) do
		-- vai mudando de lugar devagar, seguindo quem está na praia
		if (g.center - camPos).Magnitude > 600 then
			g.center = Vector3.new(camPos.X + math.random(-300, 300), math.random(28, 48), math.random(3640, 3900))
		end
		local a = g.phase + now * g.speed
		local pos = g.center + Vector3.new(math.cos(a) * g.radius, math.sin(now * 0.6 + g.phase) * 3, math.sin(a) * g.radius)
		local dir = Vector3.new(-math.sin(a), 0, math.cos(a)) * math.sign(g.speed)
		local cf = CFrame.lookAt(pos, pos + dir) * CFrame.Angles(0, 0, -0.25 * math.sign(g.speed))
		local flap = math.sin(now * 7 + g.phase) * 0.5
		g.body.CFrame = cf
		g.beak.CFrame = cf * CFrame.new(0, 0.05, -1.2)
		g.wl.CFrame = cf * CFrame.Angles(0, 0, flap) * CFrame.new(-1.5, 0, 0)
		g.wr.CFrame = cf * CFrame.Angles(0, 0, -flap) * CFrame.new(1.5, 0, 0)
	end
end

---------------------------------------------------------------------------
-- Início
---------------------------------------------------------------------------

function LitoralController.init()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	task.spawn(function()
		request = remotes:WaitForChild(GameConfig.Remotes.LitoralRequest, 30)
	end)
	local uiUpdate = remotes:WaitForChild(GameConfig.Remotes.UIUpdate)
	uiUpdate.OnClientEvent:Connect(function(kind, data)
		if kind == "PraiaDialog" and typeof(data) == "table" and not DialogController.isOpen() then
			task.spawn(DialogController.show, tostring(data.speaker or "Banhista"), data.lines or { "..." }, { { id = "ok", text = data.ok or "Valeu!" } })
		end
	end)

	waveFolder = Instance.new("Folder")
	waveFolder.Name = "OndasSurfe"
	waveFolder.Parent = Workspace

	for _, b in ipairs(CollectionService:GetTagged("Boia")) do
		table.insert(buoys, b)
	end
	CollectionService:GetInstanceAddedSignal("Boia"):Connect(function(b)
		table.insert(buoys, b)
	end)
	for tag, list in pairs({ BolaFrescobol = balls, Barco = boats }) do
		for _, b in ipairs(CollectionService:GetTagged(tag)) do
			table.insert(list, b)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(b)
			table.insert(list, b)
		end)
	end

	UserInputService.JumpRequest:Connect(tryJump)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.F or input.KeyCode == Enum.KeyCode.ButtonB then
			tryCutback()
		end
	end)
	MobileButtons.add("surfe_manobra", { icon = "🌀", title = "Rasgada", slots = { 2, 1, 3 }, hold = false, onPress = function(began)
		if began ~= false then
			tryCutback()
		end
	end })
	MobileButtons.show("surfe_manobra", false)

	player.CharacterAdded:Connect(function()
		st = { mode = nil }
		MobileButtons.show("surfe_manobra", false)
		if hud then
			hud.Enabled = false
		end
	end)

	RunService.Heartbeat:Connect(function(dt)
		local cam = Workspace.CurrentCamera
		local camPos = cam and cam.CFrame.Position or CENTER
		local near = (camPos - CENTER).Magnitude < 900
		stepFrescobol(camPos)
		stepBoats(camPos)
		stepGulls(camPos)
		local _, _, root = myParts()
		if not near and not st.mode and not (root and (root.Position - CENTER).Magnitude < 900) then
			updateWaves({}, false)
			return
		end
		local t = Workspace:GetServerTimeNow()
		local waves = SurfWaves.active(t)
		updateWaves(waves, near)
		stepSurf(math.min(dt, 0.1), waves, t)
		stepSurfers()
		stepBuoys(t, waves, camPos)
	end)
end

return LitoralController
