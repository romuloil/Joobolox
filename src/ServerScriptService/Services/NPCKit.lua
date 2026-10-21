-- NPCKit (ModuleScript)
-- Caminho: ServerScriptService > Services > NPCKit
-- Marco 5: "kit" reaproveitável para todos os NPCs da cidade (clientes, funcionários,
-- destinatários de entrega, pessoas passeando na praça e o Seu Bento).
--   * aparência aleatória (pele, camisa, calça);
--   * animações padrão do Roblox: parado, andando, acenar, comemorar, apontar;
--   * balão de fala e reação com emoji em cima da cabeça;
--   * andar por pontos (se travar, é colocado no ponto: nunca fica preso).
-- Desempenho: limite de NPCs ao mesmo tempo, estados do Humanoid que não usamos desligados
-- e NPCs parados ficam ancorados (não gastam física).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local NPCKit = {}

NPCKit.MAX_NPCS = 30 -- limite de NPCs ao mesmo tempo (sem contar os importantes)

-- Animações padrão R15 do próprio Roblox
local ANIMS = {
	idle = "rbxassetid://507766388",
	walk = "rbxassetid://507777826",
	wave = "rbxassetid://507770239",
	cheer = "rbxassetid://507770677",
	point = "rbxassetid://507770453",
}

local SKINS = { Color3.fromRGB(255, 220, 190), Color3.fromRGB(230, 180, 140), Color3.fromRGB(190, 130, 90), Color3.fromRGB(140, 90, 60), Color3.fromRGB(100, 65, 45) }
local SHIRTS = { Color3.fromRGB(200, 60, 60), Color3.fromRGB(60, 120, 200), Color3.fromRGB(240, 200, 60), Color3.fromRGB(80, 170, 90), Color3.fromRGB(170, 90, 200), Color3.fromRGB(240, 240, 240), Color3.fromRGB(250, 140, 60) }
local PANTS = { Color3.fromRGB(40, 50, 80), Color3.fromRGB(60, 60, 65), Color3.fromRGB(120, 90, 60), Color3.fromRGB(30, 30, 35), Color3.fromRGB(90, 110, 140) }

-- Estados que NPC não usa (menos trabalho para o servidor)
local OFF_STATES = {
	Enum.HumanoidStateType.Climbing,
	Enum.HumanoidStateType.Swimming,
	Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.Ragdoll,
	Enum.HumanoidStateType.Flying,
	Enum.HumanoidStateType.GettingUp,
	Enum.HumanoidStateType.Dead,
}

local rng = Random.new()
local data = {} -- data[npc] = { humanoid, root, tracks = {}, speed, important }
local count = 0

