-- ObraGuardService (ModuleScript)
-- Caminho: ServerScriptService > Services > ObraGuardService
-- Marco 10.32 (pedido do Luís: a perfuratriz não pode ser fácil de pegar): dois SEGURANÇAS armados
-- fazem ronda na obra do Residencial Vale Alto (ObraBuilder).
--   * Viu alguém dentro do canteiro: avisa ("Área restrita! Sai daqui!") e dá alguns segundos.
--   * Não saiu, ou está com a perfuratriz: saca a arma, ATIRA de verdade (tira vida) e chama a PM
--     (chamado no rádio + estrelas de procurado para quem invadiu).
--   * De noite eles enxergam bem menos (só com a lanterna) e o tapume do fundo tem um buraco:
--     dá para entrar escondido pelos fundos, longe da ronda.
--   * Mirar com uma arma num segurança por alguns segundos rende ele (mãos para cima) por um tempo.
--   * Policial em serviço não é incomodado.
-- A perfuratriz continua sorteada entre os 14 pontos da obra (FerramentasAssaltoService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local NPCKit = require(script.Parent:WaitForChild("NPCKit"))
local CrimeService = require(script.Parent:WaitForChild("CrimeService"))
local WeaponService = require(script.Parent:WaitForChild("WeaponService"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))

local ObraGuardService = {}

local C = {
	DayView = 52, NightView = 20, -- quanto enxergam (studs)
	Hearing = 8, -- perto assim ele percebe mesmo de costas
	FovDot = 0.45, -- cone de visão (~63° para cada lado)
	WarnTime = 6, NightWarnTime = 4, -- segundos para sair depois do aviso
	FireRate = 1.1, Range = 65, Hit = 0.6, NightHit = 0.42, Damage = 12,
	Forget = 25, -- sem ver o invasor por tanto tempo: volta para a ronda
	AimTime = 2.2, AimRange = 40, SurrenderTime = 60,
	WantedPoints = 2,
}
ObraGuardService.Config = C

local W, D = 150, 140 -- mesmo lote do ObraBuilder
local G = 0.7
local NAME = "Obra do Residencial Vale Alto"

local uiUpdate
local obra, lot
local guards = {} -- { npc, name, route, state = "ronda"|"alerta"|"atirando"|"rendido", ... }
local intruders = {} -- intruders[player] = { warnedAt, deadline, hostile, lastSeen, called }
local rng = Random.new()

local function notice(player, text, color)
	if uiUpdate then
		uiUpdate:FireClient(player, "Notice", { text = text, color = color })
	end
end

local function at(x, y, z)
	return lot * CFrame.new(x, y, z)
end

local function isNight()
	local t = Lighting.ClockTime
	return t < 6 or t > 18.4
end

local function rootOf(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not root or hum.Health <= 0 then
		return nil
	end
	return root, hum, char
end

local function inLot(pos, pad)
	local p = lot:PointToObjectSpace(pos)
	pad = pad or 0
	return math.abs(p.X) < W / 2 + pad and math.abs(p.Z) < D / 2 + pad and p.Y < 80
end

local function ignored(player)
	return CrimeService.isPolice(player) or player:GetAttribute("Caido") or player:GetAttribute("Preso") or CrimeService.isCuffed(player)
end

local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude
local function lineOfSight(from, to, ignoreList)
	losParams.FilterDescendantsInstances = ignoreList
	return Workspace:Raycast(from, to - from, losParams) == nil
end

local function guardRoot(g)
	local r = g.npc and g.npc.Parent and g.npc:FindFirstChild("HumanoidRootPart")
	return r
end

local function sees(g, root, night)
	local gr = guardRoot(g)
	if not gr then
		return false
	end
	local eye = gr.Position + Vector3.new(0, 1.6, 0)
	local delta = root.Position - eye
	local dist = delta.Magnitude
	if dist < C.Hearing then
		return true
	end
	local view = night and C.NightView or C.DayView
	if dist > view then
		return false
	end
	local look = gr.CFrame.LookVector
	if look:Dot(delta.Unit) < C.FovDot then
		return false
	end
	local list = { g.npc, root.Parent }
	for _, o in ipairs(guards) do
		if o.npc then
			table.insert(list, o.npc)
		end
	end
	return lineOfSight(eye, root.Position, list)
end

local function face(g, pos)
	local gr = guardRoot(g)
	if gr then
		NPCKit.face(g.npc, pos - gr.Position)
	end
end

local function setArmed(g, on)
	if on and not g.gun then
		g.gun = NPCKit.hold(g.npc, "PistolaSeguranca", Vector3.new(0.35, 0.7, 1.3), Color3.fromRGB(30, 30, 34), Enum.Material.Metal)
	elseif not on and g.gun then
		g.gun:Destroy()
		g.gun = nil
	end
end

local function callPolice(player, pos)
	local info = intruders[player]
	if info.called then
		return
	end
	info.called = true
	CrimeService.addWanted(player, C.WantedPoints)
	pcall(CrimeService.alert, "🦺 Invasão na obra: segurança atirando", NAME, pos)
	notice(player, "📻 O segurança chamou a PM pelo rádio! Você está sendo procurado.", Color3.fromRGB(220, 60, 50))
end

local function shoot(g, target, night)
	local gr = guardRoot(g)
	if not gr then
		return
	end
	face(g, target.Position)
	local eye = gr.Position + Vector3.new(0, 1.5, 0)
	local d = (target.Position - eye).Magnitude
	local chance = (night and C.NightHit or C.Hit) * math.clamp(1 - d / (C.Range * 1.6), 0.25, 1)
	local hit = rng:NextNumber() < chance
	local to = hit and target.Position or target.Position + Vector3.new(rng:NextNumber(-4, 4), rng:NextNumber(-1, 3), rng:NextNumber(-4, 4))
	if uiUpdate then
		uiUpdate:FireAllClients("Shot", { from = g.gun and g.gun.Position or eye, to = to, by = 0 })
	end
	if hit then
		local hum = target.Parent and target.Parent:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			hum:TakeDamage(C.Damage)
		end
	end
end

local function patrol(g)
	task.spawn(function()
		local i = 1
		while g.npc.Parent do
			if g.state == "ronda" then
				local p = g.route[i]
				NPCKit.walk(g.npc, { at(p.X, G, p.Z).Position }, nil, function()
					return g.state == "ronda"
				end)
				if g.state == "ronda" then
					i = i % #g.route + 1
					-- de vez em quando para e olha em volta
					if rng:NextNumber() < 0.35 then
						local gr = guardRoot(g)
						if gr then
							NPCKit.face(g.npc, Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)))
						end
						task.wait(rng:NextNumber(1.5, 3.5))
					end
				end
			end
			task.wait(0.2)
		end
	end)
