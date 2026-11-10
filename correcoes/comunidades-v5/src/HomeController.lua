-- HomeController (ModuleScript)
-- Caminho: StarterPlayer > StarterPlayerScripts > Controllers > HomeController
-- Marco 6: interface da casa.
--   * Botão redondo com casinha no topo (ao lado do Mapa) abre "Minha casa":
--     endereço, quem pode entrar (Aberta / Só amigos / Trancada),
--     "Expulsar visitantes" e, dentro da sua casa, cor da parede e "Decorar".
--   * Modo Decorar: escolha um móvel na barra de baixo, veja a prévia (verde = cabe,
--     vermelho = não cabe), gire e coloque. Toque/clique num móvel para mover ou vender.
-- O cliente só mostra e PEDE; o servidor (HomeService) confere dono, preço e posição.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local HomeConfig = require(Shared:WaitForChild("HomeConfig"))
local FurnitureArt = require(Shared:WaitForChild("FurnitureArt"))
local UIScaler = require(script.Parent:WaitForChild("UIScaler"))

local HomeController = {}

local player = Players.LocalPlayer
local homeRequest

local info = nil -- último HomeInfo do servidor
local gui, panel, decorBar, actionBar
local refreshPanel -- função que redesenha o painel
local decorating = false
local placing = nil -- { id, u (se for mover), r, x, z, ghost }
local selected = nil -- { model, box }

local DARK = Color3.fromRGB(20, 30, 50)
local GREEN = Color3.fromRGB(60, 170, 80)
local BLUE = Color3.fromRGB(40, 90, 170)
local ORANGE = Color3.fromRGB(230, 130, 40)
local RED = Color3.fromRGB(200, 70, 60)

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or UDim.new(0, 10)
	c.Parent = parent
end

local function button(parent, text, color, size, pos)
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = pos or UDim2.new()
	b.BackgroundColor3 = color
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = text
	b.AutoButtonColor = true
	b.Parent = parent
	corner(b)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 5)
	pad.PaddingBottom = UDim.new(0, 5)
	pad.Parent = b
	return b
end

local function label(parent, text, size, pos, textSize)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = pos
	l.Font = Enum.Font.GothamBold
	l.TextSize = textSize or 16
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Text = text
	l.Parent = parent
	return l
end

---------------------------------------------------------------------------
-- Interior e móveis já colocados (lidos do mundo)
---------------------------------------------------------------------------

local function myInterior()
	local folder = Workspace:FindFirstChild("Interiores")
	-- Marco 10.6: quem tem várias casas pode ter mais de um interior montado (a mansão fica uns
	-- segundos montada depois que a gente sai). Vale o da casa onde a pessoa está agora; antes
	-- pegava o primeiro e, na cobertura, os móveis eram conferidos com os da outra casa.
	local here = player:GetAttribute("InHomeIndex")
	local exact = here and folder and folder:FindFirstChild("Interior_" .. here)
	if exact and exact:GetAttribute("Owner") == player.UserId then
		return exact
	end
	for _, m in ipairs(folder and folder:GetChildren() or {}) do
		if m:GetAttribute("Owner") == player.UserId then
			return m
		end
	end
	return nil
end

local function placedItems(ignoreUid)
	local list = {}
	local interior = myInterior()
	local furniture = interior and interior:FindFirstChild("Moveis")
	if not furniture or not info then
		return list
	end
	for _, m in ipairs(furniture:GetChildren()) do
		local uid = m:GetAttribute("Uid")
		if uid ~= ignoreUid then
			local rel = info.origin:ToObjectSpace(m:GetPivot())
			local _, yaw = rel:ToOrientation()
			table.insert(list, { id = m:GetAttribute("ItemId"), x = rel.X, z = rel.Z, r = math.floor(yaw / (math.pi / 2) + 0.5) % 4 })
		end
	end
	return list
end

local function spotIsValid(id, x, z, r, ignoreUid)
	local def = HomeConfig.item(id)
	if not def or not HomeConfig.insideRoom(def, x, z, r, info and info.tier) then
		return false
	end
	local probe = { id = id, x = x, z = z, r = r }
	for _, other in ipairs(placedItems(ignoreUid)) do
		if HomeConfig.overlaps(probe, other) then
			return false
		end
	end
	return true
end

---------------------------------------------------------------------------
-- Prévia (fantasma) do móvel
---------------------------------------------------------------------------

