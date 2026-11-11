-- PetService (ModuleScript)
-- Caminho: ServerScriptService > Services > PetService
-- Marco 7: pets. O jogador adota um pet no Duto Pet Shop (cantinho "ADOTE UM AMIGO"),
-- escolhe a cor e o pet passa a seguir a pessoa pela cidade.
--   * O servidor decide tudo: quem pode adotar, preço (GameConfig.Pets), cor e o que fica salvo
--     (data.pet = { kind = "Dog", color = 1, out = true }).
--   * O pet é um modelo parado (Anchored) na pasta Workspace.Pets. Quem faz ele andar atrás do
--     dono, pular, sentar e abanar o rabo é o PetController, em cada cliente (só visual).
--   * Carinho: qualquer jogador perto aperta E no pet; o servidor confere e avisa todo mundo
--     para mostrar os coraçõezinhos.
--   * Modelo 3D: se existir ServerStorage > PetModels > (spec.Model), ele é usado (peças com
--     nome "Paint_..." pegam a cor escolhida). Sem ele, um cachorro de peças.
--   * Marco 10.3: dragão (PetDragao): peças "Glow_..." em Neon, asas "WingL/WingR" batem
--     (PetController) e spec.Aura põe faíscas e uma luz fraca no corpo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local SecurityService = require(script.Parent:WaitForChild("SecurityService"))

local PetService = {}

local uiUpdate
local pets = {} -- pets[player] = Model
local petsFolder
local adoptSign -- placa do cantinho de adoção (o aviso "Adotar" fica nela)

local function notice(player, text)
	uiUpdate:FireClient(player, "Notice", { text = text })
end

-- data.pet válido? (dados salvos podem ser de uma versão antiga)
local function petData(player)
	local data = PlayerDataService.get(player)
	local pet = data and data.pet
	if type(pet) ~= "table" then
		return nil
	end
	local spec = type(pet.kind) == "string" and GameConfig.Pets[pet.kind]
	if not spec or type(pet.color) ~= "number" then
		return nil
	end
	if not spec.Colors[pet.color] then
		pet.color = 1 -- Marco 10.7: o dragão novo tem uma cor só (a da textura); quem tinha outra fica com ela
	end
	return pet, spec
end

---------------------------------------------------------------------------
-- Modelo do pet
---------------------------------------------------------------------------

local function newPart(model, name, size, cf, color, extra)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = extra and extra.Material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if extra and extra.Shape then
		p.Shape = extra.Shape
	end
	p.Transparency = extra and extra.Transparency or 0
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Parent = model
	return p
end

