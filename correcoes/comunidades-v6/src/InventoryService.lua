-- InventoryService (ModuleScript)
-- Caminho: ServerScriptService > Services > InventoryService
-- Marco 10.5: mochila do jogador (GameConfig.Inventory).
--   * Espaços 1 e 2 = atalhos que aparecem no HUD (teclas 1 e 2). Espaços 3 a 14 = a mochila.
--   * Fica salvo (data.inventory): só as armas compradas. Itens do emprego (taser, algema e as
--     armas da PM) e coisas soltas (o refri do bar) ocupam espaço mas não ficam salvos.
--   * Baú: o guarda-roupa ("Armario") da casa moderna para cima guarda 50 itens e o baú medieval
--     ("Bau", casas padrão, Marco 10.7) guarda 20 (data.chest, o mesmo para os dois). Só o dono
--     abre, de dentro da casa.
--   * As ferramentas (Tool) ficam na Backpack do Roblox (a mochila padrão do Roblox some: o
--     cliente desenha a nossa). Renasceu: o servidor monta tudo de novo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local SecurityService = require(script.Parent:WaitForChild("SecurityService"))
local WeaponService = require(script.Parent:WaitForChild("WeaponService"))

local InventoryService = {}

local INV = GameConfig.Inventory
local TOTAL = INV.Hotbar + INV.Backpack
local uiUpdate
local inv = {} -- inv[player] = { slots = { [i] = { id, temp, job, tool } }, job = { ids } }
local chestOpen = {} -- chestOpen[player] = parte do guarda-roupa aberto
local chestSpec = {} -- chestSpec[player] = GameConfig.Inventory.Chests[...] do baú aberto (Marco 10.7)
local chestModel = {} -- chestModel[player] = móvel aberto (para fechar a tampa do baú)

local function notice(player, text)
	uiUpdate:FireClient(player, "Notice", { text = text })
end

local function state(player)
	local s = inv[player]
	if not s then
		s = { slots = {}, job = {} }
		inv[player] = s
	end
	return s
end

local function itemInfo(item)
	local def = WeaponService.def(item.id)
	return {
		id = item.id,
		name = def and def.Name or item.name or item.id,
		icon = def and def.Icon or item.icon or "📦",
		temp = item.temp == true,
		weapon = def ~= nil and GameConfig.Weapons.List[item.id] ~= nil,
	}
end

local function save(player)
	local s = inv[player]
	if not s then
		return
	end
	local out = {}
	for i = 1, TOTAL do
		local it = s.slots[i]
		if it and not it.temp then
			out[tostring(i)] = it.id
		end
	end
	PlayerDataService.set(player, "inventory", out)
end

local function publish(player)
	local s = inv[player]
	if not s or not player.Parent then
		return
	end
	local list = {}
	for i = 1, TOTAL do
		local it = s.slots[i]
		list[tostring(i)] = it and itemInfo(it) or nil
	end
	uiUpdate:FireClient(player, "Inventory", { slots = list, hotbar = INV.Hotbar, total = TOTAL })
end

local function freeSlot(s, preferHotbar)
	if preferHotbar then
		for i = 1, INV.Hotbar do
			if not s.slots[i] then
				return i
			end
		end
	end
	for i = INV.Hotbar + 1, TOTAL do
		if not s.slots[i] then
			return i
		end
	end
	for i = 1, INV.Hotbar do
		if not s.slots[i] then
			return i
		end
	end
	return nil
end

local function destroyTool(it)
	if it.tool then
		local t = it.tool
		it.tool = nil
		if t.Parent then
			t:Destroy()
		end
	end
end

