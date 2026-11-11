-- GangService (ModuleScript)
-- Caminho: ServerScriptService > Services > GangService
-- Marco 10.1: as 3 gangues (GameConfig.Gangs) e as coisas para fazer nas favelas.
--   * Chefe de cada gangue (NPC com nome e o subtítulo "Chefe da gangue") no ChefeSpot que o
--     FavelaBuilder deixou no QG. Conversar abre o diálogo no cliente (GangController).
--   * Entrar na gangue (pedido "Join"): ganha o barraco na favela e perde só a casinha da Vila
--     Esperança (HomeService.refresh). Sair ("Leave", falando com o próprio chefe): volta para a
--     casinha. Fica salvo (data.gang). Policial não pode ser de gangue (e vice-versa).
--   * Bar (pedir um refri), paredão (liga as luzes e o som) e as bolas soltas dos campos (voltam
--     para o lugar se forem longe).
-- Tudo conferido no servidor: distância até o chefe, frequência, emprego e prisão.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local SecurityService = require(script.Parent:WaitForChild("SecurityService"))
local HomeService = require(script.Parent:WaitForChild("HomeService"))
local JobService = require(script.Parent:WaitForChild("JobService"))
local NPCKit = require(script.Parent:WaitForChild("NPCKit"))
local CrimeService = require(script.Parent:WaitForChild("CrimeService"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))
local WeaponService = require(script.Parent:WaitForChild("WeaponService"))
local AssaltoConfig = require(Shared:WaitForChild("AssaltoConfig"))

local GangService = {}

local G = GameConfig.Gangs
local uiUpdate
local chiefs = {} -- chiefs[gangId] = { npc, root }

local function notice(player, text)
	uiUpdate:FireClient(player, "Notice", { text = text })
end

local function gangOf(player)
	local data = PlayerDataService.get(player)
	local gang = data and data.gang
	return (type(gang) == "string" and G.List[gang]) and gang or nil
end

local function nearChief(player, gangId)
	local chief = chiefs[gangId]
	local _, _, root = SecurityService.getLivingCharacter(player)
	return chief and root and (root.Position - chief.root.Position).Magnitude <= G.TalkDistance
end

---------------------------------------------------------------------------
-- Chefes
---------------------------------------------------------------------------

-- Nome grande e o cargo pequeno embaixo
local function nameplate(npc, g)
	local head = npc:FindFirstChild("Head")
	if not head then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "Nome"
	gui.Size = UDim2.fromOffset(220, 54)
	gui.StudsOffset = Vector3.new(0, 2.4, 0)
	gui.MaxDistance = 60
	gui.Parent = head
	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, 0, 0.6, 0)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamBlack
	name.TextScaled = true
	name.TextColor3 = Color3.new(1, 1, 1)
	name.TextStrokeTransparency = 0.4
	name.Text = g.Chief
	name.Parent = gui
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0.4, 0)
	title.Position = UDim2.fromScale(0, 0.6)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextColor3 = g.Accent
	title.TextStrokeTransparency = 0.4
	title.Text = ("%s · %s"):format(G.Title, g.Short)
	title.Parent = gui
end

local function spawnChief(spot)
	local gangId = spot:GetAttribute("Gang")
	local g = G.List[gangId]
	if not g or chiefs[gangId] then
		return
	end
	local cf = spot.CFrame * CFrame.new(0, -spot.Size.Y / 2, 0)
	local npc = NPCKit.spawn(cf, {
		name = g.Chief,
		shirt = g.Color,
		pants = Color3.fromRGB(30, 30, 36),
		anchored = true,
		important = true,
	})
	if not npc then
		return
	end
	local root = npc:FindFirstChild("HumanoidRootPart")
	nameplate(npc, g)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Conversar"
	prompt.ObjectText = g.Chief
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	chiefs[gangId] = { npc = npc, root = root }
	prompt.Triggered:Connect(function(player)
		if not SecurityService.checkRate(player, "TalkChief", 1) or not nearChief(player, gangId) then
			return
		end
		NPCKit.emote(npc, "point")
		uiUpdate:FireClient(player, "GangDialog", {
			gang = gangId,
			member = gangOf(player),
			policial = JobService.getJob(player) == "Policial",
			preso = player:GetAttribute("Preso") == true,
		})
	end)
