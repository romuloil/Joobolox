-- WeaponService (ModuleScript)
-- Caminho: ServerScriptService > Services > WeaponService
-- Marco 10.5: as armas do Luís (GameConfig.Weapons) e as ferramentas da PM (taser e algema).
--   * As ferramentas (Tool) são montadas aqui; quem guarda e entrega é o InventoryService.
--     O modelo 3D vem de ServerStorage > WeaponModels (nome = Model no GameConfig). Sem o modelo,
--     a arma aparece como um bloquinho escuro (funciona igual).
--   * Tiro: o cliente só diz para onde mirou. O servidor confere a arma na mão, a cadência, a
--     munição e o alcance, faz o raio a partir do cano e aplica o dano.
--   * Zona segura (praça, dentro das casas, locais de trabalho): ninguém leva nem dá tiro.
--   * Quem acertou por último leva a culpa da morte (CrimeService decide o que acontece).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local SecurityService = require(script.Parent:WaitForChild("SecurityService"))
local ZoneService = require(script.Parent:WaitForChild("ZoneService"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))

local WeaponService = {}

local W = GameConfig.Weapons
local uiUpdate
local killListeners = {}
local lastHit = {} -- lastHit[victimPlayer] = { by = player, t = os.clock() }
local lastShot = {} -- lastShot[player] = os.clock()
local aimDir = {} -- aimDir[player] = Vector3 (para onde a arma mira, vem do cliente)
local shotListeners = {}

-- Itens que não são armas de fogo (só a PM usa)
local TOOLS = {
	Taser = { Name = "Taser", Icon = "⚡", Kind = "taser" },
	Algema = { Name = "Algema", Icon = "⛓️", Kind = "algema" },
	-- Marco 10.30: ferramentas do assalto ao banco (modelos do Luís em ServerStorage > WeaponModels).
	-- Perfuratriz: achada na obra do Vale (não fica salva). C4: comprada do chefe (fica salva).
	Perfuratriz = { Name = "Perfuratriz", Icon = "🛠️", Kind = "perfuratriz", Model = "Perfuratriz", Length = 2.6, Illegal = true },
	C4 = { Name = "C4", Icon = "🧨", Kind = "c4", Model = "C4", Length = 1.1, Illegal = true, Save = true },
}

function WeaponService.def(id)
	return W.List[id] or TOOLS[id]
end

-- Marco 10.30: o que fica salvo na mochila (armas compradas e a C4)
function WeaponService.savable(id)
	return W.List[id] ~= nil or (TOOLS[id] ~= nil and TOOLS[id].Save == true)
end

function WeaponService.onKill(fn)
	table.insert(killListeners, fn)
end

-- Marco 10.24: quem atira (assaltos): fn(player, from, unitDir). Os NPCs não seguram bala, mas um
-- tiro na direção deles os faz se render.
function WeaponService.onShot(fn)
	table.insert(shotListeners, fn)
end

-- Marco 10.24: a pessoa está mirando em "pos"? Usa a mira de verdade; antes olhava só para onde o
-- corpo estava virado, e por isso mirar no guarda muitas vezes não rendia.
function WeaponService.isAimingAt(player, root, pos, minDot)
	local to = pos - root.Position
	if to.Magnitude < 0.1 then
		return false
	end
	return (aimDir[player] or root.CFrame.LookVector):Dot(to.Unit) > (minDot or 0.88)
end

-- true se a pessoa está num lugar onde não tem tiro
function WeaponService.isSafe(player)
	if ZoneService.isInside(player) or player:GetAttribute("Preso") then
		return true
	end
	local _, _, root = SecurityService.getLivingCharacter(player)
	if root then
		local flat = (root.Position - W.SafePlazaCenter) * Vector3.new(1, 0, 1)
		if flat.Magnitude <= W.SafePlazaRadius then
			return true
		end
	end
	return false
end

---------------------------------------------------------------------------
-- Montar as ferramentas
---------------------------------------------------------------------------