-- Põe a Tool do item na Backpack (marcando o espaço)
local function giveTool(player, i, it)
	destroyTool(it)
	if it.loose then
		return -- ferramenta solta: já existe (é a própria it.looseTool)
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	local tool = WeaponService.makeTool(it.id)
	if not tool or not backpack then
		return
	end
	tool:SetAttribute("Slot", i)
	if it.job then
		tool:SetAttribute("Servico", true) -- Marco 10.6: arma do emprego tem munição à vontade
	end
	tool.Parent = backpack
	it.tool = tool
	-- Marco 10.23: a arma nunca some de vez. destroyTool zera it.tool antes de apagar; se ela sumiu
	-- sem isso (caiu do mapa), volta para a mochila no mesmo espaço e com as mesmas balas.
	tool.AncestryChanged:Connect(function(_, parent)
		if parent ~= nil or it.tool ~= tool then
			return
		end
		task.delay(0.5, function()
			local s = inv[player]
			if it.tool ~= tool or not s or not player.Parent then
				return
			end
			for slot, other in pairs(s.slots) do
				if other == it then
					giveTool(player, slot, it)
					if it.tool then
						it.tool:SetAttribute("Ammo", tool:GetAttribute("Ammo"))
					end
					publish(player)
					break
				end
			end
		end)
	end)
end

-- Marco 10.23: rede de segurança da troca de arma. Sem o encaixe (RightGrip) no servidor a arma cai
-- e é apagada; então ela volta para a mochila e é puxada de novo, uma vez. Se ainda não pegar, fica
-- guardada, e o jogador puxa de novo pelo espaço.
local function hasGrip(character, tool)
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	local grip = hand and hand:FindFirstChild("RightGrip")
	return grip ~= nil and grip.Part1 == tool:FindFirstChild("Handle")
end

local function watchGrip(player, character)
	character.ChildAdded:Connect(function(tool)
		if not tool:IsA("Tool") or not tool:FindFirstChild("Handle") then
			return
		end
		task.wait(0.3)
		if tool.Parent ~= character or hasGrip(character, tool) then
			return
		end
		local backpack = player:FindFirstChildOfClass("Backpack")
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not backpack or not humanoid then
			return
		end
		tool.Parent = backpack
		if tool:GetAttribute("GripRetry") then
			tool:SetAttribute("GripRetry", nil)
			return
		end
		tool:SetAttribute("GripRetry", true)
		task.wait(0.25)
		if tool.Parent == backpack and humanoid.Health > 0 and not character:FindFirstChildOfClass("Tool") then
			humanoid:EquipTool(tool)
			task.delay(1, function()
				tool:SetAttribute("GripRetry", nil)
			end)
		end
	end)
end

local function setSlotAttr(it, i)
	local t = it.loose and it.looseTool or it.tool
	if t then
		t:SetAttribute("Slot", i)
	end
end

-- Coloca um item num espaço livre. Devolve o espaço ou nil (mochila cheia).
local function addItem(player, id, opts)
	opts = opts or {}
	local s = state(player)
	local i = freeSlot(s, opts.hotbar)
	if not i then
		return nil
	end
	local it = { id = id, temp = opts.temp, job = opts.job }
	s.slots[i] = it
	giveTool(player, i, it)
	if not it.temp then
		save(player)
	end
	publish(player)
	return i
end

function InventoryService.hasRoom(player)
	return freeSlot(state(player)) ~= nil
end

-- Marco 10.30: itens do assalto (Perfuratriz = temporária; C4 = fica salva)
function InventoryService.addItem(player, id, opts)
	if not WeaponService.def(id) then
		return nil
	end
	return addItem(player, id, opts)
end

function InventoryService.count(player, id)
	local n = 0
	for _, it in pairs(state(player).slots) do
		if it.id == id then
			n += 1
		end
	end
	return n
end

-- tira UM item com esse id (o que não está na mão primeiro). Devolve true se tirou.
function InventoryService.removeOne(player, id)
	local s = state(player)
	local best
	for i = 1, TOTAL do
		local it = s.slots[i]
		if it and it.id == id then
			local inHand = it.tool and player.Character and it.tool.Parent == player.Character
			if not best or (best.hand and not inHand) then
				best = { i = i, it = it, hand = inHand }
			end
		end
	end
	if not best then
		return false
	end
	destroyTool(best.it)
	s.slots[best.i] = nil
	if not best.it.temp then
		save(player)
	end
	publish(player)
	return true
end

