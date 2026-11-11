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
	sit = "rbxassetid://2506281703", -- Marco 9: sentado (passageiro do táxi)
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
	-- Marco 9.4: NPC não senta sozinho ao esbarrar num banco (os moradores da praça ficavam
	-- presos "sentados em pé" nos bancos). Quem precisa sentar usa NPCKit.sit.
	Enum.HumanoidStateType.Seated,
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
		t.Looped = name == "idle" or name == "walk" or name == "sit"
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
-- opts: name, shirt, pants, skin, speed, anchored, important (não conta no limite),
-- outfit (uniforme de OUTFITS, já com título), title (texto do título; false = sem título)
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
	local fit = opts.outfit and NPCKit.OUTFITS and NPCKit.OUTFITS[opts.outfit]
	desc.TorsoColor = opts.shirt or (fit and fit.shirt) or NPCKit.pick(SHIRTS)
	local pants = opts.pants or (fit and fit.pants) or NPCKit.pick(PANTS)
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
	npc.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- Marco 10.22: chega inteiro no aparelho (streaming)
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
	if opts.outfit then
		NPCKit.dress(npc, opts.outfit, { title = opts.title, name = opts.name })
	elseif opts.title then
		NPCKit.title(npc, opts.title, opts.titleColor)
	end
	return npc
end

-- Toca uma animação curta: "wave" (acenar), "cheer" (comemorar), "point" (apontar)
-- Marco 10.26: pose feita por código (PoseController, em todos os aparelhos). nil tira a pose.
function NPCKit.pose(model, name, seconds)
	if not model then
		return
	end
	game:GetService("CollectionService"):AddTag(model, "PoseBanco")
	model:SetAttribute("Pose", name)
	local token = (model:GetAttribute("PoseToken") or 0) + 1
	model:SetAttribute("PoseToken", token)
	if seconds then
		task.delay(seconds, function()
			if model.Parent and model:GetAttribute("PoseToken") == token then
				model:SetAttribute("Pose", nil)
			end
		end)
	end
end

-- Marco 10.26: mochila nas costas, que cresce com o saque. fraction = 0 tira.
function NPCKit.wearBag(character, fraction)
	if not character then
		return
	end
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	local bag = character:FindFirstChild("MochilaAssalto")
	if fraction <= 0 or not torso then
		if bag then
			bag:Destroy()
		end
		return
	end
	if not bag then
		bag = Instance.new("Part")
		bag.Name = "MochilaAssalto"
		bag.Color = Color3.fromRGB(38, 46, 66)
		bag.Material = Enum.Material.Fabric
		bag.CanCollide = false
		bag.CanQuery = false
		bag.CanTouch = false
		bag.Massless = true
		bag.Parent = character
		local weld = Instance.new("Weld")
		weld.Name = "Solda"
		weld.Part0 = torso
		weld.Part1 = bag
		weld.Parent = bag
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = bag
	end
	local depth = 0.7 + fraction * 1
	bag.Size = Vector3.new(1.5 + fraction * 0.5, 1.8 + fraction * 0.7, depth)
	bag.Solda.C0 = CFrame.new(0, 0, torso.Size.Z / 2 + depth * 0.4)
end

-- Marco 10.26: corda nos pulsos de quem foi amarrado
function NPCKit.rope(npc)
	for _, name in ipairs({ "RightLowerArm", "LeftLowerArm", "Right Arm", "Left Arm" }) do
		local arm = npc and npc:FindFirstChild(name)
		if arm then
			local r = Instance.new("Part")
			r.Name = "Corda"
			r.Size = Vector3.new(arm.Size.X + 0.12, 0.25, arm.Size.Z + 0.12)
			r.Color = Color3.fromRGB(176, 142, 90)
			r.Material = Enum.Material.Fabric
			r.CanCollide = false
			r.CanQuery = false
			r.CanTouch = false
			r.Massless = true
			r.Parent = npc
			local w = Instance.new("Weld")
			w.Part0 = arm
			w.Part1 = r
			w.C0 = CFrame.new(0, -arm.Size.Y * 0.38, 0)
			w.Parent = r
		end
	end
end