local function plainPart(parent, name, size, cf, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Parent = parent
	return p
end

local function weldTo(handle, part)
	local w = Instance.new("WeldConstraint")
	w.Part0 = handle
	w.Part1 = part
	w.Parent = handle
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
end

-- Modelo da arma: o cano aponta para -Z e o cabo para baixo (tools/armaprep.py). O marcador "Grip"
-- vai na mão e o "Muzzle" é a ponta do cano.
local function gunModel(def, handle)
	local folder = ServerStorage:FindFirstChild("WeaponModels")
	local src = folder and folder:FindFirstChild(def.Model)
	local length = def.Length or W.Length[def.Kind] or 2
	local muzzleOffset
	if src then
		local m = src:Clone()
		local grip = m:FindFirstChild("Grip", true)
		local muzzle = m:FindFirstChild("Muzzle", true)
		local _, size = m:GetBoundingBox()
		local long = math.max(size.X, size.Y, size.Z)
		if long > 0 then
			m:ScaleTo(m:GetScale() * length / long)
		end
		-- Marco 10.5 (teste do Luís: arma virada para o próprio boneco): o Studio pode girar o
		-- modelo ao importar, então a direção sai dos marcadores. O eixo mais comprido da arma é o
		-- cano, e ele aponta do Grip para o Muzzle; o "para cima" é o eixo médio, do cabo para o cano.
		local pivot = m:GetPivot()
		local gripPos = grip and grip:IsA("BasePart") and grip.Position or pivot.Position
		local turn = CFrame.identity -- sem marcadores: fica como veio
		if grip and muzzle and grip:IsA("BasePart") and muzzle:IsA("BasePart") then
			local box, bsize = m:GetBoundingBox()
			local axes = { { box.XVector, bsize.X }, { box.YVector, bsize.Y }, { box.ZVector, bsize.Z } }
			table.sort(axes, function(a, b)
				return a[2] > b[2]
			end)
			local toMuzzle = muzzle.Position - grip.Position
			local f = axes[1][1] * (toMuzzle:Dot(axes[1][1]) >= 0 and 1 or -1)
			local u = axes[2][1] * (toMuzzle:Dot(axes[2][1]) >= 0 and 1 or -1)
			local look = CFrame.fromMatrix(Vector3.zero, u:Cross(-f), u, -f) -- LookVector = cano
			turn = look:Inverse()
		end
		m:PivotTo(handle.CFrame * turn * CFrame.new(-gripPos) * pivot)
		if muzzle and muzzle:IsA("BasePart") then
			muzzleOffset = handle.CFrame:PointToObjectSpace(muzzle.Position)
		end
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then
				if d.Name == "Grip" or d.Name == "Muzzle" then
					d.Transparency = 1
				end
				-- a cor vem no nome da peça ("Cor_1a1a1c_3"): o Roblox não importa as cores do .glb
				local hex = d.Name:match("^Cor_(%x%x%x%x%x%x)")
				if hex then
					d.Color = Color3.fromHex(hex)
					d.Material = Enum.Material.SmoothPlastic
					if d:IsA("MeshPart") then
						d.TextureID = ""
					end
				end
				-- Marco 10.30: a cabeça da perfuratriz ("..._Gira") vai num Motor6D; o cliente gira
				-- (Motor6D.Transform) enquanto a pessoa perfura. O eixo é o da ferramenta (Z do Handle)
				-- passando pela ponta (Muzzle).
				if d.Name:match("_Gira$") and muzzle and muzzle:IsA("BasePart") then
					d.Anchored = false
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
					d.Massless = true
					local axis = handle.CFrame:PointToObjectSpace(muzzle.Position)
					local c0 = CFrame.new(axis.X, axis.Y, 0)
					local motor = Instance.new("Motor6D")
					motor.Name = "GiraCabeca"
					motor.Part0 = handle
					motor.Part1 = d
					motor.C0 = c0
					motor.C1 = handle.CFrame:ToObjectSpace(d.CFrame):Inverse() * c0
					motor.Parent = handle
				else
					weldTo(handle, d)
				end
			end
		end
		m.Parent = handle.Parent
	else
		-- sem modelo: corpo simples
		local body = plainPart(handle.Parent, "Corpo", Vector3.new(0.25, 0.35, length), handle.CFrame * CFrame.new(0, 0.15, -length / 2 + 0.3), Color3.fromRGB(40, 40, 44), Enum.Material.Metal)
		weldTo(handle, body)
		local cabo = plainPart(handle.Parent, "Cabo", Vector3.new(0.22, 0.6, 0.3), handle.CFrame * CFrame.new(0, -0.2, 0), Color3.fromRGB(30, 30, 30))
		weldTo(handle, cabo)
		muzzleOffset = Vector3.new(0, 0.15, -length + 0.3)
	end
	return muzzleOffset or Vector3.new(0, 0.1, -length * 0.8)
end

local function toolModel(kind, handle)
	if kind == "taser" then
		local body = plainPart(handle.Parent, "Corpo", Vector3.new(0.3, 0.4, 1.1), handle.CFrame * CFrame.new(0, 0.2, -0.4), Color3.fromRGB(250, 210, 30))
		weldTo(handle, body)
		local tip = plainPart(handle.Parent, "Ponta", Vector3.new(0.28, 0.28, 0.1), handle.CFrame * CFrame.new(0, 0.2, -0.98), Color3.fromRGB(60, 160, 255), Enum.Material.Neon)
		weldTo(handle, tip)
		return Vector3.new(0, 0.2, -1)
	end
	for _, x in ipairs({ -0.35, 0.35 }) do
		local ring = plainPart(handle.Parent, "Aro", Vector3.new(0.12, 0.6, 0.6), handle.CFrame * CFrame.new(x, 0.1, -0.3), Color3.fromRGB(190, 195, 205), Enum.Material.Metal)
		ring.Shape = Enum.PartType.Cylinder
		weldTo(handle, ring)
	end
	local chain = plainPart(handle.Parent, "Corrente", Vector3.new(0.6, 0.08, 0.08), handle.CFrame * CFrame.new(0, 0.1, -0.3), Color3.fromRGB(150, 150, 160), Enum.Material.Metal)
	weldTo(handle, chain)
	return Vector3.new(0, 0.1, -0.6)
end

-- Cria a Tool do item (arma, taser ou algema). Devolve nil se o id não existe.
function WeaponService.makeTool(id)
	local def = WeaponService.def(id)
	if not def then
		return nil
	end
	local tool = Instance.new("Tool")
	tool.Name = def.Name
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ToolTip = def.Name
	tool:SetAttribute("ItemId", id)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.2, 0.2, 0.2)
	handle.Transparency = 1
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	handle.Massless = true
	handle.CFrame = CFrame.new(0, 500, 0)
	handle.Parent = tool
	local muzzle
	if def.Kind == "taser" or def.Kind == "algema" then
		muzzle = toolModel(def.Kind, handle)
		tool:SetAttribute("Use", def.Kind)
	elseif def.Kind == "perfuratriz" or def.Kind == "c4" then
		-- Marco 10.30: o modelo segue as mesmas regras das armas (Grip na mão, Muzzle na ponta)
		muzzle = gunModel(def, handle)
		tool:SetAttribute("Use", def.Kind)
		tool.ToolTip = def.Kind == "perfuratriz" and "Perfuratriz: encoste na porta do cofre do banco" or "C4: plante na porta do cofre do banco"
	else
		muzzle = gunModel(def, handle)
		tool:SetAttribute("Use", "gun")
		tool:SetAttribute("Ammo", def.Mag)
		tool:SetAttribute("Mag", def.Mag)
		tool:SetAttribute("Auto", def.Auto == true)
		tool:SetAttribute("Rate", def.Rate)
		tool:SetAttribute("AmmoKind", def.AmmoKind or (def.Kind == "pistola" and "pistola" or "fuzil"))
		tool:SetAttribute("Kind", def.Kind == "pistola" and "pistola" or "fuzil") -- Marco 10.12: pose (WeaponPose)
	end
	local att = Instance.new("Attachment")
	att.Name = "Cano"
	att.Position = muzzle
	att.Parent = handle
	tool.Grip = CFrame.new(0, 0, 0)
	return tool