-- a Tool desse item que está na mão (ou nil)
function InventoryService.toolInHand(player, id)
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	if tool and tool:GetAttribute("ItemId") == id then
		return tool
	end
	return nil
end

-- põe na mão a Tool desse item (se tiver)
function InventoryService.equip(player, id)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local inHand = InventoryService.toolInHand(player, id)
	if inHand then
		return inHand
	end
	for _, it in pairs(state(player).slots) do
		if it.id == id and it.tool and it.tool.Parent then
			humanoid:EquipTool(it.tool)
			return it.tool
		end
	end
	return nil
end

-- Compra / prêmio: arma salva na mochila
function InventoryService.addWeapon(player, id)
	if not GameConfig.Weapons.List[id] then
		return false
	end
	return addItem(player, id, { hotbar = true }) ~= nil
end

function InventoryService.has(player, id)
	for _, it in pairs(state(player).slots) do
		if it.id == id then
			return true
		end
	end
	return false
end

-- Itens do emprego (a lista inteira; {} = tira todos)
function InventoryService.setJobItems(player, ids)
	local s = state(player)
	for i = 1, TOTAL do
		local it = s.slots[i]
		if it and it.job then
			destroyTool(it)
			s.slots[i] = nil
		end
	end
	s.job = {}
	for _, id in ipairs(ids) do
		if addItem(player, id, { temp = true, job = true, hotbar = true }) then
			table.insert(s.job, id)
		else
			notice(player, "Mochila cheia: não coube " .. ((WeaponService.def(id) or {}).Name or id) .. ".")
		end
	end
	publish(player)
end

function InventoryService.addJobItem(player, id)
	local s = state(player)
	for _, it in pairs(s.slots) do
		if it.id == id and it.job then
			return notice(player, "Você já pegou.")
		end
	end
	if addItem(player, id, { temp = true, job = true, hotbar = true }) then
		table.insert(s.job, id)
		notice(player, ((WeaponService.def(id) or {}).Name or id) .. " na mochila.")
	else
		notice(player, "Mochila cheia!")
	end
end

-- Preso: perde as armas que carregava (as do baú ficam). PROVISÓRIO.
function InventoryService.confiscate(player)
	local s = state(player)
	local lost = 0
	for i = 1, TOTAL do
		local it = s.slots[i]
		if it and (GameConfig.Weapons.List[it.id] or (WeaponService.def(it.id) or {}).Illegal) and not it.job then
			destroyTool(it)
			s.slots[i] = nil
			lost += 1
		end
	end
	if lost > 0 then
		save(player)
		publish(player)
		notice(player, ("A polícia apreendeu %d item(ns) proibido(s) da sua mochila."):format(lost))
	end
end

-- Marco 10.15: desistiu caído = renasce na praça SEM os itens (tudo da mochila que não é do emprego)
function InventoryService.loseAll(player)
	local s = state(player)
	local lost = 0
	for i = 1, TOTAL do
		local it = s.slots[i]
		if it and not it.job then
			destroyTool(it)
			s.slots[i] = nil
			lost += 1
		end
	end
	if lost > 0 then
		save(player)
		publish(player)
	end
	return lost
end

-- Marco 10.6: revista da PM. Proibido = arma que não é do emprego, ou item da lista Crime.Illegal.
local function isIllegal(it)
	if it.job then
		return false
	end
	return GameConfig.Weapons.List[it.id] ~= nil or GameConfig.Crime.Illegal[it.id] == true or (WeaponService.def(it.id) or {}).Illegal == true
end

-- O que a pessoa tem na mochila (para o painel do policial)
function InventoryService.listItems(player)
	local s = state(player)
	local out = {}
	for i = 1, TOTAL do
		local it = s.slots[i]
		if it then
			local info = itemInfo(it)
			info.slot = i
			info.illegal = isIllegal(it)
			table.insert(out, info)
		end
	end
	return out
end

-- Apreende um item proibido. Devolve o nome do item (ou nil se não pode).
function InventoryService.seize(player, i)
	local s = state(player)
	local it = type(i) == "number" and s.slots[i]
	if not it or not isIllegal(it) then
		return nil
	end
	local name = itemInfo(it).name
	destroyTool(it)
	s.slots[i] = nil
	save(player)
	publish(player)
	return name