end

local function stopWalking(g)
	local hum = g.npc and g.npc:FindFirstChildOfClass("Humanoid")
	local gr = guardRoot(g)
	if hum and gr then
		hum:MoveTo(gr.Position)
	end
end

local function flashlight(g, on)
	local head = g.npc and g.npc:FindFirstChild("Head")
	if not head then
		return
	end
	local l = head:FindFirstChild("Lanterna")
	if on and not l then
		l = Instance.new("SpotLight")
		l.Name = "Lanterna"
		l.Face = Enum.NormalId.Front
		l.Range = C.NightView + 8
		l.Angle = 50
		l.Brightness = 3
		l.Color = Color3.fromRGB(255, 244, 210)
		l.Shadows = false
		l.Parent = head
	elseif l then
		l.Enabled = on
	end
end

local function step(dt)
	if not obra or not obra.Parent then
		return
	end
	local now = os.clock()
	local night = isNight()
	-- quem está dentro do canteiro (ou mirando de perto)
	local inside = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local root = rootOf(p)
		if root and not ignored(p) then
			if inLot(root.Position, 2) then
				table.insert(inside, { player = p, root = root })
			end
		end
	end
	for _, g in ipairs(guards) do
		local gr = guardRoot(g)
		if gr then
			flashlight(g, night)
			-- render: alguém mirando nele
			if g.state ~= "rendido" then
				for _, p in ipairs(Players:GetPlayers()) do
					local root = rootOf(p)
					if root and not ignored(p) and (root.Position - gr.Position).Magnitude < C.AimRange and WeaponService.isAimingAt(p, root, gr.Position) then
						g.aim[p] = (g.aim[p] or 0) + dt
						if g.aim[p] >= C.AimTime then
							g.state = "rendido"
							g.until_ = now + C.SurrenderTime
							g.target = nil
							setArmed(g, false)
							stopWalking(g)
							NPCKit.pose(g.npc, "maos", C.SurrenderTime)
							NPCKit.say(g.npc, "Calma, calma! Não atira!", 3)
							notice(p, ("🙌 Você rendeu o segurança da obra por %d s."):format(C.SurrenderTime))
							-- rendido mas avisa no rádio
							intruders[p] = intruders[p] or { lastSeen = now }
							callPolice(p, root.Position)
						end
					else
						g.aim[p] = 0
					end
				end
			end
			if g.state == "rendido" then
				if now >= (g.until_ or 0) then
					g.state = "ronda"
					g.aim = {}
					NPCKit.say(g.npc, "Agora eu te pego!", 3)
				end
			else
				-- procura invasores
				local best, bestD
				for _, it in ipairs(inside) do
					local info = intruders[it.player]
					local seen = sees(g, it.root, night)
					if seen then
						if not info then
							info = { warnedAt = now, deadline = now + (night and C.NightWarnTime or C.WarnTime) }
							intruders[it.player] = info
							stopWalking(g)
							face(g, it.root.Position)
							NPCKit.say(g.npc, night and "Quem tá aí?! Sai da obra AGORA!" or "Ei! Área restrita! Sai daqui!", 3)
							NPCKit.emote(g.npc, "point")
							notice(it.player, ("🦺 SEGURANÇA DA OBRA: saia em %d s ou ele atira!"):format(math.ceil(info.deadline - now)), Color3.fromRGB(240, 170, 40))
						end
						info.lastSeen = now
						if not info.hostile and (now >= info.deadline or InventoryService.has(it.player, "Perfuratriz")) then
							info.hostile = true
							NPCKit.say(g.npc, "Avisei! PARADO!", 3)
							notice(it.player, "🔫 O segurança está ATIRANDO em você!", Color3.fromRGB(220, 60, 50))
						end
						if info.hostile then
							local d = (it.root.Position - gr.Position).Magnitude
							if not bestD or d < bestD then
								best, bestD = it, d
							end
						elseif g.state == "ronda" then
							g.state = "alerta"
						end
					end
				end
				-- continua atirando em quem já virou alvo, mesmo saindo pelo portão (se ainda vê)
				if not best then
					for p, info in pairs(intruders) do
						local root = info.hostile and rootOf(p)
						if root and not ignored(p) and now - info.lastSeen < 6 and (root.Position - gr.Position).Magnitude < C.Range and sees(g, root, night) then
							info.lastSeen = now
							best = { player = p, root = root }
						end
					end
				end
				if best then
					g.state = "atirando"
					g.target = best.player
					g.lastTarget = now
					setArmed(g, true)
					stopWalking(g)
					callPolice(best.player, best.root.Position)
					if now >= (g.nextShot or 0) then
						g.nextShot = now + C.FireRate * rng:NextNumber(0.85, 1.2)
						shoot(g, best.root, night)
					end
				elseif g.state == "atirando" and now - (g.lastTarget or 0) > 8 then
					g.state = "ronda"
					setArmed(g, false)
				elseif g.state == "alerta" then
					-- olhando para o invasor avisado
					local look
					for p, info in pairs(intruders) do
						local root = rootOf(p)
						if root and not info.hostile and now - info.lastSeen < 2 then
							look = root.Position
						end
					end
					if look then
						face(g, look)
					else
						g.state = "ronda"
					end
				end
			end
		end
	end
	-- esquece quem sumiu
	for p, info in pairs(intruders) do
		local root = rootOf(p)
		if not p.Parent or not root or (now - (info.lastSeen or 0) > C.Forget and not inLot(root.Position, 2)) then
			intruders[p] = nil
		elseif not info.hostile and not inLot(root.Position, 4) and now - info.lastSeen > 3 then
			intruders[p] = nil -- obedeceu e saiu
		end
	end