end

---------------------------------------------------------------------------
-- Tiro
---------------------------------------------------------------------------

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function equippedGun(player)
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	local id = tool and tool:GetAttribute("ItemId")
	local def = id and W.List[id]
	if def then
		return tool, def
	end
	return nil
end

local function playerOfPart(part)
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		local player = Players:GetPlayerFromCharacter(model)
		if player then
			return player, model
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

-- Marco 10.27: a bala que entra no carro pega quem está sentado mais perto da linha do tiro, porque a
-- mira para na lataria e a linha exata quase nunca cruza o boneco
local function carOccupant(car, from, unit, shooterChar)
	local best, bestDist = nil, W.CarHitRadius
	for _, seat in ipairs(car:GetDescendants()) do
		local hum = (seat:IsA("Seat") or seat:IsA("VehicleSeat")) and seat.Occupant
		local char = hum and hum.Parent
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root and char ~= shooterChar then
			local dist = (root.Position - from):Cross(unit).Magnitude
			if dist < bestDist then
				best, bestDist = root, dist
			end
		end
	end
	return best
end

local function fire(player, aim)
	if typeof(aim) ~= "Vector3" or aim ~= aim then
		return
	end
	local tool, def = equippedGun(player)
	local character, humanoid, root = SecurityService.getLivingCharacter(player)
	if not tool or not root or tool:GetAttribute("Reloading") then
		return
	end
	if player:GetAttribute("Algemado") or player:GetAttribute("Atordoado") or humanoid.PlatformStand then
		return
	end
	local now = os.clock()
	if lastShot[player] and now - lastShot[player] < def.Rate * 0.8 then
		return
	end
	local ammo = tool:GetAttribute("Ammo") or 0
	if ammo <= 0 then
		return
	end
	lastShot[player] = now
	tool:SetAttribute("Ammo", ammo - 1)
	local att = tool.Handle:FindFirstChild("Cano")
	local from = att and att.WorldPosition or root.Position
	if (from - root.Position).Magnitude > 8 then
		from = root.Position + Vector3.new(0, 1.5, 0)
	end
	local dir = aim - from
	if dir.Magnitude < 0.1 then
		return
	end
	for _, fn in ipairs(shotListeners) do
		task.spawn(fn, player, from, dir.Unit)
	end
	local unit = dir.Unit
	dir = unit * W.Range
	local ignore = { character }
	local npcs = Workspace:FindFirstChild("NPCs")
	if npcs then
		table.insert(ignore, npcs)
	end
	-- carros não seguram a bala: ela atravessa a lataria (o carro de quem atira também) e
	-- acerta quem está dentro com metade do dano (WeaponService.CarArmor)
	local vehicles = Workspace:FindFirstChild("Vehicles")
	local hit, occupant
	for _ = 1, 6 do
		rayParams.FilterDescendantsInstances = ignore
		hit = Workspace:Raycast(from, dir, rayParams)
		local car = hit and vehicles and hit.Instance:IsDescendantOf(vehicles) and hit.Instance
		if not car then
			break
		end
		while car.Parent ~= vehicles do
			car = car.Parent
		end
		-- dentro do próprio carro não pega o colega só por passar perto
		if not (humanoid.SeatPart and humanoid.SeatPart:IsDescendantOf(car)) then
			occupant = carOccupant(car, from, unit, character)
			if occupant then
				break
			end
		end
		table.insert(ignore, car)
	end
	local to = occupant and occupant.Position or (hit and hit.Position) or (from + dir)
	-- traçado e som para todo mundo (o cliente desenha)
	uiUpdate:FireAllClients("Shot", { from = from, to = to, by = player.UserId })
	local target = occupant or (hit and hit.Instance)
	if not target then
		return
	end
	local victim, vChar = playerOfPart(target)
	if not victim or victim == player then
		return
	end
	-- Marco 10.17: a PM atira em qualquer um (como já era fora das zonas seguras); e em PROCURADO
	-- atira até dentro da zona segura (praça, empregos), para o bandido não se esconder lá
	local copOnWanted = player:GetAttribute("Job") == "Policial" and (victim:GetAttribute("Procurado") or 0) > 0 and not victim:GetAttribute("Preso") and not player:GetAttribute("Preso")
	if not copOnWanted and (WeaponService.isSafe(player) or WeaponService.isSafe(victim)) then
		if WeaponService.isSafe(player) then
			uiUpdate:FireClient(player, "Notice", { text = "Zona segura: aqui o tiro não pega." })
		end
		return
	end
	local vHum = vChar:FindFirstChildOfClass("Humanoid")
	if not vHum or vHum.Health <= 0 then
		return
	end
	local dmg = def.Damage
	if target.Name == "Head" then
		dmg *= 1.5
	end
	local seat = vHum.SeatPart
	if seat and vehicles and seat:IsDescendantOf(vehicles) then
		dmg *= W.CarArmor -- a lataria segura parte do tiro
	end
	if victim:GetAttribute("Job") == "Policial" then
		dmg *= W.PoliceArmor -- o colete da PM
	end
	lastHit[victim] = { by = player, t = now }
	vHum:TakeDamage(dmg)
	uiUpdate:FireClient(player, "HitMark", { dmg = math.floor(dmg) })