end

-- Ferramenta que outro serviço colocou na Backpack (ex.: refri): ganha um espaço temporário
local function adoptLoose(player, tool)
	if not tool:IsA("Tool") or tool:GetAttribute("ItemId") or tool:GetAttribute("Adopted") then
		return
	end
	tool:SetAttribute("Adopted", true)
	local s = state(player)
	local i = freeSlot(s, true)
	if not i then
		notice(player, "Mochila cheia!")
		tool:Destroy()
		return
	end
	local it = { id = tool.Name, name = tool.Name, icon = tool.Name == "Refri" and "🥤" or "📦", temp = true, loose = true, looseTool = tool }
	s.slots[i] = it
	tool:SetAttribute("Slot", i)
	tool.AncestryChanged:Connect(function()
		if not tool:IsDescendantOf(player) and not (player.Character and tool:IsDescendantOf(player.Character)) then
			for k, other in pairs(s.slots) do
				if other == it then
					s.slots[k] = nil
					publish(player)
				end
			end
		end
	end)
	publish(player)
end

local function rebuild(player)
	local s = state(player)
	for i = 1, TOTAL do
		local it = s.slots[i]
		if it then
			if it.loose then
				s.slots[i] = nil -- o que era solto se perdeu
			else
				giveTool(player, i, it)
			end
		end
	end
	publish(player)
end

---------------------------------------------------------------------------
-- Baú (guarda-roupa das casas maiores)
---------------------------------------------------------------------------

local function chestOf(player)
	local data = PlayerDataService.get(player)
	local c = data and data.chest
	if type(c) ~= "table" then
		c = {}
	end
	return c
end

-- Marco 10.7: o baú pequeno (20) só guarda nos primeiros espaços, mas mostra o que estiver depois
-- (guardado no guarda-roupa de outra casa) para dar para pegar de volta.
local function chestSize(player)
	local spec = chestSpec[player]
	return spec and spec.Size or INV.Chest
end

local function chestPayload(player)
	local c = chestOf(player)
	local list = {}
	local total = chestSize(player)
	for i = 1, INV.Chest do
		local id = c[tostring(i)]
		if id then
			list[tostring(i)] = itemInfo({ id = id })
			total = math.max(total, i)
		end
	end
	local spec = chestSpec[player]
	return { slots = list, total = total, size = chestSize(player), label = spec and spec.Label or "Baú" }
end

-- Tampa do baú medieval: gira as peças "Lid" na dobradiça ("PivotLid")
-- Marco 10.18: porta do armário (cofre antigo): gira as peças "Door" em pé, em volta da "PivotDoor"
local LID_ANGLE = math.rad(100)
local lidState = {} -- lidState[model] = { closed = { [part] = CFrame }, open = bool }

local function setLid(model, open)
	local pivot = model and model.Parent and (model:FindFirstChild("PivotLid") or model:FindFirstChild("PivotDoor"))
	if not pivot then
		return
	end
	local door = pivot.Name == "PivotDoor"
	local moving = door and "Door" or "Lid"
	local st = lidState[model]
	if not st then
		st = { closed = {}, open = false }
		lidState[model] = st
		model.Destroying:Connect(function()
			lidState[model] = nil
		end)
	end
	if st.open == open then
		return
	end
	if open then -- guarda a tampa fechada agora (o móvel pode ter mudado de lugar)
		st.closed = {}
		for _, p in ipairs(model:GetChildren()) do
			if p:IsA("BasePart") and p.Name == moving then
				st.closed[p] = p.CFrame
			end
		end
	end
	st.open = open
	local rot = model:GetPivot().Rotation
	local hinge = CFrame.new(pivot.Position) * rot
	local sign = 1 -- a porta abre para a frente (-Z do móvel), para o lado oposto da dobradiça
	if door then
		local sum, n = Vector3.zero, 0
		for _, cf in pairs(st.closed) do
			sum += cf.Position
			n += 1
		end
		if n > 0 and hinge:PointToObjectSpace(sum / n).X < 0 then
			sign = -1
		end
	end
	task.spawn(function()
		for step = 1, 10 do
			if st.open ~= open or not model.Parent then
				return
			end
			local t = open and step / 10 or 1 - step / 10
			local turn = door and CFrame.Angles(0, sign * LID_ANGLE * t, 0) or CFrame.Angles(LID_ANGLE * t, 0, 0)
			local move = hinge * turn * hinge:Inverse()
			for p, cf in pairs(st.closed) do
				if p.Parent then
					p.CFrame = move * cf
				end
			end
			task.wait(0.03)
		end
	end)
