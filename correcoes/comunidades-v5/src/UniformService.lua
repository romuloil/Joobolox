-- UniformService (ModuleScript)
-- Caminho: ServerScriptService > Services > UniformService
-- Marco 8.4: farda da PM. O Policial veste a farda (camisa com colete e calça) nos armários
-- do arsenal da Base da PM. Vale para qualquer boneco (R6 ou R15): a roupa normal e os
-- acessórios (menos o cabelo) ficam guardados e voltam quando ele tira a farda,
-- sai do emprego ou é preso. Morrer não tira a farda.
-- Marco 9.11: também a farda do bombeiro (GameConfig.FireUniform), nos armários do vestiário do
-- quartel. Além da camisa e da calça, ela tem equipamento 3D (capacete, balaclava, mochila, cinto,
-- luvas e botas) copiado de ServerStorage > UniformModels e soldado nos attachments do boneco.
-- Cada armário diz qual farda é pelo atributo UniformLocker (true = PM, "Bombeiro" = bombeiro).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local SecurityService = require(script.Parent:WaitForChild("SecurityService"))

local UniformService = {}

local UNIFORMS = { GameConfig.PoliceUniform, GameConfig.FireUniform }
local byJob = {} -- byJob["Bombeiro"] = GameConfig.FireUniform
for _, cfg in ipairs(UNIFORMS) do
	byJob[cfg.Job] = cfg
end
-- valor do atributo UniformLocker -> farda (o true antigo é o armário da PM)
local function lockerUniform(value)
	return value == true and GameConfig.PoliceUniform or byJob[value]
end

local uiUpdate
local saved = {} -- saved[player] = { character = ..., items = { instâncias guardadas } }
local WORN = { "FardaCamisa", "FardaCalca", "FardaEquipamento", "FardaEtiqueta" }
local BODY_KEYS = { "TorsoColor3", "LeftArmColor3", "RightArmColor3", "LeftLegColor3", "RightLegColor3" }

-- Onde cada grupo do equipamento 3D vai: attachment do boneco e o mesmo ponto no manequim R6 em
-- que a farda foi modelada (pés em Y = 0). Funciona em R6 e R15 (os dois têm esses attachments).
local GEAR = {
	Capacete = { "FaceCenterAttachment", Vector3.new(0, 4.5, 0) },
	Balaclava = { "FaceCenterAttachment", Vector3.new(0, 4.5, 0) },
	Mochila = { "BodyBackAttachment", Vector3.new(0, 3, 0.5) },
	Suspensorio = { "BodyBackAttachment", Vector3.new(0, 3, 0.5) },
	Cinto = { "WaistCenterAttachment", Vector3.new(0, 2, 0) },
	-- Marco 9.14: as luvas saíram (iam longe do corpo e balançavam ao andar)
	BotaD = { "RightFootAttachment", Vector3.new(0.5, 0, 0) },
	BotaE = { "LeftFootAttachment", Vector3.new(-0.5, 0, 0) },
}

local function notice(player, text)
	uiUpdate:FireClient(player, "Notice", { text = text })
end

-- aceita 123456 ou "rbxassetid://123456" (do jeito que o Studio copiar)
local function idNumber(n)
	if type(n) == "number" then
		return math.floor(n)
	end
	return tonumber(string.match(tostring(n or ""), "%d+")) or 0
end

-- número inteiro como texto, sem virar "1.11e+14"
local function idText(n)
	return string.format("%d", idNumber(n))
end

local function assetId(n)
	return "rbxassetid://" .. idText(n)
end

-- Marco 8.6/8.8: fardado, o jogador fica sem acessórios (chapéu, óculos, cachecol, mochila, roupa 3D).
-- Marco 9: sem boné, então o cabelo (e a sobrancelha/cílios das cabeças novas) continua aparecendo.
-- Tudo volta quando ele tira a farda.
local KEEP = {
	[Enum.AccessoryType.Hair] = true,
	[Enum.AccessoryType.Eyebrow] = true,
	[Enum.AccessoryType.Eyelash] = true,
}

local function isHair(item)
	if KEEP[item.AccessoryType] then
		return true
	end
	local handle = item:FindFirstChild("Handle")
	return handle ~= nil and handle:FindFirstChild("HairAttachment") ~= nil
end

local function isAccessoryToHide(item, cfg)
	return item:IsA("Accessory") and (cfg.HideHair or not isHair(item))
end

local function findAttachment(character, name)
	for _, part in ipairs(character:GetChildren()) do
		local att = part:IsA("BasePart") and part:FindFirstChild(name)
		if att and att:IsA("Attachment") then
			return att
		end
	end
	return nil
end

local function gearTemplate(cfg)
	local folder = cfg.Model and ServerStorage:FindFirstChild("UniformModels")
	return folder and folder:FindFirstChild(cfg.Model)
end

