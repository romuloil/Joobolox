-- DownedService (ModuleScript)
-- Caminho: ServerScriptService > Services > DownedService
-- Marco 10.15 (pedido do Luís): ninguém "morre" de cara. A vida zerou = a pessoa CAI no chão e fica
-- lá por GameConfig.Downed.Time (120 s) esperando um Paramédico (emprego novo) chegar e reanimar
-- (segurar E). Ela pode DESISTIR (depois de 5 s): renasce na praça sem os itens da mochila, sem o
-- dinheiro sujo e paga a conta do hospital (2%, no máximo $5 mil). Acabou o tempo = mesma coisa.
--   * O estado "Dead" do Humanoid fica desligado (no servidor e no cliente), então o Roblox não
--     mata nem faz renascer sozinho. A queda conta como a antiga morte para o crime (WeaponService.reportDown):
--     policial que derruba procurado leva direto para a prisão (aí a pessoa levanta lá, sem esperar).
--   * O script "Health" padrão (que recupera a vida) sai; a recuperação é feita aqui (1 por segundo,
--     5 s depois do último dano), e nunca para quem está caído.
--   * Atributos no jogador: Caido = true, CaidoAte = horário do servidor em que acaba.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local GameConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("GameConfig"))
local Services = script.Parent
local SecurityService = require(Services:WaitForChild("SecurityService"))
local EconomyService = require(Services:WaitForChild("EconomyService"))
local WeaponService = require(Services:WaitForChild("WeaponService"))
local InventoryService = require(Services:WaitForChild("InventoryService"))
local CrimeService = require(Services:WaitForChild("CrimeService"))
local JobService = require(Services:WaitForChild("JobService"))
local CareerService = require(Services:WaitForChild("CareerService"))

local DownedService = {}

local D = GameConfig.Downed
local MEDIC = "Paramedico"
local REGEN_DELAY, REGEN_PER_SEC = 5, 1

local uiUpdate
local downed = {} -- [player] = { at, untilT, character }
local lastDamage = {} -- [player] = os.clock() do último dano
local giveUpHooks = {}
local respawning = {}

local function notice(player, text)
	if uiUpdate and player.Parent then
		uiUpdate:FireClient(player, "Notice", { text = text })
	end
end

local function money(n)
	return GameConfig.Economy.CurrencySymbol .. tostring(math.floor(n))
end

local function medics()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if JobService.getJob(p) == MEDIC then
			table.insert(list, p)
		end
	end
	return list
end

local function partsOf(character)
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return hum, root
end

local function removePrompt(character)
	local _, root = partsOf(character)
	local prompt = root and root:FindFirstChild("ReanimarPrompt")
	if prompt then
		prompt:Destroy()
	end
end

local function clear(player)
	local st = downed[player]
	downed[player] = nil
	if player.Parent then
		player:SetAttribute("Caido", nil)
		player:SetAttribute("CaidoAte", nil)
	end
	if st then
		removePrompt(st.character)
	end
	return st
end

-- Levanta a pessoa no mesmo lugar (paramédico ou preso agora)
local function standUp(player, health)
	local st = clear(player)
	local character = (st and st.character) or player.Character
	local hum, root = partsOf(character)
	if not hum or not root then
		return
	end
	if root.Anchored then
		local _, yaw = root.CFrame:ToEulerAnglesYXZ()
		root.Anchored = false
		root.CFrame = CFrame.new(root.Position + Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, yaw, 0)
	end
	hum.Health = math.min(hum.MaxHealth, health)
	lastDamage[player] = os.clock()
	if uiUpdate then
		uiUpdate:FireClient(player, "Levantou", {})
	end
end