local function clearSelection()
	if selected then
		selected.box:Destroy()
		selected = nil
	end
end

local function stopPlacing()
	if placing and placing.ghost then
		placing.ghost:Destroy()
	end
	placing = nil
end

local function updateGhost()
	if not placing or not info then
		return
	end
	local ok = spotIsValid(placing.id, placing.x, placing.z, placing.r, placing.u)
	placing.valid = ok
	placing.ghost:PivotTo(FurnitureArt.placement(info.origin, placing.x, placing.z, placing.r))
	for _, p in ipairs(placing.ghost:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Color = ok and Color3.fromRGB(90, 220, 110) or Color3.fromRGB(230, 70, 60)
		end
	end
end

-- Ponto do chão do cômodo embaixo da posição da tela
local function floorPoint(screenPos)
	if not info then
		return nil
	end
	local camera = Workspace.CurrentCamera
	local ray = camera:ViewportPointToRay(screenPos.X, screenPos.Y)
	local y = info.origin.Position.Y
	if math.abs(ray.Direction.Y) < 1e-3 then
		return nil
	end
	local t = (y - ray.Origin.Y) / ray.Direction.Y
	if t <= 0 then
		return nil
	end
	local world = ray.Origin + ray.Direction * t
	local rel = info.origin:PointToObjectSpace(world)
	return math.floor(rel.X * 2 + 0.5) / 2, math.floor(rel.Z * 2 + 0.5) / 2
end

local refreshActions -- declarada abaixo

local function startPlacing(id, uid, r)
	stopPlacing()
	clearSelection()
	local ghost = FurnitureArt.build(id, true)
	if not ghost then
		return
	end
	ghost.Parent = Workspace
	placing = { id = id, u = uid, r = r or 0, x = 0, z = 0, ghost = ghost }
	updateGhost()
	refreshActions()
end

local function confirmPlacing()
	if not placing then
		return
	end
	if not placing.valid then
		return -- vermelho: não manda (o servidor recusaria)
	end
	if placing.u then
		homeRequest:FireServer("Move", { u = placing.u, x = placing.x, z = placing.z, r = placing.r })
	else
		homeRequest:FireServer("Place", { id = placing.id, x = placing.x, z = placing.z, r = placing.r })
	end
	stopPlacing()
	refreshActions()
end

local function selectModel(model)
	clearSelection()
	local box = Instance.new("SelectionBox")
	box.Adornee = model
	box.LineThickness = 0.08
	box.Color3 = Color3.fromRGB(255, 200, 60)
	box.Parent = model
	selected = { model = model, box = box }
	refreshActions()
end

---------------------------------------------------------------------------
-- Barra de decorar (catálogo) e botões de ação
---------------------------------------------------------------------------

local function stopDecorating()
	decorating = false
	stopPlacing()
	clearSelection()
	if decorBar then
		decorBar.Visible = false
		actionBar.Visible = false
	end
end

function refreshActions()
	for _, c in ipairs(actionBar:GetChildren()) do
		if c:IsA("GuiButton") then
			c:Destroy()
		end
	end
	local list = {}
	if placing then
		table.insert(list, { "Girar [R]", BLUE, function()
			placing.r = (placing.r + 1) % 4
			updateGhost()
		end })
		table.insert(list, { "Colocar", GREEN, confirmPlacing })
		table.insert(list, { "Cancelar", RED, function()
			stopPlacing()
			refreshActions()
		end })
	elseif selected then
		local model = selected.model
		local rel = info.origin:ToObjectSpace(model:GetPivot())
		local _, yaw = rel:ToOrientation()
		table.insert(list, { "Mover", BLUE, function()
			local uid, id = model:GetAttribute("Uid"), model:GetAttribute("ItemId")
			startPlacing(id, uid, math.floor(yaw / (math.pi / 2) + 0.5) % 4)
			placing.x, placing.z = math.floor(rel.X * 2 + 0.5) / 2, math.floor(rel.Z * 2 + 0.5) / 2
			updateGhost()
		end })
		table.insert(list, { "Vender", ORANGE, function()
			homeRequest:FireServer("Remove", { u = model:GetAttribute("Uid") })
			clearSelection()
			refreshActions()
		end })
		table.insert(list, { "Voltar", RED, function()
			clearSelection()
			refreshActions()
		end })
	else
		table.insert(list, { "Terminar", RED, stopDecorating })
	end
	for i, entry in ipairs(list) do
		local b = button(actionBar, entry[1], entry[2], UDim2.fromOffset(120, 44))
		b.LayoutOrder = i
		b.Activated:Connect(entry[3])
	end
end

local function buildDecorUI()
	decorBar = Instance.new("ScrollingFrame")
	decorBar.Name = "Catalogo"
	decorBar.AnchorPoint = Vector2.new(0.5, 1)
	decorBar.Position = UDim2.new(0.5, 0, 1, -10)
	decorBar.Size = UDim2.new(0.9, 0, 0, 96)
	decorBar.BackgroundColor3 = DARK
	decorBar.BackgroundTransparency = 0.1
	decorBar.ScrollingDirection = Enum.ScrollingDirection.X
	decorBar.AutomaticCanvasSize = Enum.AutomaticSize.X
	decorBar.CanvasSize = UDim2.new()
	decorBar.ScrollBarThickness = 6
	decorBar.Visible = false
	decorBar.Parent = gui
	corner(decorBar, UDim.new(0, 14))
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 8)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = decorBar
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = decorBar
	for i, item in ipairs(HomeConfig.Items) do
		-- Marco 10: móveis de luxo em dourado
		local color = item.luxo and Color3.fromRGB(150, 115, 40) or Color3.fromRGB(50, 70, 110)
		local b = button(decorBar, ("%s\n$%d"):format(item.label, item.price), color, UDim2.fromOffset(104, 76))
		b.LayoutOrder = i
		b.Activated:Connect(function()
			startPlacing(item.id)
		end)
	end

	actionBar = Instance.new("Frame")
	actionBar.Name = "Acoes"
	actionBar.AnchorPoint = Vector2.new(0.5, 1)
	actionBar.Position = UDim2.new(0.5, 0, 1, -114)
	actionBar.Size = UDim2.fromOffset(400, 48)
	actionBar.BackgroundTransparency = 1
	actionBar.Visible = false
	actionBar.Parent = gui
	local alayout = Instance.new("UIListLayout")
	alayout.FillDirection = Enum.FillDirection.Horizontal
	alayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	alayout.Padding = UDim.new(0, 10)
	alayout.SortOrder = Enum.SortOrder.LayoutOrder
	alayout.Parent = actionBar
	UIScaler.attach(actionBar)