-- Cachorro de peças (até chegar o modelo 3D). Root = ponto no chão, no meio do corpo; frente = -Z.
-- Pernas e rabo têm os atributos Pivot/Offset: o PetController gira eles em volta do Pivot.
local function buildPartsDog(model, root, spec, color)
	local u = spec.Length / 3.2
	local light = color:Lerp(Color3.new(1, 1, 1), 0.45)
	local dark = color:Lerp(Color3.new(0, 0, 0), 0.35)
	local black = Color3.fromRGB(20, 20, 22)
	local function at(x, y, z)
		return root.CFrame * CFrame.new(x * u, y * u, z * u)
	end
	local function paint(p)
		p:SetAttribute("Paint", true)
		return p
	end
	paint(newPart(model, "Body", Vector3.new(1.3, 1.05, 2.0) * u, at(0, 1.35, 0.1), color))
	newPart(model, "Belly", Vector3.new(1.0, 0.3, 1.5) * u, at(0, 0.88, 0.1), light)
	paint(newPart(model, "Head", Vector3.new(1.1, 1.0, 1.0) * u, at(0, 2.15, -1.05), color))
	newPart(model, "Snout", Vector3.new(0.62, 0.45, 0.55) * u, at(0, 1.92, -1.75), light)
	newPart(model, "Nose", Vector3.new(0.24, 0.18, 0.12) * u, at(0, 2.05, -2.05), black)
	newPart(model, "Tongue", Vector3.new(0.2, 0.05, 0.25) * u, at(0, 1.68, -1.85), Color3.fromRGB(235, 110, 130))
	for _, s in ipairs({ -1, 1 }) do
		newPart(model, "Eye", Vector3.new(0.17, 0.17, 0.17) * u, at(s * 0.28, 2.3, -1.56), black, { Shape = Enum.PartType.Ball })
		local ear = newPart(model, "Ear", Vector3.new(0.18, 0.62, 0.42) * u, at(s * 0.6, 2.25, -0.95) * CFrame.Angles(0, 0, s * math.rad(-12)), dark)
		ear:SetAttribute("Side", s)
	end
	newPart(model, "Collar", Vector3.new(1.16, 0.16, 0.9) * u, at(0, 1.7, -0.78), Color3.fromRGB(210, 40, 45))
	newPart(model, "Tag", Vector3.new(0.22, 0.22, 0.06) * u, at(0, 1.55, -1.24), Color3.fromRGB(240, 200, 60), { Material = Enum.Material.Metal })
	for _, leg in ipairs({ { "LegFL", -0.4, -0.6 }, { "LegFR", 0.4, -0.6 }, { "LegBL", -0.4, 0.75 }, { "LegBR", 0.4, 0.75 } }) do
		local p = paint(newPart(model, leg[1], Vector3.new(0.36, 0.95, 0.36) * u, at(leg[2], 0.475, leg[3]), color))
		p:SetAttribute("Pivot", Vector3.new(leg[2], 0.95, leg[3]) * u) -- quadril
		p:SetAttribute("Offset", Vector3.new(0, -0.475, 0) * u)
		local paw = newPart(model, "Paw", Vector3.new(0.4, 0.14, 0.44) * u, at(leg[2], 0.07, leg[3] - 0.04), light)
		paw:SetAttribute("Leg", leg[1]) -- a patinha acompanha a perna
	end
	local tail = paint(newPart(model, "Tail", Vector3.new(0.22, 0.22, 0.85) * u, at(0, 1.75, 1.45), color))
	tail:SetAttribute("Pivot", Vector3.new(0, 1.7, 1.05) * u)
	tail:SetAttribute("Offset", Vector3.new(0, 0, 0.42) * u)
	tail:SetAttribute("Pitch", -35)
end

