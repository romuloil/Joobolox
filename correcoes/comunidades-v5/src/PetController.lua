-- PetController (ModuleScript)
-- Caminho: StarterPlayer > StarterPlayerScripts > Controllers > PetController
-- Marco 7: faz os pets (pasta Workspace.Pets, criados pelo PetService) andarem atrás do dono.
-- Tudo aqui é só visual e roda em cada cliente: o pet anda aos pulinhos, mexe as pernas,
-- abana o rabo, senta quando o dono para e some enquanto o dono está num carro ou banco.
-- Também mostra o aviso "Carinho" (C) em cada pet e a tela de adoção do Duto Pet Shop.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local UIScaler = require(script.Parent:WaitForChild("UIScaler"))

local PetController = {}

local player = Players.LocalPlayer
local petRequest
local gui, panel

local FOLLOW_BACK, FOLLOW_SIDE = 3.5, 2 -- lugar do pet: atrás e ao lado do dono
local SNAP = 60 -- longe disso (teleporte, entrou em casa) o pet aparece direto no lugar

local states = {} -- states[model] = { pos, yaw, idle, phase, wag, hidden, parts }

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function ignoreList()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	for _, name in ipairs({ "Pets", "Vehicles", "NPCs", "MarcasDePneu" }) do
		local f = Workspace:FindFirstChild(name)
		if f then
			table.insert(list, f)
		end
	end
	return list
end

local function groundAt(pos, fallback)
	local hit = Workspace:Raycast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -14, 0), rayParams)
	return hit and hit.Position.Y or fallback
end

-- Guarda como cada peça fica em relação ao Root (feito uma vez por pet)
local function setup(model)
	local root = model.PrimaryPart
	if not root then
		return nil
	end
	local want = model:GetAttribute("PartCount")
	if want then
		local have = 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				have += 1
			end
		end
		if have < want then
			return nil -- ainda chegando (o dragão tem 30 e poucas peças)
		end
	end
	local st = { yaw = 0, idle = 0, phase = 0, wag = 0, flap = 0, love = 0, hidden = false, parts = {}, legs = {}, fx = {} }
	-- Marco 10.3: pet grande (dragão) fica mais longe do dono
	st.back = model:GetAttribute("FollowBack") or FOLLOW_BACK
	st.side = model:GetAttribute("FollowSide") or FOLLOW_SIDE
	-- Marco 10.4: o lugar de cada peça é guardado em relação ao Root COMO O SERVIDOR MONTOU
	-- (base). Modelo grande (dragão) chega aos pedaços no cliente: as peças que chegam depois
	-- também entram (antes ficavam paradas no lugar onde o pet nasceu)
	local base = root.CFrame
	local function add(p)
		if p:IsA("ParticleEmitter") or p:IsA("Light") then
			table.insert(st.fx, p) -- aura do dragão: some junto com o pet
			p.Enabled = not st.hidden
		elseif p:IsA("BasePart") then
			local entry = { part = p, rel = base:ToObjectSpace(p.CFrame) }
			local pivot = p:GetAttribute("Pivot")
			if typeof(pivot) == "Vector3" then
				entry.pivot = pivot
				entry.offset = p:GetAttribute("Offset") or Vector3.zero
				entry.pitch = math.rad(p:GetAttribute("Pitch") or 0)
				entry.kind = p.Name == "Tail" and "tail" or (p.Name:sub(1, 4) == "Wing" and "wing" or "leg")
				entry.mesh = p:GetAttribute("MeshJoint") == true -- Marco 9.10: perna/rabo do modelo 3D
				entry.front = p.Name:sub(4, 4) == "F"
				entry.left = p.Name:sub(5, 5) == "L" -- "LegFL" e "WingL": a letra 5 é o lado
				if not entry.mesh then
					st.legs[p.Name] = entry
				end
			end
			if st.hidden then
				p.LocalTransparencyModifier = 1
			end
			table.insert(st.parts, entry)
		end
	end
	for _, p in ipairs(model:GetDescendants()) do
		add(p)
	end
	model.DescendantAdded:Connect(add)
	-- patinhas acompanham a perna delas
	for _, entry in ipairs(st.parts) do
		local legName = entry.part:GetAttribute("Leg")
		local leg = legName and st.legs[legName]
		if leg then
			entry.follow = leg
			entry.relToLeg = CFrame.new(leg.pivot + leg.offset):ToObjectSpace(entry.rel)
		end
	end
	-- aviso de carinho (criado só neste cliente)
	local ownerId = model:GetAttribute("Owner")
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PetPrompt"
	prompt.ActionText = "Carinho"
	prompt.ObjectText = ownerId == player.UserId and "Seu pet" or (tostring(model:GetAttribute("PetName") or "Pet"))
	-- Marco 10.6: tecla C (antes era E). O pet anda colado no dono e o aviso dele "roubava" o E
	-- das portas e elevadores (no vídeo do Luís, o elevador da cobertura não aparecia)
	prompt.KeyboardKeyCode = Enum.KeyCode.C
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OneGlobally
	prompt.Enabled = false -- Marco 10.15: o laço do init liga só quando faz sentido (promptAllowed)
	prompt.Triggered:Connect(function()
		-- vira de frente para o pet (fica parecendo que está fazendo carinho nele)
		local char = player.Character
		local myRoot = char and char:FindFirstChild("HumanoidRootPart")
		if myRoot and root.Parent then
			local p = myRoot.Position
			local flat = Vector3.new(root.Position.X, p.Y, root.Position.Z)
			if (flat - p).Magnitude > 0.5 then
				myRoot.CFrame = CFrame.lookAt(p, flat)
			end
		end
		petRequest:FireServer("Pet", ownerId)
	end)
	st.prompt = prompt
	states[model] = st
	return st