end

local function startDecorating()
	if not info or not info.insideOwn then
		return
	end
	decorating = true
	panel.Visible = false
	decorBar.Visible = true
	actionBar.Visible = true
	refreshActions()
end

-- Clique/toque no mundo durante o modo decorar
local function onWorldTap(screenPos)
	if not decorating then
		return
	end
	if placing then
		local x, z = floorPoint(screenPos)
		if x then
			placing.x, placing.z = x, z
			updateGhost()
			if UserInputService.MouseEnabled and not UserInputService.TouchEnabled then
				confirmPlacing() -- no PC o clique já coloca
			end
		end
		return
	end
	-- sem móvel na mão: tocar num móvel seleciona
	local interior = myInterior()
	local furniture = interior and interior:FindFirstChild("Moveis")
	if not furniture then
		return
	end
	local camera = Workspace.CurrentCamera
	local ray = camera:ViewportPointToRay(screenPos.X, screenPos.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { furniture }
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 200, params)
	if hit then
		local model = hit.Instance
		while model and model.Parent ~= furniture do
			model = model.Parent
		end
		if model then
			selectModel(model)
		end
	else
		clearSelection()
		refreshActions()
	end
end

---------------------------------------------------------------------------
-- Painel "Minha casa"
---------------------------------------------------------------------------

