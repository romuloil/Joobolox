-- InventoryController (ModuleScript)
-- Caminho: StarterPlayer > StarterPlayerScripts > Controllers > InventoryController
-- Marco 10.5: a nossa mochila (a do Roblox fica escondida).
--   * Embaixo, no meio: 2 atalhos (teclas 1 e 2) e o botão da mochila.
--   * Mochila: 12 espaços. Toque num item e depois em outro espaço para trocar de lugar
--     (vale para os atalhos também). Toque duas vezes para usar.
--   * Baú (guarda-roupa das casas maiores): mochila de um lado, baú do outro. Toque num item
--     para passar de um para o outro.
-- Quem decide é o InventoryService (servidor); o cliente só pede e mostra.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local UIScaler = require(script.Parent:WaitForChild("UIScaler"))

local InventoryController = {}

local INV = GameConfig.Inventory
local HOTBAR, TOTAL = INV.Hotbar, INV.Hotbar + INV.Backpack
local player = Players.LocalPlayer
local request
local gui, hotbarFrame, bagButton, bagPanel, chestPanel, hint
local slots = {} -- slots[i] = info do servidor (id, name, icon, temp, weapon)
local cells = {} -- cells[i] = { buttons } (o mesmo espaço pode aparecer no HUD e na mochila)
local chestSlots, chestCells = {}, {}
local chestInfo -- texto "Baú: 20 espaços" (Marco 10.7: o tamanho depende do baú)
local selected -- espaço escolhido para trocar
local lastTap = { slot = nil, t = 0 }

local NAVY = Color3.fromRGB(24, 32, 58)
local CELL = Color3.fromRGB(40, 52, 88)
local GOLD = Color3.fromRGB(255, 196, 60)
local GREEN = Color3.fromRGB(70, 190, 100)

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