-- Modelo 3D (ServerStorage > PetModels): mesmo esquema dos carros (frente pela peça
-- "FrontMarker", escala pelo comprimento, peças "Paint_..." pintadas com a cor escolhida)
local function buildMeshPet(model, root, spec, color, tpl)
	local clone = tpl:Clone()
	local parts, marker, pivotMarks = {}, nil, {}
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			-- Marco 9.10: "PivotLegFL", "PivotTail"... = ponto de giro de cada perna e do rabo
			local pivotName = d.Name:match("^Pivot(%a+)") or (d.Parent and d.Parent.Name:match("^Pivot(%a+)"))
			if pivotName then
				pivotMarks[pivotName] = d
			elseif d.Name:find("FrontMarker") or (d.Parent and d.Parent.Name:find("FrontMarker")) then
				marker = d
			else
				table.insert(parts, d)
			end
		end
	end
	if #parts == 0 then
		clone:Destroy()
		return false
	end
	local function bounds()
		local mn = Vector3.new(math.huge, math.huge, math.huge)
		local mx = -mn
		for _, p in ipairs(parts) do
			local half = p.Size / 2
			for _, c in ipairs({ p.CFrame * -half, p.CFrame * half }) do
				mn = mn:Min(c)
				mx = mx:Max(c)
			end
		end
		return mn, mx
	end
	local mn, mx = bounds()
	local center = (mn + mx) / 2
	local front = Vector3.new(0, 0, -1)
	if marker then
		local d = marker.Position - center
		front = math.abs(d.X) > math.abs(d.Z) and Vector3.new(math.sign(d.X), 0, 0) or Vector3.new(0, 0, math.sign(d.Z))
	end
	local length = front.X ~= 0 and (mx.X - mn.X) or (mx.Z - mn.Z)
	clone:ScaleTo(clone:GetScale() * spec.Length / math.max(length, 0.01))
	mn, mx = bounds()
	center = (mn + mx) / 2
	local groundCenter = Vector3.new(center.X, mn.Y, center.Z)
	local base = CFrame.lookAt(groundCenter, groundCenter + front)
	local pivots = {}
	for name, mark in pairs(pivotMarks) do
		pivots[name] = base:PointToObjectSpace(mark.Position)
	end
	for _, p in ipairs(parts) do
		p.CFrame = root.CFrame * base:ToObjectSpace(p.CFrame)
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		local name = p.Name:find("_%x%x%x%x%x%x") and p.Name or (p.Parent and p.Parent.Name or "")
		-- Marco 9.10: perna ou rabo ("LegFL_Paint_6e7078_3"): o PetController gira no ponto de giro
		-- Marco 10.3: asas do dragão ("WingL_Wing_7a1fd1_20") batem em volta da raiz
		local joint = name:match("^(Leg%u%u)_") or name:match("^(Tail)_") or name:match("^(Wing%u)_")
		if joint and pivots[joint] then
			p.Name = joint
			p:SetAttribute("MeshJoint", true)
			p:SetAttribute("Pivot", pivots[joint])
			name = name:sub(#joint + 2)
		end
		-- Marco 9.10: a cor de cada peça vem do nome ("Fur_f4f2ee_2"): o Roblox não importa a
		-- cor dos vértices do .glb, e sem isso o cachorro ficava todo branco
		local role, hex = name:match("^(%a+)_(%x%x%x%x%x%x)")
		if hex then
			p.Color = Color3.fromHex(hex)
			p.Material = Enum.Material.SmoothPlastic
			p.Reflectance = (role == "Eye" or role == "Nose") and 0.25 or 0
			if role == "Glow" then
				p.Material = Enum.Material.Neon -- Marco 10.3: olhos e cristas do dragão brilham
			end
			local meshPart = p:IsA("MeshPart") and p or nil
			if meshPart then
				meshPart.TextureID = ""
			end
			for _, c in ipairs(p:GetChildren()) do
				if c:IsA("SurfaceAppearance") then
					c:Destroy()
				end
			end
		end
		if name:find("^Paint") then
			p.Color = color
			p:SetAttribute("Paint", true)
			for _, c in ipairs(p:GetChildren()) do
				if c:IsA("SurfaceAppearance") then
					c:Destroy()
				end
			end
		end
		p.Parent = model
	end
	clone:Destroy()
	return true
end

-- Marco 10.7: pet com esqueleto e animações do próprio modelo (Dragão de Cristal importado do
-- .fbx com o nome spec.Rig). A frente vem dos ossos "Head" e "Tail9"; o tamanho, de spec.Length.
-- As animações (idle, walk, flap do .fbx) não passam pelo Animator: estão no ModuleScript
-- Shared/<spec.ScriptAnims> e o PetController mexe os ossos (Bone.Transform) em cada cliente.
-- Assim não precisa publicar animação (o importador de animação do Studio deixava o dragão "uma bola").
local function buildRigPet(model, root, spec, tpl)
	local clone = tpl:Clone()
	if not clone:IsA("Model") then
		local holder = Instance.new("Model")
		clone.Parent = holder
		clone = holder
	end
	local parts, visible, bones = {}, {}, {}
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
			if d.Transparency < 1 then
				table.insert(visible, d)
			end
		elseif d:IsA("Bone") then
			bones[d.Name] = d
		elseif d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Humanoid") or d:IsA("AnimationController") or d:IsA("Animator") then
			d:Destroy()
		end
	end
	if #visible == 0 then
		clone:Destroy()
		return false
	end
	local function bounds(axis)
		local mn = Vector3.new(math.huge, math.huge, math.huge)
		local mx = -mn
		for _, p in ipairs(visible) do
			local half = p.Size / 2
			for _, c in ipairs({ p.CFrame * -half, p.CFrame * half }) do
				mn = mn:Min(c)
				mx = mx:Max(c)
			end
		end
		return mn, mx
	end
	local front = Vector3.new(0, 0, -1)
	local head, tail = bones.Head, bones.Tail9 or bones.Tail1
	if head and tail then
		local d = head.WorldPosition - tail.WorldPosition
		d = Vector3.new(d.X, 0, d.Z)
		if d.Magnitude > 0.01 then
			front = d.Unit
		end
	end
	local mn, mx = bounds()
	local size = mx - mn
	local length = math.abs(front.X) > math.abs(front.Z) and size.X or size.Z
	clone:ScaleTo(clone:GetScale() * spec.Length / math.max(length, 0.01))
	mn, mx = bounds()
	local center = (mn + mx) / 2
	local ground = Vector3.new(center.X, mn.Y, center.Z)
	local base = CFrame.lookAt(ground, ground + front)
	for _, p in ipairs(parts) do
		p.CFrame = root.CFrame * base:ToObjectSpace(p.CFrame)
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
	end
	for _, c in ipairs(clone:GetChildren()) do
		c.Parent = model
	end
	clone:Destroy()
	model:SetAttribute("Rig", true)
	model:SetAttribute("AnimData", spec.ScriptAnims)
	return true
end

-- Marco 10.3: aura leve do dragão (faíscas que sobem do corpo + luz fraca). spec.Aura = 3 cores.
local function addAura(model, colors)
	local body, best = nil, 0
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") and p.Name ~= "Root" and not p:GetAttribute("MeshJoint") then
			local v = p.Size.X * p.Size.Y * p.Size.Z
			if v > best then
				body, best = p, v
			end
		end
	end
	if not body then
		return
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Aura"
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, colors[1]),
		ColorSequenceKeypoint.new(0.5, colors[2]),
		ColorSequenceKeypoint.new(1, colors[3]),
	})
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.4, 0.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.25, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(1, 1.8)
	emitter.Rate = 14
	emitter.Speed = NumberRange.new(0.3, 0.9)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, 1.2, 0)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-60, 60)
	emitter.Parent = body
	local light = Instance.new("PointLight")
	light.Name = "AuraLuz"
	light.Color = colors[2]
	light.Brightness = 0.8
	light.Range = 7
	light.Parent = body