end

---------------------------------------------------------------------------
-- Entrar e sair
---------------------------------------------------------------------------

local function setGang(player, gangId)
	PlayerDataService.set(player, "gang", gangId)
	player:SetAttribute("Gang", gangId)
	HomeService.refresh(player)
end

local function join(player, gangId)
	local g = G.List[gangId]
	if not g or not nearChief(player, gangId) then
		return
	end
	local current = gangOf(player)
	if current then
		return notice(player, current == gangId and ("Você já é do %s."):format(g.Short) or ("Você já é do %s. Saia de lá primeiro."):format(current))
	end
	if JobService.getJob(player) == "Policial" then
		return notice(player, "Policial não entra para gangue. Saia do emprego de Policial primeiro.")
	end
	if player:GetAttribute("Preso") then
		return notice(player, "Você está preso.")
	end
	setGang(player, gangId)
	local address = HomeService.addressOf(player, "barraco")
	notice(player, address and ("Agora você é do %s! Seu barraco: %s (veja no Mapa)."):format(g.Short, address) or ("Agora você é do %s!"):format(g.Short))
	local chief = chiefs[gangId]
	if chief then
		NPCKit.emote(chief.npc, "cheer")
		NPCKit.say(chief.npc, ("Bem-vindo ao %s, %s!"):format(g.Short, player.DisplayName), 4)
	end
	print(("[GangService] %s entrou para o %s."):format(player.Name, gangId))
end

local function leave(player, gangId)
	if gangOf(player) ~= gangId or not nearChief(player, gangId) then
		return
	end
	setGang(player, nil)
	notice(player, ("Você saiu do %s. Sua casinha da Vila Esperança voltou."):format(G.List[gangId].Short))
	print(("[GangService] %s saiu do %s."):format(player.Name, gangId))
end

-- Marco 10.5: entregar o dinheiro do assalto ao chefe (vira dinheiro de verdade)
local function deliver(player, gangId)
	if gangOf(player) ~= gangId or not nearChief(player, gangId) then
		return
	end
	local amount = CrimeService.deliverDirty(player)
	local chief = chiefs[gangId]
	if amount > 0 then
		notice(player, ("O chefe lavou o dinheiro: +$%d."):format(amount))
		if chief then
			NPCKit.emote(chief.npc, "cheer")
			NPCKit.say(chief.npc, "Trabalho bom, " .. player.DisplayName .. "!", 3)
		end
	else
		notice(player, "Você não tem dinheiro de assalto para entregar.")
	end
end

-- Marco 10.5: o chefe vende armas (ficam salvas na mochila). Preços em GameConfig.Weapons.
local function buy(player, gangId, weaponId)
	if gangOf(player) ~= gangId or not nearChief(player, gangId) then
		return
	end
	local def = GameConfig.Weapons.List[weaponId]
	if not def or not def.Price or not table.find(GameConfig.Weapons.GangShop, weaponId) then
		return
	end
	if not InventoryService.hasRoom(player) then
		return notice(player, "Sua mochila está cheia!")
	end
	if not EconomyService.spend(player, def.Price, "Arma: " .. def.Name) then
		return notice(player, ("%s custa $%d."):format(def.Name, def.Price))
	end
	InventoryService.addWeapon(player, weaponId)
	notice(player, def.Name .. " na mochila! Aperte o botão da mochila para ver.")
end

-- Marco 10.6: munição (kit de pistola, pente de fuzil). Fica guardada; o R recarrega dela.
local function buyAmmo(player, gangId, kind)
	if gangOf(player) ~= gangId or not nearChief(player, gangId) then
		return
	end
	local a = GameConfig.Weapons.Ammo[kind]
	if not a then
		return
	end
	if WeaponService.ammoOf(player, kind) >= GameConfig.Weapons.MaxAmmo then
		return notice(player, ("Você já tem o máximo de munição (%d)."):format(GameConfig.Weapons.MaxAmmo))
	end
	if not EconomyService.spend(player, a.Price, "Munição: " .. a.Name) then
		return notice(player, ("%s custa $%d."):format(a.Name, a.Price))
	end
	WeaponService.addAmmo(player, kind, a.Per)
	notice(player, ("%s comprado! Agora você tem %d balas de %s."):format(a.Name, WeaponService.ammoOf(player, kind), kind))
