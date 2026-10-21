-- ZoneService (ModuleScript)
-- Caminho: ServerScriptService > Services > ZoneService
-- Zonas de trabalho = interior das lojas (La Paulistana, Minas Market, Sherlex, Duto Pet Shop).
-- Dentro delas:
--   * não dá para usar bicicleta nem carro (o VehicleService desce o jogador da bike ao entrar);
--   * o jogador fica protegido: escudo invisível (ForceField) contra qualquer dano futuro
--     e não esbarra/empurra outros jogadores.
-- Também cria os grupos de colisão usados pelo jogo (jogadores, NPCs e veículos).

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local Workspace = game:GetService("Workspace")

local SecurityService = require(script.Parent:WaitForChild("SecurityService"))

local ZoneService = {}

local zones = {} -- { name, cf, half }
local insideOf = {} -- insideOf[player] = nome da zona (ou nil)
local listeners = {}

local GROUP_PLAYERS = "Jogadores"
local GROUP_SAFE = "ZonaSegura"
local GROUP_NPCS = "NPCs"
local GROUP_VEHICLES = "Veiculos"

local function setupGroups()
	for _, name in ipairs({ GROUP_PLAYERS, GROUP_SAFE, GROUP_NPCS, GROUP_VEHICLES }) do
		pcall(function()
			PhysicsService:RegisterCollisionGroup(name)
		end)
	end
	local function off(a, b)
		PhysicsService:CollisionGroupSetCollidable(a, b, false)
	end
	off(GROUP_SAFE, GROUP_SAFE) -- dentro do trabalho ninguém empurra ninguém
	off(GROUP_SAFE, GROUP_PLAYERS)
	off(GROUP_NPCS, GROUP_PLAYERS) -- clientes NPC não ficam presos nos jogadores
	off(GROUP_NPCS, GROUP_SAFE)
	off(GROUP_NPCS, GROUP_NPCS)
	off(GROUP_VEHICLES, GROUP_PLAYERS) -- carro não atropela nem arremessa jogadores
	off(GROUP_VEHICLES, GROUP_SAFE)
	off(GROUP_VEHICLES, GROUP_NPCS)
end

local function setGroup(character, group)
	for _, p in ipairs(character:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CollisionGroup = group
		end
	end
end

-- Nome da zona onde está a posição (nil = fora)
function ZoneService.zoneAt(position)
	for _, z in ipairs(zones) do
		local p = z.cf:PointToObjectSpace(position)
		if math.abs(p.X) <= z.half.X and math.abs(p.Z) <= z.half.Z and p.Y > -4 and p.Y < z.half.Y * 2 + 4 then
			return z.name
		end
	end
	return nil
end

function ZoneService.isInside(player)
	return insideOf[player] ~= nil
end

-- fn(player, inside, zoneName) é chamada quando alguém entra ou sai de uma zona
function ZoneService.onChange(fn)
	table.insert(listeners, fn)
end

local function apply(player, zone)
	local character = player.Character
	if not character then
		return
	end
	setGroup(character, zone and GROUP_SAFE or GROUP_PLAYERS)
	local shield = character:FindFirstChild("ProtecaoTrabalho")
	if zone and not shield then
		shield = Instance.new("ForceField")
		shield.Name = "ProtecaoTrabalho"
		shield.Visible = false
		shield.Parent = character
	elseif not zone and shield then
		shield:Destroy()
	end
end

local function update(player)
	local _, _, root = SecurityService.getLivingCharacter(player)
	local zone = root and ZoneService.zoneAt(root.Position) or nil
	if zone == insideOf[player] then
		return
	end
	insideOf[player] = zone
	player:SetAttribute("InWorkZone", zone)
	apply(player, zone)
	for _, fn in ipairs(listeners) do
		task.spawn(fn, player, zone ~= nil, zone)
	end
end

function ZoneService.init()
	setupGroups()
	local shops = Workspace:WaitForChild("Map"):WaitForChild("JobLocations")
	for _, shop in ipairs(shops:GetChildren()) do
		local cf = shop:GetAttribute("BaseCFrame")
		local size = shop:GetAttribute("InteriorSize")
		if cf and size then
			table.insert(zones, { name = shop:GetAttribute("PlaceName") or shop.Name, cf = cf, half = size / 2 + Vector3.new(0.5, 0, 0.5) })
		end
	end

	local function onPlayer(player)
		player.CharacterAdded:Connect(function(character)
			insideOf[player] = nil
			player:SetAttribute("InWorkZone", nil)
			setGroup(character, GROUP_PLAYERS)
			-- peças que chegam depois (acessórios, bike, itens) entram no grupo certo
			character.DescendantAdded:Connect(function(d)
				if d:IsA("BasePart") then
					d.CollisionGroup = insideOf[player] and GROUP_SAFE or GROUP_PLAYERS
				end
			end)
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		insideOf[player] = nil
	end)

	task.spawn(function()
		while true do
			for _, player in ipairs(Players:GetPlayers()) do
				update(player)
			end
			task.wait(0.25)
		end
	end)
end

ZoneService.Groups = { Players = GROUP_PLAYERS, Safe = GROUP_SAFE, NPCs = GROUP_NPCS, Vehicles = GROUP_VEHICLES }

return ZoneService