end

-- Marco 10.7: pet com esqueleto (Dragão de Cristal): toca as animações do próprio .fbx (idle, walk,
-- flap) mexendo os ossos direto (Bone.Transform), sem Animator e sem publicar nada. Os quadros estão
-- no ModuleScript Shared/<AnimData> (tools/dragaoanims.py); entre um quadro e outro o giro é
-- interpolado, e na troca de animação as duas se misturam por 0,25 s.
-- Parado = Idle, andando = Walk (mais rápido quando corre), carinho ou dono no ar = Flap.
local BLEND = 0.25
local animCache = {}

local function animData(name)
	if animCache[name] == nil then
		animCache[name] = false
		local mod = ReplicatedStorage:WaitForChild("Shared"):FindFirstChild(name)
		local ok, data = pcall(function()
			return mod and require(mod)
		end)
		if ok and type(data) == "table" and data.FPS then
			-- cada quadro vira um CFrame (só giro) uma vez só
			for _, clip in pairs(data) do
				if type(clip) == "table" and clip.Bones then
					clip.CF = {}
					for bone, q in pairs(clip.Bones) do
						local list = {}
						for i = 0, clip.Frames - 1 do
							local k = i * 4
							list[i] = CFrame.new(0, 0, 0, q[k + 1], q[k + 2], q[k + 3], q[k + 4])
						end
						clip.CF[bone] = list
					end
				end
			end
			animCache[name] = data
		else
			warn("[PetController] Animações do pet não carregaram: " .. tostring(name))
		end
	end
	return animCache[name] or nil
end

local function rigSetup(model, st)
	if st.rig ~= nil then
		return st.rig
	end
	local name = model:GetAttribute("AnimData")
	local data = model:GetAttribute("Rig") and type(name) == "string" and name ~= "" and animData(name)
	if not data then
		st.rig = false
		return false
	end
	local bones = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Bone") then
			bones[d.Name] = d
		end
	end
	if next(bones) == nil then
		return nil -- os ossos ainda não chegaram; tenta no próximo quadro
	end
	local used = {}
	for _, clip in pairs(data) do
		if type(clip) == "table" and clip.CF then
			for name in pairs(clip.CF) do
				if bones[name] then
					used[name] = bones[name]
				end
			end
		end
	end
	st.rig = { data = data, bones = used, cur = { name = "Idle", t = 0 }, old = nil, w = 1 }
	return st.rig
end

local function pose(data, clipName, bone, t)
	local clip = data[clipName]
	local list = clip and clip.CF[bone]
	if not list then
		return CFrame.identity
	end
	local f = (t * data.FPS) % clip.Frames
	local i = math.floor(f)
	return list[i]:Lerp(list[(i + 1) % clip.Frames], f - i)
end

local function stepRig(rig, want, speed, dt)
	local data = rig.data
	if not data[want] then
		want = "Idle"
	end
	if rig.cur.name ~= want then
		rig.old = rig.cur
		rig.cur = { name = want, t = 0 }
		rig.w = 0
	end
	rig.cur.t += dt * (speed or 1)
	if rig.old then
		rig.old.t += dt
		rig.w = math.min(1, rig.w + dt / BLEND)
		if rig.w >= 1 then
			rig.old = nil
		end
	end
	for name, bone in pairs(rig.bones) do
		local c = pose(data, rig.cur.name, name, rig.cur.t)
		if rig.old then
			c = pose(data, rig.old.name, name, rig.old.t):Lerp(c, rig.w)
		end
		bone.Transform = c
	end
