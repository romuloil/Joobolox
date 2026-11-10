-- FerramentasAssaltoService (ModuleScript)
-- Caminho: ServerScriptService > Services > FerramentasAssaltoService
-- Marco 10.30: a PERFURATRIZ escondida na obra do Residencial Vale Alto (ObraBuilder).
--   * Só existe UMA largada no mundo por vez, num dos pontos "PontoPerfuratriz" da obra (sorteado).
--     Ninguém pegou em 15 min: ela muda de lugar. Pegou: a próxima aparece 30 min depois
--     (AssaltoConfig.Perfuratriz). Quem é de gangue pega (vai para a mochila, não fica salva);
--     policial em serviço APREENDE (some e volta mais tarde).
--   * Perdeu (preso, revistado, desistiu caído, saiu do jogo): a obra recebe outra em 5 min.
--   * No banco, ela gasta a broca: depois de furar o cofre, quebra (consume).
--   * Quando chega uma nova, quem é de gangue recebe o aviso.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local AssaltoConfig = require(Shared:WaitForChild("AssaltoConfig"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))
local WeaponService = require(script.Parent:WaitForChild("WeaponService"))
local CrimeService = require(script.Parent:WaitForChild("CrimeService"))

local FerramentasAssaltoService = {}

local P = AssaltoConfig.Perfuratriz
local ID = "Perfuratriz"
local uiUpdate
local obra
local spots = {}
local world -- { model, spot, since, prompt }
local nextSpawn = 0
local holders = {} -- holders[player] = true (pegou e ainda tem)
local consumed = {} -- consumed[player] = true (quebrou no banco: não conta como perdida)
local lastSpot

local function notice(player, text)
	if uiUpdate and player.Parent then
		uiUpdate:FireClient(player, "Notice", { text = text })
	end
end

local function now()
	return os.clock()
end

-- modelo deitado no chão: a própria ferramenta (Handle + peças soldadas), com o Handle ancorado
local function buildModel(spot)
	local tool = WeaponService.makeTool(ID)
	if not tool then
		return nil
	end
	local m = Instance.new("Model")
	m.Name = "PerfuratrizNaObra"
	for _, c in ipairs(tool:GetChildren()) do
		c.Parent = m
	end
	tool:Destroy()
	local handle = m:FindFirstChild("Handle")
	if not handle then
		m:Destroy()
		return nil
	end
	m.PrimaryPart = handle
	handle.Anchored = true
	-- de lado, apontando para onde o marcador olha; depois apoia no chão do ponto
	m:PivotTo(spot.CFrame)
	m.Parent = obra
	local box, size = m:GetBoundingBox()
	local bottom = box.Position.Y - size.Y / 2
	m:PivotTo(m:GetPivot() + Vector3.new(0, spot.Position.Y - bottom + 0.05, 0))
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = d == handle
		end
	end
	-- um brilho fraco (dá para achar no escuro, mas não de longe)
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 200, 120)
	glow.Range = 7
	glow.Brightness = 0.8
	glow.Parent = handle
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 230, 160))
	sparkle.LightEmission = 1
	sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.25), NumberSequenceKeypoint.new(1, 0) })
	sparkle.Rate = 1.5
	sparkle.Lifetime = NumberRange.new(0.6, 1)
	sparkle.Speed = NumberRange.new(0.5, 1)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Parent = handle
	return m, handle
end

local function isCop(player)
	return CrimeService.isPolice and CrimeService.isPolice(player) or player:GetAttribute("Job") == "Policial"
end

local despawn -- (abaixo)

local function onPrompt(player)
	if not world then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or (root.Position - world.handle.Position).Magnitude > 12 then
		return
	end
	if isCop(player) then
		despawn()
		nextSpawn = now() + P.LostRespawn * 2
		notice(player, "🚓 Você apreendeu a perfuratriz da obra. Os bandidos vão ter que esperar outra.")
		return
	end
	if not player:GetAttribute("Gang") then
		return notice(player, "Essa perfuratriz é para o assalto ao banco: só quem é de gangue usa.")
	end
	if player:GetAttribute("Preso") then
		return
	end
	if InventoryService.has(player, ID) then
		return notice(player, "Você já tem uma perfuratriz.")
	end
	if not InventoryService.hasRoom(player) then
		return notice(player, "Sua mochila está cheia!")
	end
	if not InventoryService.addItem(player, ID, { temp = true, hotbar = true }) then
		return notice(player, "Sua mochila está cheia!")
	end
	despawn()
	holders[player] = true
	nextSpawn = now() + P.RespawnAfterTaken
	notice(player, "🛠️ PERFURATRIZ na mochila! No banco, com ela na mão, segure E na porta do cofre. (Ela some se você for preso ou sair do jogo.)")
	print(("[FerramentasAssalto] %s pegou a perfuratriz da obra."):format(player.Name))