end

local function despawn(player)
	local m = pets[player]
	pets[player] = nil
	if m then
		m:Destroy()
	end
end

local function spawnPet(player)
	despawn(player)
	local pet, spec = petData(player)
	if not pet or pet.out == false then
		return
	end
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local color = spec.Colors[pet.color].Color
	local model = Instance.new("Model")
	model.Name = player.Name .. "_Pet"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent -- todos os clientes sempre têm o pet
	local start = hrp.Position - hrp.CFrame.LookVector * 3.5 + hrp.CFrame.RightVector * 2
	local root = newPart(model, "Root", Vector3.new(0.2, 0.2, 0.2), CFrame.new(start.X, hrp.Position.Y - 3, start.Z), Color3.new(1, 1, 1), { Transparency = 1 })
	model.PrimaryPart = root
	local folder = ServerStorage:FindFirstChild("PetModels")
	local tpl = folder and spec.Model and folder:FindFirstChild(spec.Model)
	local ok = false
	-- Marco 10.7: com o modelo de esqueleto importado (PetDragaoRig), usa ele com as animações do .fbx
	local rig = folder and spec.Rig and spec.ScriptAnims and folder:FindFirstChild(spec.Rig)
	if rig then
		local good, result = pcall(buildRigPet, model, root, spec, rig)
		ok = good and result
		if not ok then
			warn(("[PetService] Modelo com esqueleto de %s com problema (%s); usando o normal."):format(spec.Name, tostring(result)))
			for _, p in ipairs(model:GetChildren()) do
				if p ~= root then
					p:Destroy()
				end
			end
		end
	end
	if tpl and not ok then
		local good, result = pcall(buildMeshPet, model, root, spec, color, tpl)
		ok = good and result
		if not ok then
			warn(("[PetService] Modelo 3D de %s com problema (%s); usando o de peças."):format(spec.Name, tostring(result)))
			for _, p in ipairs(model:GetChildren()) do
				if p ~= root then
					p:Destroy()
				end
			end
		end
	end
	if not ok then
		buildPartsDog(model, root, spec, color)
	elseif spec.Aura then
		addAura(model, spec.Aura)
	end
	-- Marco 10.3: pet grande (dragão) anda mais longe do dono
	model:SetAttribute("FollowBack", spec.FollowBack)
	model:SetAttribute("FollowSide", spec.FollowSide)
	-- Marco 10.4: o cliente espera chegarem todas as peças antes de começar a mexer o pet
	local count = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			count += 1
		end
	end
	model:SetAttribute("PartCount", count)
	model:SetAttribute("Owner", player.UserId)
	model:SetAttribute("Kind", pet.kind)
	model:SetAttribute("PetName", spec.Name)
	model.Parent = petsFolder
	pets[player] = model