local function stroke(parent, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = props.Size
	l.Position = props.Position or UDim2.new()
	l.AnchorPoint = props.Anchor or Vector2.zero
	l.Font = props.Font or Enum.Font.GothamBold
	l.Text = props.Text or ""
	l.TextColor3 = props.Color or Color3.new(1, 1, 1)
	l.TextScaled = props.Scaled ~= false
	l.TextSize = props.TextSize or 14
	l.TextWrapped = true
	l.ZIndex = props.ZIndex or 2
	l.Parent = parent
	return l
end

---------------------------------------------------------------------------
-- Usar (equipar) e trocar de lugar
---------------------------------------------------------------------------

local function toolInSlot(i)
	local character = player.Character
	for _, holder in ipairs({ player:FindFirstChildOfClass("Backpack"), character }) do
		for _, t in ipairs(holder and holder:GetChildren() or {}) do
			if t:IsA("Tool") and t:GetAttribute("Slot") == i then
				return t
			end
		end
	end
	return nil
end

local function equippedSlot()
	local character = player.Character
	local t = character and character:FindFirstChildOfClass("Tool")
	return t and t:GetAttribute("Slot")
end

local refresh -- definida abaixo
local equipToken = 0

local function equip(i)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local want -- true = quer a arma na mão; false = guardar
	if equippedSlot() == i then
		want = false
		humanoid:UnequipTools()
	else
		local tool = toolInSlot(i)
		if not tool then
			return
		end
		want = true
		-- Marco 10.23: trocar direto de uma arma para outra deixava a nova sem encaixe no servidor:
		-- ela caía pelo mapa e era apagada. Guarda a que está na mão, espera e só então puxa a nova.
		equipToken += 1
		local token = equipToken
		if character:FindFirstChildOfClass("Tool") then
			humanoid:UnequipTools()
			task.wait(0.15)
			if token ~= equipToken or humanoid.Health <= 0 or not tool.Parent then
				return
			end
		end
		humanoid:EquipTool(tool)
	end
	task.delay(0.1, refresh)
	-- Marco 10.20: às vezes o equipar do cliente não pega (a ferramenta acabou de ser recriada pelo
	-- servidor, ou o fuzil ainda estava chegando no aparelho). Se não pegou, o servidor equipa.
	task.delay(0.35, function()
		if (equippedSlot() == i) ~= want then
			request:FireServer("Equip", i, want)
			task.delay(0.3, refresh)
		end
	end)
end

local function tapSlot(i)
	local now = os.clock()
	local double = lastTap.slot == i and now - lastTap.t < 0.4
	lastTap = { slot = i, t = now }
	if selected and selected ~= i then
		request:FireServer("Swap", selected, i)
		selected = nil
		lastTap = { slot = nil, t = 0 }
		refresh()
		return
	end
	if i <= HOTBAR and not (bagPanel and bagPanel.Visible) then
		equip(i) -- no HUD: um toque já usa
		return
	end
	if double and slots[i] then
		selected = nil
		equip(i)
		return
	end
	selected = (selected ~= i and slots[i]) and i or nil
	refresh()
end

---------------------------------------------------------------------------
-- Desenho
---------------------------------------------------------------------------

local function makeCell(parent, i, size, showKey)
	local b = Instance.new("TextButton")
	b.Name = "Slot" .. i
	b.Size = UDim2.fromOffset(size, size)
	b.BackgroundColor3 = CELL
	b.BackgroundTransparency = 0.1
	b.AutoButtonColor = true
	b.Text = ""
	b.LayoutOrder = i
	b.Parent = parent
	corner(b, 12)
	local st = stroke(b, Color3.fromRGB(90, 110, 170), 2)
	local icon = label(b, { Size = UDim2.new(1, -8, 0.55, 0), Position = UDim2.new(0, 4, 0.06, 0), Font = Enum.Font.GothamBlack })
	local name = label(b, { Size = UDim2.new(1, -6, 0.26, 0), Position = UDim2.new(0, 3, 0.66, 0), Color = Color3.fromRGB(220, 228, 255) })
	if showKey then
		local key = label(b, { Text = tostring(i), Size = UDim2.fromOffset(18, 18), Position = UDim2.fromOffset(4, 3), Color = GOLD, Font = Enum.Font.GothamBlack, ZIndex = 3 })
		key.TextXAlignment = Enum.TextXAlignment.Left
	end
	b.Activated:Connect(function()
		tapSlot(i)
	end)
	cells[i] = cells[i] or {}
	table.insert(cells[i], { button = b, stroke = st, icon = icon, name = name })
end

-- Marco 10.6: ícone de verdade da arma (o modelo 3D girando parado num ViewportFrame). Os
-- modelos vêm de ReplicatedStorage > ArmaIcones (o WeaponService copia de ServerStorage).
-- Sem o modelo, fica o emoji de antes.
local function gunViewport(id)
	local def = id and GameConfig.Weapons.List[id]
	local folder = ReplicatedStorage:FindFirstChild("ArmaIcones")
	local src = def and folder and folder:FindFirstChild(def.Model)
	if not src then
		return nil
	end
	local m = src:Clone()
	if not m:IsA("Model") then
		local holder = Instance.new("Model")
		m.Parent = holder
		m = holder
	end
	local grip = m:FindFirstChild("Grip", true)
	local muzzle = m:FindFirstChild("Muzzle", true)
	for _, d in ipairs({ grip, muzzle }) do
		if d and d:IsA("BasePart") then
			d.Transparency = 1
		end
	end
	local box, size = m:GetBoundingBox()
	local axes = { { box.XVector, size.X }, { box.YVector, size.Y }, { box.ZVector, size.Z } }
	table.sort(axes, function(a, b)
		return a[2] > b[2]
	end)
	-- cano para a direita e cabo para baixo (igual ao WeaponService: Grip -> Muzzle)
	local f, u = axes[1][1], axes[2][1]
	if grip and muzzle and grip:IsA("BasePart") and muzzle:IsA("BasePart") then
		local toMuzzle = muzzle.Position - grip.Position
		f = f * (toMuzzle:Dot(f) >= 0 and 1 or -1)
		u = u * (toMuzzle:Dot(u) >= 0 and 1 or -1)
	end
	local look = u:Cross(f)
	local vp = Instance.new("ViewportFrame")
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(200, 200, 205)
	vp.LightColor = Color3.new(1, 1, 1)
	vp.LightDirection = Vector3.new(-0.3, -1, -0.5)
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	local dist = axes[1][2] * 1.75
	cam.CFrame = CFrame.lookAt(box.Position - look * dist, box.Position, u)
	cam.Parent = vp
	vp.CurrentCamera = cam
	m.Parent = vp
	return vp
end

InventoryController.gunViewport = gunViewport -- Marco 10.8: a loja do chefe usa também

local function setGunIcon(c, info)
	local id = info and info.weapon and info.id or nil
	if c.vpId ~= id then
		if c.vp then
			c.vp:Destroy()
			c.vp = nil
		end
		c.vpId = id
		local vp = id and gunViewport(id)
		if vp then
			vp.Size = UDim2.new(1, -4, 0.62, 0)
			vp.Position = UDim2.new(0, 2, 0.04, 0)
			vp.ZIndex = 2
			vp.Parent = c.button
			c.vp = vp
		end
	end
	return c.vp ~= nil
end

local function drawCell(c, info, i, eq)
	c.icon.Text = (not setGunIcon(c, info)) and info and info.icon or ""
	c.name.Text = info and info.name or ""
	c.button.BackgroundColor3 = info and CELL or Color3.fromRGB(30, 38, 64)
	if selected == i then
		c.stroke.Color, c.stroke.Thickness = GOLD, 3
	elseif eq == i and info then
		c.stroke.Color, c.stroke.Thickness = GREEN, 3
	else
		c.stroke.Color, c.stroke.Thickness = Color3.fromRGB(90, 110, 170), 2
	end
end

refresh = function()
	local eq = equippedSlot()
	for i = 1, TOTAL do
		for _, c in ipairs(cells[i] or {}) do
			drawCell(c, slots[i], i, eq)
		end
	end
	for i, c in pairs(chestCells) do
		local info = chestSlots[i]
		c.icon.Text = (not setGunIcon(c, info)) and info and info.icon or ""
		c.name.Text = info and info.name or ""
		c.button.BackgroundColor3 = info and CELL or Color3.fromRGB(30, 38, 64)
	end
	if hint then
		hint.Text = selected and "Agora toque no espaço para onde quer levar." or "Toque num item e depois em outro espaço para trocar. Dois toques: usar."
	end
end

-- Desenho da mochila no botão (feito com frames, sem imagem)
local function drawBag(parent)
	local body = Instance.new("Frame")
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.Position = UDim2.fromScale(0.5, 0.48)
	body.Size = UDim2.fromScale(0.5, 0.5)
	body.BackgroundColor3 = Color3.fromRGB(235, 120, 50)
	body.Parent = parent
	corner(body, 10)
	stroke(body, Color3.fromRGB(120, 55, 20), 2)
	local flap = Instance.new("Frame")
	flap.Size = UDim2.fromScale(1, 0.42)
	flap.BackgroundColor3 = Color3.fromRGB(250, 160, 70)
	flap.Parent = body
	corner(flap, 9)
	local pocket = Instance.new("Frame")
	pocket.AnchorPoint = Vector2.new(0.5, 0)
	pocket.Position = UDim2.fromScale(0.5, 0.56)
	pocket.Size = UDim2.fromScale(0.6, 0.32)
	pocket.BackgroundColor3 = Color3.fromRGB(210, 95, 40)
	pocket.Parent = body
	corner(pocket, 6)
	local buckle = Instance.new("Frame")
	buckle.AnchorPoint = Vector2.new(0.5, 0.5)
	buckle.Position = UDim2.fromScale(0.5, 0.42)
	buckle.Size = UDim2.fromScale(0.18, 0.14)
	buckle.BackgroundColor3 = GOLD
	buckle.Parent = body
	corner(buckle, 3)
	local handle = Instance.new("Frame")
	handle.AnchorPoint = Vector2.new(0.5, 1)
	handle.Position = UDim2.fromScale(0.5, 0.25)
	handle.Size = UDim2.fromScale(0.24, 0.1)
	handle.BackgroundTransparency = 1
	handle.Parent = parent
	stroke(handle, Color3.fromRGB(120, 55, 20), 3)
	corner(handle, 6)
end

local function panelBase(name, w, h, title)
	local p = Instance.new("Frame")
	p.Name = name
	p.AnchorPoint = Vector2.new(0.5, 0.5)
	p.Position = UDim2.fromScale(0.5, 0.48)
	p.Size = UDim2.fromOffset(w, h)
	p.BackgroundColor3 = NAVY
	p.BackgroundTransparency = 0.04
	p.Visible = false
	p.Parent = gui
	corner(p, 18)
	stroke(p, Color3.fromRGB(255, 160, 70), 3)
	UIScaler.attach(p)
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 200, 230))
	grad.Rotation = 90
	grad.Parent = p
	label(p, { Text = title, Size = UDim2.new(1, -90, 0, 34), Position = UDim2.fromOffset(18, 10), Font = Enum.Font.GothamBlack }).TextXAlignment = Enum.TextXAlignment.Left
	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -10, 0, 10)
	close.Size = UDim2.fromOffset(38, 38)
	close.BackgroundColor3 = Color3.fromRGB(210, 60, 60)
	close.Font = Enum.Font.GothamBlack
	close.TextScaled = true
	close.TextColor3 = Color3.new(1, 1, 1)
	close.Text = "X"
	close.Parent = p
	corner(close, 10)
	return p, close
