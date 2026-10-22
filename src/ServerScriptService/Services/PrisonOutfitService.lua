-- Roupa de custódia original: preserva os objetos do avatar, nunca usa assets
-- externos nem altera HumanoidDescription. PrisonService é o único chamador.
local PrisonOutfitService = {}
local leases = {}
local ORANGE = Color3.fromRGB(239, 112, 25)
local SEAM = Color3.fromRGB(155, 64, 19)
local UNDERSHIRT = Color3.fromRGB(228, 224, 206)
local layeredTypes = {
	[Enum.AccessoryType.TShirt] = true, [Enum.AccessoryType.Shirt] = true,
	[Enum.AccessoryType.Sweater] = true, [Enum.AccessoryType.Jacket] = true,
	[Enum.AccessoryType.Pants] = true, [Enum.AccessoryType.Shorts] = true,
	[Enum.AccessoryType.DressSkirt] = true,
}
local limbNames = {
	Torso = true, UpperTorso = true, LowerTorso = true,
	["Left Arm"] = true, ["Right Arm"] = true,
	LeftUpperArm = true, RightUpperArm = true, LeftLowerArm = true, RightLowerArm = true,
	["Left Leg"] = true, ["Right Leg"] = true,
	LeftUpperLeg = true, RightUpperLeg = true, LeftLowerLeg = true, RightLowerLeg = true,
}

local function piece(lease, limb, name, size, offset, color)
	local p = Instance.new("Part")
	p.Name, p.Size, p.Color = name, size, color or ORANGE
	p.Material = Enum.Material.Fabric
	p.Anchored, p.Massless, p.CanCollide, p.CanTouch, p.CanQuery = false, true, false, false, false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.CFrame = limb.CFrame * offset
	p:SetAttribute("PrisonUniform", true)
	p.Parent = lease.model
	local weld = Instance.new("WeldConstraint")
	weld.Name, weld.Part0, weld.Part1, weld.Parent = "CosturaCustódia", limb, p, p
	return p
end

local function buildLimb(lease, limb)
	if not limb:IsA("BasePart") or limb.Parent ~= lease.character or not limbNames[limb.Name]
		or lease.built[limb] then return end
	lease.built[limb] = true
	local size = limb.Size
	local torso = limb.Name == "Torso" or limb.Name == "UpperTorso"
	piece(lease, limb, torso and "JaquetaLaranja" or "MacacãoLaranja", size + Vector3.new(0.12, 0.025, 0.12), CFrame.new())
	if torso then
		local front = -size.Z / 2 - 0.095
		piece(lease, limb, "CamisetaInterna", Vector3.new(size.X * 0.38, size.Y * 0.14, 0.035),
			CFrame.new(0, size.Y * 0.4, front), UNDERSHIRT)
		piece(lease, limb, "Zíper", Vector3.new(0.035, size.Y * 0.78, 0.035),
			CFrame.new(0, -size.Y * 0.065, front - 0.01), SEAM)
		for _, side in ipairs({-1, 1}) do
			piece(lease, limb, "GolaCustódia", Vector3.new(size.X * 0.24, size.Y * 0.15, 0.05),
				CFrame.new(side * size.X * 0.15, size.Y * 0.34, front - 0.02) * CFrame.Angles(0, 0, side * math.rad(22)), SEAM)
			piece(lease, limb, "BolsoCustódia", Vector3.new(size.X * 0.29, size.Y * 0.22, 0.04),
				CFrame.new(side * size.X * 0.3, -size.Y * 0.1, front - 0.01), ORANGE:Lerp(SEAM, 0.15))
		end
		piece(lease, limb, "CosturaCintura", Vector3.new(size.X + 0.14, 0.04, size.Z + 0.14),
			CFrame.new(0, -size.Y * 0.45, 0), SEAM)
	end
end

local function hideProperty(lease, object, property, hidden)
	local key = lease.saved[object]
	if key then return end
	key = { property = property, value = object[property] }
	lease.saved[object] = key
	object[property] = hidden
	table.insert(lease.connections, object:GetPropertyChangedSignal(property):Connect(function()
		-- AppearanceLoaded pode escrever no mesmo Shirt/Handle depois de Parent.
		-- Guarda esse valor mais recente e volta a esconder enquanto preso.
		if object[property] ~= hidden then
			key.value = object[property]
			object[property] = hidden
		end
	end))
end

local function preserve(lease, object)
	if object == lease.model or object:IsDescendantOf(lease.model) then return end
	if object:IsA("Shirt") then hideProperty(lease, object, "ShirtTemplate", "")
	elseif object:IsA("Pants") then hideProperty(lease, object, "PantsTemplate", "")
	elseif object:IsA("ShirtGraphic") then hideProperty(lease, object, "Graphic", "") end
	local accessory = object:IsA("Accessory") and object or object:FindFirstAncestorOfClass("Accessory")
	if accessory and layeredTypes[accessory.AccessoryType] then
		for _, item in ipairs(accessory:GetDescendants()) do
			if item:IsA("BasePart") then hideProperty(lease, item, "Transparency", 1) end
		end
	end
	buildLimb(lease, object)
end

function PrisonOutfitService.restore(player)
	local lease = leases[player]
	leases[player] = nil
	if lease then
		for _, connection in ipairs(lease.connections) do connection:Disconnect() end
		if lease.model then lease.model:Destroy() end
		for object, snapshot in pairs(lease.saved) do
			if object.Parent then
				pcall(function() object[snapshot.property] = snapshot.value end)
			end
		end
	end
	player:SetAttribute("PrisonUniform", false)
end

function PrisonOutfitService.apply(player)
	local character = player.Character
	if not character then return false end
	local previous = leases[player]
	if previous and previous.character == character then return true end
	PrisonOutfitService.restore(player)
	local model = Instance.new("Model")
	model.Name = "UniformePrisional"
	model:SetAttribute("PrisonUniform", true)
	local lease = { character = character, model = model, saved = {}, connections = {}, built = {} }
	leases[player] = lease
	local ok, err = pcall(function()
		model.Parent = character
		table.insert(lease.connections, character.DescendantAdded:Connect(function(object)
			if leases[player] == lease then preserve(lease, object) end
		end))
		for _, object in ipairs(character:GetDescendants()) do preserve(lease, object) end
		if player.CharacterAppearanceLoaded then
			table.insert(lease.connections, player.CharacterAppearanceLoaded:Connect(function(loadedCharacter)
				if loadedCharacter ~= character or leases[player] ~= lease then return end
				-- Atualiza dimensões depois do carregamento/escalonamento do R15.
				for _, item in ipairs(model:GetChildren()) do item:Destroy() end
				lease.built = {}
				for _, object in ipairs(character:GetDescendants()) do preserve(lease, object) end
			end))
		end
	end)
	if not ok then
		PrisonOutfitService.restore(player)
		warn("[PrisonOutfitService] Falha ao vestir roupa de custódia: " .. tostring(err))
		return false
	end
	player:SetAttribute("PrisonUniform", true)
	return true
end

return PrisonOutfitService
