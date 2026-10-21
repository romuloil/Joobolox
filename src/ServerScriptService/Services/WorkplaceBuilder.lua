-- Vestiários das profissões já existentes. O servidor valida cargo e proximidade.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local WorkplaceBuilder = {}

function WorkplaceBuilder.build(workplaces)
	local locations = Workspace:WaitForChild("Map"):WaitForChild("JobLocations")
	for _, definition in ipairs({
		{ role = "Pizzaiolo", place = GameConfig.Places.Pizzaria, color = Color3.fromRGB(185, 59, 49) },
		{ role = "Atendente", place = GameConfig.Places.Mercearia, color = Color3.fromRGB(45, 135, 75) },
		{ role = "Entregador", place = GameConfig.Places.Entregas, color = Color3.fromRGB(225, 136, 43) },
	}) do
		local shop
		for _, candidate in ipairs(locations:GetChildren()) do
			if candidate:GetAttribute("PlaceName") == definition.place then shop = candidate; break end
		end
		assert(shop, "Local de trabalho ausente: " .. definition.place)
		local locker = shop:FindFirstChild("VestiarioProfissional")
		if not locker then
			locker = Instance.new("Part")
			locker.Name = "VestiarioProfissional"
			locker.Size = Vector3.new(0.45, 5, 3)
			locker.CFrame = shop:GetAttribute("BaseCFrame") * CFrame.new(20.4, 3.5, -12)
			locker.Anchored, locker.CanCollide, locker.CanTouch = true, false, false
			locker.Material, locker.Color = Enum.Material.Metal, definition.color
			locker:SetAttribute("WorkRole", definition.role)
			locker.Parent = shop
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "UniformeProfissional"
			prompt.ActionText = "Retirar uniforme"
			prompt.ObjectText = "Vestiário • " .. definition.role
			prompt.MaxActivationDistance, prompt.HoldDuration = 9, 0.5
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.RequiresLineOfSight = false
			prompt.Parent = locker
		end
		local entry = workplaces[definition.role] or { vehiclePrompts = {}, vehicleSpawns = {} }
		entry.uniformPrompts = { assert(locker:FindFirstChildOfClass("ProximityPrompt")) }
		workplaces[definition.role] = entry
	end
	return workplaces
end

return WorkplaceBuilder
