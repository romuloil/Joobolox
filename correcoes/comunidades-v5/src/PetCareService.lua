-- PetCareService (ModuleScript)
-- Caminho: ServerScriptService > Services > PetCareService
-- Marco 9: Cuidador de animais no Duto Pet Shop. Os pedidos são normais do MissionService
-- (JobConfig: careOrder); aqui ficam as ações especiais das etapas:
--   * careArrive: o dono (NPC) entra com o bichinho e espera no balcão;
--   * careTake: o dono entrega o pet e fica esperando;
--   * careMove: o pet vai (pulinhos) até a estação da etapa (banheira, mesa, comedouro, balcão);
--   * careFx: bolhas, água, vento, brilho ou coração no pet quando a etapa termina;
--   * careReturn: o dono recebe o pet, agradece e os dois vão embora.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local NPCKit = require(script.Parent:WaitForChild("NPCKit"))
local PetService = require(script.Parent:WaitForChild("PetService"))

local PetCareService = {}

local sites
local visits = {} -- visits[player] = { owner = npc, pet = model }
local petFolder

local HELLO = { "Oi! Cuida bem do %s pra mim?", "O %s precisa de um trato!", "Trouxe o %s. Ele é bonzinho!" }
local THANKS = { "Ficou lindo! Obrigado!", "Que cheiroso! Valeu!", "Ele amou! Até a próxima!" }

-- Efeitos de cada etapa: cor das partículas e emoji
local FX = {
	Bolhas = { color = Color3.fromRGB(200, 235, 255), emoji = "🧼", size = 0.6 },
	Agua = { color = Color3.fromRGB(80, 170, 255), emoji = "💦", size = 0.3 },
	Vento = { color = Color3.fromRGB(240, 240, 240), emoji = "💨", size = 0.4 },
	Brilho = { color = Color3.fromRGB(255, 225, 90), emoji = "✨", size = 0.35 },
	Coracao = { color = Color3.fromRGB(255, 110, 150), emoji = "❤️", size = 0.4 },
}