end

-- Marco 10.30: C4 para o cofre do banco (fica salva na mochila)
local function buyC4(player, gangId)
	if gangOf(player) ~= gangId or not nearChief(player, gangId) then
		return
	end
	local C = AssaltoConfig.C4
	if InventoryService.count(player, "C4") >= C.Max then
		return notice(player, ("Você já tem %d C4 (o máximo)."):format(C.Max))
	end
	if not InventoryService.hasRoom(player) then
		return notice(player, "Sua mochila está cheia!")
	end
	if not EconomyService.spend(player, C.Price, "C4 (explosivo)") then
		return notice(player, ("A C4 custa $%d."):format(C.Price))
	end
	InventoryService.addItem(player, "C4", {})
	local chief = chiefs[gangId]
	if chief then
		NPCKit.say(chief.npc, "Cuidado com isso aí. Planta na porta e CORRE.", 3)
	end
	notice(player, "🧨 C4 na mochila! No banco, segure E na porta do cofre para plantar.")
end

local function onRequest(player, action, gangId, extra)
	if not SecurityService.checkRate(player, "GangRequest", 1) then
		return
	end
	if not SecurityService.isShortString(action, 8) or not SecurityService.isShortString(gangId, 8) then
		return
	end
	if action == "Join" then
		join(player, gangId)
	elseif action == "Leave" then
		leave(player, gangId)
	elseif action == "Deliver" then
		deliver(player, gangId)
	elseif action == "Buy" and SecurityService.isShortString(extra, 16) then
		buy(player, gangId, extra)
	elseif action == "Ammo" and SecurityService.isShortString(extra, 16) then
		buyAmmo(player, gangId, extra)
	elseif action == "C4" then
		buyC4(player, gangId)
	end
end

---------------------------------------------------------------------------
-- Coisas para fazer na favela
---------------------------------------------------------------------------

-- Refri: uma ferramenta simples na mão (beber = some)
local function giveDrink(player, barName)
	local backpack = player:FindFirstChildOfClass("Backpack")
	local character = player.Character
	if not backpack or (backpack:FindFirstChild("Refri") or (character and character:FindFirstChild("Refri"))) then
		return notice(player, "Você já tem um refri na mão!")
	end
	if not EconomyService.spend(player, G.DrinkPrice, "Refri: " .. barName) then
		return notice(player, ("Um refri custa $%d."):format(G.DrinkPrice))
	end
	local tool = Instance.new("Tool")
	tool.Name = "Refri"
	tool.ToolTip = "Clique para beber"
	tool.CanBeDropped = false
	local can = Instance.new("Part")
	can.Name = "Handle"
	can.Shape = Enum.PartType.Cylinder
	can.Size = Vector3.new(1.1, 0.7, 0.7)
	can.Color = ({ Color3.fromRGB(200, 30, 30), Color3.fromRGB(40, 150, 60), Color3.fromRGB(240, 140, 30) })[math.random(1, 3)]
	can.Material = Enum.Material.Metal
	can.CanCollide = false
	can.Massless = true
	can.Parent = tool
	tool.Grip = CFrame.Angles(0, 0, math.rad(90))
	local sips = 0
	tool.Activated:Connect(function()
		sips += 1
		if sips >= 3 then
			notice(player, "Refri geladinho! 😋")
			tool:Destroy()
		end
	end)
	tool.Parent = backpack
	notice(player, "Pegou um refri! Clique para beber.")
end

local function setupBars(root)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("BarBalcao") then
			local barName = d:GetAttribute("BarBalcao")
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = ("Pedir um refri ($%d)"):format(G.DrinkPrice)
			prompt.ObjectText = barName
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.MaxActivationDistance = 8
			prompt.RequiresLineOfSight = false
			prompt.Parent = d
			prompt.Triggered:Connect(function(player)
				if SecurityService.checkRate(player, "Drink", 2) then
					giveDrink(player, barName)
				end
			end)
		end
	end