end

---------------------------------------------------------------------------
-- Munição guardada (Marco 10.6): data.ammo = { pistola = n, fuzil = n }. O atributo
-- "Municao_pistola" / "Municao_fuzil" no jogador mostra a reserva na tela.
---------------------------------------------------------------------------

local function ammoKind(def)
	return def.AmmoKind or (def.Kind == "pistola" and "pistola" or "fuzil")
end

function WeaponService.ammoOf(player, kind)
	local data = PlayerDataService.get(player)
	local a = data and type(data.ammo) == "table" and data.ammo[kind]
	return type(a) == "number" and math.max(0, math.floor(a)) or 0
end

local function setAmmo(player, kind, n)
	local data = PlayerDataService.get(player)
	if not data then
		return
	end
	local ammo = type(data.ammo) == "table" and data.ammo or {}
	ammo[kind] = math.clamp(math.floor(n), 0, W.MaxAmmo)
	PlayerDataService.set(player, "ammo", ammo)
	player:SetAttribute("Municao_" .. kind, ammo[kind])
end

-- Compra (GangService): soma munição. Devolve false se já está no máximo.
function WeaponService.addAmmo(player, kind, n)
	local have = WeaponService.ammoOf(player, kind)
	if have >= W.MaxAmmo then
		return false
	end
	setAmmo(player, kind, have + n)
	return true