end

local function grid(parent, cols, cell, pos, size)
	local f = Instance.new("ScrollingFrame")
	f.BackgroundTransparency = 1
	f.Position = pos
	f.Size = size
	f.ScrollBarThickness = 6
	f.AutomaticCanvasSize = Enum.AutomaticSize.Y
	f.CanvasSize = UDim2.new()
	f.BorderSizePixel = 0
	f.Parent = parent
	local g = Instance.new("UIGridLayout")
	g.CellSize = UDim2.fromOffset(cell, cell)
	g.CellPadding = UDim2.fromOffset(8, 8)
	g.FillDirectionMaxCells = cols
	g.SortOrder = Enum.SortOrder.LayoutOrder
	g.HorizontalAlignment = Enum.HorizontalAlignment.Center
	g.Parent = f
	return f
end

local function setBag(open)
	bagPanel.Visible = open
	selected = nil
	if open and chestPanel.Visible then
		chestPanel.Visible = false
		request:FireServer("ChestClose")
	end
	TweenService:Create(bagButton, TweenInfo.new(0.15), { Rotation = open and -8 or 0 }):Play()
	refresh()
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "InventoryUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")

	-- HUD: 2 atalhos + botão da mochila
	hotbarFrame = Instance.new("Frame")
	hotbarFrame.Name = "Hotbar"
	hotbarFrame.AnchorPoint = Vector2.new(0.5, 1)
	hotbarFrame.Position = UDim2.new(0.5, 0, 1, -64)
	hotbarFrame.Size = UDim2.fromOffset(3 * 70 + 16, 70)
	hotbarFrame.BackgroundTransparency = 1
	hotbarFrame.Parent = gui
	UIScaler.attach(hotbarFrame)
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.Padding = UDim.new(0, 8)
	row.HorizontalAlignment = Enum.HorizontalAlignment.Center
	row.VerticalAlignment = Enum.VerticalAlignment.Bottom
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Parent = hotbarFrame
	for i = 1, HOTBAR do
		makeCell(hotbarFrame, i, 64, true)
	end
	bagButton = Instance.new("TextButton")
	bagButton.Name = "Mochila"
	bagButton.LayoutOrder = 100
	bagButton.Size = UDim2.fromOffset(70, 70)
	bagButton.BackgroundColor3 = Color3.fromRGB(255, 205, 90)
	bagButton.Text = ""
	bagButton.Parent = hotbarFrame
	corner(bagButton, 18)
	stroke(bagButton, Color3.fromRGB(255, 255, 255), 3)
	local bg = Instance.new("UIGradient")
	bg.Color = ColorSequence.new(Color3.fromRGB(255, 230, 140), Color3.fromRGB(255, 150, 60))
	bg.Rotation = 90
	bg.Parent = bagButton
	drawBag(bagButton)
	label(bagButton, { Text = "Mochila", Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 1, -16), Color = Color3.fromRGB(90, 40, 10), Font = Enum.Font.GothamBlack, ZIndex = 3 })
	-- Marco 10.12b: tecla Q abre/fecha a mochila (letrinha no canto do ícone, como o 1 e o 2)
	if UserInputService.KeyboardEnabled then
		label(bagButton, { Text = "Q", Size = UDim2.fromOffset(14, 14), Position = UDim2.fromOffset(5, 3), Color = Color3.fromRGB(90, 40, 10), Font = Enum.Font.GothamBlack, ZIndex = 3 })
	end
	bagButton.Activated:Connect(function()
		setBag(not bagPanel.Visible)
	end)

	-- Painel da mochila: 12 espaços (4 x 3) + os 2 atalhos em cima
	local close
	bagPanel, close = panelBase("Mochila", 4 * 78 + 60, 420, "🎒 Mochila")
	close.Activated:Connect(function()
		setBag(false)
	end)
	label(bagPanel, { Text = "Atalhos (teclas 1 e 2)", Size = UDim2.new(1, -36, 0, 16), Position = UDim2.fromOffset(18, 50), Color = GOLD }).TextXAlignment = Enum.TextXAlignment.Left
	local top = grid(bagPanel, HOTBAR, 70, UDim2.fromOffset(18, 70), UDim2.new(1, -36, 0, 78))
	for i = 1, HOTBAR do
		makeCell(top, i, 70, true)
	end
	local g = grid(bagPanel, 4, 70, UDim2.fromOffset(18, 152), UDim2.new(1, -36, 0, 3 * 78))
	for i = HOTBAR + 1, TOTAL do
		makeCell(g, i, 70, false)
	end
	hint = label(bagPanel, { Size = UDim2.new(1, -36, 0, 30), Position = UDim2.new(0, 18, 1, -36), Color = Color3.fromRGB(200, 210, 240), Font = Enum.Font.Gotham })

	-- Baú: mochila (esquerda) e baú (direita): 20 espaços no baú medieval, 50 no guarda-roupa
	chestPanel, close = panelBase("Bau", 760, 440, "🧰 Baú")
	close.Activated:Connect(function()
		chestPanel.Visible = false
		request:FireServer("ChestClose")
	end)
	label(chestPanel, { Text = "Sua mochila (toque para guardar)", Size = UDim2.fromOffset(250, 16), Position = UDim2.fromOffset(18, 50), Color = GOLD }).TextXAlignment = Enum.TextXAlignment.Left
	chestInfo = label(chestPanel, { Text = "Baú (toque para pegar)", Size = UDim2.fromOffset(440, 16), Position = UDim2.fromOffset(300, 50), Color = GOLD })
	chestInfo.TextXAlignment = Enum.TextXAlignment.Left
	local mine = grid(chestPanel, 4, 56, UDim2.fromOffset(14, 72), UDim2.fromOffset(270, 350))
	for i = 1, TOTAL do
		local b = Instance.new("TextButton")
		b.Size = UDim2.fromOffset(56, 56)
		b.BackgroundColor3 = CELL
		b.Text = ""
		b.LayoutOrder = i
		b.Parent = mine
		corner(b, 10)
		local st = stroke(b, Color3.fromRGB(90, 110, 170), 2)
		local icon = label(b, { Size = UDim2.new(1, -6, 0.55, 0), Position = UDim2.new(0, 3, 0.05, 0) })
		local name = label(b, { Size = UDim2.new(1, -4, 0.28, 0), Position = UDim2.new(0, 2, 0.66, 0), Color = Color3.fromRGB(220, 228, 255) })
		b.Activated:Connect(function()
			if slots[i] then
				request:FireServer("ChestPut", i)
			end
		end)
		cells[i] = cells[i] or {}
		table.insert(cells[i], { button = b, stroke = st, icon = icon, name = name })
	end
	local chestGrid = grid(chestPanel, 7, 56, UDim2.fromOffset(296, 72), UDim2.fromOffset(450, 350))
	for i = 1, INV.Chest do
		local b = Instance.new("TextButton")
		b.Size = UDim2.fromOffset(56, 56)
		b.BackgroundColor3 = CELL
		b.Text = ""
		b.LayoutOrder = i
		b.Parent = chestGrid
		corner(b, 10)
		stroke(b, Color3.fromRGB(150, 110, 60), 2)
		local icon = label(b, { Size = UDim2.new(1, -6, 0.55, 0), Position = UDim2.new(0, 3, 0.05, 0) })
		local name = label(b, { Size = UDim2.new(1, -4, 0.28, 0), Position = UDim2.new(0, 2, 0.66, 0), Color = Color3.fromRGB(240, 225, 200) })
		b.Activated:Connect(function()
			if chestSlots[i] then
				request:FireServer("ChestTake", i)
			end
		end)
		chestCells[i] = { button = b, icon = icon, name = name }
	end