end

local function setHidden(st, hidden)
	if st.hidden == hidden then
		return
	end
	st.hidden = hidden
	for _, entry in ipairs(st.parts) do
		entry.part.LocalTransparencyModifier = hidden and 1 or 0
	end
	for _, fx in ipairs(st.fx) do
		fx.Enabled = not hidden
	end
	st.prompt.Enabled = not hidden
end

local function stepPet(model, st, dt, t)
	local owner = Players:GetPlayerByUserId(model:GetAttribute("Owner") or 0)
	local character = owner and owner.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid then
		return
	end
	local cf = hrp.CFrame
	local target = cf.Position - cf.LookVector * st.back + cf.RightVector * st.side
	target = Vector3.new(target.X, 0, target.Z)
	setHidden(st, humanoid.SeatPart ~= nil) -- no carro, na bike ou num banco: o pet "vai junto"

	if not st.pos or (target - st.pos).Magnitude > SNAP or st.hidden then
		st.pos = target
		st.y = nil
		st.yaw = math.atan2(-cf.LookVector.X, -cf.LookVector.Z)
	end
	local delta = target - st.pos
	local dist = delta.Magnitude
	local moving = dist > 0.6
	if moving then
		local ownerSpeed = Vector3.new(hrp.AssemblyLinearVelocity.X, 0, hrp.AssemblyLinearVelocity.Z).Magnitude
		local speed = math.min(dist * 3, ownerSpeed + 8, 45)
		st.pos += delta.Unit * math.min(dist, speed * dt)
		local wantYaw = math.atan2(-delta.X, -delta.Z)
		local diff = (wantYaw - st.yaw + math.pi) % (2 * math.pi) - math.pi
		st.yaw += diff * math.min(1, dt * 10)
		st.idle = 0
		st.phase += dt * math.clamp(speed, 4, 30) * 0.55 -- Marco 9.14: passos mais calmos
	else
		st.idle += dt
		-- parado: olha para o dono
		local look = Vector3.new(cf.Position.X, 0, cf.Position.Z) - st.pos
		if look.Magnitude > 0.1 then
			local wantYaw = math.atan2(-look.X, -look.Z)
			local diff = (wantYaw - st.yaw + math.pi) % (2 * math.pi) - math.pi
			st.yaw += diff * math.min(1, dt * 4)
		end
	end
	-- Marco 9.10: o chão é procurado a partir da altura do próprio pet (antes era a do dono:
	-- quando o dono pulava, o raio não chegava no chão e o pet "teleportava" para cima)
	local base = st.y or (hrp.Position.Y - 3)
	local ground = groundAt(Vector3.new(st.pos.X, base + 1, st.pos.Z), nil)
		or groundAt(Vector3.new(st.pos.X, hrp.Position.Y, st.pos.Z), base)
	if not st.y or ground > st.y + 1.2 then
		st.y = ground -- degrau alto: na hora
	elseif ground >= st.y then
		st.y += (ground - st.y) * math.min(1, dt * 18) -- Marco 9.14: calçada e emendas do chão sem "pulinho"
	else
		st.y = math.max(ground, st.y - 30 * dt) -- descer: cai rapidinho, sem pular
	end
	local y = st.y
	-- Marco 9.14: andando de verdade (o Luís achou que ele dava pulinhos): o corpo só balança um
	-- pouquinho a cada passo e as pernas fazem o resto
	-- (Marco 10.7: o pet com esqueleto já balança na animação dele)
	local rigged = model:GetAttribute("Rig") == true
	local bob = (moving and not rigged) and math.abs(math.sin(st.phase * 2)) * 0.06 or 0
	local sway = (moving and not rigged) and math.sin(st.phase * 2) * math.rad(2) or 0
	local root = CFrame.new(st.pos.X, y + bob, st.pos.Z) * CFrame.Angles(0, st.yaw, 0) * CFrame.Angles(0, 0, sway)
	-- sentado depois de um tempinho parado (inclina o corpo para trás)
	local sit = rigged and 0 or math.clamp((st.idle - 1.2) * 3, 0, 1)
	if sit > 0 then
		root = root * CFrame.new(0, 0, 0.75) * CFrame.Angles(math.rad(22) * sit, 0, 0) * CFrame.new(0, 0, -0.75)
	end
	if st.love > 0 then
		st.love -= dt
		root = root * CFrame.new(0, math.abs(math.sin(st.love * 12)) * 0.4, 0)
	end
	-- rabo: abana mais rápido quando está feliz (carinho) ou andando
	st.wag += dt * (st.love > 0 and 28 or (moving and 14 or 6))
	local wagAngle = math.sin(st.wag) * (st.love > 0 and 0.7 or 0.4)
	local swing = moving and math.sin(st.phase * 2) * 0.6 or 0
	-- Marco 10.3: asas do dragão: respiram devagar parado, batem andando e no carinho
	st.flap += dt * (st.love > 0 and 9 or (moving and 6 or 1.6))
	local flap = math.sin(st.flap) * (st.love > 0 and 0.5 or (moving and 0.3 or 0.08))

	local parts, cframes = {}, {}
	local legCf = {}
	for _, entry in ipairs(st.parts) do
		local c
		if entry.mesh then
			-- Marco 9.10: modelo 3D: gira a peça em volta do quadril (perna) ou da base (rabo)
			local rot
			if entry.kind == "tail" then
				rot = CFrame.Angles(0, wagAngle, 0)
			elseif entry.kind == "wing" then
				rot = CFrame.Angles(0, 0, entry.left and -flap or flap)
			else
				rot = CFrame.Angles(swing * 0.55 * ((entry.front == entry.left) and 1 or -1), 0, 0)
			end
			c = root * CFrame.new(entry.pivot) * rot * CFrame.new(-entry.pivot) * entry.rel
		elseif entry.kind == "tail" then
			c = root * CFrame.new(entry.pivot) * CFrame.Angles(0, wagAngle, 0) * CFrame.Angles(entry.pitch, 0, 0) * CFrame.new(entry.offset)
		elseif entry.kind == "leg" then
			local s = swing * ((entry.front == entry.left) and 1 or -1)
			c = root * CFrame.new(entry.pivot) * CFrame.Angles(s, 0, 0) * CFrame.new(entry.offset)
			legCf[entry] = c
		elseif entry.follow and legCf[entry.follow] then
			c = legCf[entry.follow] * entry.relToLeg
		else
			c = root * entry.rel
		end
		table.insert(parts, entry.part)
		table.insert(cframes, c)
	end
	Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	local rig = not st.hidden and rigSetup(model, st)
	if rig then
		local inAir = humanoid.FloorMaterial == Enum.Material.Air
		if st.love > 0 or inAir then
			stepRig(rig, "Flap", 1, dt)
		elseif moving then
			local speed = math.min(dist * 3, 45)
			stepRig(rig, "Walk", math.clamp(speed / 12, 0.6, 2), dt)
		else
			stepRig(rig, "Idle", 1, dt)
		end
	end