end

-- Paredão: liga/desliga as luzes piscando (e a música, se tiver ID)
local function setupParedoes(root)
	for _, box in ipairs(root:GetDescendants()) do
		if box:IsA("BasePart") and box:GetAttribute("Paredao") then
			local lights = {}
			for _, p in ipairs(box.Parent:GetChildren()) do
				if p:IsA("BasePart") and p:GetAttribute("ParedaoLuz") then
					table.insert(lights, p)
				end
			end
			local sound
			if (G.MusicId or 0) > 0 then
				sound = Instance.new("Sound")
				sound.SoundId = "rbxassetid://" .. G.MusicId
				sound.Looped = true
				sound.Volume = 0.4
				sound.RollOffMaxDistance = 140
				sound.Parent = box
			end
			local on = false
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Ligar o som"
			prompt.ObjectText = "Paredão"
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.MaxActivationDistance = 9
			prompt.RequiresLineOfSight = false
			prompt.Parent = box
			local colors = { Color3.fromRGB(255, 60, 200), Color3.fromRGB(60, 200, 255), Color3.fromRGB(255, 220, 60), Color3.fromRGB(120, 255, 120) }
			prompt.Triggered:Connect(function(player)
				if not SecurityService.checkRate(player, "Paredao", 1.5) then
					return
				end
				on = not on
				prompt.ActionText = on and "Desligar o som" or "Ligar o som"
				if sound then
					if on then
						sound:Play()
					else
						sound:Stop()
					end
				end
				if on then
					task.spawn(function()
						local i = 0
						while on and box.Parent do
							i += 1
							for k, light in ipairs(lights) do
								light.Transparency = 0
								light.Color = colors[((i + k) % #colors) + 1]
							end
							task.wait(0.45)
						end
						for _, light in ipairs(lights) do
							light.Transparency = 0.6
						end
					end)
				end
			end)
		end
	end
end

-- Bolas soltas: se forem longe do campo (ou caírem), voltam para o meio
local function watchBalls(root)
	local balls = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("Bola") then
			table.insert(balls, d)
		end
	end
	if #balls == 0 then
		return
	end
	task.spawn(function()
		while true do
			task.wait(5)
			for _, ball in ipairs(balls) do
				local home = ball:GetAttribute("Home")
				local radius = ball:GetAttribute("Radius") or 60
				if ball.Parent and typeof(home) == "CFrame" then
					local away = (ball.Position - home.Position) * Vector3.new(1, 0, 1)
					if away.Magnitude > radius or ball.Position.Y < home.Position.Y - 10 then
						ball.AssemblyLinearVelocity = Vector3.zero
						ball.AssemblyAngularVelocity = Vector3.zero
						ball.CFrame = home
					end
				end
			end
		end
	end)
end

---------------------------------------------------------------------------
-- Início
---------------------------------------------------------------------------

-- Marco 10.9: o JewelryService põe o "receptador" (vender as joias) nos chefes
function GangService.getChiefs()
	return chiefs
end

function GangService.init(remotes)
	uiUpdate = remotes[GameConfig.Remotes.UIUpdate]
	remotes[GameConfig.Remotes.GangRequest].OnServerEvent:Connect(onRequest)

	local map = Workspace:FindFirstChild("Map")
	local favelas = map and map:FindFirstChild("Favelas")
	if favelas then
		for _, d in ipairs(favelas:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == "ChefeSpot" then
				local ok, err = pcall(spawnChief, d)
				if not ok then
					warn("[GangService] Erro ao criar o chefe: " .. tostring(err))
				end
			end
		end
		setupBars(favelas)
		setupParedoes(favelas)
		watchBalls(favelas)
	else
		warn("[GangService] Map.Favelas não encontrado (as favelas não foram montadas).")
	end

	-- gangue salva -> atributo (o cliente e o JobService leem)
	PlayerDataService.onLoaded(function(player)
		player:SetAttribute("Gang", gangOf(player))
	end)
	local n = 0
	for _ in pairs(chiefs) do
		n += 1
	end
	print(("[GangService] %d chefes de gangue prontos."):format(n))
end

return GangService
