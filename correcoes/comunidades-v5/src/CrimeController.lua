-- CrimeController (ModuleScript)
-- Caminho: StarterPlayer > StarterPlayerScripts > Controllers > CrimeController
-- Marco 10.5: as telas do ladrão e da polícia.
--   * Ladrão (de gangue): o "Assaltar"/"Hackear" só aparece para quem é de gangue. Barra do
--     assalto na loja; minijogo de 3 etapas no caixa eletrônico. Estrelas de procurado e o
--     dinheiro sujo embaixo do saldo.
--   * Policial: botão "Chamados" (alarmes e chamados da central) com a aba "Procurados";
--     "Ir" marca o lugar no Mapa. Estrelas em cima da cabeça de quem é procurado (só a PM vê).
--   * Marco 10.6: revista (G perto da pessoa): barra de 7 a 10 s e painel para apreender.
-- O servidor (CrimeService) decide tudo.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local HudController = require(script.Parent:WaitForChild("HudController"))
local MapController = require(script.Parent:WaitForChild("MapController"))
local UIScaler = require(script.Parent:WaitForChild("UIScaler"))

local CrimeController = {}

local CR = GameConfig.Crime
local player = Players.LocalPlayer
local request
local gui, statusFrame, starsLabel, dirtyLabel
local robFrame, robTitle, robBar, robFill, robButton, robCancel
local callsButton, callsBadge, callsPanel, callsList, tabCalls, tabWanted
local calls, wanted = {}, {}
local tab = "calls"
local seen = 0

local NAVY = Color3.fromRGB(24, 32, 58)
local RED = Color3.fromRGB(210, 55, 55)
local GOLD = Color3.fromRGB(255, 200, 60)
local BLUE = Color3.fromRGB(40, 90, 200)

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
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
	l.TextScaled = true
	l.TextXAlignment = props.Align or Enum.TextXAlignment.Center
	l.Parent = parent
	return l
end

local function button(parent, text, color, size, pos)
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = pos or UDim2.new()
	b.BackgroundColor3 = color
	b.Font = Enum.Font.GothamBlack
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = text
	b.Parent = parent
	corner(b, 10)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = b
	return b
end

local function isPolice()
	return player:GetAttribute("Job") == "Policial"
end

---------------------------------------------------------------------------
-- Quem vê os botões de assalto e de abordagem
---------------------------------------------------------------------------

local function canRob()
	return player:GetAttribute("Gang") ~= nil and not isPolice()
end

local function setPrompt(prompt)
	if prompt.Name == "CrimePrompt" then
		prompt.Enabled = canRob()
	elseif prompt.Name == "AbordarPrompt" then
		prompt.Enabled = isPolice()
	elseif prompt.Name == "RevistarPrompt" then
		-- Marco 10.6: revista (só a PM vê, e nunca em cima de si mesmo)
		local mine = player.Character and prompt:IsDescendantOf(player.Character)
		prompt.Enabled = isPolice() and not mine
	end
end

local function refreshPrompts()
	for _, part in ipairs(CollectionService:GetTagged("CrimeSpot")) do
		local p = part:FindFirstChild("CrimePrompt")
		if p then
			setPrompt(p)
		end
	end
	local npcs = Workspace:FindFirstChild("NPCs")
	for _, d in ipairs(npcs and npcs:GetDescendants() or {}) do
		if d:IsA("ProximityPrompt") and d.Name == "AbordarPrompt" then
			setPrompt(d)
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		local prompt = root and root:FindFirstChild("RevistarPrompt")
		if prompt then
			setPrompt(prompt)
		end
	end
end

---------------------------------------------------------------------------
-- Revista (Marco 10.6): barra dos 7 a 10 s e o painel do que a pessoa tem
---------------------------------------------------------------------------

local friskPanel, friskList, friskTitle
local friskToken = 0