-- Copia o equipamento 3D para o boneco. O importador pode mudar a escala e a posição do modelo:
-- RefPe (pé do manequim) e RefTopo (5 studs acima) dizem quanto.
local function addGear(character, cfg)
	local template = gearTemplate(cfg)
	if not template then
		return
	end
	local refPe = template:FindFirstChild("RefPe", true)
	local refTopo = template:FindFirstChild("RefTopo", true)
	if not (refPe and refTopo) then
		warn("[UniformService] " .. template.Name .. " sem RefPe/RefTopo (use o GLB do tools/fardaprep.py)")
		return
	end
	local scale = (refTopo.Position - refPe.Position).Magnitude / 5
	-- Marco 9.14: o importador do Roblox vira o modelo de costas (a frente do .glb é -Z, a do
	-- Roblox também, mas o equipamento saía virado para trás). Aqui ele é desvirado: frente e
	-- costas trocam. Se o lado também veio trocado (bota direita na esquerda), troca o lado.
	local flipX = false
	for _, part in ipairs(template:GetDescendants()) do
		if part:IsA("BasePart") and string.match(part.Name, "^BotaD") then
			flipX = refPe.CFrame:PointToObjectSpace(part.Position).X < 0
			break
		end
	end
	local turn = CFrame.Angles(0, math.pi, 0)
	local gear = Instance.new("Model")
	gear.Name = "FardaEquipamento"
	for _, part in ipairs(template:GetDescendants()) do
		if part:IsA("BasePart") and part ~= refPe and part ~= refTopo then
			-- "BotaD_cano" -> grupo BotaD (se o importador renomear a peça, vale o nome do pai)
			local group = string.match(part.Name, "^(%a+)_") or string.match(part.Parent.Name, "^(%a+)_")
			local spot = GEAR[group]
			local att = spot and findAttachment(character, spot[1])
			if att then
				local rel = refPe.CFrame:ToObjectSpace(part.CFrame)
				local p = rel.Position
				if cfg.GearFlip ~= false then
					rel = CFrame.new(flipX and -p.X or p.X, p.Y, -p.Z) * turn * rel.Rotation
				end
				local copy = part:Clone()
				copy:ClearAllChildren()
				for _, child in ipairs(part:GetChildren()) do
					if child:IsA("SurfaceAppearance") then
						child:Clone().Parent = copy
					end
				end
				copy.Size = part.Size / scale
				copy.Anchored = false
				copy.CanCollide = false
				copy.CanTouch = false
				copy.CanQuery = false
				copy.Massless = true
				local offset = CFrame.new(rel.Position / scale - spot[2]) * rel.Rotation
				local body = att.Parent
				copy.CFrame = body.CFrame * CFrame.new(att.Position) * offset
				local weld = Instance.new("Weld")
				weld.Part0 = body
				weld.Part1 = copy
				weld.C0 = CFrame.new(att.Position) * offset
				weld.Parent = copy
				copy.Parent = gear
			end
		end
	end
	gear.Parent = character
end

-- Devolve as roupas guardadas (só se ainda for o mesmo boneco)
local function restore(player)
	local s = saved[player]
	saved[player] = nil
	local character = player.Character
	if not character then
		return
	end
	for _, name in ipairs(WORN) do
		local item = character:FindFirstChild(name)
		if item then
			item:Destroy()
		end
	end
	if s and s.character == character then
		for _, item in ipairs(s.items) do
			item.Parent = character
		end
		-- Marco 10.8: cores do corpo (macacão sem ID)
		local bc = character:FindFirstChildOfClass("BodyColors")
		if s.colors and bc then
			for k, v in pairs(s.colors) do
				bc[k] = v
			end
		end
	end
end

-- Marco 10.8: "L.L.K" e o número do preso nas costas (placa fininha soldada no tronco)
local function addBackTag(player, character, cfg)
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if not torso or not cfg.BackText then
		return
	end
	local tag = Instance.new("Part")
	tag.Name = "FardaEtiqueta"
	tag.Size = Vector3.new(torso.Size.X * 0.85, torso.Size.Y * 0.55, 0.05)
	tag.Transparency = 1
	tag.CanCollide = false
	tag.CanQuery = false
	tag.CanTouch = false
	tag.Massless = true
	local offset = CFrame.new(0, torso.Size.Y * 0.12, torso.Size.Z / 2 + 0.03)
	tag.CFrame = torso.CFrame * offset
	local weld = Instance.new("Weld")
	weld.Part0 = torso
	weld.Part1 = tag
	weld.C0 = offset
	weld.Parent = tag
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Back
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 60
	sg.LightInfluence = 1
	sg.Parent = tag
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 0.62)
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextColor3 = Color3.fromRGB(25, 22, 20)
	t.Text = cfg.BackText
	t.Parent = sg
	local n = Instance.new("TextLabel")
	n.BackgroundTransparency = 1
	n.Position = UDim2.fromScale(0.15, 0.64)
	n.Size = UDim2.fromScale(0.7, 0.3)
	n.Font = Enum.Font.GothamBold
	n.TextScaled = true
	n.TextColor3 = Color3.fromRGB(25, 22, 20)
	n.Text = ("Nº %04d"):format(player.UserId % 10000)
	n.Parent = sg
	tag.Parent = character
end