end

-- Marco 9: bichinhos "de cliente" do Cuidador de animais, feitos de peças (até chegarem os
-- modelos 3D do Luís). look = uma raça de GameConfig.PetCare.Breeds:
--   { kind = "Dog"/"Cat", color, light, dark, spots, body (comprimento), legs (altura da perna),
--     ears = "floppy"/"pointy", fluffy = true (poodle), size (escala) }
-- Root = ponto no chão, no meio do corpo; frente = -Z.
local function buildPartsAnimal(model, root, look)
	local u = look.size or 1
	local color = look.color
	local light = look.light or color:Lerp(Color3.new(1, 1, 1), 0.45)
	local dark = look.dark or color:Lerp(Color3.new(0, 0, 0), 0.35)
	local black = Color3.fromRGB(20, 20, 22)
	local cat = look.kind == "Cat"
	local bodyLen = look.body or 2
	local legH = look.legs or 0.95
	local fluffy = look.fluffy and { Shape = Enum.PartType.Ball, Material = Enum.Material.Fabric } or nil
	local function at(x, y, z)
		return root.CFrame * CFrame.new(x * u, y * u, z * u)
	end
	local bodyY = legH + 0.45
	local front = -bodyLen / 2
	local body = newPart(model, "Body", Vector3.new(cat and 1.0 or 1.3, cat and 0.85 or 1.05, bodyLen) * u, at(0, bodyY, 0), color)
	if fluffy then
		-- poodle: bolinhas de pelo no peito, no quadril e na cabeça
		newPart(model, "Fluff", Vector3.new(1.6, 1.4, 1.4) * u, at(0, bodyY + 0.1, front + 0.4), color, fluffy)
		newPart(model, "Fluff", Vector3.new(1.3, 1.2, 1.2) * u, at(0, bodyY + 0.1, -front - 0.3), color, fluffy)
	end
	newPart(model, "Belly", Vector3.new(cat and 0.8 or 1.0, 0.3, bodyLen * 0.75) * u, at(0, bodyY - 0.45, 0), light)
	for i, spot in ipairs(look.spots and { { 0.66, 0.2, -0.4 }, { -0.66, 0.1, 0.3 }, { 0.66, -0.1, 0.6 }, { 0, 0.53, 0.1 }, { -0.66, 0.25, -0.5 } } or {}) do
		local size = spot[1] == 0 and Vector3.new(0.4, 0.05, 0.45) or Vector3.new(0.05, 0.35 + (i % 2) * 0.1, 0.4)
		newPart(model, "Spot", size * u, at(spot[1], bodyY + spot[2], spot[3]), look.spots)
	end
	-- cabeça
	local headY = bodyY + (cat and 0.55 or 0.8)
	local headZ = front - (cat and 0.25 or 0.35)
	local hs = cat and 0.9 or 1.0
	newPart(model, "Head", Vector3.new(hs + 0.1, hs, hs) * u, at(0, headY, headZ), look.face or color, fluffy and { Material = Enum.Material.Fabric } or nil)
	if fluffy then
		newPart(model, "Topete", Vector3.new(1.0, 0.8, 0.9) * u, at(0, headY + 0.6, headZ + 0.1), color, fluffy)
	end
	local snoutZ = headZ - hs / 2 - (cat and 0.1 or 0.25)
	newPart(model, "Snout", Vector3.new(cat and 0.45 or 0.62, cat and 0.3 or 0.45, cat and 0.25 or 0.55) * u, at(0, headY - 0.22, snoutZ), light)
	newPart(model, "Nose", Vector3.new(cat and 0.16 or 0.24, 0.14, 0.1) * u, at(0, headY - (cat and 0.12 or 0.1), snoutZ - (cat and 0.14 or 0.3)), cat and Color3.fromRGB(240, 140, 160) or black)
	for _, s in ipairs({ -1, 1 }) do
		newPart(model, "Eye", Vector3.new(0.17, 0.17, 0.17) * u, at(s * 0.26, headY + 0.12, headZ - hs / 2 - 0.02), cat and Color3.fromRGB(120, 190, 60) or black, { Shape = Enum.PartType.Ball })
		if look.ears == "pointy" or cat then
			local ear = Instance.new("WedgePart")
			ear.Name = "Ear"
			ear.Size = Vector3.new(0.12, 0.5, 0.4) * u
			ear.CFrame = at(s * 0.3, headY + hs / 2 + 0.22, headZ) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, s * math.rad(-10))
			ear.Color = dark
			ear.Anchored = true
			ear.CanCollide = false
			ear.CanQuery = false
			ear.CanTouch = false
			ear.Parent = model
		else
			newPart(model, "Ear", Vector3.new(0.18, look.longEars and 0.9 or 0.62, 0.42) * u, at(s * (hs / 2 + 0.08), headY + 0.05, headZ + 0.1) * CFrame.Angles(0, 0, s * math.rad(-12)), dark)
		end
	end
	if not cat then
		newPart(model, "Collar", Vector3.new(1.16, 0.16, 0.9) * u, at(0, headY - 0.45, headZ + 0.27), look.collar or Color3.fromRGB(210, 40, 45))
	else
		newPart(model, "Collar", Vector3.new(0.9, 0.12, 0.7) * u, at(0, headY - 0.42, headZ + 0.2), look.collar or Color3.fromRGB(60, 140, 230))
	end
	-- pernas e patas
	local lx = cat and 0.3 or 0.4
	local lz = bodyLen / 2 - 0.35
	for _, leg in ipairs({ { -lx, -lz }, { lx, -lz }, { -lx, lz }, { lx, lz } }) do
		newPart(model, "Leg", Vector3.new(cat and 0.26 or 0.36, legH, cat and 0.26 or 0.36) * u, at(leg[1], legH / 2, leg[2]), fluffy and light or color)
		newPart(model, "Paw", Vector3.new(cat and 0.3 or 0.4, 0.14, cat and 0.34 or 0.44) * u, at(leg[1], 0.07, leg[2] - 0.04), fluffy and color or light, fluffy)
	end
	-- rabo (gato: comprido e para cima)
	if cat then
		newPart(model, "Tail", Vector3.new(0.18, 0.18, 1.3) * u, at(0, bodyY + 0.55, -front + 0.45) * CFrame.Angles(math.rad(50), 0, 0), look.tail or color)
	else
		newPart(model, "Tail", Vector3.new(0.22, 0.22, 0.85) * u, at(0, bodyY + 0.35, -front + 0.3) * CFrame.Angles(math.rad(35), 0, 0), color, fluffy)
	end
	body:SetAttribute("Paint", true)