local function buildPanel()
	panel = Instance.new("Frame")
	panel.Name = "MinhaCasa"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(380, 400)
	panel.BackgroundColor3 = DARK
	panel.Visible = false
	panel.Parent = gui
	corner(panel, UDim.new(0, 16))
	UIScaler.attach(panel)
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromScale(1, 1)
	content.Parent = panel

	refreshPanel = function()
		content:ClearAllChildren()
		-- Marco 10.1: o jogador pode ter várias casas (o painel mostra a que ele está, ou a principal)
		local total = info and type(info.homes) == "table" and #info.homes or 1
		label(content, total > 1 and ("Minhas casas (%d)"):format(total) or "Minha casa", UDim2.new(1, -70, 0, 30), UDim2.fromOffset(16, 10), 22)
		local close = button(content, "X", RED, UDim2.fromOffset(36, 32), UDim2.new(1, -46, 0, 8))
		close.Activated:Connect(function()
			panel.Visible = false
		end)
		if not info then
			label(content, "Carregando sua casa...", UDim2.new(1, -32, 0, 40), UDim2.fromOffset(16, 50))
			return
		end
		local y = 46
		label(content, HomeConfig.tier(info.tier).label .. "  ·  " .. (info.address or ""), UDim2.new(1, -32, 0, 22), UDim2.fromOffset(16, y), 16).TextColor3 = Color3.fromRGB(180, 210, 255)
		y += 28
		if info.insideOwn then
			local decor = button(content, "Decorar", GREEN, UDim2.new(1, -32, 0, 44), UDim2.fromOffset(16, y))
			decor.Activated:Connect(startDecorating)
		elseif not info.insideOther then
			-- Marco 8.3: sem "Ir para casa"; para chegar, vá dirigindo (o botão da casinha mostra no mapa)
			label(content, "Vá até a sua casa para decorar.", UDim2.new(1, -32, 0, 44), UDim2.fromOffset(16, y), 16)
		else
			label(content, "Você está na casa de " .. info.insideOther, UDim2.new(1, -32, 0, 44), UDim2.fromOffset(16, y), 16)
		end
		y += 56
		label(content, "Quem pode entrar:", UDim2.new(1, -32, 0, 22), UDim2.fromOffset(16, y), 16)
		y += 26
		local n = #HomeConfig.LockModes
		for i, mode in ipairs(HomeConfig.LockModes) do
			local active = info.lock == mode.id
			local b = button(content, mode.label, active and ORANGE or Color3.fromRGB(60, 70, 95), UDim2.new(1 / n, -10, 0, 40), UDim2.new((i - 1) / n, 16 - (i - 1) * 6, 0, y))
			b.Activated:Connect(function()
				homeRequest:FireServer("SetLock", { mode = mode.id })
			end)
		end
		y += 46
		for _, mode in ipairs(HomeConfig.LockModes) do
			if mode.id == info.lock then
				label(content, mode.hint, UDim2.new(1, -32, 0, 20), UDim2.fromOffset(16, y), 14).TextColor3 = Color3.fromRGB(200, 200, 210)
			end
		end
		y += 28
		local kick = button(content, "Expulsar visitantes", RED, UDim2.new(1, -32, 0, 40), UDim2.fromOffset(16, y))
		kick.Activated:Connect(function()
			homeRequest:FireServer("Kick")
		end)
		y += 52
		if info.insideOwn then
			label(content, ("Cor da parede  ·  Móveis: %d/%d"):format(info.count or 0, info.max or 0), UDim2.new(1, -32, 0, 20), UDim2.fromOffset(16, y), 14)
			y += 24
			for i, color in ipairs(HomeConfig.WallColors) do
				local sw = Instance.new("TextButton")
				sw.Text = ""
				sw.Size = UDim2.fromOffset(40, 40)
				sw.Position = UDim2.fromOffset(16 + (i - 1) * 52, y)
				sw.BackgroundColor3 = color
				sw.Parent = content
				corner(sw, UDim.new(1, 0))
				if info.wall == i then
					local stroke = Instance.new("UIStroke")
					stroke.Color = ORANGE
					stroke.Thickness = 3
					stroke.Parent = sw
				end
				sw.Activated:Connect(function()
					homeRequest:FireServer("SetWall", { index = i })
				end)
			end
		end
	end
	refreshPanel()
end

-- Ícone de casinha (Frames): telhado girado + corpo + porta
local function drawHouseIcon(parent)
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.55)
	holder.Size = UDim2.fromOffset(22, 20)
	holder.BackgroundTransparency = 1
	holder.Parent = parent
	local roof = Instance.new("Frame")
	roof.AnchorPoint = Vector2.new(0.5, 0.5)
	roof.Position = UDim2.new(0.5, 0, 0, 5)
	roof.Size = UDim2.fromOffset(15, 15)
	roof.Rotation = 45
	roof.BackgroundColor3 = Color3.fromRGB(230, 90, 60)
	roof.BorderSizePixel = 0
	roof.Parent = holder
	local body = Instance.new("Frame")
	body.AnchorPoint = Vector2.new(0.5, 1)
	body.Position = UDim2.fromScale(0.5, 1)
	body.Size = UDim2.fromOffset(16, 11)
	body.BackgroundColor3 = Color3.fromRGB(245, 235, 210)
	body.BorderSizePixel = 0
	body.Parent = holder
	local door = Instance.new("Frame")
	door.AnchorPoint = Vector2.new(0.5, 1)
	door.Position = UDim2.fromScale(0.5, 1)
	door.Size = UDim2.fromOffset(5, 7)
	door.BackgroundColor3 = Color3.fromRGB(140, 90, 50)
	door.BorderSizePixel = 0
	door.Parent = body