local function showFriskBar(data)
	friskToken += 1
	local token = friskToken
	robFrame.Visible = true
	robButton.Visible = false
	robCancel.Visible = false
	robFill.Size = UDim2.fromScale(0, 1)
	local t0, total = os.clock(), tonumber(data.dur) or 8
	task.spawn(function()
		while friskToken == token do
			local f = math.clamp((os.clock() - t0) / total, 0, 1)
			robFill.Size = UDim2.fromScale(f, 1)
			robTitle.Text = data.cop and ("Revistando %s... fique perto (%ds)"):format(tostring(data.name), math.ceil(total * (1 - f)))
				or ("%s está te revistando (%ds)"):format(tostring(data.name), math.ceil(total * (1 - f)))
			task.wait(0.1)
		end
	end)
end

local function hideFriskBar()
	friskToken += 1
	robFrame.Visible = false
	robCancel.Visible = true
end

local function friskRow(order, text, color, actionText, onAction)
	local r = Instance.new("Frame")
	r.Size = UDim2.new(1, -8, 0, 40)
	r.BackgroundColor3 = Color3.fromRGB(36, 46, 78)
	r.LayoutOrder = order
	r.Parent = friskList
	corner(r, 10)
	label(r, { Text = text, Size = UDim2.new(1, actionText and -130 or -16, 0, 24), Position = UDim2.fromOffset(10, 8), Color = color, Align = Enum.TextXAlignment.Left })
	if actionText then
		local b = button(r, actionText, RED, UDim2.fromOffset(112, 32), UDim2.new(1, -118, 0, 4))
		b.Activated:Connect(onAction)
	end
end