end

-- Marco 9: pet "de cliente" parado (Cuidador de animais). cf = no chão, frente para -Z.
function PetService.buildDisplay(cf, look, parent)
	local model = Instance.new("Model")
	model.Name = "PetCliente"
	local root = newPart(model, "Root", Vector3.new(0.2, 0.2, 0.2), cf, Color3.new(1, 1, 1), { Transparency = 1 })
	model.PrimaryPart = root
	-- Marco 9.9: raça com modelo 3D (husky, dálmata, pastor); sem ele, o bichinho de peças
	local folder = ServerStorage:FindFirstChild("PetModels")
	local tpl = folder and look.model and folder:FindFirstChild(look.model)
	local ok = false
	if tpl then
		local color = look.coats and look.coats[math.random(1, #look.coats)] or look.color
		local good, result = pcall(buildMeshPet, model, root, { Length = look.length or 3.2 }, color, tpl)
		ok = good and result
		if not ok then
			for _, p in ipairs(model:GetChildren()) do
				if p ~= root then
					p:Destroy()
				end
			end
		end
	end
	if not ok then
		buildPartsAnimal(model, root, look)
	end
	model:SetAttribute("Breed", look.name)
	model.Parent = parent
	return model
end

---------------------------------------------------------------------------
-- Adoção (Duto Pet Shop)
---------------------------------------------------------------------------

local function nearSign(player)
	local _, _, root = SecurityService.getLivingCharacter(player)
	return root and adoptSign and (root.Position - adoptSign.Position).Magnitude <= GameConfig.PetShop.UseDistance
end

local function openShop(player)
	local kinds = {}
	for id, spec in pairs(GameConfig.Pets) do
		local colors = {}
		for i, c in ipairs(spec.Colors) do
			colors[i] = { name = c.Name, rgb = { math.floor(c.Color.R * 255 + 0.5), math.floor(c.Color.G * 255 + 0.5), math.floor(c.Color.B * 255 + 0.5) } }
		end
		table.insert(kinds, { id = id, name = spec.Name, price = spec.Price or 0, colors = colors })
	end
	table.sort(kinds, function(a, b)
		return a.price < b.price
	end)
	local pet, spec = petData(player)
	uiUpdate:FireClient(player, "PetShopOpen", {
		kinds = kinds,
		current = pet and { name = spec.Name, color = spec.Colors[pet.color].Name, out = pet.out ~= false } or nil,
		money = EconomyService.getMoney(player) or 0,
	})
end

local function adopt(player, data)
	local kind = type(data) == "table" and data.kind
	local spec = type(kind) == "string" and GameConfig.Pets[kind]
	local color = type(data) == "table" and data.color
	if not spec or type(color) ~= "number" or color % 1 ~= 0 or not spec.Colors[color] then
		return
	end
	if not nearSign(player) then
		return notice(player, "Chegue mais perto do cantinho de adoção.")
	end
	local saved = PlayerDataService.get(player)
	if not saved then
		return notice(player, "Seus dados ainda estão carregando. Tente de novo.")
	end
	local price = spec.Price or 0
	if price > 0 and not EconomyService.spend(player, price, "Pet " .. spec.Name) then
		return notice(player, ("Falta dinheiro: custa %s%d."):format(GameConfig.Economy.CurrencySymbol, price))
	end
	PlayerDataService.set(player, "pet", { kind = kind, color = color, out = true })
	task.spawn(PlayerDataService.save, player)
	spawnPet(player)
	notice(player, ("Você adotou um %s %s! Ele vai te seguir. Aperte E nele para fazer carinho."):format(spec.Name:lower(), spec.Colors[color].Name:lower()))
end

local function toggle(player)
	local pet = petData(player)
	if not pet then
		return
	end
	if not nearSign(player) then
		return
	end
	local copy = { kind = pet.kind, color = pet.color, out = pet.out == false }
	PlayerDataService.set(player, "pet", copy)
	if copy.out then
		spawnPet(player)
		notice(player, "Seu pet voltou a te seguir.")
	else
		despawn(player)
		notice(player, "Seu pet ficou descansando no Duto Pet Shop.")
	end
end

-- Carinho: confere se quem fez está perto do dono do pet e avisa todo mundo (coraçõezinhos)
local function love(player, ownerId)
	if type(ownerId) ~= "number" then
		return
	end
	local owner = Players:GetPlayerByUserId(ownerId)
	if not owner or not pets[owner] then
		return
	end
	local _, _, root = SecurityService.getLivingCharacter(player)
	local _, _, ownerRoot = SecurityService.getLivingCharacter(owner)
	if not root or not ownerRoot or (root.Position - ownerRoot.Position).Magnitude > 30 then
		return
	end
	uiUpdate:FireAllClients("PetLove", { owner = ownerId, from = player.UserId })
end

local function onRequest(player, action, data)
	if not SecurityService.checkRate(player, "PetRequest", 1) then
		return
	end
	if action == "Adopt" then
		adopt(player, data)
	elseif action == "Toggle" then
		toggle(player)
	elseif action == "Pet" then
		love(player, data)
	end
end

-- Cantinho de adoção dentro do Duto Pet Shop: cercadinho, placa e um cachorro de exemplo
local function buildAdoptionCorner()
	local stations = Workspace:WaitForChild("JobStations", 20)
	local map = Workspace:FindFirstChild("Map")
	local shops = map and map:FindFirstChild("JobLocations")
	local shop = shops and shops:FindFirstChild(GameConfig.Places.PetShop)
	local base = shop and shop:GetAttribute("BaseCFrame") -- chão de dentro (frente = porta)
	if not stations or not base then
		warn("[PetService] Duto Pet Shop não encontrado; sem adoção.")
		return
	end
	local corner = Instance.new("Model")
	corner.Name = "Adocao"
	local function at(x, y, z)
		return base * CFrame.new(x, y, z)
	end
	local cx, cz = -9, -7
	local fence = Color3.fromRGB(250, 250, 250)
	for _, side in ipairs({ { 0, -2.6, 7, 0.3 }, { 0, 2.6, 7, 0.3 }, { -3.5, 0, 0.3, 5.5 }, { 3.5, 0, 0.3, 5.5 } }) do
		newPart(corner, "Fence", Vector3.new(side[3], 1.6, side[4]), at(cx + side[1], 0.8, cz + side[2]), fence).CanCollide = true
	end
	newPart(corner, "Grass", Vector3.new(6.7, 0.1, 4.9), at(cx, 0.06, cz), Color3.fromRGB(110, 190, 90), { Material = Enum.Material.Grass })
	newPart(corner, "Pole", Vector3.new(0.3, 5, 0.3), at(cx + 4.2, 2.5, cz - 2.4), Color3.fromRGB(130, 80, 200))
	adoptSign = newPart(corner, "AdoptionSign", Vector3.new(4.4, 1.8, 0.25), at(cx + 4.2, 5.4, cz - 2.4) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(130, 80, 200))
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back -- virada para a porta
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = adoptSign
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = "ADOTE UM AMIGO"
	label.Parent = gui
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "AdoptPrompt"
	prompt.ActionText = "Adotar um pet"
	prompt.ObjectText = "Duto Pet Shop"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = adoptSign
	prompt.Triggered:Connect(function(player)
		if SecurityService.checkRate(player, "PetShopOpen", 1) then
			openShop(player)
		end
	end)
	-- Marco 9.9: husky, dálmata e pastor de exemplo no cercadinho (se os modelos 3D estiverem lá)
	local folder = ServerStorage:FindFirstChild("PetModels")
	local shown = 0
	for i, kind in ipairs({ "Husky", "Dalmata", "Pastor" }) do
		local spec = GameConfig.Pets[kind]
		local tpl = folder and spec and folder:FindFirstChild(spec.Model)
		if tpl then
			local demo = Instance.new("Model")
			demo.Name = "Exemplo" .. kind
			local root = newPart(demo, "Root", Vector3.new(0.2, 0.2, 0.2), at(cx - 4.4 + i * 2.2, 0.1, cz) * CFrame.Angles(0, math.pi, 0), Color3.new(1, 1, 1), { Transparency = 1 })
			demo.PrimaryPart = root
			if pcall(buildMeshPet, demo, root, spec, spec.Colors[1].Color, tpl) then
				demo.Parent = corner
				shown += 1
			else
				demo:Destroy()
			end
		end
	end
	-- cachorro de exemplo (parado) dentro do cercadinho
	local spec = GameConfig.Pets.Dog
	if spec and shown == 0 then
		local demo = Instance.new("Model")
		demo.Name = "CachorroDeExemplo"
		local root = newPart(demo, "Root", Vector3.new(0.2, 0.2, 0.2), at(cx, 0.1, cz) * CFrame.Angles(0, math.pi, 0), Color3.new(1, 1, 1), { Transparency = 1 })
		demo.PrimaryPart = root
		buildPartsDog(demo, root, spec, spec.Colors[1].Color)
		demo.Parent = corner
	end
	corner.Parent = stations
end

function PetService.init(remotes)
	uiUpdate = remotes[GameConfig.Remotes.UIUpdate]
	remotes[GameConfig.Remotes.PetRequest].OnServerEvent:Connect(onRequest)
	petsFolder = Instance.new("Folder")
	petsFolder.Name = "Pets"
	petsFolder.Parent = Workspace
	task.spawn(buildAdoptionCorner)

	local function onPlayer(player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("HumanoidRootPart", 10)
			spawnPet(player)
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end
	-- dados carregaram depois do personagem nascer
	PlayerDataService.onLoaded(function(player)
		if player.Character and not pets[player] then
			spawnPet(player)
		end
	end)
	Players.PlayerRemoving:Connect(despawn)
end

return PetService