local function wear(player, cfg)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	if saved[player] and saved[player].character == character then
		return -- já está de farda
	end
	-- sem o ID da camisa (ou da calça), fica a roupa normal do jogador nessa parte
	local hasShirt, hasPants = idNumber(cfg.Shirt) ~= 0, idNumber(cfg.Pants) ~= 0
	local paint = cfg.BodyColor and not (hasShirt and hasPants) -- Marco 10.8: macacão sem ID = corpo laranja
	local items = {}
	for _, item in ipairs(character:GetChildren()) do
		local clothes = ((hasShirt or paint) and (item:IsA("Shirt") or item:IsA("ShirtGraphic"))) or ((hasPants or paint) and item:IsA("Pants"))
		if clothes or isAccessoryToHide(item, cfg) then
			item.Parent = nil
			table.insert(items, item)
		end
	end
	saved[player] = { character = character, items = items, cfg = cfg }
	if paint then
		local bc = character:FindFirstChildOfClass("BodyColors")
		if bc then
			local colors = {}
			for _, k in ipairs(BODY_KEYS) do
				colors[k] = bc[k]
				bc[k] = cfg.BodyColor
			end
			saved[player].colors = colors
		end
	end
	if cfg.BackText and not hasShirt then
		addBackTag(player, character, cfg)
	end
	if hasShirt then
		local shirt = Instance.new("Shirt")
		shirt.Name = "FardaCamisa"
		shirt.ShirtTemplate = assetId(cfg.Shirt)
		shirt.Parent = character
	end
	if hasPants then
		local pants = Instance.new("Pants")
		pants.Name = "FardaCalca"
		pants.PantsTemplate = assetId(cfg.Pants)
		pants.Parent = character
	end
	addGear(character, cfg)
	player:SetAttribute("Farda", true)
end

local function takeOff(player)
	player:SetAttribute("Farda", nil)
	restore(player)
end

local function onLocker(player, cfg)
	if not SecurityService.checkRate(player, "Farda", 1) then
		return
	end
	if player:GetAttribute("Job") ~= cfg.Job then
		return notice(player, "Só " .. cfg.Job .. " pode pegar essa farda.")
	end
	if idNumber(cfg.Shirt) == 0 and idNumber(cfg.Pants) == 0 and not gearTemplate(cfg) then
		return notice(player, "Essa farda ainda não foi configurada (GameConfig).")
	end
	if player:GetAttribute("Farda") then
		takeOff(player)
		notice(player, "Você tirou a farda.")
	else
		wear(player, cfg)
		notice(player, cfg.Wear)
	end
end

local function watch(player)
	-- saiu do emprego (ou foi preso e perdeu o cargo): a farda sai
	player:GetAttributeChangedSignal("Job"):Connect(function()
		local s = saved[player]
		if s and s.cfg.Prison then
			return -- Marco 10.8: o macacão só sai quando a pessoa é solta
		end
		if player:GetAttribute("Farda") and not (s and s.cfg.Job == player:GetAttribute("Job")) then
			takeOff(player)
		end
	end)
	-- renasceu: veste de novo quando a aparência do boneco terminar de carregar
	-- Marco 10.8: preso veste o macacão laranja; solto, volta a roupa dele
	player:GetAttributeChangedSignal("Preso"):Connect(function()
		if player:GetAttribute("Preso") then
			if player:GetAttribute("Farda") then
				takeOff(player)
			end
			wear(player, GameConfig.PrisonUniform)
			player:SetAttribute("Farda", nil) -- o macacão não é farda de emprego
			player:SetAttribute("Macacao", true)
		elseif player:GetAttribute("Macacao") then
			player:SetAttribute("Macacao", nil)
			restore(player)
		end
	end)
	player.CharacterAppearanceLoaded:Connect(function()
		saved[player] = nil
		if player:GetAttribute("Preso") then
			wear(player, GameConfig.PrisonUniform)
			player:SetAttribute("Farda", nil)
			player:SetAttribute("Macacao", true)
			return
		end
		local cfg = byJob[player:GetAttribute("Job")]
		if player:GetAttribute("Farda") and cfg then
			wear(player, cfg)
		elseif player:GetAttribute("Farda") then
			player:SetAttribute("Farda", nil)
		end
	end)
end

function UniformService.init(remotes)
	uiUpdate = remotes[GameConfig.Remotes.UIUpdate]
	local map = Workspace:FindFirstChild("Map")
	local count = 0
	if map then
		for _, part in ipairs(map:GetDescendants()) do
			local cfg = part:IsA("BasePart") and lockerUniform(part:GetAttribute("UniformLocker"))
			if cfg then
				local prompt = Instance.new("ProximityPrompt")
				prompt.ObjectText = cfg.Locker
				prompt.ActionText = "Farda (vestir / tirar)"
				prompt.MaxActivationDistance = cfg.UseDistance
				prompt.RequiresLineOfSight = false
				prompt.Parent = part
				prompt.Triggered:Connect(function(player)
					onLocker(player, cfg)
				end)
				count += 1
			end
		end
	end
	print(("[UniformService] %d armários da farda."):format(count))

	for _, player in ipairs(Players:GetPlayers()) do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		saved[player] = nil
	end)
end

return UniformService