local function pick(list)
	return list[math.random(1, #list)]
end

local function onGround(cf)
	local y = NPCKit.groundAt(cf.Position)
	return CFrame.new(cf.X, y, cf.Z) * cf.Rotation
end

local function removeVisit(player)
	local v = visits[player]
	visits[player] = nil
	if v then
		if v.owner then
			v.owner:Destroy()
		end
		if v.pet then
			v.pet:Destroy()
		end
	end
end

local function pointPart(state)
	local point = state.point and sites.points[state.point]
	return point and point.part
end

-- Pet anda até "target" (CFrame no chão) em pulinhos curtos
local function slide(pet, target, duration)
	if not pet.Parent then
		return
	end
	local from = pet:GetPivot()
	local steps = math.max(1, math.floor(duration * 20))
	for i = 1, steps do
		if not pet.Parent then
			return
		end
		local t = i / steps
		local hop = math.abs(math.sin(t * math.pi * 4)) * 0.35
		local cf = from:Lerp(target, t)
		pet:PivotTo(cf + Vector3.new(0, hop, 0))
		task.wait(duration / steps)
	end
	pet:PivotTo(target)
end

-- Emoji que sobe em cima do pet
local function emoji(pet, text)
	local root = pet.PrimaryPart
	if not root then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(46, 46)
	gui.StudsOffset = Vector3.new(0, 3.2, 0)
	gui.MaxDistance = 50
	gui.Parent = root
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Text = text
	label.Parent = gui
	Debris:AddItem(gui, 1.8)
end

local function burst(pet, fx)
	local body = pet:FindFirstChild("Body") or pet.PrimaryPart
	if not body then
		return
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(fx.color)
	emitter.Size = NumberSequence.new(fx.size)
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.Speed = NumberRange.new(2, 4)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Transparency = NumberSequence.new(0.2, 1)
	emitter.Rate = 0
	emitter.Parent = body
	emitter:Emit(25)
	Debris:AddItem(emitter, 2)
	emoji(pet, fx.emoji)
end

local Hooks = {}

-- Etapa 1 começou: o dono entra pela porta com o bichinho e para na frente do balcão.
-- Devolve quantos segundos esperar até poder receber (tempo de ele chegar).
function Hooks.careArrive(player, state)
	removeVisit(player)
	local spot = pointPart(state)
	local shop = sites.shops.Cuidador
	local info = state.order.pet
	local breeds = GameConfig.PetCare.Breeds
	local look = info and breeds[info.breed] or breeds[1]
	if not spot or not shop or not look then
		return nil
	end
	local customer = spot:GetAttribute("Customer")
	local petSpot = spot:GetAttribute("PetSpot")
	if typeof(customer) ~= "CFrame" then
		return nil
	end
	local v = {}
	visits[player] = v
	local doorOut, doorIn = onGround(shop.door[1]), onGround(shop.door[2])
	v.owner = NPCKit.spawn(doorOut, { name = "Cliente", important = true, speed = 9 })
	v.pet = PetService.buildDisplay(doorOut * CFrame.new(2, 0, 0), look, petFolder)
	task.spawn(function()
		if v.owner then
			task.spawn(NPCKit.walk, v.owner, { doorIn, customer }, spot.Position - customer.Position) -- olhando o balcão
		end
		if typeof(petSpot) == "CFrame" then
			slide(v.pet, onGround(doorIn) * CFrame.new(2, 0, 0), 1.2)
			slide(v.pet, petSpot, 1.8)
		end
		if v.owner and v.owner.Parent and info then
			NPCKit.say(v.owner, pick(HELLO):format(info.name))
			NPCKit.emote(v.owner, "wave")
		end
	end)
	return 3
end

-- O dono entregou o pet
function Hooks.careTake(player)
	local v = visits[player]
	if v and v.pet then
		emoji(v.pet, "🐾")
	end
end

-- O pet vai até a estação da etapa
function Hooks.careMove(player, state)
	local v = visits[player]
	local spot = pointPart(state)
	local target = spot and spot:GetAttribute("PetSpot")
	if not v or not v.pet or typeof(target) ~= "CFrame" then
		return
	end
	task.spawn(slide, v.pet, target, 1)
	return 1 -- espera o pet chegar
end

function Hooks.careFx(player, state, step)
	local v = visits[player]
	local fx = FX[step.fx]
	if v and v.pet and fx then
		burst(v.pet, fx)
	end
end

-- Pet devolvido: o dono agradece e os dois vão embora
function Hooks.careReturn(player)
	local v = visits[player]
	visits[player] = nil -- o próximo cliente não apaga este (ainda está saindo)
	if not v then
		return
	end
	local shop = sites.shops.Cuidador
	task.spawn(function()
		if v.owner and v.owner.Parent then
			NPCKit.say(v.owner, pick(THANKS))
			NPCKit.react(v.owner, pick({ "😊", "🥰", "👍" }))
			NPCKit.emote(v.owner, "cheer")
		end
		if v.pet then
			emoji(v.pet, "❤️")
		end
		task.wait(1.8)
		if shop then
			local doorIn, doorOut = onGround(shop.door[2]), onGround(shop.door[1])
			if v.owner and v.owner.Parent then
				task.spawn(NPCKit.walk, v.owner, { doorIn, doorOut })
			end
			if v.pet then
				slide(v.pet, doorIn * CFrame.new(2, 0, 0) * CFrame.Angles(0, math.pi, 0), 1.8)
				slide(v.pet, doorOut * CFrame.new(2, 0, 0) * CFrame.Angles(0, math.pi, 0), 1.2)
			end
		end
		task.wait(0.5)
		if v.owner then
			v.owner:Destroy()
		end
		if v.pet then
			v.pet:Destroy()
		end
	end)
end

function PetCareService.init(missionService, jobSites)
	sites = jobSites
	petFolder = Instance.new("Folder")
	petFolder.Name = "PetsClientes"
	petFolder.Parent = Workspace
	for name, fn in pairs(Hooks) do
		missionService.registerHook(name, fn)
	end
	-- largou o emprego, morreu ou saiu: cliente e pet somem
	missionService.onStop(removeVisit)
	Players.PlayerRemoving:Connect(removeVisit)
end

return PetCareService
