-- GangController (ModuleScript)
-- Caminho: StarterPlayer > StarterPlayerScripts > Controllers > GangController
-- Marco 10.1: conversa com o chefe da gangue (diálogo com escolhas) e as pipas balançando no céu
-- das favelas. O cliente só mostra e pergunta: quem decide é o GangService (servidor).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local AssaltoConfig = require(Shared:WaitForChild("AssaltoConfig")) -- Marco 10.30: C4
local DialogController = require(script.Parent:WaitForChild("DialogController"))
local UIScaler = require(script.Parent:WaitForChild("UIScaler"))
local TweenService = game:GetService("TweenService")

local GangController = {}

local G = GameConfig.Gangs
local player = Players.LocalPlayer
local gangRequest


---------------------------------------------------------------------------
-- Marco 10.8: loja do chefe (armas e munição) numa tela própria, com o modelo 3D girando,
-- barras de dano/cadência/pente e a sua munição guardada. Quem confere e cobra é o GangService.
---------------------------------------------------------------------------
local shopGui
local shop = {} -- { panel, scale, list, detail, ... }
local SH = {
	Bg = Color3.fromRGB(14, 18, 28),
	Card = Color3.fromRGB(26, 32, 46),
	CardOn = Color3.fromRGB(38, 46, 66),
	Muted = Color3.fromRGB(140, 152, 176),
	Green = Color3.fromRGB(60, 180, 100),
	Red = Color3.fromRGB(200, 70, 60),
}