local function giveUp(player, why)
	if not downed[player] then
		return
	end
	clear(player)
	for _, fn in ipairs(giveUpHooks) do
		local ok, err = pcall(fn, player)
		if not ok then
			warn("[DownedService] " .. tostring(err))
		end
	end
	local items = InventoryService.loseAll(player)
	local dirty = CrimeService.clearDirty(player)
	local cash = EconomyService.getMoney(player) or 0
	local fee = math.min(D.HospitalMax, math.floor(cash * D.HospitalFee))
	if fee > 0 then
		EconomyService.spend(player, fee, "Conta do hospital")
	end
	local parts = {}
	if items > 0 then
		table.insert(parts, ("perdeu %d item(ns) da mochila"):format(items))
	end
	if dirty > 0 then
		table.insert(parts, "perdeu " .. money(dirty) .. " do assalto")
	end
	if fee > 0 then
		table.insert(parts, "hospital: -" .. money(fee))
	end
	local head = why == "tempo" and "Nenhum paramédico chegou a tempo." or "Você desistiu."
	notice(player, head .. " Renasceu na praça" .. (#parts > 0 and (": " .. table.concat(parts, ", ") .. ".") or "."))
	if player.Parent then
		player:LoadCharacter()
	end
end

local function lieDown(character)
	local hum, root = partsOf(character)
	if not hum or not root then
		return
	end
	hum:UnequipTools()
	local seat = hum.SeatPart
	if seat then
		local weld = seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
		hum.Sit = false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.RespectCanCollide = true
	local hit = Workspace:Raycast(root.Position + Vector3.new(0, 1, 0), Vector3.new(0, -30, 0), params)
	local y = hit and hit.Position.Y or (root.Position.Y - 3)
	local _, yaw = root.CFrame:ToEulerAnglesYXZ()
	root.Anchored = true
	-- deitado de barriga para cima
	root.CFrame = CFrame.new(root.Position.X, y + 0.9, root.Position.Z) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(90), 0, 0)
end

local function revive(medic, target)
	local st = downed[target]
	if not st or JobService.getJob(medic) ~= MEDIC or medic == target then
		return
	end
	local _, _, mRoot = SecurityService.getLivingCharacter(medic)
	local _, tRoot = partsOf(st.character)
	if not mRoot or not tRoot or (mRoot.Position - tRoot.Position).Magnitude > D.ReviveRange + 4 then
		return
	end
	standUp(target, D.ReviveHealth)
	local paid = CareerService.taskPay(medic, MEDIC, D.RevivePay, "Reanimou " .. target.Name)
	notice(target, ("🚑 %s te reanimou!"):format(medic.DisplayName))
	if uiUpdate then
		uiUpdate:FireClient(medic, "CrimePaid", { amount = paid, text = ("Reanimou %s: +%s"):format(target.DisplayName, money(paid)) })
	end
end

local function addPrompt(player, character)
	local _, root = partsOf(character)
	if not root or root:FindFirstChild("ReanimarPrompt") then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ReanimarPrompt"
	prompt.ActionText = "Reanimar"
	prompt.ObjectText = player.DisplayName .. " (caído)"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = D.ReviveTime
	prompt.MaxActivationDistance = D.ReviveRange
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false -- o cliente liga só para os paramédicos (DownedController)
	prompt.Parent = root
	prompt.Triggered:Connect(function(medic)
		if SecurityService.checkRate(medic, "Reanimar", 1) then
			revive(medic, player)
		end
	end)
end

local function goDown(player, character)
	if downed[player] or player.Character ~= character then
		return
	end
	-- conta como a antiga morte (procurado, preso pela PM...)
	WeaponService.reportDown(player)
	if player:GetAttribute("Preso") then
		-- a PM derrubou e prendeu: levanta direto (já está indo para a prisão)
		local hum = partsOf(character)
		if hum and player.Character == character then
			hum.Health = hum.MaxHealth
		end
		return
	end
	if player.Character ~= character then
		return -- renasceu no meio (prisão, etc.)
	end
	local now = os.clock()
	downed[player] = { at = now, untilT = now + D.Time, character = character }
	player:SetAttribute("Caido", true)
	player:SetAttribute("CaidoAte", Workspace:GetServerTimeNow() + D.Time)
	lieDown(character)
	addPrompt(player, character)
	local list = medics()
	if uiUpdate then
		uiUpdate:FireClient(player, "Caiu", { time = D.Time, giveUpAfter = D.GiveUpAfter, medics = #list })
	end
	for _, m in ipairs(list) do
		notice(m, ("🚑 %s caiu! Veja a cruz vermelha no mapa."):format(player.DisplayName))
	end
end

local function setupCharacter(player, character)
	local hum = character:WaitForChild("Humanoid", 10)
	if not hum then
		return
	end
	hum.BreakJointsOnDeath = false
	hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	-- sem a recuperação de vida padrão (fazemos aqui, e nunca para quem está caído)
	local function killRegen(child)
		if child.Name == "Health" and child:IsA("Script") then
			child:Destroy()
		end
	end
	for _, c in ipairs(character:GetChildren()) do
		killRegen(c)
	end
	character.ChildAdded:Connect(killRegen)
	local last = hum.Health
	hum.HealthChanged:Connect(function(h)
		if h < last then
			lastDamage[player] = os.clock()
		end
		last = h
		if h <= 0 and not downed[player] then
			task.defer(goDown, player, character)
		end
	end)
end

function DownedService.isDowned(player)
	return downed[player] ~= nil
end

-- Quem precisa saber quando alguém desiste (joalheria: perde a bolsa)
function DownedService.onGiveUp(fn)
	table.insert(giveUpHooks, fn)
end

-- Para a prisão e outros: levanta sem cobrar nada
function DownedService.standUp(player)
	if downed[player] then
		standUp(player, 100)
	end
end

function DownedService.init(remotes)
	uiUpdate = remotes[GameConfig.Remotes.UIUpdate]
	remotes[GameConfig.Remotes.DownedRequest].OnServerEvent:Connect(function(player, action)
		if action ~= "Desistir" or not SecurityService.checkRate(player, "Desistir", 1) then
			return
		end
		local st = downed[player]
		if st and os.clock() - st.at >= D.GiveUpAfter then
			giveUp(player, "desistiu")
		end
	end)
	local function watch(player)
		player.CharacterAdded:Connect(function(character)
			if downed[player] then
				clear(player) -- renasceu por outro motivo (prisão, reset)
			end
			setupCharacter(player, character)
		end)
		if player.Character then
			task.spawn(setupCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, p in ipairs(Players:GetPlayers()) do
		watch(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		downed[player] = nil
		lastDamage[player] = nil
	end)
	-- relógio: tempo de quem está caído, recuperação de vida e quem caiu no "vazio"
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			for _, player in ipairs(Players:GetPlayers()) do
				local st = downed[player]
				local character = player.Character
				if st then
					local _, root = partsOf(st.character)
					if not root or not st.character:IsDescendantOf(Workspace) or now >= st.untilT then
						task.spawn(giveUp, player, "tempo")
					end
				elseif character then
					local hum = partsOf(character)
					if not character:IsDescendantOf(Workspace) then
						-- caiu do mapa (o Roblox apagou o boneco): renasce
						if Players.CharacterAutoLoads and not respawning[player] then
							respawning[player] = true
							task.spawn(function()
								task.wait(2)
								if player.Parent and player.Character == character then
									player:LoadCharacter()
								end
								respawning[player] = nil
							end)
						end
					elseif hum and hum.Health > 0 and hum.Health < hum.MaxHealth and now - (lastDamage[player] or 0) >= REGEN_DELAY then
						hum.Health = math.min(hum.MaxHealth, hum.Health + REGEN_PER_SEC)
					end
				end
			end
		end
	end)
end

return DownedService