end

local function closeChest(player)
	local model = chestModel[player]
	chestOpen[player] = nil
	chestSpec[player] = nil
	chestModel[player] = nil
	if model then
		for _, other in pairs(chestModel) do
			if other == model then
				return
			end
		end
		setLid(model, false)
	end
end

local function nearChest(player)
	local part = chestOpen[player]
	local _, _, root = SecurityService.getLivingCharacter(player)
	return part and part.Parent and root and (root.Position - part.Position).Magnitude <= 14
end

local function putInChest(player, slot)
	local s = state(player)
	local it = s.slots[slot]
	if not it or not nearChest(player) then
		return
	end
	if it.temp then
		return notice(player, "Esse item não pode ser guardado.")
	end
	local c = chestOf(player)
	for i = 1, chestSize(player) do
		if not c[tostring(i)] then
			c[tostring(i)] = it.id
			destroyTool(it)
			s.slots[slot] = nil
			PlayerDataService.set(player, "chest", c)
			save(player)
			publish(player)
			uiUpdate:FireClient(player, "Chest", chestPayload(player))
			return
		end
	end
	notice(player, "O baú está cheio!")
end

local function takeFromChest(player, index)
	if type(index) ~= "number" or not nearChest(player) then
		return
	end
	local c = chestOf(player)
	local key = tostring(math.floor(index))
	local id = c[key]
	if not id then
		return
	end
	local s = state(player)
	local i = freeSlot(s, false)
	if not i then
		return notice(player, "A mochila está cheia!")
	end
	c[key] = nil
	PlayerDataService.set(player, "chest", c)
	s.slots[i] = { id = id }
	giveTool(player, i, s.slots[i])
	save(player)
	publish(player)
	uiUpdate:FireClient(player, "Chest", chestPayload(player))
end

local function setupWardrobe(model)
	local spec = INV.Chests[model:GetAttribute("ItemId") or ""]
	if not spec or model:FindFirstChild("BauPrompt", true) then
		return
	end
	local interior = model:FindFirstAncestorOfClass("Model")
	while interior and not interior:GetAttribute("Tier") do
		interior = interior:FindFirstAncestorOfClass("Model")
	end
	if not interior or not spec.Tiers[interior:GetAttribute("Tier")] then
		return
	end
	local body = model:FindFirstChild("Body") or model:FindFirstChildWhichIsA("BasePart")
	if not body then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BauPrompt"
	prompt.ActionText = "Abrir o baú"
	prompt.ObjectText = spec.Label
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = body
	prompt.Triggered:Connect(function(player)
		if not SecurityService.checkRate(player, "Bau", 0.5) then
			return
		end
		if interior:GetAttribute("Owner") ~= player.UserId then
			return notice(player, "Só o dono abre o baú.")
		end
		chestOpen[player] = body
		chestSpec[player] = spec
		chestModel[player] = model
		setLid(model, true)
		uiUpdate:FireClient(player, "Chest", chestPayload(player))
	end)
end

---------------------------------------------------------------------------

local function swap(player, a, b)
	if type(a) ~= "number" or type(b) ~= "number" then
		return
	end
	a, b = math.floor(a), math.floor(b)
	if a < 1 or b < 1 or a > TOTAL or b > TOTAL or a == b then
		return
	end
	local s = state(player)
	s.slots[a], s.slots[b] = s.slots[b], s.slots[a]
	if s.slots[a] then
		setSlotAttr(s.slots[a], a)
	end
	if s.slots[b] then
		setSlotAttr(s.slots[b], b)
	end
	save(player)
	publish(player)