-- Marco 10.26: lista do que está na bolsa. Quem mexe só em value e slots (evento que rasga a bolsa,
-- rival que puxa) não atualiza a lista; aqui ela volta a bater com a bolsa.
function NPCKit.bagItems(b)
	b.items = b.items or {}
	local value, slots = 0, 0
	for _, it in ipairs(b.items) do
		value += it.value
		slots += it.slots
	end
	while #b.items > 0 and (value > b.value + 1 or slots > b.slots) do
		local it = table.remove(b.items)
		value -= it.value
		slots -= it.slots
	end
	if b.slots > slots or b.value > value + 1 then
		table.insert(b.items, { name = "Diversos", value = math.max(0, b.value - value), slots = math.max(1, b.slots - slots) })
	end
	return b.items
end

-- Quais itens largar para abrir "need" espaços (os mais baratos). Devolve a lista e o valor.
function NPCKit.bagCheapest(b, need, max)
	local items = table.clone(NPCKit.bagItems(b))
	table.sort(items, function(x, y)
		return x.value / x.slots < y.value / y.slots
	end)
	local out, value, free = {}, 0, max - b.slots
	for _, it in ipairs(items) do
		if free >= need then
			break
		end
		table.insert(out, it)
		value += it.value
		free += it.slots
	end
	return free >= need and out or nil, value
end

function NPCKit.emote(npc, name)
	local t = npc and track(npc, name)
	if t then
		t:Play(0.15)
	end
end

-- Marco 9: pose de sentado (sem ela o NPC "sentava" em pé e as pernas e os braços
-- atravessavam a lataria do carro). on = false volta ao normal.
function NPCKit.sit(npc, on)
	local sit = npc and track(npc, "sit")
	local walk = npc and track(npc, "walk")
	if not sit then
		return
	end
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, on == true)
	end
	if on then
		if walk then
			walk:Stop(0)
		end
		sit:Play(0.1)
	else
		sit:Stop(0.2)
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

---------------------------------------------------------------------------
-- Marco 10.21: UNIFORMES e TÍTULO em cima da cabeça dos funcionários (o Luís não sabia quem era o
-- segurança na joalheria). NPCKit.spawn(cf, { outfit = "seguranca", title = "SEGURANÇA" }) ou
-- NPCKit.dress(npc, "seguranca") / NPCKit.title(npc, "SEGURANÇA", cor). Tudo de peças leves
-- soldadas no corpo (sem asset de roupa): boné, colete com texto, gravata, crachá, rádio, avental...
---------------------------------------------------------------------------