end

-- Coraçõezinhos subindo em cima do pet
local function hearts(model, count)
	local root = model.PrimaryPart
	if not root then
		return
	end
	count = count or 3
	for i = 1, count do
		task.delay((i - 1) * 0.12, function()
			if not root.Parent then
				return
			end
			local bb = Instance.new("BillboardGui")
			bb.Size = UDim2.fromOffset(40, 40)
			bb.StudsOffset = Vector3.new((i - (count + 1) / 2) * 0.7, 3, 0)
			bb.AlwaysOnTop = true
			bb.Adornee = root
			bb.Parent = root
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Text = "❤"
			label.TextScaled = true
			label.TextColor3 = Color3.fromRGB(240, 70, 110)
			label.Parent = bb
			local info = TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			TweenService:Create(bb, info, { StudsOffset = bb.StudsOffset + Vector3.new(0, 2.5, 0) }):Play()
			TweenService:Create(label, info, { TextTransparency = 1 }):Play()
			task.delay(1.3, function()
				bb:Destroy()
			end)
		end)
	end
end

-- Marco 10.15: carinho seguido vira "combo" (até x5): mais corações, o pet pula mais tempo
-- e aparece "Thor adorou! x3" em cima dele
local function comboLabel(model, text)
	local root = model.PrimaryPart
	if not root then
		return
	end
	local old = root:FindFirstChild("CarinhoCombo")
	if old then
		old:Destroy()
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "CarinhoCombo"
	bb.Size = UDim2.fromOffset(150, 26)
	bb.StudsOffset = Vector3.new(0, 4.6, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 60
	bb.Adornee = root
	bb.Parent = root
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = Color3.fromRGB(255, 225, 235)
	label.TextStrokeColor3 = Color3.fromRGB(200, 40, 90)
	label.TextStrokeTransparency = 0.2
	label.Parent = bb
	local info = TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(1.7, function()
		bb:Destroy()
	end)
end

local combos = {} -- [ownerId] = { n, at }

function PetController.love(data)
	local folder = Workspace:FindFirstChild("Pets")
	if type(data) ~= "table" or not folder then
		return
	end
	local c = combos[data.owner]
	local t = os.clock()
	if c and t - c.at < 3.5 then
		c.n = math.min(c.n + 1, 5)
		c.at = t
	else
		c = { n = 1, at = t }
		combos[data.owner] = c
	end
	for _, model in ipairs(folder:GetChildren()) do
		if model:GetAttribute("Owner") == data.owner then
			local st = states[model]
			if st then
				st.love = 1.2 + c.n * 0.3
			end
			hearts(model, 2 + c.n)
			local name = tostring(model:GetAttribute("PetName") or "O pet")
			comboLabel(model, c.n > 1 and ("%s adorou! x%d"):format(name, c.n) or ("%s adorou!"):format(name))
		end
	end
end

---------------------------------------------------------------------------
-- Tela de adoção (Duto Pet Shop)
---------------------------------------------------------------------------

local DARK = Color3.fromRGB(20, 30, 50)
local ROW = Color3.fromRGB(32, 46, 72)
local PURPLE = Color3.fromRGB(130, 80, 200)

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 10)
	c.Parent = parent