end

local function buildButton()
	local buttonGui = Instance.new("ScreenGui")
	buttonGui.Name = "HomeButtonUI"
	buttonGui.ResetOnSpawn = false
	buttonGui.IgnoreGuiInset = true
	buttonGui.DisplayOrder = 4
	buttonGui.Parent = player:WaitForChild("PlayerGui")
	local size = 40
	local topbar = GuiService:GetGuiInset().Y
	local b = Instance.new("ImageButton")
	b.Name = "HomeButton"
	b.AnchorPoint = Vector2.new(0.5, 0)
	b.Position = UDim2.new(0.5, -25, 0, math.max(4, (topbar - size) / 2)) -- Marco 10.12: o botão do mapa saiu (virou minimapa)
	b.Size = UDim2.fromOffset(size, size)
	b.BackgroundColor3 = Color3.new(0, 0, 0)
	b.BackgroundTransparency = 0.35
	b.Image = ""
	b.Parent = buttonGui
	corner(b, UDim.new(1, 0))
	drawHouseIcon(b)
	b.Activated:Connect(function()
		if decorating then
			return
		end
		-- Marco 8.3: fora de casa, a casinha mostra onde ela fica no mapa; dentro, abre "Minha casa"
		if not panel.Visible and not (info and info.insideOwn) then
			local MapController = require(script.Parent:WaitForChild("MapController"))
			if MapController.showHome() then
				return
			end
		end
		panel.Visible = not panel.Visible
		refreshPanel()
	end)
end

---------------------------------------------------------------------------

function HomeController.handle(kind, data)
	if kind == "HomeInfo" then
		info = data
		if typeof(info.origin) ~= "CFrame" then
			info.origin = CFrame.new()
		end
		if decorating and not info.insideOwn then
			stopDecorating() -- saiu de casa
		end
		if panel and panel.Visible then
			refreshPanel()
		end
	end
end

function HomeController.init()
	homeRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(GameConfig.Remotes.HomeRequest)
	-- Marco 10.5: na mansão a mesma porta entra e sai. Para quem está dentro, o aviso diz "Sair".
	ProximityPromptService.PromptShown:Connect(function(prompt)
		if prompt.Name ~= "HomePrompt" or not prompt.Parent then
			return
		end
		local index = prompt.Parent:GetAttribute("HomeIndex")
		if index and index == player:GetAttribute("InHomeIndex") then
			if prompt.ActionText ~= "Sair" then
				prompt:SetAttribute("TextoFora", prompt.ActionText)
				prompt.ActionText = "Sair"
			end
		elseif prompt.ActionText == "Sair" and prompt:GetAttribute("TextoFora") then
			prompt.ActionText = prompt:GetAttribute("TextoFora")
		end
	end)
	gui = Instance.new("ScreenGui")
	gui.Name = "HomeUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 6
	gui.Parent = player:WaitForChild("PlayerGui")
	buildPanel()
	buildDecorUI()
	buildButton()

	-- PC: a prévia segue o mouse; clique coloca. Celular: toque move a prévia; "Colocar" confirma.
	RunService.RenderStepped:Connect(function()
		if placing and UserInputService.MouseEnabled and not UserInputService.TouchEnabled then
			local x, z = floorPoint(UserInputService:GetMouseLocation())
			if x and (x ~= placing.x or z ~= placing.z) then
				placing.x, placing.z = x, z
				updateGhost()
			end
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not decorating then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			onWorldTap(UserInputService:GetMouseLocation())
		elseif input.KeyCode == Enum.KeyCode.R and placing then
			placing.r = (placing.r + 1) % 4
			updateGhost()
		end
	end)
	UserInputService.TouchTap:Connect(function(positions, processed)
		if not processed and positions[1] then
			-- o toque vem sem a faixa do topo; o raio da câmera precisa dela
			onWorldTap(positions[1] + GuiService:GetGuiInset())
		end
	end)
end

return HomeController