local OUTFITS = {
	-- shirt/pants = cor do corpo; title/color = título padrão; pieces = acessórios
	seguranca = { shirt = Color3.fromRGB(28, 34, 52), pants = Color3.fromRGB(22, 24, 30), title = "SEGURANÇA", color = Color3.fromRGB(40, 90, 200), pieces = { "cap", "vest", "radio", "badge" }, vestText = "SEGURANÇA", vestColor = Color3.fromRGB(18, 18, 22), textColor = Color3.fromRGB(255, 210, 60), capColor = Color3.fromRGB(24, 30, 50) },
	gerente = { shirt = Color3.fromRGB(32, 34, 44), pants = Color3.fromRGB(26, 28, 36), title = "GERENTE", color = Color3.fromRGB(150, 110, 40), pieces = { "shirtV", "tie", "nametag", "glasses" }, tieColor = Color3.fromRGB(130, 24, 40) },
	caixa = { shirt = Color3.fromRGB(236, 238, 244), pants = Color3.fromRGB(30, 36, 60), title = "CAIXA", color = Color3.fromRGB(40, 110, 170), pieces = { "vestOpen", "tie", "nametag" }, vestColor = Color3.fromRGB(30, 40, 70), tieColor = Color3.fromRGB(30, 60, 140) },
	funcionario = { shirt = Color3.fromRGB(236, 238, 244), pants = Color3.fromRGB(30, 36, 60), title = "FUNCIONÁRIO", color = Color3.fromRGB(90, 100, 120), pieces = { "lanyard", "tie" }, tieColor = Color3.fromRGB(30, 60, 140) },
	vendedora = { shirt = Color3.fromRGB(18, 18, 22), pants = Color3.fromRGB(18, 18, 22), title = "CONSULTORA", color = Color3.fromRGB(200, 160, 60), pieces = { "scarf", "nametag", "necklace" }, scarfColor = Color3.fromRGB(200, 160, 60) },
	leiloeiro = { shirt = Color3.fromRGB(14, 14, 18), pants = Color3.fromRGB(14, 14, 18), title = "LEILOEIRO", color = Color3.fromRGB(170, 40, 50), pieces = { "shirtV", "bowtie", "pocket" } },
	diretor = { shirt = Color3.fromRGB(46, 22, 30), pants = Color3.fromRGB(26, 26, 32), title = "DIRETOR REGIONAL", color = Color3.fromRGB(120, 40, 60), pieces = { "shirtV", "tie", "pocket" }, tieColor = Color3.fromRGB(210, 170, 70) },
	guardacostas = { shirt = Color3.fromRGB(12, 12, 14), pants = Color3.fromRGB(12, 12, 14), title = "GUARDA-COSTAS", color = Color3.fromRGB(60, 60, 70), pieces = { "shirtV", "tie", "earpiece", "glasses" }, tieColor = Color3.fromRGB(12, 12, 14) },
	carroforte = { shirt = Color3.fromRGB(60, 70, 60), pants = Color3.fromRGB(40, 44, 40), title = "CARRO-FORTE", color = Color3.fromRGB(70, 110, 70), pieces = { "cap", "vest", "radio" }, vestText = "VALORES", vestColor = Color3.fromRGB(34, 40, 34), textColor = Color3.fromRGB(240, 240, 240), capColor = Color3.fromRGB(40, 46, 40) },
	choque = { shirt = Color3.fromRGB(20, 22, 28), pants = Color3.fromRGB(20, 22, 28), title = "BATALHÃO DE CHOQUE", color = Color3.fromRGB(30, 50, 110), pieces = { "helmet", "vest" }, vestText = "CHOQUE", vestColor = Color3.fromRGB(14, 14, 18), textColor = Color3.fromRGB(240, 240, 240) },
	pizzaiolo = { shirt = Color3.fromRGB(245, 245, 240), pants = Color3.fromRGB(40, 40, 46), title = "PIZZAIOLO", color = Color3.fromRGB(190, 50, 40), pieces = { "chefhat", "apron", "scarf" }, apronColor = Color3.fromRGB(190, 50, 40), scarfColor = Color3.fromRGB(40, 140, 70) },
	mercado = { shirt = Color3.fromRGB(240, 240, 236), pants = Color3.fromRGB(40, 50, 80), title = "ATENDENTE", color = Color3.fromRGB(40, 140, 70), pieces = { "apron", "cap", "nametag" }, apronColor = Color3.fromRGB(40, 140, 70), capColor = Color3.fromRGB(40, 140, 70) },
	entregas = { shirt = Color3.fromRGB(240, 140, 30), pants = Color3.fromRGB(40, 50, 80), title = "ENTREGAS", color = Color3.fromRGB(230, 120, 20), pieces = { "cap", "vest" }, vestText = "SHERLEX", vestColor = Color3.fromRGB(230, 120, 20), textColor = Color3.fromRGB(20, 20, 24), capColor = Color3.fromRGB(20, 20, 24) },
	petshop = { shirt = Color3.fromRGB(130, 80, 200), pants = Color3.fromRGB(40, 50, 80), title = "PET SHOP", color = Color3.fromRGB(130, 80, 200), pieces = { "apron", "nametag" }, apronColor = Color3.fromRGB(240, 240, 250) },
	loja = { shirt = Color3.fromRGB(200, 40, 40), pants = Color3.fromRGB(40, 40, 46), title = "ATENDENTE", color = Color3.fromRGB(200, 40, 40), pieces = { "cap", "nametag" }, capColor = Color3.fromRGB(200, 40, 40) },
	vip = { shirt = Color3.fromRGB(60, 20, 70), pants = Color3.fromRGB(20, 20, 26), pieces = { "shirtV", "bowtie", "necklace" } },
	vipa = { shirt = Color3.fromRGB(150, 20, 40), pants = Color3.fromRGB(150, 20, 40), pieces = { "necklace", "scarf" }, scarfColor = Color3.fromRGB(240, 220, 160) },
}
NPCKit.OUTFITS = OUTFITS

