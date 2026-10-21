-- Moradores fixos nas calçadas, construídos com o NPCKit já usado pelo jogo.
-- Conversas são textos preparados; nenhum remoto cria NPC, missão ou pagamento.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("StreetNPCConfig"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local CivicConfig = require(Shared:WaitForChild("CivicConfig"))
local NPCKit = require(script.Parent:WaitForChild("NPCKit"))
local Security = require(script.Parent:WaitForChild("SecurityService"))

local StreetNPCService = {}
local initialized = false
local residents = {}
local conversations = {}
local nextSpeech = {}

local function flat(point)
	return Vector3.new(point.X, 0, point.Z)
end

local function finitePoint(point)
	return point.X == point.X and point.Y == point.Y and point.Z == point.Z
		and math.abs(point.X) < math.huge and math.abs(point.Y) < math.huge
		and math.abs(point.Z) < math.huge
end

local function flatNear(a, b, radius)
	return (flat(a) - flat(b)).Magnitude < radius
end

local function template(text, streetName)
	local names = {
		street = streetName,
		pizza = GameConfig.Places.Pizzaria,
		market = GameConfig.Places.Mercearia,
		delivery = GameConfig.Places.Entregas,
		taxi = CivicConfig.Taxi and CivicConfig.Taxi.Name or "LXR Táxis",
	}
	return text:gsub("{([%w_]+)}", function(key) return names[key] or key end)
end

-- Nomes e posições dos prédios não decidem a calçada: usamos as peças que o
-- MapBuilder realmente construiu. Assim cada morador continua junto de sua rua.
local function streetSidewalks(map, index)
	local roads = map:FindFirstChild("Roads")
	if not roads then return {} end
	local direction = CFrame.Angles(0, (index - 1) * math.pi / 4, 0).LookVector
	local sidewalks = {}
	for _, road in ipairs(roads:GetChildren()) do
		if road.Name == "Road" then
			local surface = road:FindFirstChild("Asphalt")
			if surface and surface:IsA("BasePart") and surface.CFrame.LookVector:Dot(direction) > 0.99 then
				for _, piece in ipairs(road:GetChildren()) do
					if piece:IsA("BasePart") and piece.Name == "Sidewalk" then
						table.insert(sidewalks, piece)
					end
				end
			end
		end
	end
	return sidewalks, direction
end

local function findRegions(map)
	local regions = {}
	for _, part in ipairs(map:GetDescendants()) do
		if part:IsA("BasePart") then
			local road = part:GetAttribute("RoadStart") ~= nil
			if part.Name == "Door" or part.Name == "Driveway" or road then
				table.insert(regions, { part = part, door = part.Name == "Door" })
			end
		end
	end
	return regions
end

local function passageClear(position, regions)
	for _, region in ipairs(regions) do
		local part = region.part
		if region.door then
			if flatNear(position, part.Position, 7) then return false end
		else
			local p = part.CFrame:PointToObjectSpace(position)
			if math.abs(p.X) <= part.Size.X / 2 + 1.5 and math.abs(p.Z) <= part.Size.Z / 2 + 1.5 then
				return false
			end
		end
	end
	return true
end

local function bodyClear(map, position)
	local ray = RaycastParams.new()
	ray.FilterType = Enum.RaycastFilterType.Include
	ray.FilterDescendantsInstances = { map }
	local hit = Workspace:Raycast(position + Vector3.new(0, 5, 0), Vector3.new(0, -12, 0), ray)
	if not hit or hit.Normal.Y < 0.95 or hit.Instance.Name ~= "Sidewalk" then return nil end
	local ground = Vector3.new(position.X, hit.Position.Y, position.Z)
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then table.insert(ignore, player.Character) end
	end
	overlap.FilterDescendantsInstances = ignore
	local center = CFrame.new(ground + Vector3.new(0, 3.05, 0))
	for _, obstacle in ipairs(Workspace:GetPartBoundsInBox(center, Config.Clearance, overlap)) do
		if obstacle.CanCollide then return nil end
		-- NPCs do not collide with players, but should not share their standing spot.
		local owner = obstacle:FindFirstAncestorOfClass("Model")
		if owner and owner:FindFirstChildOfClass("Humanoid") then return nil end
	end
	return ground
end

local function findSpot(map, definition, regions, used)
	local sidewalks, direction = streetSidewalks(map, definition.street)
	if not direction then return nil end
	local perpendicular = Vector3.new(-direction.Z, 0, direction.X)
	for _, side in ipairs({ definition.side, -definition.side }) do
		for _, offset in ipairs(Config.DistanceOffsets) do
			local distance = definition.distance + offset
			local roadPoint = direction * distance
			for _, sidewalk in ipairs(sidewalks) do
				local actualSide = sidewalk.Position:Dot(perpendicular) >= 0 and 1 or -1
				local along = sidewalk.CFrame:PointToObjectSpace(roadPoint).Z
				if actualSide == side and math.abs(along) < sidewalk.Size.Z / 2 - 6 then
					local outerSign = sidewalk.CFrame.RightVector:Dot(perpendicular * side) >= 0 and 1 or -1
					-- Stand on the outer edge; leave over three studs of pavement free.
					local lateral = outerSign * (sidewalk.Size.X / 2 - 1.4)
					local position = (sidewalk.CFrame * CFrame.new(lateral, sidewalk.Size.Y / 2, along)).Position
					local spaced = true
					for _, previous in ipairs(used) do
						if flatNear(position, previous, Config.MinSpacing) then spaced = false; break end
					end
					if spaced and passageClear(position, regions) then
						local ground = bodyClear(map, position)
						if ground then
							local facing = flat(roadPoint - ground)
							return CFrame.lookAt(ground, ground + facing), ground
						end
					end
				end
			end
		end
	end
	return nil
end

local function connectConversation(npc, definition)
	local root = npc:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local prompt = root:FindFirstChild("StreetTalkPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "StreetTalkPrompt"
		prompt.ActionText, prompt.ObjectText = "Conversar", definition.name
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.MaxActivationDistance, prompt.RequiresLineOfSight = 9, true
		prompt.Parent = root
	end
	local street = GameConfig.Map.StreetNames[definition.street] or "Bairro central"
	prompt.Triggered:Connect(function(player)
		if not npc.Parent then return end
		local _, _, playerRoot = Security.getLivingCharacter(player)
		if not playerRoot or not finitePoint(playerRoot.Position)
			or (playerRoot.Position - root.Position).Magnitude > Config.TalkDistance then return end
		if not Security.checkRate(player, "StreetConversation", Config.TalkCooldown) then return end
		local now = Workspace:GetServerTimeNow()
		if now < (nextSpeech[npc] or 0) then return end
		nextSpeech[npc] = now + Config.NPCSpeechCooldown
		local lines = Config.Lines[definition.topic] or Config.Lines.city
		local history = conversations[player]
		if not history then history = {}; conversations[player] = history end
		local index = (history[definition.id] or 0) % #lines + 1
		history[definition.id] = index
		NPCKit.say(npc, template(lines[index], street), 5.5)
		NPCKit.emote(npc, index == 1 and "wave" or "point")
	end)
end

function StreetNPCService.init(_sites)
	if initialized then return end
	initialized = true
	Players.PlayerRemoving:Connect(function(player) conversations[player] = nil end)
	-- A fábrica de avatares pode ceder execução; não atrasa o nascimento dos jogadores.
	task.spawn(function()
	local map = Workspace:FindFirstChild("Map")
	if not map then warn("[StreetNPCService] Mapa ausente; moradores não foram criados."); return end
	local regions, used = findRegions(map), {}
	local existing = {}
	for _, npc in ipairs(NPCKit.folder():GetChildren()) do
		local id = npc:GetAttribute("StreetResidentId")
		if id and npc:FindFirstChild("HumanoidRootPart") then existing[id] = npc end
	end
	for _, definition in ipairs(Config.Residents) do
		local npc = existing[definition.id]
		local point = npc and npc:FindFirstChild("HumanoidRootPart").Position
		if not npc then
			if NPCKit.count() >= NPCKit.MAX_NPCS then
				warn("[StreetNPCService] Limite de NPCs atingido; preservando espaço dos moradores existentes.")
				break
			end
			local cf, ground = findSpot(map, definition, regions, used)
			if cf then
				npc = NPCKit.spawn(cf, { name = definition.name, anchored = true, important = false, showName = true })
				point = ground
			end
		end
		if npc then
			residents[definition.id] = npc
			npc:SetAttribute("StreetResident", true)
			npc:SetAttribute("StreetResidentId", definition.id)
			npc:SetAttribute("StreetName", GameConfig.Map.StreetNames[definition.street])
			npc:SetAttribute("District", "Bairro central")
			local root = npc:FindFirstChild("HumanoidRootPart")
			root.Anchored = true
			local humanoid = npc:FindFirstChildOfClass("Humanoid")
			if humanoid then humanoid.WalkSpeed = 0 end
			if point then table.insert(used, point) end
			connectConversation(npc, definition)
		else
			warn("[StreetNPCService] Sem ponto seguro ou modelo disponível para " .. definition.name)
		end
	end
	end)
end

function StreetNPCService.count()
	local count = 0
	for _, npc in pairs(residents) do if npc.Parent then count += 1 end end
	return count
end

return StreetNPCService