end

local function onRequest(player, action, a, b)
	if not SecurityService.checkRate(player, "Inventory", 0.15) or not SecurityService.isShortString(action, 12) then
		return
	end
	if action == "Swap" then
		swap(player, a, b)
	elseif action == "ChestPut" and type(a) == "number" then
		putInChest(player, math.floor(a))
	elseif action == "ChestTake" then
		takeFromChest(player, a)
	elseif action == "ChestClose" then
		closeChest(player)
	elseif action == "Sync" then
		publish(player)
	elseif action == "Equip" and type(a) == "number" then
		-- Marco 10.20: o cliente pediu e não conseguiu equipar sozinho: o servidor equipa
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 or player:GetAttribute("Caido") or player:GetAttribute("Algemado") then
			return
		end
		local held = character:FindFirstChildOfClass("Tool")
		if b == false then
			if held and held:GetAttribute("Slot") == a then
				humanoid:UnequipTools()
			end
			return
		end
		if held and held:GetAttribute("Slot") == a then
			return
		end
		local backpack = player:FindFirstChildOfClass("Backpack")
		for _, t in ipairs(backpack and backpack:GetChildren() or {}) do
			if t:IsA("Tool") and t:GetAttribute("Slot") == a then
				if held then -- Marco 10.23: a troca direta deixa a arma nova sem encaixe (veja watchGrip)
					humanoid:UnequipTools()
					task.wait(0.15)
				end
				humanoid:EquipTool(t)
				break
			end
		end
	end
end

function InventoryService.init(remotes)
	uiUpdate = remotes[GameConfig.Remotes.UIUpdate]
	remotes[GameConfig.Remotes.InventoryRequest].OnServerEvent:Connect(onRequest)

	PlayerDataService.onLoaded(function(player, data)
		local s = state(player)
		local saved = type(data.inventory) == "table" and data.inventory or {}
		for i = 1, TOTAL do
			local id = saved[tostring(i)]
			if type(id) == "string" and WeaponService.savable(id) then -- Marco 10.30: + a C4
				local at = s.slots[i] and freeSlot(s, false) or i -- o espaço já tem item do emprego
				if at then
					s.slots[at] = { id = id }
				end
			end
		end
		rebuild(player)
	end)

	local function watch(player)
		if player.Character then
			watchGrip(player, player.Character)
		end
		player.CharacterAdded:Connect(function(character)
			watchGrip(player, character)
			local backpack = player:WaitForChild("Backpack", 10)
			if not backpack then
				return
			end
			task.wait(0.1)
			rebuild(player)
			backpack.ChildAdded:Connect(function(child)
				task.defer(adoptLoose, player, child)
			end)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, p in ipairs(Players:GetPlayers()) do
		watch(p)
		if p.Character then
			local backpack = p:FindFirstChildOfClass("Backpack")
			if backpack then
				backpack.ChildAdded:Connect(function(child)
					task.defer(adoptLoose, p, child)
				end)
			end
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		save(player)
		inv[player] = nil
		closeChest(player)
	end)

	-- Marco 10.7: quem se afasta do baú aberto: fecha a tela e a tampa
	task.spawn(function()
		while true do
			task.wait(1)
			local far = {}
			for player in pairs(chestModel) do
				if not nearChest(player) then
					table.insert(far, player)
				end
			end
			for _, player in ipairs(far) do
				closeChest(player)
				if player.Parent then
					uiUpdate:FireClient(player, "Chest", { shut = true })
				end
			end
		end
	end)

	-- guarda-roupas nos interiores das casas (montados quando alguém entra)
	local interiors = Workspace:WaitForChild("Interiores", 30)
	if interiors then
		for _, d in ipairs(interiors:GetDescendants()) do
			if d:IsA("Model") then
				setupWardrobe(d)
			end
		end
		interiors.DescendantAdded:Connect(function(d)
			if d:IsA("Model") then
				task.defer(setupWardrobe, d)
			end
		end)
	end
end

return InventoryService