local GOLD = Color3.fromRGB(220, 180, 80)

local function piece(npc, body, name, size, offset, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CollisionGroup = "NPCs"
	p.CFrame = body.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = body
	weld.Part1 = p
	weld.Parent = p
	p.Parent = npc:FindFirstChild("Uniforme") or npc
	return p
end

local function surfaceText(part, face, text, color, ppx)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = ppx or 60
	gui.LightInfluence = 0.5
	gui.Parent = part
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBlack
	l.TextScaled = true
	l.TextColor3 = color
	l.Text = text
	l.Parent = gui
end

local PIECES = {}
PIECES.cap = function(npc, o, head)
	local h = head.Size
	local c = o.capColor or Color3.fromRGB(30, 30, 40)
	piece(npc, head, "Bone", Vector3.new(0.42, h.X * 1.04, h.Z * 1.04), CFrame.new(0, h.Y * 0.42, 0.02) * CFrame.Angles(0, 0, math.pi / 2), c, Enum.Material.Fabric, Enum.PartType.Cylinder)
	piece(npc, head, "Aba", Vector3.new(h.X * 0.8, 0.08, h.Z * 0.45), CFrame.new(0, h.Y * 0.3, -h.Z * 0.62), c, Enum.Material.Fabric)
	if o.vestText then
		piece(npc, head, "Emblema", Vector3.new(0.3, 0.22, 0.04), CFrame.new(0, h.Y * 0.44, -h.Z * 0.53), o.textColor or GOLD, Enum.Material.Metal)
	end
end
PIECES.helmet = function(npc, _, head)
	local h = head.Size
	piece(npc, head, "Capacete", Vector3.new(h.X * 1.18, h.Y * 0.75, h.Z * 1.18), CFrame.new(0, h.Y * 0.3, 0.02), Color3.fromRGB(20, 24, 34), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	local v = piece(npc, head, "Viseira", Vector3.new(h.X * 0.95, h.Y * 0.3, 0.06), CFrame.new(0, h.Y * 0.1, -h.Z * 0.6), Color3.fromRGB(120, 150, 190), Enum.Material.SmoothPlastic)
	v.Transparency = 0.45
end
PIECES.chefhat = function(npc, _, head)
	local h = head.Size
	local w = Color3.fromRGB(250, 250, 250)
	piece(npc, head, "Chapeu", Vector3.new(0.8, h.X * 0.95, h.Z * 0.95), CFrame.new(0, h.Y * 0.7, 0) * CFrame.Angles(0, 0, math.pi / 2), w, Enum.Material.Fabric, Enum.PartType.Cylinder)
	piece(npc, head, "Topo", Vector3.new(h.X * 1.15, 0.6, h.Z * 1.15), CFrame.new(0, h.Y * 1.1, 0), w, Enum.Material.Fabric, Enum.PartType.Ball)
end
PIECES.glasses = function(npc, _, head)
	local h = head.Size
	for _, x in ipairs({ -0.22, 0.22 }) do
		piece(npc, head, "Lente", Vector3.new(0.3, 0.16, 0.04), CFrame.new(x * h.X / 1.2, h.Y * 0.08, -h.Z * 0.51), Color3.fromRGB(10, 10, 12))
	end
	piece(npc, head, "Ponte", Vector3.new(0.18, 0.04, 0.04), CFrame.new(0, h.Y * 0.1, -h.Z * 0.51), Color3.fromRGB(10, 10, 12))
end
PIECES.earpiece = function(npc, _, head)
	local h = head.Size
	piece(npc, head, "Ponto", Vector3.new(0.08, 0.14, 0.1), CFrame.new(h.X * 0.52, 0, 0), Color3.fromRGB(20, 20, 20))
	piece(npc, head, "Fio", Vector3.new(0.03, 0.6, 0.03), CFrame.new(h.X * 0.52, -h.Y * 0.4, 0.05), Color3.fromRGB(200, 200, 200))
end
PIECES.vest = function(npc, o, _, torso)
	local t = torso.Size
	local v = piece(npc, torso, "Colete", Vector3.new(t.X * 1.06, t.Y * 0.86, t.Z * 1.22), CFrame.new(0, -t.Y * 0.04, 0), o.vestColor or Color3.fromRGB(18, 18, 22), Enum.Material.Fabric)
	if o.vestText then
		surfaceText(v, Enum.NormalId.Back, o.vestText, o.textColor or GOLD, 50)
		local tag = piece(npc, torso, "TextoFrente", Vector3.new(t.X * 0.42, 0.22, 0.02), CFrame.new(-t.X * 0.22, t.Y * 0.18, -t.Z * 0.62), o.vestColor or Color3.fromRGB(18, 18, 22))
		surfaceText(tag, Enum.NormalId.Front, o.vestText, o.textColor or GOLD, 80)
	end
end
PIECES.vestOpen = function(npc, o, _, torso)
	local t = torso.Size
	for _, sx in ipairs({ -1, 1 }) do
		piece(npc, torso, "Colete", Vector3.new(t.X * 0.36, t.Y * 0.82, t.Z * 1.12), CFrame.new(sx * t.X * 0.33, -t.Y * 0.06, 0), o.vestColor or Color3.fromRGB(30, 40, 70), Enum.Material.Fabric)
	end
end
PIECES.shirtV = function(npc, _, _, torso)
	local t = torso.Size
	piece(npc, torso, "Camisa", Vector3.new(t.X * 0.28, t.Y * 0.62, 0.04), CFrame.new(0, t.Y * 0.18, -t.Z * 0.51), Color3.fromRGB(245, 245, 248), Enum.Material.Fabric)
end
PIECES.tie = function(npc, o, _, torso)
	local t = torso.Size
	local c = o.tieColor or Color3.fromRGB(130, 24, 40)
	piece(npc, torso, "No", Vector3.new(0.2, 0.16, 0.06), CFrame.new(0, t.Y * 0.42, -t.Z * 0.54), c)
	piece(npc, torso, "Gravata", Vector3.new(0.18, t.Y * 0.62, 0.05), CFrame.new(0, t.Y * 0.05, -t.Z * 0.54), c)
end
PIECES.bowtie = function(npc, _, _, torso)
	local t = torso.Size
	piece(npc, torso, "Gravatinha", Vector3.new(0.5, 0.18, 0.06), CFrame.new(0, t.Y * 0.43, -t.Z * 0.55), Color3.fromRGB(12, 12, 14))
end
PIECES.pocket = function(npc, _, _, torso)
	local t = torso.Size
	piece(npc, torso, "Lenco", Vector3.new(0.26, 0.14, 0.04), CFrame.new(t.X * 0.28, t.Y * 0.22, -t.Z * 0.52), Color3.fromRGB(220, 50, 60))
end
PIECES.badge = function(npc, _, _, torso)
	local t = torso.Size
	piece(npc, torso, "Distintivo", Vector3.new(0.26, 0.3, 0.05), CFrame.new(t.X * 0.25, t.Y * 0.2, -t.Z * 0.64), GOLD, Enum.Material.Metal)
end
PIECES.radio = function(npc, _, _, torso)
	local t = torso.Size
	piece(npc, torso, "Radio", Vector3.new(0.22, 0.4, 0.14), CFrame.new(-t.X * 0.4, t.Y * 0.28, -t.Z * 0.66), Color3.fromRGB(14, 14, 16))
	piece(npc, torso, "Antena", Vector3.new(0.05, 0.3, 0.05), CFrame.new(-t.X * 0.44, t.Y * 0.6, -t.Z * 0.66), Color3.fromRGB(14, 14, 16))
end
PIECES.nametag = function(npc, _, _, torso, name)
	local t = torso.Size
	local tag = piece(npc, torso, "Cracha", Vector3.new(0.5, 0.2, 0.03), CFrame.new(t.X * 0.27, t.Y * 0.22, -t.Z * 0.52), Color3.fromRGB(250, 250, 250))
	surfaceText(tag, Enum.NormalId.Front, name or "", Color3.fromRGB(20, 20, 30), 100)
end
PIECES.lanyard = function(npc, _, _, torso)
	local t = torso.Size
	piece(npc, torso, "Cordao", Vector3.new(0.06, t.Y * 0.4, 0.03), CFrame.new(0, t.Y * 0.25, -t.Z * 0.52), Color3.fromRGB(30, 80, 170))
	piece(npc, torso, "Cracha", Vector3.new(0.34, 0.44, 0.03), CFrame.new(0, -t.Y * 0.04, -t.Z * 0.53), Color3.fromRGB(250, 250, 250))
end
PIECES.apron = function(npc, o, _, torso, _, lower)
	local t = torso.Size
	local c = o.apronColor or Color3.fromRGB(240, 240, 240)
	piece(npc, torso, "Avental", Vector3.new(t.X * 0.7, t.Y * 0.75, 0.05), CFrame.new(0, -t.Y * 0.1, -t.Z * 0.52), c, Enum.Material.Fabric)
	if lower then
		local l = lower.Size
		piece(npc, lower, "AventalBaixo", Vector3.new(t.X * 0.7, l.Y + 0.7, 0.05), CFrame.new(0, -0.3, -l.Z * 0.56), c, Enum.Material.Fabric)
	end
end
PIECES.scarf = function(npc, o, _, torso)
	local t = torso.Size
	piece(npc, torso, "Lenco", Vector3.new(t.X * 0.55, 0.16, t.Z * 1.06), CFrame.new(0, t.Y * 0.44, 0), o.scarfColor or GOLD, Enum.Material.Fabric)
end
PIECES.necklace = function(npc, _, _, torso)
	local t = torso.Size
	piece(npc, torso, "Colar", Vector3.new(t.X * 0.4, 0.08, 0.04), CFrame.new(0, t.Y * 0.36, -t.Z * 0.52), GOLD, Enum.Material.Neon)
	piece(npc, torso, "Pingente", Vector3.new(0.14, 0.14, 0.05), CFrame.new(0, t.Y * 0.28, -t.Z * 0.53), Color3.fromRGB(120, 200, 255), Enum.Material.Neon)
end

-- Título bonitinho em cima da cabeça (nome pequeno + faixa colorida com o cargo)
function NPCKit.title(npc, title, color, name)
	local head = npc and npc:FindFirstChild("Head")
	if not head then
		return
	end
	local old = head:FindFirstChild("Titulo")
	if old then
		old:Destroy()
	end
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "Titulo"
	bb.Size = UDim2.fromOffset(170, 44)
	bb.StudsOffset = Vector3.new(0, 2.6, 0)
	bb.MaxDistance = 45
	bb.LightInfluence = 0
	bb.Parent = head
	local n = Instance.new("TextLabel")
	n.BackgroundTransparency = 1
	n.Size = UDim2.new(1, 0, 0, 18)
	n.Font = Enum.Font.GothamBold
	n.TextSize = 14
	n.TextColor3 = Color3.new(1, 1, 1)
	n.TextStrokeTransparency = 0.5
	n.Text = name or npc.Name
	n.Parent = bb
	if title then
		local pill = Instance.new("TextLabel")
		pill.AnchorPoint = Vector2.new(0.5, 0)
		pill.Position = UDim2.new(0.5, 0, 0, 20)
		pill.Size = UDim2.fromOffset(0, 20)
		pill.AutomaticSize = Enum.AutomaticSize.X
		pill.BackgroundColor3 = color or Color3.fromRGB(40, 90, 200)
		pill.Font = Enum.Font.GothamBlack
		pill.TextSize = 12
		pill.TextColor3 = Color3.new(1, 1, 1)
		pill.Text = "  " .. title .. "  "
		pill.Parent = bb
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 10)
		c.Parent = pill
		local st = Instance.new("UIStroke")
		st.Color = Color3.new(1, 1, 1)
		st.Transparency = 0.6
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		st.Parent = pill
	end
	return bb
end

-- Veste o uniforme "kind" (ver OUTFITS). Também pinta o corpo, se o NPC já existe.
function NPCKit.dress(npc, kind, opts)
	local o = OUTFITS[kind]
	if not npc or not o then
		return
	end
	opts = opts or {}
	local head = npc:FindFirstChild("Head")
	local torso = npc:FindFirstChild("UpperTorso") or npc:FindFirstChild("Torso")
	local lower = npc:FindFirstChild("LowerTorso")
	if not head or not torso then
		return
	end
	local old = npc:FindFirstChild("Uniforme")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Uniforme"
	folder.Parent = npc
	local shirt, pants = opts.shirt or o.shirt, opts.pants or o.pants
	for _, p in ipairs(npc:GetChildren()) do
		if p:IsA("BasePart") then
			if shirt and (p.Name:find("Torso") or p.Name:find("UpperArm") or p.Name:find("LowerArm")) and p.Name ~= "LowerTorso" then
				p.Color = shirt
			elseif pants and (p.Name:find("Leg") or p.Name:find("Foot") or p.Name == "LowerTorso") then
				p.Color = pants
			end
		end
	end
	local displayName = opts.name or npc.Name
	for _, key in ipairs(o.pieces or {}) do
		local fn = PIECES[key]
		if fn then
			local ok, err = pcall(fn, npc, o, head, torso, displayName, lower)
			if not ok then
				warn("[NPCKit] uniforme " .. key .. ": " .. tostring(err))
			end
		end
	end
	if opts.title ~= false and (opts.title or o.title) then
		NPCKit.title(npc, opts.title or o.title, opts.color or o.color, displayName)
	end
	npc:SetAttribute("Uniforme", kind)
end

-- Marco 10.21: parafusadeira (modelo do Luís: ServerStorage > BankModels > Parafusadeira,
-- "Low poly cordless drill" de BarnusModels no Sketchfab). Sem o modelo, sai uma de peças.
-- weldTo = mão (RightHand): fica soldada na mão; sem weldTo = peça ancorada em cf (enfeite).
-- O arquivo foi preparado com a broca para -Z e o cabo para baixo; GRIP = cabo em relação ao centro.
local DRILL_GRIP = Vector3.new(0, -0.141, 0.447)
local function drillTemplate()
	local folder = game:GetService("ServerStorage"):FindFirstChild("BankModels")
	local t = folder and folder:FindFirstChild("Parafusadeira")
	if t and t:IsA("Model") then
		t = t:FindFirstChildWhichIsA("BasePart", true)
	end
	return t and t:IsA("BasePart") and t or nil
end

function NPCKit.drill(parent, cf, weldTo)
	local part
	local t = drillTemplate()
	if t then
		part = t:Clone()
	else
		part = Instance.new("Part")
		part.Size = Vector3.new(0.35, 1.15, 1.6)
		part.Transparency = 1
		local function bit(name, size, offset, color, material)
			local p = Instance.new("Part")
			p.Name = name
			p.Size = size
			p.Color = color
			p.Material = material or Enum.Material.SmoothPlastic
			p.CanCollide = false
			p.CanQuery = false
			p.Massless = true
			p.CFrame = part.CFrame * CFrame.new(offset)
			local w = Instance.new("WeldConstraint")
			w.Part0 = part
			w.Part1 = p
			w.Parent = p
			p.Parent = part
		end
		bit("Corpo", Vector3.new(0.34, 0.42, 0.9), Vector3.new(0, 0.36, -0.05), Color3.fromRGB(40, 140, 170))
		bit("Cabo", Vector3.new(0.26, 0.6, 0.3), Vector3.new(0, -0.1, 0.45), Color3.fromRGB(30, 30, 34))
		bit("Bateria", Vector3.new(0.34, 0.2, 0.55), Vector3.new(0, -0.47, 0.42), Color3.fromRGB(30, 30, 34))
		bit("Broca", Vector3.new(0.06, 0.06, 0.6), Vector3.new(0, 0.36, -0.8), Color3.fromRGB(170, 170, 176), Enum.Material.Metal)
	end
	part.Name = "Parafusadeira"
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	if weldTo then
		part.Anchored = false
		part.Massless = true
		part.CFrame = weldTo.CFrame * CFrame.new(0, -0.2, 0) * CFrame.new(-DRILL_GRIP)
		local w = Instance.new("WeldConstraint")
		w.Part0 = weldTo
		w.Part1 = part
		w.Parent = part
	else
		part.Anchored = true
		part.CFrame = cf
	end
	part.Parent = parent
	return part
end

-- parafusadeira na mão de um jogador ou NPC (some com :Destroy())
function NPCKit.drillInHand(character)
	local hand = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm"))
	if not hand then
		return nil
	end
	local old = character:FindFirstChild("Parafusadeira")
	if old then
		old:Destroy()
	end
	return NPCKit.drill(character, nil, hand)
end

return NPCKit