end

-- Revista da PM: tira toda a munição de um tipo
function WeaponService.takeAmmo(player, kind)
	local have = WeaponService.ammoOf(player, kind)
	setAmmo(player, kind, 0)
	return have
end

local function reload(player)
	local tool, def = equippedGun(player)
	if not tool or tool:GetAttribute("Reloading") or (tool:GetAttribute("Ammo") or 0) >= def.Mag then
		return
	end
	local need = def.Mag - (tool:GetAttribute("Ammo") or 0)
	local take = need
	if not tool:GetAttribute("Servico") then
		local kind = ammoKind(def)
		take = math.min(need, WeaponService.ammoOf(player, kind))
		if take <= 0 then
			local a = W.Ammo[kind]
			uiUpdate:FireClient(player, "Notice", { text = ("Sem munição! Compre %s com o chefe da gangue."):format(a and a.Name or "balas") })
			return
		end
		setAmmo(player, kind, WeaponService.ammoOf(player, kind) - take)
	end
	tool:SetAttribute("Reloading", true)
	task.delay(W.ReloadTime, function()
		if tool.Parent then
			tool:SetAttribute("Ammo", math.min(def.Mag, (tool:GetAttribute("Ammo") or 0) + take))
			tool:SetAttribute("Reloading", nil)
		end
	end)