local function sCorner(o, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = o
	return c
end

local function sText(parent, t, size, font, color, align)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = t
	l.TextSize = size
	l.Font = font or Enum.Font.GothamBold
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.TextXAlignment = align or Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

local function money()
	return player:GetAttribute("Money") or 0
end

local function fmt(n)
	local s = tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1."):reverse()
	if s:sub(1, 1) == "." then
		s = s:sub(2)
	end
	return "$" .. s
end

local function viewportFor(id)
	local ok, Inv = pcall(require, script.Parent:WaitForChild("InventoryController"))
	if ok and Inv.gunViewport then
		return Inv.gunViewport(id)
	end
	return nil
end

local function statBar(parent, y, labelText, value01, valueText)
	local l = sText(parent, labelText, 12, Enum.Font.GothamBold, SH.Muted)
	l.Position = UDim2.fromOffset(0, y)
	l.Size = UDim2.new(0, 80, 0, 16)
	local track = Instance.new("Frame")
	track.Position = UDim2.fromOffset(84, y + 5)
	track.Size = UDim2.new(1, -140, 0, 6)
	track.BackgroundColor3 = SH.Card
	track.BorderSizePixel = 0
	track.Parent = parent
	sCorner(track, 3)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = shop.accent or SH.Green
	fill.BorderSizePixel = 0
	fill.Parent = track
	sCorner(fill, 3)
	TweenService:Create(fill, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { Size = UDim2.new(math.clamp(value01, 0.05, 1), 0, 1, 0) }):Play()
	local v = sText(parent, valueText, 12, Enum.Font.GothamBold, Color3.new(1, 1, 1), Enum.TextXAlignment.Right)
	v.Position = UDim2.new(1, -50, 0, y)
	v.Size = UDim2.new(0, 50, 0, 16)
end

local function closeShop()
	if shop.panel then
		shop.panel.Visible = false
	end
	shop.spin = nil
end

local function buyButtonState()
	local b, price = shop.buyButton, shop.price or 0
	if not b then
		return
	end
	local can = money() >= price and not shop.full
	b.BackgroundColor3 = can and SH.Green or SH.Red
	b.AutoButtonColor = can
	if shop.full then
		b.Text = "Máximo de munição"
	else
		b.Text = can and ("Comprar  •  " .. fmt(price)) or ("Falta " .. fmt(price - money()))
	end
	shop.moneyLabel.Text = fmt(money())
end

-- Painel da direita: modelo grande girando + detalhes + botão
local function showDetail(item)
	for _, c in ipairs(shop.detail:GetChildren()) do
		if not c:IsA("UICorner") and not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
	shop.selected = item
	local W = GameConfig.Weapons
	local stage = Instance.new("Frame")
	stage.Size = UDim2.new(1, 0, 0, 150)
	stage.BackgroundColor3 = SH.Card
	stage.Parent = shop.detail
	sCorner(stage, 12)
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(SH.CardOn, SH.Bg)
	grad.Rotation = 90
	grad.Parent = stage
	shop.spin = nil
	if item.weapon then
		local vp = viewportFor(item.id)
		if vp then
			vp.Size = UDim2.fromScale(1, 1)
			vp.Parent = stage
			local cam = vp.CurrentCamera
			local model = vp:FindFirstChildWhichIsA("Model")
			if cam and model then
				local pivot = model:GetPivot()
				shop.spin = { model = model, pivot = pivot, t = 0, axis = cam.CFrame.UpVector }
			end
		end
	else
		local big = sText(stage, item.icon, 54, Enum.Font.GothamBold, Color3.new(1, 1, 1), Enum.TextXAlignment.Center)
		big.Size = UDim2.fromScale(1, 1)
	end
	local name = sText(shop.detail, item.name, 20, Enum.Font.GothamBlack)
	name.Position = UDim2.fromOffset(0, 160)
	name.Size = UDim2.new(1, 0, 0, 24)
	local sub = sText(shop.detail, item.sub, 12, Enum.Font.Gotham, SH.Muted)
	sub.Position = UDim2.fromOffset(0, 184)
	sub.Size = UDim2.new(1, 0, 0, 16)
	local stats = Instance.new("Frame")
	stats.BackgroundTransparency = 1
	stats.Position = UDim2.fromOffset(0, 210)
	stats.Size = UDim2.new(1, 0, 0, 70)
	stats.Parent = shop.detail
	shop.full = false
	if item.weapon then
		local def = W.List[item.id]
		statBar(stats, 0, "Dano", def.Damage / 30, tostring(def.Damage))
		statBar(stats, 22, "Cadência", (1 / def.Rate) / 11, ("%.1f/s"):format(1 / def.Rate))
		statBar(stats, 44, "Pente", def.Mag / 30, tostring(def.Mag))
	elseif item.special == "C4" then
		local C = AssaltoConfig.C4
		statBar(stats, 0, "Contagem", C.Fuse / 15, ("%d s"):format(C.Fuse))
		statBar(stats, 22, "Estrago", 1, "Porta do cofre")
		statBar(stats, 44, "Máximo", C.Max / 3, ("%d na mochila"):format(C.Max))
	else
		local a = W.Ammo[item.id]
		local have = player:GetAttribute("Municao_" .. item.id) or 0
		statBar(stats, 0, "Guardada", have / W.MaxAmmo, ("%d/%d"):format(have, W.MaxAmmo))
		statBar(stats, 22, "Por compra", a.Per / 30, ("+%d"):format(a.Per))
		shop.full = have >= W.MaxAmmo
	end
	shop.price = item.price
	local buy = Instance.new("TextButton")
	buy.AnchorPoint = Vector2.new(0, 1)
	buy.Position = UDim2.new(0, 0, 1, 0)
	buy.Size = UDim2.new(1, 0, 0, 44)
	buy.Font = Enum.Font.GothamBlack
	buy.TextSize = 16
	buy.TextColor3 = Color3.new(1, 1, 1)
	buy.Parent = shop.detail
	sCorner(buy, 22)
	shop.buyButton = buy
	buyButtonState()
	buy.Activated:Connect(function()
		if money() < (shop.price or 0) or shop.full then
			return
		end
		if item.weapon then
			gangRequest:FireServer("Buy", shop.gang, item.id)
		elseif item.special == "C4" then
			gangRequest:FireServer("C4", shop.gang)
		else
			gangRequest:FireServer("Ammo", shop.gang, item.id)
		end
		buy.Text = "✔  Comprado!"
		local sc = Instance.new("UIScale")
		sc.Parent = buy
		sc.Scale = 0.94
		TweenService:Create(sc, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		task.delay(1.1, function()
			if shop.selected == item then
				showDetail(item) -- atualiza a munição e o dinheiro
			end
		end)
	end)
end

local function fillList(tab)
	for _, c in ipairs(shop.list:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local W = GameConfig.Weapons
	local items = {}
	if tab == "guns" then
		for _, id in ipairs(W.GangShop) do
			local def = W.List[id]
			table.insert(items, { weapon = true, id = id, name = def.Name, price = def.Price, icon = "🔫",
				sub = (def.Kind == "pistola" and "Pistola" or (def.Auto and "Automática" or "Fuzil")) .. "  •  vai para a mochila" })
		end
	else
		for _, kind in ipairs({ "pistola", "fuzil" }) do
			local a = W.Ammo[kind]
			table.insert(items, { weapon = false, id = kind, name = a.Name, price = a.Price, icon = a.Icon,
				sub = kind == "pistola" and "Para pistolas" or "Para fuzis e submetralhadoras" })
		end
		-- Marco 10.30: C4 para explodir a porta do cofre do banco
		table.insert(items, { weapon = false, special = "C4", id = "C4", name = "C4 (explosivo)", price = AssaltoConfig.C4.Price, icon = "🧨",
			sub = "Explode a porta do cofre do banco  •  fica na mochila" })
	end
	for i, item in ipairs(items) do
		local card = Instance.new("TextButton")
		card.Text = ""
		card.Size = UDim2.new(1, 0, 0, 62)
		card.BackgroundColor3 = SH.Card
		card.AutoButtonColor = true
		card.LayoutOrder = i
		card.Parent = shop.list
		sCorner(card, 12)
		local iconHolder = Instance.new("Frame")
		iconHolder.Position = UDim2.fromOffset(6, 6)
		iconHolder.Size = UDim2.fromOffset(72, 50)
		iconHolder.BackgroundColor3 = SH.Bg
		iconHolder.Parent = card
		sCorner(iconHolder, 10)
		local vp = item.weapon and viewportFor(item.id)
		if vp then
			vp.Size = UDim2.fromScale(1, 1)
			vp.Parent = iconHolder
		else
			local e = sText(iconHolder, item.icon, 26, Enum.Font.GothamBold, Color3.new(1, 1, 1), Enum.TextXAlignment.Center)
			e.Size = UDim2.fromScale(1, 1)
		end
		local n = sText(card, item.name, 14, Enum.Font.GothamBlack)
		n.Position = UDim2.fromOffset(88, 12)
		n.Size = UDim2.new(1, -96, 0, 18)
		n.TextTruncate = Enum.TextTruncate.AtEnd
		local p = sText(card, fmt(item.price), 13, Enum.Font.GothamBold, money() >= item.price and SH.Green or SH.Red)
		p.Position = UDim2.fromOffset(88, 32)
		p.Size = UDim2.new(1, -96, 0, 16)
		card.Activated:Connect(function()
			for _, other in ipairs(shop.list:GetChildren()) do
				if other:IsA("TextButton") then
					other.BackgroundColor3 = SH.Card
				end
			end
			card.BackgroundColor3 = SH.CardOn
			showDetail(item)
		end)
		if i == 1 then
			card.BackgroundColor3 = SH.CardOn
			showDetail(item)
		end
	end
	for id, t in pairs(shop.tabs) do
		t.BackgroundColor3 = id == tab and (shop.accent or SH.Green) or SH.Card
	end
end

local function buildShop()
	shopGui = Instance.new("ScreenGui")
	shopGui.Name = "LojaChefeUI"
	shopGui.ResetOnSpawn = false
	shopGui.DisplayOrder = 8
	shopGui.Parent = player:WaitForChild("PlayerGui")
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(660, 430)
	panel.BackgroundColor3 = SH.Bg
	panel.BackgroundTransparency = 0.03
	panel.Visible = false
	panel.Parent = shopGui
	sCorner(panel, 20)
	local st = Instance.new("UIStroke")
	st.Color = Color3.new(1, 1, 1)
	st.Transparency = 0.88
	st.Parent = panel
	UIScaler.attach(panel)
	shop.scale = Instance.new("UIScale")
	shop.scale.Parent = panel
	shop.panel = panel
	-- faixa da cor da gangue no topo
	local strip = Instance.new("Frame")
	strip.Size = UDim2.new(1, 0, 0, 4)
	strip.BorderSizePixel = 0
	strip.Parent = panel
	shop.strip = strip
	shop.title = sText(panel, "", 20, Enum.Font.GothamBlack)
	shop.title.Position = UDim2.fromOffset(20, 14)
	shop.title.Size = UDim2.new(1, -220, 0, 24)
	shop.subtitle = sText(panel, "", 12, Enum.Font.Gotham, SH.Muted)
	shop.subtitle.Position = UDim2.fromOffset(20, 38)
	shop.subtitle.Size = UDim2.new(1, -220, 0, 16)
	local mon = Instance.new("Frame")
	mon.AnchorPoint = Vector2.new(1, 0)
	mon.Position = UDim2.new(1, -58, 0, 16)
	mon.Size = UDim2.fromOffset(130, 32)
	mon.BackgroundColor3 = SH.Card
	mon.Parent = panel
	sCorner(mon, 16)
	shop.moneyLabel = sText(mon, "", 14, Enum.Font.GothamBlack, SH.Green, Enum.TextXAlignment.Center)
	shop.moneyLabel.Size = UDim2.fromScale(1, 1)
	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -16, 0, 16)
	close.Size = UDim2.fromOffset(32, 32)
	close.BackgroundColor3 = SH.Card
	close.Text = "✕"
	close.Font = Enum.Font.GothamBold
	close.TextSize = 16
	close.TextColor3 = Color3.new(1, 1, 1)
	close.Parent = panel
	sCorner(close, 16)
	close.Activated:Connect(closeShop)
	-- abas
	shop.tabs = {}
	for i, tab in ipairs({ { "guns", "🔫  Armas" }, { "ammo", "🧨  Munição e C4" } }) do
		local t = Instance.new("TextButton")
		t.Position = UDim2.fromOffset(20 + (i - 1) * 128, 66)
		t.Size = UDim2.fromOffset(120, 32)
		t.BackgroundColor3 = SH.Card
		t.Text = tab[2]
		t.Font = Enum.Font.GothamBold
		t.TextSize = 13
		t.TextColor3 = Color3.new(1, 1, 1)
		t.Parent = panel
		sCorner(t, 16)
		shop.tabs[tab[1]] = t
		t.Activated:Connect(function()
			fillList(tab[1])
		end)
	end
	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(20, 110)
	list.Size = UDim2.new(0, 290, 1, -130)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 4
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	local lp = Instance.new("UIPadding")
	lp.PaddingRight = UDim.new(0, 8)
	lp.Parent = list
	shop.list = list
	local detail = Instance.new("Frame")
	detail.Position = UDim2.fromOffset(326, 66)
	detail.Size = UDim2.new(1, -346, 1, -86)
	detail.BackgroundTransparency = 1
	detail.Parent = panel
	shop.detail = detail
	-- gira o modelo grande devagar enquanto a loja está aberta
	RunService.RenderStepped:Connect(function(dt)
		local sp = shop.spin
		if sp and panel.Visible and sp.model.Parent then
			sp.t += dt
			local box = sp.model:GetBoundingBox()
			local spin = CFrame.fromAxisAngle(sp.axis, math.sin(sp.t * 0.8) * dt * 0.9)
			sp.model:PivotTo(CFrame.new(box.Position) * spin * (CFrame.new(-box.Position) * sp.model:GetPivot()))
		end
	end)
	player:GetAttributeChangedSignal("Money"):Connect(function()
		if panel.Visible then
			buyButtonState()
		end
	end)
end

local function openShop(gangId, speaker)
	local g = G.List[gangId]
	if not shopGui then
		buildShop()
	end
	shop.gang = gangId
	shop.accent = g and g.Color or SH.Green
	shop.strip.BackgroundColor3 = shop.accent
	shop.title.Text = "Arsenal do " .. (g and g.Chief or "chefe")
	shop.subtitle.Text = (g and g.Community or "") .. "  •  " .. (speaker:match("·%s*(.+)$") or G.Title) .. "  •  se a polícia revistar, leva"
	shop.panel.Visible = true
	shop.scale.Scale = 0.92
	TweenService:Create(shop.scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	fillList("guns")
	-- fecha sozinha se você se afastar do chefe
	task.spawn(function()
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local start = root and root.Position
		while shop.panel.Visible and start do
			task.wait(0.5)
			root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if not root or (root.Position - start).Magnitude > 20 then
				closeShop()
			end
		end
	end)
end

-- Falas do chefe (dependem de quem está conversando)
local function talk(data)
	local g = G.List[data.gang]
	if not g or DialogController.isOpen() then
		return
	end
	local speaker = ("%s  ·  %s"):format(g.Chief, G.Title)
	if data.member == data.gang then
		-- Marco 10.5: entregar o dinheiro do assalto e comprar armas
		local dirty = player:GetAttribute("DinheiroSujo") or 0
		local options = { { id = "stay", text = "Tô dentro" } }
		if dirty > 0 then
			table.insert(options, 1, { id = "deliver", text = ("Entregar $%d"):format(dirty) })
		end
		table.insert(options, { id = "shop", text = "🔫 Loja (armas e balas)" })
		table.insert(options, { id = "leave", text = "Sair da gangue" })
		local choice = DialogController.show(speaker, {
			("Fala, %s! Tá em casa aqui no %s."):format(player.DisplayName, g.Community),
			dirty > 0 and ("Trouxe o dinheiro do assalto? São $%d. Entrega aqui que eu deixo limpo."):format(dirty)
				or "Assalta uma lojinha ou um caixa eletrônico e traz o dinheiro aqui. Vai continuar com a gente?",
		}, options)
		if choice == "deliver" then
			gangRequest:FireServer("Deliver", data.gang)
		elseif choice == "shop" then
			openShop(data.gang, speaker) -- Marco 10.8: tela da loja
		elseif choice == "leave" then
			local sure = DialogController.show(speaker, {
				("Se sair do %s, você perde o barraco e volta para a casinha da Vila Esperança. Certeza?"):format(g.Short),
			}, { { id = "no", text = "Vou ficar" }, { id = "yes", text = "Sair" } })
			if sure == "yes" then
				gangRequest:FireServer("Leave", data.gang)
			end
		end
	elseif data.member then
		local other = G.List[data.member]
		DialogController.show(speaker, {
			("Opa, você é do %s. Aqui é o %s."):format(other and other.Short or data.member, g.Short),
			"Se quiser fechar com a gente, sai de lá primeiro.",
		}, { { id = "ok", text = "Beleza" } })
	elseif data.policial then
		DialogController.show(speaker, {
			"Polícia por aqui? Aqui você não entra não.",
			"Se um dia largar a farda, vem conversar.",
		}, { { id = "ok", text = "Tá bom" } })
	elseif data.preso then
		DialogController.show(speaker, { "Você tá preso, parceiro. Resolve isso primeiro." }, { { id = "ok", text = "Tá bom" } })
	else
		local choice = DialogController.show(speaker, {
			("E aí! Eu sou o %s, chefe do %s (%s)."):format(g.Chief, g.Name, g.Short),
			("Aqui no %s a gente se fecha. Quem entra para o %s ganha um barraco aqui na comunidade."):format(g.Community, g.Short),
			"Mas presta atenção: quem entra perde a casinha da Vila Esperança. As outras casas continuam suas.",
			("E aí, vai fechar com o %s?"):format(g.Short),
		}, { { id = "join", text = "Entrar para o " .. g.Short }, { id = "no", text = "Agora não" } })
		if choice == "join" then
			gangRequest:FireServer("Join", data.gang)
		end
	end
end

function GangController.handle(kind, data)
	if kind == "GangDialog" then
		task.spawn(talk, data)
	end
end

-- Pipas: balançam devagar em volta do lugar de cada uma (só no cliente)
local function animateKites()
	-- Marco 10.22 (streaming): as pipas chegam e saem do aparelho conforme o jogador anda
	local kites = {}
	local function addKite(d)
		if d:IsA("BasePart") and d.Name == "Pipa" and typeof(d:GetAttribute("Base")) == "CFrame" then
			table.insert(kites, { part = d, base = d:GetAttribute("Base"), phase = #kites * 1.7 })
		end
	end
	task.spawn(function()
		local map = Workspace:WaitForChild("Map")
		local favelas = map:WaitForChild("Favelas", 60)
		if not favelas then
			return
		end
		for _, d in ipairs(favelas:GetDescendants()) do
			addKite(d)
		end
		favelas.DescendantAdded:Connect(addKite)
	end)
	local t = 0
	RunService.Heartbeat:Connect(function(dt)
		t += dt
		for i = #kites, 1, -1 do
			local k = kites[i]
			if not k.part:IsDescendantOf(Workspace) then
				table.remove(kites, i)
			else
				k.tail = k.tail and k.tail.Parent and k.tail or k.part:FindFirstChild("Rabiola")
				local s = math.sin(t * 0.9 + k.phase)
				local c = math.cos(t * 0.6 + k.phase)
				local cf = k.base * CFrame.new(s * 2.5, c * 1.5, 0) * CFrame.Angles(0, 0, s * 0.25)
				k.part.CFrame = cf
				if k.tail then
					k.tail.CFrame = cf * CFrame.Angles(0, 0, -math.rad(45) - s * 0.25) * CFrame.new(0, -3.6, 0)
				end
			end
		end
	end)
end

function GangController.init()
	gangRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(GameConfig.Remotes.GangRequest)
	task.spawn(animateKites)
end

return GangController
