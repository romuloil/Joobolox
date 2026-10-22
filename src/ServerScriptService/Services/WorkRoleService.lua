-- Uma única profissão por jogador e uniforme retirado apenas no próprio trabalho.
-- Não há remoto que escolha uma profissão ou permita equipar roupa em qualquer lugar.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("WorkRoleConfig"))
local Rules = require(Shared:WaitForChild("WorkRoleRules"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Security = require(script.Parent:WaitForChild("SecurityService"))

local WorkRoleService = {}
local roles, uniforms, listeners = {}, {}, {}
local watched = {}
local workplaces, uiUpdate
local initialized = false
local layeredTypes = {
	[Enum.AccessoryType.TShirt] = true, [Enum.AccessoryType.Shirt] = true,
	[Enum.AccessoryType.Sweater] = true, [Enum.AccessoryType.Jacket] = true,
	[Enum.AccessoryType.Pants] = true, [Enum.AccessoryType.Shorts] = true,
	[Enum.AccessoryType.DressSkirt] = true,
}

local function notice(player, message)
	if uiUpdate and player.Parent == Players then
		uiUpdate:FireClient(player, "Notice", { text = message })
	end
end

local function notifyRole(player, newRole, oldRole)
	for _, callback in ipairs(listeners) do
		local ok, err = pcall(callback, player, newRole, oldRole)
		if not ok then warn("[WorkRoleService] Falha ao atualizar equipamento: " .. tostring(err)) end
	end
end

local function restoreUniform(player)
	local lease = uniforms[player]
	uniforms[player] = nil
	if not lease then
		player:SetAttribute("WorkUniformRole", nil)
		return
	end
	for _, connection in ipairs(lease.connections) do connection:Disconnect() end
	if lease.model then lease.model:Destroy() end
	for object, snapshot in pairs(lease.clothing) do
		if object.Parent then
			pcall(function() object[snapshot.property] = snapshot.value end)
		end
	end
	for object, transparency in pairs(lease.hats) do
		if object.Parent then pcall(function() object.Transparency = transparency end) end
	end
	player:SetAttribute("WorkUniformRole", nil)
end

function WorkRoleService.getRole(player)
	return roles[player]
end

function WorkRoleService.hasRole(player, role)
	return roles[player] ~= nil and roles[player] == role
end

function WorkRoleService.onChanged(callback)
	assert(type(callback) == "function", "Callback de emprego inválido")
	table.insert(listeners, callback)
	local active = true
	return {
		Disconnect = function()
			if not active then return end
			active = false
			local index = table.find(listeners, callback)
			if index then table.remove(listeners, index) end
		end,
	}
end

function WorkRoleService.assign(player, role)
	if not initialized or player.Parent ~= Players then return false, "unavailable" end
	local character = Security.getLivingCharacter(player)
	local accepted, reason = Rules.canAssign(roles[player], role, character ~= nil, player:GetAttribute("Detained"))
	if not accepted then return false, reason end
	if roles[player] == role then return true end
	local oldRole = roles[player]
	roles[player] = role
	player:SetAttribute("WorkRole", role)
	notifyRole(player, role, oldRole)
	return true
end

function WorkRoleService.clear(player, expectedRole)
	local oldRole = roles[player]
	if expectedRole ~= nil and oldRole ~= expectedRole then return false end
	roles[player] = nil
	restoreUniform(player)
	player:SetAttribute("WorkRole", nil)
	if oldRole ~= nil then notifyRole(player, nil, oldRole) end
	return oldRole ~= nil
end

local function promptPosition(prompt)
	local parent = prompt and prompt.Parent
	if parent and parent:IsA("BasePart") then return parent.Position end
	if parent and parent:IsA("Attachment") then return parent.WorldPosition end
	return nil
end

local function workplaceDistance(role, root)
	local site = workplaces and workplaces[role]
	local closest = math.huge
	for _, prompt in ipairs(site and site.uniformPrompts or {}) do
		local position = promptPosition(prompt)
		if Rules.finitePoint(position) then closest = math.min(closest, (root.Position - position).Magnitude) end
	end
	return closest
end

local function preserveClothing(lease, object)
	local property
	if object:IsA("Shirt") then property = "ShirtTemplate"
	elseif object:IsA("Pants") then property = "PantsTemplate"
	elseif object:IsA("ShirtGraphic") then property = "Graphic" end
	if property and not lease.clothing[object] then
		local saved = { property = property, value = object[property] }
		lease.clothing[object] = saved
		object[property] = ""
		table.insert(lease.connections, object:GetPropertyChangedSignal(property):Connect(function()
			if object[property] ~= "" then
				saved.value = object[property]
				object[property] = ""
			end
		end))
	end
	-- A roupa em camadas também é ocultada para não cobrir o uniforme.
	-- Objetos e valores são preservados, inclusive carregamentos tardios do avatar.
	local accessory = object:IsA("Accessory") and object or object:FindFirstAncestorOfClass("Accessory")
	if not accessory then return end
	if accessory.AccessoryType ~= Enum.AccessoryType.Hat and accessory.AccessoryType ~= Enum.AccessoryType.Hair
		and not layeredTypes[accessory.AccessoryType] then return end
	for _, handle in ipairs(accessory:GetDescendants()) do
		if handle:IsA("BasePart") and lease.hats[handle] == nil then
			lease.hats[handle] = handle.Transparency
			handle.Transparency = 1
			table.insert(lease.connections, handle:GetPropertyChangedSignal("Transparency"):Connect(function()
				if handle.Transparency ~= 1 then
					lease.hats[handle] = handle.Transparency
					handle.Transparency = 1
				end
			end))
		end
	end
end

local function piece(lease, limb, name, size, offset, color, shape, material)
	local p = Instance.new("Part")
	p.Name, p.Size, p.Color = name, size, color
	p.Material = material or Enum.Material.Fabric
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.Massless = false, false, false, false, true
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	if shape then p.Shape = shape end
	p.CFrame = limb.CFrame * offset
	p:SetAttribute("WorkUniform", true)
	p.Parent = lease.model
	local weld = Instance.new("WeldConstraint")
	weld.Name, weld.Part0, weld.Part1, weld.Parent = "CosturaUniforme", limb, p, p
	return p
end

local function emblem(part, value, color)
	local gui = Instance.new("SurfaceGui")
	gui.Name, gui.Face = "Identificação", Enum.NormalId.Front
	gui.LightInfluence, gui.PixelsPerStud, gui.SizingMode = 0, 100, Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.Parent = part
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency, text.Size = 1, UDim2.fromScale(1, 1)
	text.Text, text.Font, text.TextScaled, text.TextColor3 = value, Enum.Font.GothamBold, true, color
	text.Parent = gui
end

local function buildUniform(lease, character, definition)
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	local lower = character:FindFirstChild("LowerTorso")
	local head = character:FindFirstChild("Head")
	if not torso or not head then error("O personagem ainda não tem tronco/cabeça.") end
	local dark = Color3.fromRGB(24, 29, 37)
	piece(lease, torso, "CamisaUniforme", torso.Size + Vector3.new(0.12, 0.05, 0.14), CFrame.new(), definition.shirt)
	if lower then piece(lease, lower, "CinturaUniforme", lower.Size + Vector3.new(0.08, 0.02, 0.1), CFrame.new(), definition.pants) end
	for _, name in ipairs({"LeftUpperArm", "RightUpperArm", "Left Arm", "Right Arm"}) do
		local limb = character:FindFirstChild(name)
		if limb then
			local r6 = name == "Left Arm" or name == "Right Arm"
			local height = limb.Size.Y * (r6 and 0.48 or 0.82)
			piece(lease, limb, "MangaUniforme", Vector3.new(limb.Size.X + 0.1, height, limb.Size.Z + 0.1),
				CFrame.new(0, (limb.Size.Y - height) / 2, 0), definition.shirt)
		end
	end
	for _, name in ipairs({"LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg", "Left Leg", "Right Leg"}) do
		local limb = character:FindFirstChild(name)
		if limb then piece(lease, limb, "CalçaUniforme", limb.Size + Vector3.new(0.08, 0.015, 0.08), CFrame.new(), definition.pants) end
	end
	for _, name in ipairs({"LeftFoot", "RightFoot"}) do
		local foot = character:FindFirstChild(name)
		if foot then piece(lease, foot, "SapatoUniforme", foot.Size + Vector3.new(0.08, 0.04, 0.08), CFrame.new(), dark, nil, Enum.Material.SmoothPlastic) end
	end
	local front = -torso.Size.Z / 2 - 0.12
	local patchColor = definition.style == "Taxi" and definition.trim or definition.shirt
	local overApron = definition.style == "Chef" or definition.style == "Apron"
	local patch = piece(lease, torso, "NomeEmprego", Vector3.new(torso.Size.X * 0.45, torso.Size.Y * 0.18, 0.06),
		CFrame.new(torso.Size.X * 0.18, torso.Size.Y * 0.15, front - (overApron and 0.1 or 0)), patchColor, nil, Enum.Material.SmoothPlastic)
	emblem(patch, definition.label, definition.style == "Taxi" and Color3.fromRGB(27, 65, 116) or Color3.fromRGB(247, 241, 215))
	piece(lease, torso, "CintoUniforme", Vector3.new(torso.Size.X + 0.14, torso.Size.Y * 0.12, torso.Size.Z + 0.17),
		CFrame.new(0, -torso.Size.Y * 0.38, 0), dark, nil, Enum.Material.SmoothPlastic)
	if definition.style == "Police" then
		piece(lease, torso, "GravataPolicial", Vector3.new(torso.Size.X * 0.13, torso.Size.Y * 0.64, 0.06),
			CFrame.new(0, torso.Size.Y * 0.06, front - 0.03), dark)
		piece(lease, torso, "NóGravataPolicial", Vector3.new(torso.Size.X * 0.18, torso.Size.Y * 0.14, 0.075),
			CFrame.new(0, torso.Size.Y * 0.38, front - 0.045), dark)
		for _, side in ipairs({-1, 1}) do
			piece(lease, torso, "BolsoCamisaPolicial", Vector3.new(torso.Size.X * 0.26, torso.Size.Y * 0.28, 0.055),
				CFrame.new(side * torso.Size.X * 0.3, -torso.Size.Y * 0.06, front), definition.cap)
			piece(lease, torso, "GolaPolicial", Vector3.new(torso.Size.X * 0.25, torso.Size.Y * 0.16, 0.06),
				CFrame.new(side * torso.Size.X * 0.15, torso.Size.Y * 0.38, front) * CFrame.Angles(0, 0, side * math.rad(24)), definition.shirt)
		end
		piece(lease, torso, "FivelaPolicial", Vector3.new(0.3, torso.Size.Y * 0.13, 0.07),
			CFrame.new(0, -torso.Size.Y * 0.38, front - 0.015), definition.trim, nil, Enum.Material.Metal)
		local badge = piece(lease, torso, "DistintivoPolicial", Vector3.new(0.3, 0.4, 0.08),
			CFrame.new(-torso.Size.X * 0.25, torso.Size.Y * 0.2, front - 0.02), definition.trim, nil, Enum.Material.Metal)
		emblem(badge, "★", Color3.fromRGB(52, 68, 90))
		for _, side in ipairs({-1, 1}) do
			piece(lease, torso, "OmbreiraPolicial", Vector3.new(torso.Size.X * 0.28, 0.05, torso.Size.Z * 0.6),
				CFrame.new(side * torso.Size.X * 0.32, torso.Size.Y / 2 + 0.035, 0), definition.trim)
		end
	elseif definition.style == "Chef" or definition.style == "Apron" then
		piece(lease, torso, "Avental", Vector3.new(torso.Size.X * 0.7, torso.Size.Y * 0.86, 0.07),
			CFrame.new(0, -torso.Size.Y * 0.08, front - 0.04), definition.trim)
		if lower then
			piece(lease, lower, "BarraAvental", Vector3.new(lower.Size.X * 0.8, lower.Size.Y * 0.9, 0.08),
				CFrame.new(0, 0, -lower.Size.Z / 2 - 0.15), definition.trim)
		end
	elseif definition.style == "Courier" then
		for _, side in ipairs({-1, 1}) do
			piece(lease, torso, "FaixaRefletora", Vector3.new(0.13, torso.Size.Y * 0.8, 0.035),
				CFrame.new(side * torso.Size.X * 0.3, 0, front - 0.02), definition.trim)
		end
	end
	local crownHeight = definition.style == "Chef" and 0.7 or 0.38
	piece(lease, head, "ChapéuProfissional", Vector3.new(crownHeight, head.Size.X * 1.04, head.Size.Z * 1.1),
		CFrame.new(0, head.Size.Y / 2 + crownHeight / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
		definition.cap, Enum.PartType.Cylinder)
	if definition.style == "Chef" then
		for _, x in ipairs({-0.4, 0, 0.4}) do
			piece(lease, head, "TopoChapéuChef", Vector3.new(0.8, 0.55, 0.85),
				CFrame.new(x * head.Size.X / 2, head.Size.Y / 2 + 0.85, 0), definition.cap, Enum.PartType.Ball)
		end
	else
		piece(lease, head, "AbaBoné", Vector3.new(head.Size.X * 0.95, 0.09, head.Size.Z * 0.7),
			CFrame.new(0, head.Size.Y / 2 + 0.02, -head.Size.Z * 0.48), dark)
		local insignia = piece(lease, head, "InsígniaBoné", Vector3.new(head.Size.X * 0.35, 0.25, 0.06),
			CFrame.new(0, head.Size.Y / 2 + 0.19, -head.Size.Z * 0.56), definition.trim)
		emblem(insignia, definition.style == "Police" and "★" or definition.style == "Taxi" and "LXR" or "LLK", dark)
	end
end

function WorkRoleService.equipUniform(player, requestedRole)
	local role = requestedRole or roles[player]
	if not initialized or player.Parent ~= Players or not Config.Roles[role] then return false, "role" end
	local character, _, root = Security.getLivingCharacter(player)
	local stunnedUntil = player:GetAttribute("StunnedUntil")
	local stunned = Rules.finite(stunnedUntil) and stunnedUntil > Workspace:GetServerTimeNow()
	local distance = root and Rules.finitePoint(root.Position) and workplaceDistance(role, root) or math.huge
	local allowed, reason = Rules.canEquip(roles[player], role, distance, character ~= nil, player:GetAttribute("Detained"), stunned)
	if not allowed then return false, reason end
	if not Security.checkRate(player, "WorkUniform", Config.UniformCooldown) then return false, "rate" end
	local existing = uniforms[player]
	if existing and existing.character == character and existing.role == role then return true end
	restoreUniform(player)
	local model = Instance.new("Model")
	model.Name = "UniformeDeTrabalho"
	model:SetAttribute("WorkUniform", true)
	model:SetAttribute("Role", role)
	local lease = { character = character, role = role, model = model, clothing = {}, hats = {}, connections = {} }
	uniforms[player] = lease
	local ok, err = pcall(function()
		for _, object in ipairs(character:GetDescendants()) do preserveClothing(lease, object) end
		buildUniform(lease, character, Config.Roles[role])
		model.Parent = character
		table.insert(lease.connections, character.DescendantAdded:Connect(function(object)
			if uniforms[player] == lease then preserveClothing(lease, object) end
		end))
	end)
	if not ok then
		restoreUniform(player)
		warn("[WorkRoleService] Não foi possível vestir uniforme: " .. tostring(err))
		return false, "avatar"
	end
	player:SetAttribute("WorkUniformRole", role)
	notice(player, "Uniforme de " .. Config.Roles[role].name .. " retirado. Ele será devolvido ao sair do emprego.")
	return true
end

local function watchPlayer(player)
	if watched[player] then return end
	watched[player] = true
	local function onCharacter(character)
		restoreUniform(player)
		local function watchHumanoid(humanoid)
			if humanoid and humanoid:IsA("Humanoid") then
				humanoid.Died:Connect(function()
					if uniforms[player] and uniforms[player].character == character then restoreUniform(player) end
				end)
			end
		end
		watchHumanoid(character:FindFirstChildOfClass("Humanoid"))
		character.ChildAdded:Connect(function(object)
			if object:IsA("Humanoid") then watchHumanoid(object) end
		end)
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then onCharacter(player.Character) end
	player:GetAttributeChangedSignal("Detained"):Connect(function()
		if player:GetAttribute("Detained") then WorkRoleService.clear(player) end
	end)
end

function WorkRoleService.init(remotes, registeredWorkplaces)
	if initialized then return end
	workplaces = registeredWorkplaces or {}
	uiUpdate = remotes and remotes[GameConfig.Remotes.UIUpdate]
	initialized = true
	for role, site in pairs(workplaces) do
		if Config.Roles[role] then
			for _, prompt in ipairs(site.uniformPrompts or {}) do
				prompt.Enabled = true
				prompt.ActionText, prompt.ObjectText = "Retirar uniforme", Config.Roles[role].name
				prompt:SetAttribute("WorkRole", role)
				prompt.Triggered:Connect(function(player)
					local ok, reason = WorkRoleService.equipUniform(player, role)
					if not ok and reason ~= "rate" then
						notice(player, reason == "role" and "Você precisa estar empregado nesta profissão para retirar o uniforme."
							or "Retire o uniforme perto do armário do seu trabalho, com o personagem disponível.")
					end
				end)
			end
		end
	end
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in ipairs(Players:GetPlayers()) do watchPlayer(player) end
	Players.PlayerRemoving:Connect(function(player)
		WorkRoleService.clear(player)
		watched[player] = nil
	end)
end

return WorkRoleService