end

local function label(parent, text, size, pos, textSize, color)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = pos
	l.Font = Enum.Font.GothamBold
	l.TextSize = textSize or 16
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.Text = text
	l.Parent = parent
	return l
end

local function button(parent, text, color, size, pos)
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = pos
	b.BackgroundColor3 = color
	b.Font = Enum.Font.GothamBold
	b.TextSize = 16
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = text
	b.Parent = parent
	corner(b, 8)
	return b
end

local function close()
	if panel then
		panel:Destroy()
		panel = nil
	end
end

function PetController.openShop(data)
	close()
	if type(data) ~= "table" or type(data.kinds) ~= "table" then
		return
	end
	panel = Instance.new("Frame")
	panel.Name = "Adocao"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundColor3 = DARK
	panel.BackgroundTransparency = 0.05
	panel.Parent = gui
	corner(panel, 14)
	UIScaler.attach(panel)
	label(panel, "Adote um amigo", UDim2.new(1, -70, 0, 30), UDim2.fromOffset(16, 10), 24)
	button(panel, "X", Color3.fromRGB(200, 70, 60), UDim2.fromOffset(36, 32), UDim2.new(1, -46, 0, 10)).Activated:Connect(close)

	local y = 50
	local current = type(data.current) == "table" and data.current or nil
	if current then
		label(panel, ("Seu pet: %s %s"):format(tostring(current.name), tostring(current.color):lower()), UDim2.new(1, -150, 0, 20), UDim2.fromOffset(16, y + 8), 15, Color3.fromRGB(200, 220, 250))
		local t = button(panel, current.out and "Deixar aqui" or "Levar junto", PURPLE, UDim2.fromOffset(120, 34), UDim2.new(1, -132, 0, y))
		t.TextSize = 14
		t.Activated:Connect(function()
			petRequest:FireServer("Toggle")
			close()
		end)
		y += 44
	end
	-- Marco 10.3: com o dragão são 5 bichos; a lista rola se não couber (celular)
	local list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.Position = UDim2.fromOffset(0, y)
	list.Parent = panel
	local ly = 0
	for _, kind in ipairs(data.kinds) do
		if type(kind) == "table" and type(kind.colors) == "table" then
			local r = Instance.new("Frame")
			r.BackgroundColor3 = ROW
			r.Size = UDim2.new(1, -24, 0, 96)
			r.Position = UDim2.fromOffset(12, ly)
			r.Parent = list
			corner(r, 10)
			local price = (tonumber(kind.price) or 0) > 0 and (GameConfig.Economy.CurrencySymbol .. tostring(kind.price)) or "Grátis"
			label(r, tostring(kind.name) .. "  •  " .. price, UDim2.new(1, -20, 0, 22), UDim2.fromOffset(12, 6), 18)
			local chosen = 1
			local swatches = {}
			local function mark()
				for i, sw in ipairs(swatches) do
					sw:FindFirstChildOfClass("UIStroke").Thickness = i == chosen and 3 or 0
				end
			end
			for i, c in ipairs(kind.colors) do
				local rgb = type(c.rgb) == "table" and c.rgb or { 200, 200, 200 }
				local sw = Instance.new("TextButton")
				sw.Text = ""
				sw.Size = UDim2.fromOffset(44, 44)
				sw.Position = UDim2.fromOffset(12 + (i - 1) * 54, 38)
				sw.BackgroundColor3 = Color3.fromRGB(tonumber(rgb[1]) or 0, tonumber(rgb[2]) or 0, tonumber(rgb[3]) or 0)
				sw.Parent = r
				corner(sw, 22)
				local stroke = Instance.new("UIStroke")
				stroke.Color = Color3.fromRGB(250, 210, 60)
				stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				stroke.Parent = sw
				swatches[i] = sw
				sw.Activated:Connect(function()
					chosen = i
					mark()
				end)
			end
			mark()
			local adopt = button(r, current and "Trocar" or "Adotar", Color3.fromRGB(60, 170, 80), UDim2.fromOffset(96, 44), UDim2.new(1, -108, 0, 38))
			adopt.Activated:Connect(function()
				petRequest:FireServer("Adopt", { kind = kind.id, color = chosen })
				close()
			end)
			ly += 104
		end
	end
	local h = math.min(ly, 104 * 4)
	list.Size = UDim2.new(1, 0, 0, h)
	list.CanvasSize = UDim2.fromOffset(0, ly)
	panel.Size = UDim2.fromOffset(380, y + h + 8)