end

local function spawnGuards()
	local routes = {
		-- 1: portão, escritório (contêineres), betoneira e frente do prédio
		{ name = "Jorge", start = Vector3.new(4, 0, -60), route = { Vector3.new(4, 0, -60), Vector3.new(32, 0, -44), Vector3.new(30, 0, -24), Vector3.new(-20, 0, -38), Vector3.new(-62, 0, -42), Vector3.new(-62, 0, -60) } },
		-- 2: volta no prédio, grua, gerador e um pedaço dos fundos
		{ name = "Valdir", start = Vector3.new(18, 0, 0), route = { Vector3.new(18, 0, -34), Vector3.new(18, 0, 30), Vector3.new(48, 0, 44), Vector3.new(-10, 0, 34), Vector3.new(-58, 0, 30), Vector3.new(-58, 0, -34) } },
	}
	for _, r in ipairs(routes) do
		local npc = NPCKit.spawn(at(r.start.X, G, r.start.Z), { name = "Segurança " .. r.name, outfit = "seguranca", title = "SEGURANÇA DA OBRA", speed = 8, important = true })
		if npc then
			npc:SetAttribute("SegurancaObra", true)
			local g = { npc = npc, name = r.name, route = r.route, state = "ronda", aim = {} }
			table.insert(guards, g)
			patrol(g)
		end
	end
end

function ObraGuardService.init(remotes)
	uiUpdate = remotes and remotes[GameConfig.Remotes.UIUpdate]
	task.spawn(function()
		for _ = 1, 60 do
			obra = CollectionService:GetTagged("Obra")[1]
			if obra then
				break
			end
			task.wait(1)
		end
		if not obra then
			warn("[ObraGuard] Obra não encontrada: sem seguranças.")
			return
		end
		lot = obra:GetAttribute("MapaPivot")
		if typeof(lot) ~= "CFrame" then
			warn("[ObraGuard] Obra sem MapaPivot: sem seguranças.")
			return
		end
		task.wait(3)
		spawnGuards()
		local acc = 0
		game:GetService("RunService").Heartbeat:Connect(function(dt)
			acc += dt
			if acc >= 0.25 then
				local ok, err = pcall(step, acc)
				if not ok then
					warn("[ObraGuard] " .. tostring(err))
				end
				acc = 0
			end
		end)
		print(("[ObraGuard] %d seguranças na obra."):format(#guards))
	end)
	Players.PlayerRemoving:Connect(function(p)
		intruders[p] = nil
		for _, g in ipairs(guards) do
			g.aim[p] = nil
		end
	end)
end

-- (testes no Studio)
function ObraGuardService.state()
	local out = {}
	for _, g in ipairs(guards) do
		local r = guardRoot(g)
		table.insert(out, { name = g.name, state = g.state, pos = r and r.Position })
	end
	return out
end

return ObraGuardService