end

local function onRequest(player, action, arg)
	if not SecurityService.isShortString(action, 12) then
		return
	end
	if action == "Fire" then
		fire(player, arg)
	elseif action == "Mira" then
		-- Marco 10.12: para onde o braço aponta (todo mundo vê a pose) e se está mirando (zoom)
		if type(arg) ~= "table" or not SecurityService.checkRate(player, "Mira", 0.08) then
			return
		end
		local character = player.Character
		if not character then
			return
		end
		local pitch = tonumber(arg.p)
		if pitch and pitch == pitch then
			character:SetAttribute("MiraPitch", math.floor(math.clamp(pitch, -75, 75) + 0.5))
		end
		character:SetAttribute("Mirando", arg.a == true or nil)
		if typeof(arg.d) == "Vector3" and arg.d == arg.d and arg.d.Magnitude > 0.5 then
			aimDir[player] = arg.d.Unit
		end
	elseif action == "Reload" and SecurityService.checkRate(player, "Reload", 0.5) then
		reload(player)
	end
end

-- Marco 10.15: quem "morre" agora fica CAÍDO (DownedService). A queda conta como a antiga morte
-- para as regras do crime (procurado, preso pela PM). Roda os ouvintes na hora (sem task.spawn),
-- para o DownedService saber logo depois se a pessoa foi presa.
function WeaponService.reportDown(player)
	local h = lastHit[player]
	lastHit[player] = nil
	if h and os.clock() - h.t <= W.KillMemory and h.by.Parent then
		for _, fn in ipairs(killListeners) do
			local ok, err = pcall(fn, h.by, player)
			if not ok then
				warn("[WeaponService] " .. tostring(err))
			end
		end
	end
end

local function watch(player)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid then
			return
		end
		humanoid.Died:Connect(function()
			WeaponService.reportDown(player)
		end)
	end)
end

function WeaponService.init(remotes)
	uiUpdate = remotes[GameConfig.Remotes.UIUpdate]
	remotes[GameConfig.Remotes.WeaponRequest].OnServerEvent:Connect(onRequest)
	Players.PlayerAdded:Connect(watch)
	for _, p in ipairs(Players:GetPlayers()) do
		watch(p)
	end
	PlayerDataService.onLoaded(function(player)
		for kind in pairs(W.Ammo) do
			player:SetAttribute("Municao_" .. kind, WeaponService.ammoOf(player, kind))
		end
	end)
	-- ícone de verdade das armas na mochila (Marco 10.6): uma cópia dos modelos para o cliente
	local src = ServerStorage:FindFirstChild("WeaponModels")
	if src and not ReplicatedStorage:FindFirstChild("ArmaIcones") then
		local copy = src:Clone()
		copy.Name = "ArmaIcones"
		for _, d in ipairs(copy:GetDescendants()) do
			if d:IsA("Script") or d:IsA("LocalScript") then
				d:Destroy()
			elseif d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
			end
		end
		copy.Parent = ReplicatedStorage
	end
	Players.PlayerRemoving:Connect(function(player)
		lastHit[player] = nil
		lastShot[player] = nil
		aimDir[player] = nil
	end)
	local folder = ServerStorage:FindFirstChild("WeaponModels")
	local found, total = 0, 0
	for _, def in pairs(W.List) do
		total += 1
		if folder and folder:FindFirstChild(def.Model) then
			found += 1
		end
	end
	print(("[WeaponService] %d de %d modelos de arma em ServerStorage > WeaponModels."):format(found, total))
end

return WeaponService