end

-- Marco 10.15: o "Carinho" não briga mais com a revista da PM nem com as outras teclas.
-- Ele só aparece quando você está PARADO perto do pet, sem nada na mão, e sem ninguém para
-- revistar por perto (o pet anda colado no dono e o aviso ficava sempre na tela).
local function frisking(myRoot)
	for _, other in ipairs(Players:GetPlayers()) do
		local char = other ~= player and other.Character
		local r = char and char:FindFirstChild("HumanoidRootPart")
		local fp = r and r:FindFirstChild("RevistarPrompt")
		if fp and fp.Enabled and (r.Position - myRoot.Position).Magnitude <= fp.MaxActivationDistance + 2 then
			return true
		end
	end
	return false
end

local function promptAllowed()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local myRoot = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not myRoot or hum.Health <= 0 or hum.SeatPart then
		return false
	end
	if hum.MoveDirection.Magnitude > 0.1 or char:FindFirstChildOfClass("Tool") then
		return false
	end
	if player:GetAttribute("Caido") or player:GetAttribute("Algemado") then
		return false
	end
	return not frisking(myRoot)
end

function PetController.init()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	petRequest = remotes:WaitForChild(GameConfig.Remotes.PetRequest)
	gui = Instance.new("ScreenGui")
	gui.Name = "PetUI"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local lastPromptCheck = 0
	RunService.Heartbeat:Connect(function()
		local t = os.clock()
		if t - lastPromptCheck < 0.2 then
			return
		end
		lastPromptCheck = t
		local allowed = promptAllowed()
		for _, st in pairs(states) do
			if st.prompt and st.prompt.Enabled ~= allowed then
				st.prompt.Enabled = allowed
			end
		end
	end)

	local lastIgnore = 0
	-- RenderStepped: roda logo antes de desenhar, então a posição local sempre ganha
	RunService.RenderStepped:Connect(function(dt)
		local folder = Workspace:FindFirstChild("Pets")
		if not folder then
			return
		end
		local t = os.clock()
		if t - lastIgnore > 1 then
			lastIgnore = t
			rayParams.FilterDescendantsInstances = ignoreList()
		end
		for _, model in ipairs(folder:GetChildren()) do
			local st = states[model] or setup(model)
			if st then
				stepPet(model, st, math.min(dt, 0.1), t)
			end
		end
		for model in pairs(states) do
			if not model.Parent then
				states[model] = nil
			end
		end
		-- longe do cantinho de adoção: fecha a tela
		if panel then
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			if not hrp or not panel:GetAttribute("At") then
				panel:SetAttribute("At", hrp and hrp.Position or Vector3.zero)
			elseif (hrp.Position - panel:GetAttribute("At")).Magnitude > 16 then
				close()
			end
		end
	end)
end

return PetController
