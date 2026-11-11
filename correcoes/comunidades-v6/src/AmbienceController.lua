-- AmbienceController (ModuleScript)
-- Caminho: StarterPlayer > StarterPlayerScripts > Controllers > AmbienceController
-- Marco 9.12: sons de ambiente da cidade, baixinhos, só neste aparelho. Os números ficam em
-- GameConfig.Ambience (0 = sem som):
--   * Trafego: fundo de trânsito, mais forte perto do centro e sumindo longe da cidade;
--   * Passaros: fundo de passarinhos, mais forte longe do centro e no parque;
--   * Parque: crianças brincando, perto da MigueLândia;
--   * Chafariz: barulho de água em volta de cada chafariz (som 3D no próprio chafariz);
--   * Cachorros e Obra: de vez em quando, um latido ou um barulho de obra ao longe, vindo de
--     algum lado em volta do jogador (som 3D), só dentro da cidade.
-- Os volumes mudam devagar, então andar de um lugar para outro não dá "pulo" no som.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local AmbienceController = {}

local CFG = GameConfig.Ambience
local CITY = GameConfig.Map.RoadLength -- a cidade vai do centro (0, 0) até o anel externo

local function has(id)
	return id ~= nil and id ~= 0 and id ~= ""
end

local function soundId(id)
	return type(id) == "number" and ("rbxassetid://" .. string.format("%d", id)) or tostring(id)
end

local function newSound(parent, name, id, looped)
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = soundId(id)
	sound.Looped = looped
	sound.Volume = 0
	sound.Parent = parent
	return sound
end

-- 1 perto, 0 longe (some aos poucos entre near e far)
local function closeness(distance, near, far)
	return 1 - math.clamp((distance - near) / (far - near), 0, 1)
end

local layers = {} -- fundos que tocam sempre (sem posição), volume pelo lugar
local parkCenter

local function addLayer(name, entry, level)
	if not (entry and has(entry.Id)) then
		return
	end
	local sound = newSound(SoundService, "Ambiente" .. name, entry.Id, true)
	sound:Play()
	table.insert(layers, { sound = sound, volume = entry.Volume or 0.15, level = level })
end

-- som 3D num ponto do mundo, que some sozinho
local function playAt(position, name, entry)
	local holder = Instance.new("Attachment")
	holder.Name = "SomAmbiente" .. name
	holder.WorldPosition = position
	holder.Parent = Workspace.Terrain
	local sound = newSound(holder, name, entry.Id, false)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 30
	sound.RollOffMaxDistance = 260
	sound.Volume = (entry.Volume or 0.2) * (CFG.Master or 1)
	sound.PlaybackSpeed = 0.92 + math.random() * 0.16
	sound:Play()
	local life = entry.MaxSeconds or 10
	task.delay(life, function()
		-- sons longos (obra) param devagar em vez de cortar
		for i = 1, 10 do
			if not sound.Parent then
				return
			end
			sound.Volume *= 0.7
			task.wait(0.1)
		end
		holder:Destroy()
	end)
end

local function addFountain(model)
	if not (CFG.Chafariz and has(CFG.Chafariz.Id)) or model:FindFirstChild("SomChafariz", true) then
		return
	end
	local jet = model:FindFirstChild("Jato") or model:FindFirstChildWhichIsA("BasePart")
	if not jet then
		return
	end
	local sound = newSound(jet, "SomChafariz", CFG.Chafariz.Id, true)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 10
	sound.RollOffMaxDistance = 90
	sound.Volume = (CFG.Chafariz.Volume or 0.25) * (CFG.Master or 1)
	sound:Play()
end

local function watchMap(map)
	for _, d in ipairs(map:GetDescendants()) do
		if d:IsA("Model") and d.Name == "Chafariz" then
			addFountain(d)
		elseif d:IsA("Model") and d.Name == "MigueLandia" then
			parkCenter = (d:GetAttribute("MapaPivot") or d:GetPivot()).Position
		end
	end
	map.DescendantAdded:Connect(function(d)
		-- Marco 10.22 (streaming): a peça do chafariz chega depois do Model, quando a gente chega perto
		local fountain = d:IsA("BasePart") and d:FindFirstAncestor("Chafariz")
		if fountain and fountain:IsA("Model") then
			task.defer(addFountain, fountain)
		elseif d.Name == "Chafariz" and d:IsA("Model") then
			task.defer(addFountain, d) -- espera as peças chegarem
		elseif d.Name == "MigueLandia" and d:IsA("Model") then
			task.defer(function()
				parkCenter = (d:GetAttribute("MapaPivot") or d:GetPivot()).Position
			end)
		end
	end)
end

-- sorteia quando toca o próximo som de vez em quando
local function nextTime(entry)
	local every = entry.Every or { 30, 80 }
	return os.clock() + every[1] + math.random() * (every[2] - every[1])
end

function AmbienceController.init()
	if not CFG then
		return
	end
	local place = { city = 1, park = 0 }
	addLayer("Trafego", CFG.Trafego, function()
		return 0.25 + place.city * 0.75
	end)
	addLayer("Passaros", CFG.Passaros, function()
		return 0.55 + (1 - place.city) * 0.45 + place.park * 0.3
	end)
	addLayer("Parque", CFG.Parque, function()
		return place.park
	end)
	local occasional = {}
	for _, name in ipairs({ "Cachorros", "Obra" }) do
		local entry = CFG[name]
		if entry and has(entry.Id) then
			table.insert(occasional, { name = name, entry = entry, at = nextTime(entry) })
		end
	end

	task.spawn(function()
		watchMap(Workspace:WaitForChild("Map"))
	end)

	RunService.Heartbeat:Connect(function(dt)
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local pos = camera.Focus.Position
		local flat = Vector3.new(pos.X, 0, pos.Z).Magnitude
		place.city = closeness(flat, CITY * 0.7, CITY * 1.6)
		place.park = parkCenter and closeness((pos - parkCenter).Magnitude, 120, 360) or 0
		local k = math.min(1, dt * 0.8)
		for _, layer in ipairs(layers) do
			local target = layer.volume * layer.level() * (CFG.Master or 1)
			layer.sound.Volume += (target - layer.sound.Volume) * k
		end
		local now = os.clock()
		for _, o in ipairs(occasional) do
			if now >= o.at then
				o.at = nextTime(o.entry)
				if place.city > 0.3 then -- latidos e obra só dentro da cidade
					local angle = math.random() * math.pi * 2
					local far = 70 + math.random() * 90
					playAt(pos + Vector3.new(math.cos(angle) * far, 4, math.sin(angle) * far), o.name, o.entry)
				end
			end
		end
	end)
end

return AmbienceController
