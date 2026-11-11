-- MochilaController (ModuleScript)
-- Caminho: StarterPlayer > StarterPlayerScripts > Controllers > MochilaController
-- Marco 10.26: a mochila do assalto (banco e joalheria). B abre a lista do que está na bolsa, e dá
-- para LARGAR qualquer item (para fugir mais leve). Quando acha algo que não cabe, abre um cartão:
-- trocar pelo que vale menos, ou deixar. O servidor confere tudo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local UIScaler = require(script.Parent:WaitForChild("UIScaler"))
local MobileButtons = require(script.Parent:WaitForChild("MobileButtons"))

local MochilaController = {}

local player = Players.LocalPlayer
local gui, tab, panel, list, title, card, cardText, swapBtn
local remotes = {}
local bags = {} -- bags[fonte] = payload da bolsa
local offerFrom

local DARK = Color3.fromRGB(16, 20, 30)
local ROW = Color3.fromRGB(34, 40, 56)
local GOLD = Color3.fromRGB(255, 215, 110)

local function corner(o, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = o
end

local function text(parent, str, x, y, w, h, size, color, font)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromOffset(x, y)
	l.Size = UDim2.fromOffset(w, h)
	l.Font = font or Enum.Font.GothamBold
	l.TextSize = size
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Text = str
	l.Parent = parent
	return l
end

local function button(parent, str, color, x, y, w, h, fn)
	local b = Instance.new("TextButton")
	b.Position = UDim2.fromOffset(x, y)
	b.Size = UDim2.fromOffset(w, h)
	b.BackgroundColor3 = color
	b.Font = Enum.Font.GothamBold
	b.TextSize = 13
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = str
	b.Parent = parent
	corner(b, 8)
	b.Activated:Connect(fn)
	return b
end

local function active()
	local b, source = bags.banco, "banco"
	if not (b and (b.slots or 0) > 0) then
		b, source = bags.joia, "joia"
	end
	if b and (b.slots or 0) > 0 then
		return b, source
	end
	return nil
end

-- com a lista aberta o mouse fica solto, mesmo com a câmera travada
local function setOpen(on)
	panel.Visible = on
	player:SetAttribute("MochilaAberta", (on or card.Visible) and true or nil)
end

local function draw()
	local b, source = active()
	tab.Visible = b ~= nil
	MobileButtons.show("mochila", b ~= nil)
	if not b then
		setOpen(false)
		return
	end
	tab.Text = ("🎒 Mochila %d/%d  •  $%d  (B)"):format(b.slots or 0, b.max or 0, b.value or 0)
	title.Text = ("🎒 %d/%d espaços  •  $%d"):format(b.slots or 0, b.max or 0, b.value or 0)
	list:ClearAllChildren()
	local y = 0
	for i, it in ipairs(b.items or {}) do
		local row = Instance.new("Frame")
		row.Position = UDim2.fromOffset(0, y)
		row.Size = UDim2.new(1, 0, 0, 34)
		row.BackgroundColor3 = ROW
		row.Parent = list
		corner(row, 8)
		text(row, tostring(it.name), 8, 2, 190, 16, 13)
		text(row, ("$%d  •  %d espaço(s)"):format(it.value or 0, it.slots or 1), 8, 17, 190, 14, 11, GOLD, Enum.Font.Gotham)
		button(row, "Largar", Color3.fromRGB(170, 60, 50), 206, 5, 66, 24, function()
			remotes[source]:FireServer("Largar", i)
		end)
		y += 38
	end
	list.CanvasSize = UDim2.fromOffset(0, y)
end

function MochilaController.update(source, data)
	bags[source] = data
	if gui then
		draw()
	end
end

-- data = { name, value, slots, drop = { nomes }, dropValue }
function MochilaController.offer(source, data)
	offerFrom = source
	cardText.Text = ("Achou %s ($%d, %d espaço(s)), mas não cabe.\nTrocar por: %s ($%d)?"):format(tostring(data.name), data.value or 0, data.slots or 1, table.concat(data.drop or {}, ", "), data.dropValue or 0)
	swapBtn.Text = (data.value or 0) > (data.dropValue or 0) and "✅ Trocar: vale mais! (Y)" or "Trocar mesmo assim (Y)"
	card.Visible = true
	player:SetAttribute("MochilaAberta", true)
end

local function answer(action)
	if card.Visible and offerFrom then
		card.Visible = false
		player:SetAttribute("MochilaAberta", panel.Visible and true or nil)
		remotes[offerFrom]:FireServer(action)
	end
end

function MochilaController.init()
	local folder = ReplicatedStorage:WaitForChild("Remotes")
	remotes.banco = folder:WaitForChild(GameConfig.Remotes.BankRequest)
	remotes.joia = folder:WaitForChild(GameConfig.Remotes.JewelryRequest)

	gui = Instance.new("ScreenGui")
	gui.Name = "MochilaUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 6
	gui.Parent = player:WaitForChild("PlayerGui")

	tab = Instance.new("TextButton")
	tab.AnchorPoint = Vector2.new(0, 1)
	tab.Position = UDim2.new(0, 14, 1, -14)
	tab.Size = UDim2.fromOffset(290, 34)
	tab.BackgroundColor3 = DARK
	tab.Font = Enum.Font.GothamBold
	tab.TextSize = 14
	tab.TextColor3 = GOLD
	tab.Visible = false
	tab.Parent = gui
	corner(tab, 10)
	UIScaler.attach(tab)

	panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.Position = UDim2.new(0, 14, 1, -54)
	panel.Size = UDim2.fromOffset(300, 320)
	panel.BackgroundColor3 = DARK
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 12)
	UIScaler.attach(panel)
	title = text(panel, "", 12, 8, 276, 20, 14, GOLD, Enum.Font.GothamBlack)
	text(panel, "Largue o que for pesado para correr mais.", 12, 28, 276, 16, 11, Color3.fromRGB(170, 176, 196), Enum.Font.Gotham)
	list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(12, 50)
	list.Size = UDim2.new(1, -18, 1, -60)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 5
	list.Parent = panel

	card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.55)
	card.Size = UDim2.fromOffset(420, 132)
	card.BackgroundColor3 = DARK
	card.Visible = false
	card.Parent = gui
	corner(card, 14)
	UIScaler.attach(card)
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 2
	stroke.Parent = card
	cardText = text(card, "", 16, 12, 388, 64, 15)
	cardText.TextWrapped = true
	cardText.TextTruncate = Enum.TextTruncate.None
	cardText.TextYAlignment = Enum.TextYAlignment.Top
	swapBtn = button(card, "Trocar (Y)", Color3.fromRGB(50, 150, 90), 16, 84, 226, 36, function()
		answer("Trocar")
	end)
	button(card, "Deixar (N)", Color3.fromRGB(80, 86, 104), 252, 84, 152, 36, function()
		answer("Deixar")
	end)

	local function toggle()
		if active() then
			setOpen(not panel.Visible)
		end
	end
	tab.Activated:Connect(toggle)
	MobileButtons.add("mochila", { icon = "🎒", title = "Mochila", slots = { 5 }, onPress = toggle })
	MobileButtons.show("mochila", false)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == Enum.KeyCode.B then
			toggle()
		elseif input.KeyCode == Enum.KeyCode.Y then
			answer("Trocar")
		elseif input.KeyCode == Enum.KeyCode.N then
			answer("Deixar")
		end
	end)
	draw()
end

return MochilaController