end

despawn = function()
	if world then
		if world.model.Parent then
			world.model:Destroy()
		end
		world = nil
	end
end

local function spawnAt(spot)
	despawn()
	local model, handle = buildModel(spot)
	if not model then
		warn("[FerramentasAssalto] Não deu para montar a perfuratriz.")
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PerfuratrizPrompt"
	prompt.ActionText = "Pegar a perfuratriz"
	prompt.ObjectText = "Perfuratriz"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = P.PickupTime
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = handle
	prompt.Triggered:Connect(onPrompt)
	world = { model = model, handle = handle, spot = spot, since = now() }
	lastSpot = spot
	print(("[FerramentasAssalto] Perfuratriz em: %s"):format(tostring(spot:GetAttribute("Lugar"))))
end

local function pickSpot()
	if #spots == 0 then
		return nil
	end
	local choices = {}
	for _, s in ipairs(spots) do
		if s ~= lastSpot then
			table.insert(choices, s)
		end
	end
	if #choices == 0 then
		choices = spots
	end
	return choices[math.random(1, #choices)]
end

local function announce()
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("Gang") then
			notice(p, "🛠️ Chegou uma PERFURATRIZ nova na obra do Residencial Vale Alto (Estrada do Vale). Procurem nos andares, nos contêineres e até na grua. Cuidado: tem SEGURANÇA ARMADO fazendo ronda (de noite dá pra entrar pelo buraco no tapume dos fundos)!")
		end
	end
end

local function step()
	local t = now()
	-- quem pegou ainda tem? (preso, revistado, desistiu caído = perdeu)
	for p in pairs(holders) do
		if not p.Parent or not InventoryService.has(p, ID) then
			holders[p] = nil
			if consumed[p] then
				consumed[p] = nil
			else
				nextSpawn = math.min(nextSpawn, t + P.LostRespawn)
			end
		end
	end
	if world then
		if not world.model.Parent then
			world = nil
		elseif t - world.since >= P.Relocate then
			local spot = pickSpot()
			if spot then
				spawnAt(spot)
			end
		end
	elseif t >= nextSpawn then
		local spot = pickSpot()
		if spot then
			spawnAt(spot)
			announce()
		end
		nextSpawn = math.huge
	end
end

-- A broca gastou no cofre: a perfuratriz quebra
function FerramentasAssaltoService.consume(player)
	if player and InventoryService.has(player, ID) then
		consumed[player] = true
		InventoryService.removeOne(player, ID)
		notice(player, "🛠️ A broca gastou e a perfuratriz quebrou. A obra do Vale vai receber outra.")
	end
end

-- (para testes no Studio) onde ela está agora
function FerramentasAssaltoService.where()
	return world and world.spot:GetAttribute("Lugar") or nil
end

function FerramentasAssaltoService.init(remotes)
	uiUpdate = remotes[GameConfig.Remotes.UIUpdate]
	task.spawn(function()
		-- espera a obra (o mapa é montado antes, mas pode atrasar)
		for _ = 1, 60 do
			obra = CollectionService:GetTagged("Obra")[1]
			if obra then
				break
			end
			task.wait(1)
		end
		if not obra then
			warn("[FerramentasAssalto] Obra não encontrada no mapa: a perfuratriz não vai aparecer.")
			return
		end
		for _, d in ipairs(obra:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == "PontoPerfuratriz" then
				table.insert(spots, d)
			end
		end
		print(("[FerramentasAssalto] Obra com %d pontos para a perfuratriz."):format(#spots))
		nextSpawn = now() + P.FirstDelay
		Players.PlayerRemoving:Connect(function(p)
			consumed[p] = nil
		end)
		while true do
			local ok, err = pcall(step)
			if not ok then
				warn("[FerramentasAssalto] " .. tostring(err))
			end
			task.wait(1)
		end
	end)
end

return FerramentasAssaltoService