local function showFriskResult(data)
	friskPanel.Visible = true
	friskTitle.Text = ("🔎 Revista: %s %s"):format(tostring(data.name), (data.stars or 0) > 0 and string.rep("★", data.stars) or "")
	for _, c in ipairs(friskList:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	local order = 0
	local function add(...)
		order += 1
		friskRow(order, ...)
	end
	local dirty = tonumber(data.dirty) or 0
	if dirty > 0 then
		add(("💰 $%d de dinheiro sujo"):format(dirty), Color3.fromRGB(140, 230, 140), "Apreender", function()
			request:FireServer("Seize", "dirty")
		end)
	end
	for kind, n in pairs(data.ammo or {}) do
		if n > 0 then
			add(("🟧 %d balas de %s"):format(n, kind), GOLD, "Apreender", function()
				request:FireServer("Seize", "ammo_" .. kind)
			end)
		end
	end
	for _, it in ipairs(data.items or {}) do
		add(("%s %s%s"):format(tostring(it.icon or "📦"), tostring(it.name), it.illegal and "  (proibido)" or ""), it.illegal and Color3.fromRGB(255, 140, 140) or Color3.new(1, 1, 1),
			it.illegal and "Apreender" or nil, function()
				request:FireServer("Seize", it.slot)
			end)
	end
	if order == 0 then
		add("Nada de errado com essa pessoa. Pode liberar.", Color3.fromRGB(170, 200, 255))
	end
end

---------------------------------------------------------------------------
-- Estrelas e dinheiro sujo (embaixo do saldo)
---------------------------------------------------------------------------

local function refreshStatus()
	local stars = player:GetAttribute("Procurado") or 0
	local dirty = player:GetAttribute("DinheiroSujo") or 0
	statusFrame.Visible = stars > 0 or dirty > 0
	starsLabel.Text = stars > 0 and (string.rep("★", stars) .. string.rep("☆", 5 - stars)) or "Ninguém te procura"
	starsLabel.TextColor3 = stars > 0 and GOLD or Color3.fromRGB(180, 190, 210)
	dirtyLabel.Text = dirty > 0 and ("💰 $%d sujo: leve ao chefe"):format(dirty) or ""
end

---------------------------------------------------------------------------
-- Assalto (barra da loja e minijogo do caixa eletrônico)
---------------------------------------------------------------------------

local robToken = 0

local function hideRob()
	robToken += 1
	robFrame.Visible = false
end

local function startStore(data)
	robToken += 1
	local token = robToken
	robFrame.Visible = true
	robButton.Visible = false
	robTitle.Text = "Assaltando: " .. tostring(data.place)
	robFill.Size = UDim2.fromScale(0, 1)
	local t0 = os.clock()
	local total = tonumber(data.time) or CR.StoreTime
	task.spawn(function()
		while robToken == token do
			local f = math.clamp((os.clock() - t0) / total, 0, 1)
			robFill.Size = UDim2.fromScale(f, 1)
			robTitle.Text = ("Assaltando %s... fique perto do caixa (%ds)"):format(tostring(data.place), math.ceil(total * (1 - f)))
			task.wait(0.1)
		end
	end)
end

local ATM_STEPS = { "Ligar o notebook no caixa", "Quebrar a senha", "Puxar o dinheiro" }

local function startAtm(data)
	robToken += 1
	local token = robToken
	local steps = tonumber(data.steps) or 3
	local wait = tonumber(data.stepMin) or CR.AtmStepMin
	robFrame.Visible = true
	local step = 1
	local function nextStep()
		if robToken ~= token or step > steps then
			return
		end
		robButton.Visible = false
		robTitle.Text = ("Etapa %d de %d: %s..."):format(step, steps, ATM_STEPS[step] or "Hackeando")
		robFill.Size = UDim2.fromScale(0, 1)
		local t0 = os.clock()
		while robToken == token and os.clock() - t0 < wait do
			robFill.Size = UDim2.fromScale((os.clock() - t0) / wait, 1)
			task.wait(0.05)
		end
		if robToken ~= token then
			return
		end
		robFill.Size = UDim2.fromScale(1, 1)
		robButton.Text = step < steps and "Pronto! Continuar" or "Pegar o dinheiro!"
		robButton.Visible = true
	end
	robButton:SetAttribute("Token", token)
	robButton:SetAttribute("Step", 1)
	CrimeController._atmNext = function()
		if robToken ~= token then
			return
		end
		request:FireServer("AtmStep")
		step += 1
		if step <= steps then
			task.spawn(nextStep)
		else
			robButton.Visible = false
			robTitle.Text = "Saindo com o dinheiro..."
		end
	end
	task.spawn(nextStep)
end

---------------------------------------------------------------------------
-- Painel da polícia
---------------------------------------------------------------------------

local function ago(sec)
	sec = tonumber(sec) or 0
	if sec < 60 then
		return ("há %ds"):format(sec)
	end
	return ("há %d min"):format(math.floor(sec / 60))
end

local function row(parent, order, title, sub, color, onGo)
	local f = Instance.new("Frame")
	f.Size = UDim2.new(1, -8, 0, 58)
	f.BackgroundColor3 = Color3.fromRGB(38, 48, 82)
	f.LayoutOrder = order
	f.Parent = parent
	corner(f, 10)
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(0, 6, 1, -12)
	bar.Position = UDim2.fromOffset(6, 6)
	bar.BackgroundColor3 = color
	bar.BorderSizePixel = 0
	bar.Parent = f
	label(f, { Text = title, Size = UDim2.new(1, -110, 0, 26), Position = UDim2.fromOffset(18, 5), Align = Enum.TextXAlignment.Left, Font = Enum.Font.GothamBlack })
	label(f, { Text = sub, Size = UDim2.new(1, -110, 0, 18), Position = UDim2.fromOffset(18, 33), Align = Enum.TextXAlignment.Left, Color = Color3.fromRGB(190, 200, 230), Font = Enum.Font.Gotham })
	local go = button(f, "Ir", Color3.fromRGB(60, 170, 80), UDim2.fromOffset(76, 40), UDim2.new(1, -84, 0, 9))
	go.Activated:Connect(onGo)
end

local function drawCalls()
	if not callsPanel then
		return
	end
	for _, c in ipairs(callsList:GetChildren()) do
		if c:IsA("Frame") or c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	tabCalls.BackgroundColor3 = tab == "calls" and BLUE or Color3.fromRGB(60, 70, 100)
	tabWanted.BackgroundColor3 = tab == "wanted" and RED or Color3.fromRGB(60, 70, 100)
	tabCalls.Text = ("📻 Chamados (%d)"):format(#calls)
	tabWanted.Text = ("⭐ Procurados (%d)"):format(#wanted)
	if tab == "calls" then
		if #calls == 0 then
			label(callsList, { Text = "Nenhum chamado agora. Patrulhe a cidade!", Size = UDim2.new(1, -8, 0, 30), Color = Color3.fromRGB(190, 200, 230) })
		end
		for i, c in ipairs(calls) do
			row(callsList, i, tostring(c.title), ("%s · %s"):format(tostring(c.place), ago(c.age)), c.npc and Color3.fromRGB(80, 150, 255) or RED, function()
				MapController.setTarget(nil, c.pos)
				HudController.toast("Chamado marcado no Mapa (bolinha laranja)", BLUE)
			end)
		end
	else
		if #wanted == 0 then
			label(callsList, { Text = "Ninguém na lista de procurados.", Size = UDim2.new(1, -8, 0, 30), Color = Color3.fromRGB(190, 200, 230) })
		end
		for i, w in ipairs(wanted) do
			row(callsList, i, tostring(w.name), ("%s  · recompensa $%d"):format(string.rep("★", w.stars or 0), w.bounty or 0), GOLD, function()
				local p = Players:GetPlayerByUserId(w.userId)
				local r = p and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
				if r then
					MapController.setTarget(nil, r.Position)
					HudController.toast("Última posição marcada no Mapa", RED)
				end
			end)
		end
	end
end

local function refreshCallsButton()
	local police = isPolice()
	callsButton.Visible = police
	if not police then
		callsPanel.Visible = false
	end
	local unseen = math.max(0, #calls - seen)
	callsBadge.Visible = unseen > 0 and not callsPanel.Visible
	callsBadge.Text = tostring(unseen)
end

---------------------------------------------------------------------------
-- Estrelas em cima da cabeça (só a polícia vê)
---------------------------------------------------------------------------

local function overheadLoop()
	while true do
		task.wait(1)
		local show = isPolice() and CR.ShowStarsToPolice
		for _, p in ipairs(Players:GetPlayers()) do
			local head = p ~= player and p.Character and p.Character:FindFirstChild("Head")
			if head then
				local stars = p:GetAttribute("Procurado") or 0
				local tag = head:FindFirstChild("EstrelasPM")
				if show and stars > 0 then
					if not tag then
						tag = Instance.new("BillboardGui")
						tag.Name = "EstrelasPM"
						tag.Size = UDim2.fromOffset(120, 26)
						tag.StudsOffset = Vector3.new(0, 2.8, 0)
						tag.AlwaysOnTop = true
						tag.MaxDistance = 160
						tag.Parent = head
						local l = Instance.new("TextLabel")
						l.Name = "T"
						l.Size = UDim2.fromScale(1, 1)
						l.BackgroundTransparency = 1
						l.Font = Enum.Font.GothamBlack
						l.TextScaled = true
						l.TextColor3 = GOLD
						l.TextStrokeTransparency = 0.3
						l.Parent = tag
					end
					tag.T.Text = string.rep("★", stars)
				elseif tag then
					tag:Destroy()
				end
			end
		end
	end
end

---------------------------------------------------------------------------

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "CrimeUI"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- estrelas + dinheiro sujo (embaixo do saldo, canto de cima à esquerda)
	statusFrame = Instance.new("Frame")
	statusFrame.Position = UDim2.fromOffset(12, 76)
	statusFrame.Size = UDim2.fromOffset(260, 52)
	statusFrame.BackgroundColor3 = NAVY
	statusFrame.BackgroundTransparency = 0.15
	statusFrame.Visible = false
	statusFrame.Parent = gui
	corner(statusFrame, 12)
	UIScaler.attach(statusFrame)
	starsLabel = label(statusFrame, { Size = UDim2.new(1, -16, 0, 26), Position = UDim2.fromOffset(8, 2), Font = Enum.Font.GothamBlack, Align = Enum.TextXAlignment.Left })
	dirtyLabel = label(statusFrame, { Size = UDim2.new(1, -16, 0, 18), Position = UDim2.fromOffset(8, 30), Color = Color3.fromRGB(140, 230, 140), Align = Enum.TextXAlignment.Left })

	-- assalto
	robFrame = Instance.new("Frame")
	robFrame.AnchorPoint = Vector2.new(0.5, 0)
	robFrame.Position = UDim2.new(0.5, 0, 0, 170)
	robFrame.Size = UDim2.fromOffset(420, 118)
	robFrame.BackgroundColor3 = NAVY
	robFrame.BackgroundTransparency = 0.08
	robFrame.Visible = false
	robFrame.Parent = gui
	corner(robFrame, 14)
	UIScaler.attach(robFrame)
	robTitle = label(robFrame, { Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 8), Font = Enum.Font.GothamBlack })
	robBar = Instance.new("Frame")
	robBar.Size = UDim2.new(1, -20, 0, 16)
	robBar.Position = UDim2.fromOffset(10, 40)
	robBar.BackgroundColor3 = Color3.fromRGB(50, 60, 90)
	robBar.Parent = robFrame
	corner(robBar, 8)
	robFill = Instance.new("Frame")
	robFill.Size = UDim2.fromScale(0, 1)
	robFill.BackgroundColor3 = Color3.fromRGB(240, 70, 70)
	robFill.Parent = robBar
	corner(robFill, 8)
	robButton = button(robFrame, "Continuar", Color3.fromRGB(60, 170, 80), UDim2.fromOffset(240, 44), UDim2.fromOffset(10, 66))
	robButton.Visible = false
	robButton.Activated:Connect(function()
		if CrimeController._atmNext then
			CrimeController._atmNext()
		end
	end)
	robCancel = button(robFrame, "Desistir", RED, UDim2.fromOffset(140, 44), UDim2.new(1, -150, 0, 66))
	robCancel.Activated:Connect(function()
		request:FireServer("CancelRob")
	end)

	-- polícia: botão Chamados (esquerda, no meio da tela) e o painel
	callsButton = button(gui, "📻 Chamados", BLUE, UDim2.fromOffset(150, 48))
	callsButton:SetAttribute("HudFixo", true) -- Marco 10.9: botão fixo do HUD (não solta o mouse da mira)
	callsButton.AnchorPoint = Vector2.new(0, 0.5)
	callsButton.Position = UDim2.new(0, 12, 0.5, 0)
	callsButton.Visible = false
	UIScaler.attach(callsButton)
	callsBadge = label(callsButton, { Size = UDim2.fromOffset(26, 26), Position = UDim2.new(1, -8, 0, -16), Font = Enum.Font.GothamBlack })
	callsBadge.BackgroundTransparency = 0
	callsBadge.BackgroundColor3 = RED
	callsBadge.Visible = false
	corner(callsBadge, 13)

	callsPanel = Instance.new("Frame")
	callsPanel.AnchorPoint = Vector2.new(0, 0.5)
	callsPanel.Position = UDim2.new(0, 172, 0.5, 0)
	callsPanel.Size = UDim2.fromOffset(400, 420)
	callsPanel.BackgroundColor3 = NAVY
	callsPanel.BackgroundTransparency = 0.05
	callsPanel.Visible = false
	callsPanel.Parent = gui
	corner(callsPanel, 16)
	UIScaler.attach(callsPanel)
	tabCalls = button(callsPanel, "📻 Chamados", BLUE, UDim2.new(0.5, -15, 0, 40), UDim2.fromOffset(10, 10))
	tabWanted = button(callsPanel, "⭐ Procurados", RED, UDim2.new(0.5, -15, 0, 40), UDim2.new(0.5, 5, 0, 10))
	tabCalls.Activated:Connect(function()
		tab = "calls"
		drawCalls()
	end)
	tabWanted.Activated:Connect(function()
		tab = "wanted"
		drawCalls()
	end)
	callsList = Instance.new("ScrollingFrame")
	callsList.Position = UDim2.fromOffset(8, 58)
	callsList.Size = UDim2.new(1, -16, 1, -66)
	callsList.BackgroundTransparency = 1
	callsList.BorderSizePixel = 0
	callsList.ScrollBarThickness = 6
	callsList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	callsList.CanvasSize = UDim2.new()
	callsList.Parent = callsPanel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = callsList
	-- painel da revista (Marco 10.6)
	friskPanel = Instance.new("Frame")
	friskPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	friskPanel.Position = UDim2.fromScale(0.5, 0.5)
	friskPanel.Size = UDim2.fromOffset(420, 400)
	friskPanel.BackgroundColor3 = NAVY
	friskPanel.BackgroundTransparency = 0.05
	friskPanel.Visible = false
	friskPanel.Parent = gui
	corner(friskPanel, 16)
	UIScaler.attach(friskPanel)
	friskTitle = label(friskPanel, { Size = UDim2.new(1, -70, 0, 30), Position = UDim2.fromOffset(14, 12), Font = Enum.Font.GothamBlack, Align = Enum.TextXAlignment.Left })
	local friskClose = button(friskPanel, "X", RED, UDim2.fromOffset(40, 40), UDim2.new(1, -50, 0, 8))
	friskClose.Activated:Connect(function()
		friskPanel.Visible = false
		request:FireServer("FriskClose")
	end)
	friskList = Instance.new("ScrollingFrame")
	friskList.Position = UDim2.fromOffset(8, 56)
	friskList.Size = UDim2.new(1, -16, 1, -64)
	friskList.BackgroundTransparency = 1
	friskList.BorderSizePixel = 0
	friskList.ScrollBarThickness = 6
	friskList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	friskList.CanvasSize = UDim2.new()
	friskList.Parent = friskPanel
	local friskLayout = Instance.new("UIListLayout")
	friskLayout.Padding = UDim.new(0, 6)
	friskLayout.SortOrder = Enum.SortOrder.LayoutOrder
	friskLayout.Parent = friskList

	callsButton.Activated:Connect(function()
		callsPanel.Visible = not callsPanel.Visible
		if callsPanel.Visible then
			seen = #calls
			request:FireServer("Calls")
			drawCalls()
		end
		refreshCallsButton()
	end)
end

function CrimeController.handle(kind, data)
	if kind == "CrimeRob" then
		if data.kind == "atm" then
			startAtm(data)
		else
			startStore(data)
		end
	elseif kind == "CrimeRobEnd" then
		hideRob()
		CrimeController._atmNext = nil
		if data.ok then
			HudController.toast(("+$%d de dinheiro sujo! Leve ao chefe da gangue."):format(data.reward or 0), Color3.fromRGB(60, 150, 70))
		elseif data.reason then
			HudController.toast(tostring(data.reason), RED)
		end
	elseif kind == "CrimeCalls" then
		calls = data.calls or {}
		seen = math.min(seen, #calls)
		if callsPanel.Visible then
			seen = #calls
			drawCalls()
		end
		refreshCallsButton()
	elseif kind == "CrimeNewCall" then
		HudController.toast(("%s: %s"):format(tostring(data.title), tostring(data.place)), data.npc and BLUE or RED)
		TweenService:Create(callsButton, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 3, true), { Rotation = 6 }):Play()
	elseif kind == "CrimeWanted" then
		wanted = data.list or {}
		if callsPanel.Visible then
			drawCalls()
		end
	elseif kind == "CrimeFrisk" then
		showFriskBar(data)
	elseif kind == "CrimeFriskEnd" then
		hideFriskBar()
		if data.reason then
			HudController.toast(tostring(data.reason), BLUE)
		end
	elseif kind == "CrimeFriskResult" then
		hideFriskBar()
		showFriskResult(data)
	elseif kind == "CrimePaid" then
		HudController.toast(tostring(data.text or ""), Color3.fromRGB(60, 150, 70))
	end
end

function CrimeController.init()
	request = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(GameConfig.Remotes.CrimeRequest)
	build()
	refreshStatus()
	for _, key in ipairs({ "Procurado", "DinheiroSujo" }) do
		player:GetAttributeChangedSignal(key):Connect(refreshStatus)
	end
	for _, key in ipairs({ "Gang", "Job" }) do
		player:GetAttributeChangedSignal(key):Connect(function()
			refreshPrompts()
			refreshCallsButton()
		end)
	end
	refreshCallsButton()
	-- botões criados depois (lugares e NPCs dos chamados)
	Workspace.DescendantAdded:Connect(function(d)
		if d:IsA("ProximityPrompt") and (d.Name == "CrimePrompt" or d.Name == "AbordarPrompt" or d.Name == "RevistarPrompt") then
			setPrompt(d)
		end
	end)
	refreshPrompts()
	task.spawn(overheadLoop)
end

return CrimeController