function NPCKit.pick(list)
	return list[rng:NextInteger(1, #list)]
end

function NPCKit.folder()
	local f = Workspace:FindFirstChild("NPCs")
	if not f then
		f = Instance.new("Folder")
		f.Name = "NPCs"
		f.Parent = Workspace
	end
	return f
end

function NPCKit.count()
	return count
end

local function track(npc, name)
	local d = data[npc]
	if not d or not ANIMS[name] then
		return nil
	end
	if not d.tracks[name] then
		local animator = d.humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = d.humanoid
		end
		local anim = Instance.new("Animation")
		anim.AnimationId = ANIMS[name]
		local ok, t = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		if not ok then
			return nil
		end
		t.Looped = name == "idle" or name == "walk"
		t.Priority = (name == "idle" or name == "walk") and Enum.AnimationPriority.Core or Enum.AnimationPriority.Action
		d.tracks[name] = t
	end
	return d.tracks[name]
end

-- Liga as animações de parado/andando num NPC (serve para NPCs criados em outro lugar, como o Seu Bento)
function NPCKit.animate(npc, important)
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	local root = npc:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or data[npc] then
		return
	end
	for _, state in ipairs(OFF_STATES) do
		humanoid:SetStateEnabled(state, false)
	end
	-- o script "Animate" que vem no modelo não roda em NPC; as animações tocam pelo servidor
	local animate = npc:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end
	data[npc] = { humanoid = humanoid, root = root, tracks = {}, important = important }
	if not important then
		count += 1
	end
	local walking = false
	local idle = track(npc, "idle")
	if idle then
		idle:Play()
	end
	humanoid.Running:Connect(function(speed)
		local moving = speed > 0.5
		if moving == walking then
			return
		end
		walking = moving
		local walk = track(npc, "walk")
		if walk then
			if moving then
				walk:Play(0.2)
				walk:AdjustSpeed(humanoid.WalkSpeed / 14)
			else
				walk:Stop(0.2)
			end
		end
	end)
	npc.AncestryChanged:Connect(function(_, parent)
		if not parent and data[npc] then
			if not data[npc].important then
				count -= 1
			end
			data[npc] = nil
		end
	end)
end

-- Cria um NPC em pé no chão em "cf" (a posição Y de cf = altura do chão).
-- opts: name, shirt, pants, skin, speed, anchored, important (não conta no limite)
-- Devolve nil se já houver NPCs demais.
function NPCKit.spawn(cf, opts)
	opts = opts or {}
	if not opts.important and count >= NPCKit.MAX_NPCS then
		return nil
	end
	local desc = Instance.new("HumanoidDescription")
	local skin = opts.skin or NPCKit.pick(SKINS)
	desc.HeadColor = skin
	desc.LeftArmColor = skin
	desc.RightArmColor = skin
	desc.TorsoColor = opts.shirt or NPCKit.pick(SHIRTS)
	local pants = opts.pants or NPCKit.pick(PANTS)
	desc.LeftLegColor = pants
	desc.RightLegColor = pants
	local ok, npc = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not npc then
		warn("[NPCKit] Não deu para criar NPC: " .. tostring(npc))
		return nil
	end
	npc.Name = opts.name or "Morador"
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	local root = npc:FindFirstChild("HumanoidRootPart")
	humanoid.DisplayDistanceType = opts.showName and Enum.HumanoidDisplayDistanceType.Viewer or Enum.HumanoidDisplayDistanceType.None
	humanoid.DisplayName = opts.name or ""
	humanoid.NameDisplayDistance = 40
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.WalkSpeed = opts.speed or 12
	for _, p in ipairs(npc:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CollisionGroup = "NPCs" -- não esbarra nos jogadores nem nos carros (ZoneService)
		end
	end
	local height = humanoid.HipHeight + root.Size.Y / 2
	npc:PivotTo(cf + Vector3.new(0, height + 0.1, 0))
	root.Anchored = opts.anchored == true
	npc.Parent = NPCKit.folder()
	if not root.Anchored then
		pcall(function()
			root:SetNetworkOwner(nil) -- o servidor controla o andar
		end)
	end
	NPCKit.animate(npc, opts.important)
	return npc
end

-- Toca uma animação curta: "wave" (acenar), "cheer" (comemorar), "point" (apontar)
function NPCKit.emote(npc, name)
	local t = npc and track(npc, name)
	if t then
		t:Play(0.15)
	end
end

-- Balão de fala em cima da cabeça
function NPCKit.say(npc, text, duration)
	local head = npc and npc:FindFirstChild("Head")
	if not head then
		return
	end
	local old = head:FindFirstChild("Fala")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "Fala"
	gui.Size = UDim2.fromOffset(190, 46)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.MaxDistance = 45
	gui.Parent = head
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(30, 30, 40)
	label.Text = text
	label.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = label
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(60, 60, 80)
	stroke.Thickness = 1.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = label
	task.delay(duration or 3.5, function()
		if gui.Parent then
			gui:Destroy()
		end
	end)
end

-- Emoji que sobe e some em cima da cabeça (ex.: "😊", "❤️", "😕")
function NPCKit.react(npc, emoji)
	local head = npc and npc:FindFirstChild("Head")
	if not head then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "Reacao"
	gui.Size = UDim2.fromOffset(50, 50)
	gui.StudsOffset = Vector3.new(1.6, 2, 0)
	gui.MaxDistance = 45
	gui.Parent = head
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Text = emoji
	label.Parent = gui
	TweenService:Create(gui, TweenInfo.new(1.8), { StudsOffset = Vector3.new(1.6, 4.5, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 }):Play()
	game:GetService("Debris"):AddItem(gui, 2)
end

-- Vira o NPC para uma direção (sem mexer na posição)
function NPCKit.face(npc, direction)
	local root = npc and npc:FindFirstChild("HumanoidRootPart")
	if root and direction.Magnitude > 0 then
		local flat = Vector3.new(direction.X, 0, direction.Z)
		npc:PivotTo(CFrame.lookAt(root.Position, root.Position + flat))
	end
end

-- Anda pelos pontos (CFrame ou Vector3) em ordem. Se travar, é colocado no ponto.
-- Para no meio se "keepGoing()" devolver false.
function NPCKit.walk(npc, points, faceDir, keepGoing)
	local d = data[npc]
	if not d then
		return
	end
	if d.root.Anchored then
		d.root.Anchored = false
		pcall(function()
			d.root:SetNetworkOwner(nil)
		end)
	end
	for _, p in ipairs(points) do
		if not npc.Parent or (keepGoing and not keepGoing()) then
			return
		end
		local pos = typeof(p) == "CFrame" and p.Position or p
		local target = Vector3.new(pos.X, d.root.Position.Y, pos.Z)
		local timeout = (target - d.root.Position).Magnitude / math.max(d.humanoid.WalkSpeed, 1) + 1.5
		local reached = false
		local conn = d.humanoid.MoveToFinished:Connect(function(ok)
			reached = ok
		end)
		d.humanoid:MoveTo(target)
		local started = os.clock()
		while not reached and os.clock() - started < timeout and npc.Parent do
			task.wait(0.1)
		end
		conn:Disconnect()
		if not reached and npc.Parent then
			npc:PivotTo(CFrame.new(target) * d.root.CFrame.Rotation)
		end
	end
	if npc.Parent and faceDir then
		NPCKit.face(npc, faceDir)
	end
end

-- Faz um objeto (ex.: sacola, caixa de pizza, pacote) aparecer na mão do NPC
function NPCKit.hold(npc, name, size, color, material)
	local hand = npc and (npc:FindFirstChild("RightHand") or npc:FindFirstChild("Right Arm"))
	if not hand then
		return nil
	end
	local item = Instance.new("Part")
	item.Name = name
	item.Size = size
	item.Color = color
	item.Material = material or Enum.Material.SmoothPlastic
	item.CanCollide = false
	item.CanQuery = false
	item.Massless = true
	item.CFrame = hand.CFrame * CFrame.new(0, -0.3 - size.Y / 2, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hand
	weld.Part1 = item
	weld.Parent = item
	item.Parent = npc
	return item
end

-- Altura do chão em uma posição (só o mapa conta)
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
function NPCKit.groundAt(position)
	local include = {}
	for _, name in ipairs({ "Map", "JobStations" }) do
		local f = Workspace:FindFirstChild(name)
		if f then
			table.insert(include, f)
		end
	end
	groundParams.FilterDescendantsInstances = include
	local hit = Workspace:Raycast(Vector3.new(position.X, position.Y + 6, position.Z), Vector3.new(0, -40, 0), groundParams)
	return hit and hit.Position.Y or position.Y
end

-- true se algum jogador está a menos de "radius" studs (para só animar o que alguém vê)
function NPCKit.anyPlayerNear(position, radius)
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - position).Magnitude <= radius then
			return true
		end
	end
	return false
end

return NPCKit