end

---------------------------------------------------------------------------

function InventoryController.handle(kind, data)
	if kind == "Inventory" then
		slots = {}
		for k, info in pairs(data.slots or {}) do
			local i = tonumber(k)
			if i then
				slots[i] = info
			end
		end
		if selected and not slots[selected] then
			selected = nil
		end
		refresh()
	elseif kind == "Chest" then
		if data.shut then -- Marco 10.7: o servidor fechou (ficou longe do baú)
			chestPanel.Visible = false
			return
		end
		chestSlots = {}
		for k, info in pairs(data.slots or {}) do
			local i = tonumber(k)
			if i then
				chestSlots[i] = info
			end
		end
		bagPanel.Visible = false
		local total = tonumber(data.total) or INV.Chest
		for i, c in pairs(chestCells) do
			c.button.Visible = i <= total
		end
		chestInfo.Text = ("%s: %d espaços (toque para pegar)"):format(tostring(data.label or "Baú"), tonumber(data.size) or total)
		chestPanel.Visible = true
		refresh()
	end
end

local function hideRobloxBackpack()
	for _ = 1, 20 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
		if ok then
			return
		end
		task.wait(0.5)
	end
end

function InventoryController.init()
	request = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(GameConfig.Remotes.InventoryRequest)
	task.spawn(hideRobloxBackpack)
	build()
	refresh()
	local function seatedNow()
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		return hum ~= nil and hum.SeatPart ~= nil
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == Enum.KeyCode.One then
			equip(1)
		elseif input.KeyCode == Enum.KeyCode.Two then
			equip(2)
		elseif input.KeyCode == Enum.KeyCode.Q and bagPanel and not seatedNow() then -- de moto o Q é o grau
			setBag(not bagPanel.Visible) -- Marco 10.12b
		end
	end)
	-- o que está na mão muda (equipar, renascer): redesenha a borda verde
	local function watchCharacter(character)
		character.ChildAdded:Connect(function(c)
			if c:IsA("Tool") then
				refresh()
			end
		end)
		character.ChildRemoved:Connect(function(c)
			if c:IsA("Tool") then
				refresh()
			end
		end)
		refresh()
	end
	if player.Character then
		watchCharacter(player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)
	-- se ficar longe do guarda-roupa, o baú fecha
	task.spawn(function()
		while true do
			task.wait(1)
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if chestPanel.Visible and not root then
				chestPanel.Visible = false
			end
		end
	end)
	task.delay(2, function()
		request:FireServer("Sync")
	end)
end

return InventoryController
