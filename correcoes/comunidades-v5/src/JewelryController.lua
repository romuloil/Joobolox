-- JewelryController (ModuleScript)
-- Caminho: StarterPlayer > StarterPlayerScripts > Controllers > JewelryController
-- Marco 10.8: telas do assalto à joalheria (o JewelryService decide tudo).
-- Marco 10.9: minigame de mira (vitrines, gavetas, cofre, terminal), medidor de ALERTA, lista de
-- objetivos (cartão, código, cofre, saída), rastreador da bolsa e venda ao receptador.
-- Marco 10.11: animação de pegar joias (GameConfig.Jewelry.GrabAnim, R15 e R6) quando o minigame
-- dá certo: o boneco vira para a vitrine, quebra, pega e guarda (fica parado enquanto toca).
--   * Botões: "JoiaPrompt" só para quem é de gangue (e não é policial) e quando o servidor marca
--     "Ativo"; "JoiaPolicia" (arrombar a saída de emergência) só para a PM; "JoiaReceptador" (no chefe
--     da gangue) só para quem é daquela gangue e tem joias na bolsa.
--   * Reconhecimento: lista dos pontos; olhar para um deles (no meio da tela, sem nada na frente)
--     por um instante "anota" o ponto e avisa o servidor.
--   * Minigame: o ponteiro vai e volta; aperte E ou clique/toque em AGORA quando ele estiver na
--     faixa verde. Cada aperto vai para o servidor (ele confere tudo).

local CollectionService = game:GetService("CollectionService")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local HudController = require(script.Parent:WaitForChild("HudController"))
local UIScaler = require(script.Parent:WaitForChild("UIScaler"))

local JewelryController = {}

local J = GameConfig.Jewelry
local player = Players.LocalPlayer
local request
local MochilaController = require(script.Parent:WaitForChild("MochilaController"))
local MiniJogos = require(script.Parent:WaitForChild("MiniJogos"))
local gui, panel, chip, phaseLabel, timerRow, timerLabel, timerFill, noiseRow, noiseLabel, noiseFill
local goalsRow, goalLabels, casesRow, casesLabel, casesFill, bagLabel, escapeRow, escapeLabel, escapeFill, copLabel, hintLabel
local reconPanel, focusRing, focusFill
local mini, miniTitle, miniTrack, miniZone, miniCursor, miniDots, miniMiss, miniButton, miniHelp, miniArea
local BAR_HELP = "Aperte E (ou o AGORA) com o ponteiro no verde"
local status -- último JoiaStatus
local statusAt = 0
local bag = { value = 0, slots = 0, max = J.BagSlots, count = 0 }
local bagAt = 0
local copNear = false
local recon -- { alvos = { id = { row, found } }, endsAt, focus = { id, t } }
local mg -- minigame aberto: { id, hits, done, miss, maxMiss, zone, speed, center, t0, last }
local gunNow

local DARK = Color3.fromRGB(14, 15, 20)
local ROW = Color3.fromRGB(28, 30, 38)
local GOLD = Color3.fromRGB(232, 186, 88)
local RED = Color3.fromRGB(225, 60, 60)
local GREEN = Color3.fromRGB(70, 190, 110)
local MUTED = Color3.fromRGB(150, 156, 172)
local YELLOW = Color3.fromRGB(250, 205, 70)
local BLUE = Color3.fromRGB(120, 180, 255)

local function corner(parent, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

local function stroke(parent, color, t)
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.new(1, 1, 1)
	s.Transparency = t or 0.85
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
	l.TextSize = props.TextSize or 14
	l.TextScaled = props.Scaled == true
	l.TextXAlignment = props.Align or Enum.TextXAlignment.Left
	l.TextWrapped = props.Wrap == true
	l.TextTruncate = props.Wrap and Enum.TextTruncate.None or Enum.TextTruncate.AtEnd
	l.Parent = parent
	return l
end

local function bar(parent, pos, color, width)
	local b = Instance.new("Frame")
	b.Position = pos
	b.Size = width or UDim2.new(1, -28, 0, 6)
	b.BackgroundColor3 = Color3.fromRGB(45, 48, 60)
	b.BorderSizePixel = 0
	b.Parent = parent
	corner(b, 3)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = b
	corner(fill, 3)
	return b, fill
end

-- linha do painel (altura fixa, empilhada pelo UIListLayout)
local function row(height, order)
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.Size = UDim2.new(1, 0, 0, height)
	f.LayoutOrder = order
	f.Parent = panel
	return f
end

local function fmt(sec)
	sec = math.max(0, math.ceil(sec))
	return ("%d:%02d"):format(sec // 60, sec % 60)
end

local function storeModel()
	return CollectionService:GetTagged("Joalheria")[1]
end

local function isPolice()
	return player:GetAttribute("Job") == "Policial"
end

local function canRob()
	return player:GetAttribute("Gang") ~= nil and not isPolice()
end

local function hasGun()
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	return tool ~= nil and tool:GetAttribute("Use") == "gun"
end

---------------------------------------------------------------------------
-- Botões
---------------------------------------------------------------------------

local function setPrompt(prompt)
	if prompt.Name == "JoiaPrompt" then
		prompt.Enabled = canRob() and prompt:GetAttribute("Ativo") == true
		local kind = prompt:GetAttribute("Vitrine")
		if kind == "aneis" or kind == "relogios" or kind == "colares" then
			local onCounter = prompt.Parent and prompt.Parent.Parent and prompt.Parent.Parent:GetAttribute("Minigame") == "vitrine"
			if onCounter then
				prompt.ActionText = hasGun() and "Quebrar vitrine" or "Quebrar vitrine (sem arma: mais difícil)"
			end
		end
	elseif prompt.Name == "JoiaPolicia" then
		prompt.Enabled = isPolice()
	elseif prompt.Name == "JoiaReceptador" then
		prompt.Enabled = player:GetAttribute("Gang") ~= nil and player:GetAttribute("Gang") == prompt:GetAttribute("Gang") and (player:GetAttribute("JoiasNaBolsa") or 0) > 0
	end
end

local WATCH = { JoiaPrompt = true, JoiaPolicia = true, JoiaReceptador = true }
local watched = {}
local function watchPrompt(prompt)
	if watched[prompt] then
		return
	end
	watched[prompt] = true
	prompt:GetAttributeChangedSignal("Ativo"):Connect(function()
		setPrompt(prompt)
	end)
	prompt.Destroying:Connect(function()
		watched[prompt] = nil
	end)
	setPrompt(prompt)
end

local function refreshPrompts()
	for prompt in pairs(watched) do
		if prompt.Parent then
			setPrompt(prompt)
		end
	end
	local store = storeModel()
	if not store then
		return
	end
	for _, d in ipairs(store:GetDescendants()) do
		if d:IsA("ProximityPrompt") and WATCH[d.Name] then
			watchPrompt(d)
		end
	end
end

---------------------------------------------------------------------------
-- Painel do assalto
---------------------------------------------------------------------------

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "JoalheriaUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 3
	gui.Parent = player:WaitForChild("PlayerGui")

	panel = Instance.new("Frame")
	panel.Name = "PainelAssalto"
	panel:SetAttribute("HudFixo", true) -- Marco 10.30: o painel do assalto não solta a mira travada
	-- Marco 10.12: embaixo do minimapa e das barras de vida/stamina
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -14, 0, 206)
	UIScaler.onChanged(function(sc)
		panel.Position = UDim2.new(1, -14, 0, 206 * sc)
	end)
	panel.Size = UDim2.fromOffset(262, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = DARK
	panel.BackgroundTransparency = 0.08
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 14)
	stroke(panel, GOLD, 0.55)
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(34, 30, 24), Color3.fromRGB(12, 13, 18))
	grad.Rotation = 90
	grad.Parent = panel
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = panel

	local head = row(22, 1)
	label(head, { Text = "💎  " .. string.upper(J.Name), Position = UDim2.fromOffset(14, 2), Size = UDim2.new(1, -120, 0, 18), Font = Enum.Font.GothamBlack, TextSize = 14, Color = GOLD })
	chip = Instance.new("TextLabel")
	chip.AnchorPoint = Vector2.new(1, 0)
	chip.Position = UDim2.new(1, -12, 0, 1)
	chip.Size = UDim2.fromOffset(98, 20)
	chip.BackgroundColor3 = ROW
	chip.Font = Enum.Font.GothamBold
	chip.TextSize = 11
	chip.TextColor3 = Color3.new(1, 1, 1)
	chip.Text = ""
	chip.Parent = head
	corner(chip, 10)

	phaseLabel = label(row(16, 2), { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -28, 1, 0), TextSize = 12, Color = MUTED })

	timerRow = row(34, 3)
	timerLabel = label(timerRow, { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -28, 0, 22), Font = Enum.Font.GothamBlack, TextSize = 18 })
	local _, tf = bar(timerRow, UDim2.fromOffset(14, 26), YELLOW)
	timerFill = tf

	noiseRow = row(30, 4)
	noiseLabel = label(noiseRow, { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -28, 0, 16), TextSize = 12 })
	local _, nf = bar(noiseRow, UDim2.fromOffset(14, 19), GREEN, UDim2.new(1, -28, 0, 8))
	noiseFill = nf

	goalsRow = row(5 * 17 + 6, 5)
	local goalsBg = Instance.new("Frame")
	goalsBg.Position = UDim2.fromOffset(10, 2)
	goalsBg.Size = UDim2.new(1, -20, 1, -4)
	goalsBg.BackgroundColor3 = ROW
	goalsBg.BackgroundTransparency = 0.25
	goalsBg.Parent = goalsRow
	corner(goalsBg, 8)
	goalLabels = {}
	for i = 1, 5 do
		goalLabels[i] = label(goalsBg, { Position = UDim2.fromOffset(8, 2 + (i - 1) * 17), Size = UDim2.new(1, -14, 0, 16), TextSize = 11, Font = Enum.Font.GothamMedium })
	end

	casesRow = row(28, 6)
	casesLabel = label(casesRow, { Position = UDim2.fromOffset(14, 2), Size = UDim2.new(1, -28, 0, 16), TextSize = 12 })
	local _, cf = bar(casesRow, UDim2.fromOffset(14, 21), GOLD)
	casesFill = cf

	bagLabel = label(row(20, 7), { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -28, 1, 0), TextSize = 14, Font = Enum.Font.GothamBlack })

	escapeRow = row(64, 8)
	escapeLabel = label(escapeRow, { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -28, 0, 16), TextSize = 12 })
	local _, ef = bar(escapeRow, UDim2.fromOffset(14, 20), RED)
	escapeFill = ef
	hintLabel = label(escapeRow, { Position = UDim2.fromOffset(14, 30), Size = UDim2.new(1, -28, 0, 16), TextSize = 11, Color = MUTED })
	copLabel = label(escapeRow, { Position = UDim2.fromOffset(14, 46), Size = UDim2.new(1, -28, 0, 16), TextSize = 12, Color = RED, Text = "🚓 Polícia perto! Despiste primeiro." })

	-- reconhecimento
	reconPanel = Instance.new("Frame")
	reconPanel.Name = "Reconhecimento"
	reconPanel.AnchorPoint = Vector2.new(0, 0.5)
	reconPanel.Position = UDim2.new(0, 14, 0.5, 0)
	reconPanel.Size = UDim2.fromOffset(270, 218)
	reconPanel.BackgroundColor3 = DARK
	reconPanel.BackgroundTransparency = 0.08
	reconPanel.Visible = false
	reconPanel.Parent = gui
	corner(reconPanel, 14)
	stroke(reconPanel, BLUE, 0.55)
	label(reconPanel, { Text = "📋  RECONHECIMENTO", Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 18), Font = Enum.Font.GothamBlack, TextSize = 14, Color = Color3.fromRGB(150, 200, 255) })
	local sub = label(reconPanel, { Text = "Olhe para cada ponto até anotar.", Position = UDim2.fromOffset(14, 30), Size = UDim2.new(1, -28, 0, 14), TextSize = 11, Color = MUTED })
	sub.Name = "Sub"
	local list = Instance.new("Frame")
	list.Name = "Lista"
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromOffset(10, 50)
	list.Size = UDim2.new(1, -20, 1, -58)
	list.Parent = reconPanel
	local rl = Instance.new("UIListLayout")
	rl.Padding = UDim.new(0, 4)
	rl.SortOrder = Enum.SortOrder.LayoutOrder
	rl.Parent = list

	-- anel que enche no meio da tela quando está "anotando" um ponto
	focusRing = Instance.new("Frame")
	focusRing.AnchorPoint = Vector2.new(0.5, 0.5)
	focusRing.Position = UDim2.new(0.5, 0, 0.5, 40)
	focusRing.Size = UDim2.fromOffset(150, 26)
	focusRing.BackgroundColor3 = DARK
	focusRing.BackgroundTransparency = 0.2
	focusRing.Visible = false
	focusRing.Parent = gui
	corner(focusRing, 13)
	local fr = label(focusRing, { Text = "📸 Anotando...", Size = UDim2.fromScale(1, 1), Align = Enum.TextXAlignment.Center, TextSize = 12 })
	fr.ZIndex = 3
	focusFill = Instance.new("Frame")
	focusFill.Size = UDim2.fromScale(0, 1)
	focusFill.BackgroundColor3 = Color3.fromRGB(60, 130, 230)
	focusFill.BorderSizePixel = 0
	focusFill.ZIndex = 2
	focusFill.Parent = focusRing
	corner(focusFill, 13)

	-- minigame de mira
	mini = Instance.new("Frame")
	mini.Name = "Minigame"
	mini.AnchorPoint = Vector2.new(0.5, 0.5)
	mini.Position = UDim2.fromScale(0.5, 0.7)
	mini.Size = UDim2.fromOffset(380, 132)
	mini.BackgroundColor3 = DARK
	mini.BackgroundTransparency = 0.05
	mini.Visible = false
	mini.Parent = gui
	corner(mini, 14)
	stroke(mini, GOLD, 0.4)
	miniTitle = label(mini, { Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -60, 0, 18), Font = Enum.Font.GothamBlack, TextSize = 14, Color = GOLD })
	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -10, 0, 8)
	close.Size = UDim2.fromOffset(26, 22)
	close.BackgroundColor3 = ROW
	close.Text = "✖"
	close.TextColor3 = MUTED
	close.Font = Enum.Font.GothamBold
	close.TextSize = 12
	close.Parent = mini
	corner(close, 6)
	close.Activated:Connect(function()
		if mg then
			request:FireServer("MiniSair")
		end
	end)
	miniTrack = Instance.new("Frame")
	miniTrack.Position = UDim2.fromOffset(20, 38)
	miniTrack.Size = UDim2.new(1, -40, 0, 24)
	miniTrack.BackgroundColor3 = Color3.fromRGB(40, 42, 52)
	miniTrack.ClipsDescendants = true
	miniTrack.Parent = mini
	corner(miniTrack, 6)
	miniZone = Instance.new("Frame")
	miniZone.AnchorPoint = Vector2.new(0.5, 0)
	miniZone.Size = UDim2.fromScale(0.2, 1)
	miniZone.BackgroundColor3 = GREEN
	miniZone.Parent = miniTrack
	corner(miniZone, 4)
	miniCursor = Instance.new("Frame")
	miniCursor.AnchorPoint = Vector2.new(0.5, 0.5)
	miniCursor.Position = UDim2.fromScale(0, 0.5)
	miniCursor.Size = UDim2.new(0, 5, 1, 8)
	miniCursor.BackgroundColor3 = Color3.new(1, 1, 1)
	miniCursor.ZIndex = 3
	miniCursor.Parent = miniTrack
	miniDots = label(mini, { Position = UDim2.fromOffset(20, 70), Size = UDim2.fromOffset(150, 18), TextSize = 16, Font = Enum.Font.GothamBlack, Color = GREEN })
	miniMiss = label(mini, { Position = UDim2.fromOffset(20, 92), Size = UDim2.fromOffset(170, 16), TextSize = 11, Color = MUTED })
	miniHelp = label(mini, { Position = UDim2.fromOffset(20, 108), Size = UDim2.fromOffset(190, 16), TextSize = 10, Color = MUTED, Text = BAR_HELP })
	-- Marco 10.27: os outros minigames (MiniJogos) se desenham aqui
	miniArea = Instance.new("Frame")
	miniArea.Name = "Jogo"
	miniArea.Position = UDim2.fromOffset(20, 36)
	miniArea.Size = UDim2.new(1, -40, 0, 150)
	miniArea.BackgroundTransparency = 1
	miniArea.Visible = false
	miniArea.Parent = mini
	miniButton = Instance.new("TextButton")
	miniButton.AnchorPoint = Vector2.new(1, 1)
	miniButton.Position = UDim2.new(1, -16, 1, -14)
	miniButton.Size = UDim2.fromOffset(140, 46)
	miniButton.BackgroundColor3 = Color3.fromRGB(200, 150, 50)
	miniButton.Text = "AGORA!"
	miniButton.TextColor3 = Color3.fromRGB(20, 16, 8)
	miniButton.Font = Enum.Font.GothamBlack
	miniButton.TextSize = 20
	miniButton.Parent = mini
	corner(miniButton, 12)
end

local GOAL = {
	gerente = "🔑 Cartão: com o GERENTE (dormindo ou rendido)",
	seu = "🔑 Cartão com VOCÊ: passe no leitor da porta",
	pego = "🔑 Cartão: com alguém da gangue",
	aberta = "✅ Porta dos funcionários aberta",
}

local function setGoal(i, text, color)
	goalLabels[i].Text = text or ""
	goalLabels[i].TextColor3 = color or Color3.fromRGB(220, 222, 230)
end

local function render()
	local active = status and status.state == "assalto"
	local carrying = (bag.value or 0) > 0
	panel.Visible = active or carrying
	if not panel.Visible then
		return
	end
	local now = os.clock()
	local dt = now - statusAt
	timerRow.Visible = active
	noiseRow.Visible = active and status.noise ~= nil
	goalsRow.Visible = active
	casesRow.Visible = active
	if active then
		local silent = status.approach == "silencioso"
		chip.Text = silent and "🤫 Silencioso" or "🔫 Barulhento"
		chip.BackgroundColor3 = silent and Color3.fromRGB(40, 70, 120) or Color3.fromRGB(120, 40, 40)
		-- fase e relógio
		if status.locked then
			phaseLabel.Text = "🚨 PM a caminho • loja trancada"
			timerLabel.Text = "🔒 LOCKDOWN"
			timerLabel.TextColor3 = RED
			timerFill.Size = UDim2.fromScale(1, 1)
			timerFill.BackgroundColor3 = RED
		elseif status.alarm and status.lockIn then
			local left = status.lockIn - dt
			phaseLabel.Text = "🚨 Alarme tocando • PM a caminho"
			timerLabel.Text = "Lockdown em " .. fmt(left)
			timerLabel.TextColor3 = (math.floor(now * 2) % 2 == 0) and RED or Color3.fromRGB(255, 140, 140)
			timerFill.Size = UDim2.fromScale(math.clamp(left / J.Lockdown, 0, 1), 1)
			timerFill.BackgroundColor3 = RED
		elseif status.gasIn then
			local left = status.gasIn - dt
			phaseLabel.Text = "Funcionários dormindo 💤"
			timerLabel.Text = "Eles acordam em " .. fmt(left)
			timerLabel.TextColor3 = left < 30 and RED or YELLOW
			timerFill.Size = UDim2.fromScale(math.clamp(left / J.GasDuration, 0, 1), 1)
			timerFill.BackgroundColor3 = YELLOW
		else
			phaseLabel.Text = ""
			timerLabel.Text = "Assalto em andamento"
			timerLabel.TextColor3 = Color3.new(1, 1, 1)
			timerFill.Size = UDim2.fromScale(1, 1)
			timerFill.BackgroundColor3 = GREEN
		end
		-- medidor de alerta
		if status.noise then
			local n = math.clamp(status.noise, 0, 100)
			noiseLabel.Text = ("🔊 Alerta %d%%%s"):format(n, status.cams and "  •  📷 câmeras vendo" or "")
			noiseLabel.TextColor3 = n >= 70 and RED or (n >= 40 and YELLOW or Color3.new(1, 1, 1))
			noiseFill.Size = UDim2.fromScale(n / 100, 1)
			noiseFill.BackgroundColor3 = n >= 70 and RED or (n >= 40 and YELLOW or GREEN)
		end
		-- objetivos
		local guard = status.guard
		if guard == "alerta" then
			setGoal(1, ("👮 MIRE NO SEGURANÇA! %s"):format(fmt((status.guardIn or 0) - dt)), RED)
		elseif guard == "rendido" then
			setGoal(1, "✅ Segurança rendido", GREEN)
		elseif guard == "panico" then
			setGoal(1, "🚨 O segurança apertou o pânico", RED)
		elseif guard == "acordado" then
			setGoal(1, "😠 Funcionários acordados", RED)
		else
			setGoal(1, "💤 Segurança dormindo", MUTED)
		end
		setGoal(2, GOAL[status.card] or GOAL.gerente, status.card == "aberta" and GREEN or (status.card == "seu" and YELLOW or nil))
		if status.hackIn then
			setGoal(3, ("💻 Hackeado: câmeras e lasers OFF %s"):format(fmt(status.hackIn - dt)), GREEN)
		elseif status.code then
			setGoal(3, "📝 Código do cofre: " .. status.code, YELLOW)
		else
			setGoal(3, "📝 Código: gaveta do gerente ou terminal")
		end
		if status.vault == "aberto" then
			setGoal(4, status.hackIn and "✅ Cofre aberto (lasers desligados)" or "✅ Cofre aberto • CUIDADO com os lasers", GREEN)
		elseif status.vault == "furando" then
			setGoal(4, ("🔩 Furadeira no cofre: %s"):format(fmt((status.drillIn or 0) - dt)), YELLOW)
		else
			setGoal(4, "🏦 Cofre fechado (código ou furadeira)")
		end
		local ex = status.exit
		if ex == "trancada" then
			setGoal(5, ("🔒 Saída TRANCADA: segure E %d s nela"):format(J.ExitForceTime), RED)
		elseif ex == "destravada" then
			setGoal(5, ("🚪 Saída destravada pelo hack: %s"):format(fmt((status.exitIn or 0) - dt)), YELLOW)
		elseif ex == "forcada" then
			setGoal(5, "🚪 Saída forçada: está livre", GREEN)
		else
			setGoal(5, "🚪 Saída de emergência livre (tranca no lockdown)", MUTED)
		end
		-- Marco 10.20: evento acontecendo (o primeiro da lista) na linha da fase
		local ev = status.events and status.events[1]
		if ev then
			local left = ev.left and (ev.left - dt) or nil
			phaseLabel.Text = ("%s %s • %s%s"):format(ev.icon or "⚡", tostring(ev.name or ""), tostring(ev.hint or ""), left and left > 0 and ("  " .. fmt(left)) or "")
		end
		local total = math.max(1, status.total or 1)
		local taken = total - (status.left or 0)
		casesLabel.Text = ("Peças levadas: %d de %d"):format(taken, total)
		casesFill.Size = UDim2.fromScale(taken / total, 1)
	else
		chip.Text = "🏃 Fuga"
		chip.BackgroundColor3 = Color3.fromRGB(40, 110, 70)
		phaseLabel.Text = "Leve as joias ao receptador"
	end
	local heavy = (bag.slots or 0) >= math.ceil((bag.max or J.BagSlots) * 0.6)
	bagLabel.Text = ("🎒 Bolsa %d/%d  •  $%d%s"):format(bag.slots or 0, bag.max or J.BagSlots, bag.value or 0, heavy and "  •  pesada" or "")
	escapeRow.Visible = carrying
	if carrying then
		local left = bag.trackerIn and (bag.trackerIn - (now - bagAt)) or 0
		if bag.tracked and left > 0 then
			escapeLabel.Text = ("📡 Rastreador ligado: %s (a PM vê você)"):format(fmt(left))
			escapeLabel.TextColor3 = (math.floor(now * 2) % 2 == 0) and RED or Color3.fromRGB(255, 160, 160)
			escapeFill.Size = UDim2.fromScale(math.clamp(left / J.TrackerTime, 0, 1), 1)
			hintLabel.Text = "O chefe não compra enquanto ele estiver ligado."
		else
			escapeLabel.Text = "🤝 Venda ao chefe da sua gangue (F)"
			escapeLabel.TextColor3 = GREEN
			escapeFill.Size = UDim2.fromScale(0, 1)
			hintLabel.Text = active and "Saia da loja antes do lockdown!" or "Vá até a sua favela sem a polícia perto."
		end
		copLabel.Visible = copNear
	end
end

---------------------------------------------------------------------------
-- Minigame
---------------------------------------------------------------------------

local function tri(x)
	local f = x % 1
	return 1 - math.abs(f * 2 - 1)
end

local function newZone()
	local half = mg.zone / 2
	mg.center = half + 0.04 + math.random() * (1 - mg.zone - 0.08)
	miniZone.Size = UDim2.fromScale(mg.zone, 1)
	miniZone.Position = UDim2.fromScale(mg.center, 0)
end

local function drawDots()
	local s = ""
	for i = 1, mg.hits do
		s ..= (i <= mg.done) and "● " or "○ "
	end
	miniDots.Text = s
	local m = ""
	for i = 1, mg.maxMiss do
		m ..= (i <= mg.miss) and "✖ " or "· "
	end
	miniMiss.Text = "Erros: " .. m
	miniMiss.TextColor3 = mg.miss > 0 and RED or MUTED
end

local function setPromptsVisible(on)
	pcall(function()
		ProximityPromptService.Enabled = on
	end)
end

local function closeMini()
	mg = nil
	MiniJogos.close()
	mini.Visible = false
	setPromptsVisible(true)
end

-- Marco 10.27: resultado de cada etapa dos MiniJogos; o servidor ignora dois avisos com menos de 0.15 s
local function reportMini(hit)
	if not mg or mg.done >= mg.hits then
		return
	end
	local id = mg.id
	local now = os.clock()
	local delay = math.max(mg.last + 0.18 - now, 0)
	mg.last = now + delay
	task.delay(delay, function()
		request:FireServer("MiniHit", { id = id, hit = hit })
	end)
	if hit then
		mg.done += 1
		if mg.done >= mg.hits then
			miniTitle.Text = "✔ Feito!"
		end
	else
		mg.miss += 1
	end
	drawDots()
end

local function openMini(data)
	mg = {
		id = data.id,
		hits = data.hits or 2,
		done = 0,
		miss = 0,
		maxMiss = data.maxMiss or 3,
		zone = data.zone or 0.2,
		speed = data.speed or 1,
		t0 = os.clock() + math.random() * 0.5,
		last = 0,
	}
	miniTitle.Text = tostring(data.title or "")
	miniTrack.BackgroundColor3 = data.key == "terminal" and Color3.fromRGB(20, 40, 60) or Color3.fromRGB(40, 42, 52)
	local kind = MiniJogos.has(data.type) and data.type or nil
	mg.kind = kind
	miniTrack.Visible = not kind
	miniButton.Visible = not kind
	miniArea.Visible = kind ~= nil
	mini.Size = UDim2.fromOffset(380, kind and 248 or 132)
	mini.Position = UDim2.fromScale(0.5, kind and 0.6 or 0.7)
	miniDots.Position = UDim2.fromOffset(20, kind and 190 or 70)
	miniMiss.Position = UDim2.fromOffset(20, kind and 210 or 92)
	miniHelp.Position = UDim2.fromOffset(20, kind and 228 or 108)
	miniHelp.Size = UDim2.fromOffset(kind and 340 or 190, 16)
	if kind then
		local current = mg
		miniHelp.Text = MiniJogos.open(kind, miniArea, data, mg.hits, function()
			return current.done
		end, reportMini)
	else
		MiniJogos.close()
		miniHelp.Text = BAR_HELP
		newZone()
	end
	drawDots()
	mini.Visible = true
	setPromptsVisible(false)
	local scale = mini:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Scale = 0.8
	scale.Parent = mini
	TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function flash(color)
	miniTrack.BackgroundColor3 = color
	TweenService:Create(miniTrack, TweenInfo.new(0.35), { BackgroundColor3 = Color3.fromRGB(40, 42, 52) }):Play()
end

local function press()
	if not mg or mg.kind or mg.done >= mg.hits then
		return
	end
	local now = os.clock()
	if now - mg.last < 0.18 then
		return
	end
	mg.last = now
	local pos = tri((now - mg.t0) * mg.speed)
	local hit = math.abs(pos - mg.center) <= mg.zone / 2 + 0.01
	request:FireServer("MiniHit", { id = mg.id, hit = hit })
	if hit then
		mg.done += 1
		flash(GREEN)
		if mg.done < mg.hits then
			newZone()
		else
			miniTitle.Text = "✔ Feito!"
		end
	else
		mg.miss += 1
		flash(RED)
	end
	drawDots()
end

local function miniStep(dt)
	if not mg then
		return
	end
	if mg.kind then
		if mg.done < mg.hits then
			MiniJogos.step(dt)
		end
		return
	end
	local pos = tri((os.clock() - mg.t0) * mg.speed)
	miniCursor.Position = UDim2.fromScale(pos, 0.5)
end

---------------------------------------------------------------------------
-- Reconhecimento
---------------------------------------------------------------------------

local function targetPart(id)
	local store = storeModel()
	if not store then
		return nil
	end
	for _, d in ipairs(store:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("Alvo") == id then
			return d
		end
	end
	return nil
end

local function startRecon(data)
	local list = reconPanel:FindFirstChild("Lista")
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	recon = { alvos = {}, endsAt = os.clock() + (data.time or J.ReconTime) }
	for i, a in ipairs(data.alvos or {}) do
		local r = Instance.new("Frame")
		r.Size = UDim2.new(1, 0, 0, 22)
		r.BackgroundColor3 = ROW
		r.LayoutOrder = i
		r.Parent = list
		corner(r, 6)
		local l = label(r, { Text = "○  " .. tostring(a.name), Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -16, 1, 0), TextSize = 11 })
		l.Name = "Texto"
		recon.alvos[a.id] = { row = r, label = l, name = a.name, part = targetPart(a.id) }
	end
	reconPanel.Visible = true
	HudController.toast("📋 Reconhecimento: ache as câmeras, o leitor de cartão, o quadro de energia (beco) e o duto (telhado).", Color3.fromRGB(60, 120, 210))
end

local function markFound(id)
	local a = recon and recon.alvos[id]
	if not a or a.found then
		return
	end
	a.found = true
	a.label.Text = "✅  " .. a.name
	a.label.TextColor3 = GREEN
	if a.part then
		local h = Instance.new("Highlight")
		h.FillTransparency = 1
		h.OutlineColor = GREEN
		h.Adornee = a.part.Parent:IsA("Model") and a.part.Parent or a.part
		h.Parent = gui
		task.delay(4, function()
			h:Destroy()
		end)
	end
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function reconStep(dt)
	if not recon then
		focusRing.Visible = false
		return
	end
	local sub = reconPanel:FindFirstChild("Sub")
	if sub then
		sub.Text = ("Olhe para cada ponto até anotar • %s"):format(fmt(recon.endsAt - os.clock()))
	end
	local camera = Workspace.CurrentCamera
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not camera or not root then
		return
	end
	local vp = camera.ViewportSize
	local best
	for id, a in pairs(recon.alvos) do
		if not a.found and a.part and a.part.Parent then
			local p = a.part.Position
			if (p - root.Position).Magnitude <= 70 then
				local sp, on = camera:WorldToViewportPoint(p)
				if on and math.abs(sp.X - vp.X / 2) < vp.X * 0.14 and math.abs(sp.Y - vp.Y / 2) < vp.Y * 0.16 then
					rayParams.FilterDescendantsInstances = { player.Character, a.part.Parent.Name == "CameraSeguranca" and a.part.Parent or a.part }
					local origin = camera.CFrame.Position
					local hit = Workspace:Raycast(origin, p - origin, rayParams)
					if not hit or (hit.Position - p).Magnitude < 2 then
						best = id
					end
				end
			end
		end
	end
	if best then
		if not recon.focus or recon.focus.id ~= best then
			recon.focus = { id = best, t = 0 }
		end
		recon.focus.t += dt
		focusRing.Visible = true
		focusFill.Size = UDim2.fromScale(math.clamp(recon.focus.t / 0.9, 0, 1), 1)
		if recon.focus.t >= 0.9 and not recon.focus.sent then
			recon.focus.sent = true
			request:FireServer("Spot", best)
		end
	else
		recon.focus = nil
		focusRing.Visible = false
	end
end

local function endRecon()
	recon = nil
	focusRing.Visible = false
	task.delay(1.5, function()
		if not recon then
			reconPanel.Visible = false
		end
	end)
end

---------------------------------------------------------------------------
-- Efeitos
---------------------------------------------------------------------------

local function popup(text, color)
	local l = Instance.new("TextLabel")
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position = UDim2.new(0.5, 0, 0.58, 0)
	l.Size = UDim2.fromOffset(360, 34)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBlack
	l.TextSize = 26
	l.TextColor3 = color or GOLD
	l.TextStrokeTransparency = 0.4
	l.Text = text
	l.Parent = gui
	TweenService:Create(l, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0.48, 0), TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(1.5, function()
		l:Destroy()
	end)
end

local function bigCard(title, sub, color)
	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.32)
	card.Size = UDim2.fromOffset(400, 100)
	card.BackgroundColor3 = DARK
	card.BackgroundTransparency = 0.05
	card.Parent = gui
	corner(card, 16)
	stroke(card, color, 0.3)
	local scale = Instance.new("UIScale")
	scale.Scale = 0.6
	scale.Parent = card
	label(card, { Text = title, Position = UDim2.fromOffset(0, 14), Size = UDim2.new(1, 0, 0, 34), Align = Enum.TextXAlignment.Center, Font = Enum.Font.GothamBlack, TextSize = 28, Color = color })
	label(card, { Text = sub, Position = UDim2.fromOffset(16, 54), Size = UDim2.new(1, -32, 0, 34), Align = Enum.TextXAlignment.Center, TextSize = 14, Wrap = true, Color = Color3.fromRGB(220, 222, 230) })
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(5, function()
		TweenService:Create(card, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		task.wait(0.4)
		card:Destroy()
	end)
end

---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Animação de pegar joias (Marco 10.11)
---------------------------------------------------------------------------

local GA = J.GrabAnim or {}
local grabTrack -- { char, id, track }
local grabToken = 0
local grabWarned = false
local studioIds = {} -- [rig] = id temporário do Studio (KeyframeSequence sem publicar)

local function toAnimId(v)
	if type(v) == "number" and v > 0 then
		return "rbxassetid://" .. tostring(math.floor(v))
	elseif type(v) == "string" and v ~= "" and v ~= "0" then
		return string.find(v, "://", 1, true) and v or ("rbxassetid://" .. v)
	end
	return nil
end

local function grabAnimId(rig)
	local id = toAnimId(GA[rig])
	if id then
		return id
	end
	-- sem ID: só no Studio, usando o KeyframeSequence em ReplicatedStorage > Animacoes
	if not RunService:IsStudio() then
		return nil
	end
	if studioIds[rig] then
		return studioIds[rig]
	end
	local folder = ReplicatedStorage:FindFirstChild("Animacoes")
	local ks = folder and folder:FindFirstChild("JewelGrab_" .. rig)
	if ks and ks:IsA("KeyframeSequence") then
		local ok, tmp = pcall(function()
			return KeyframeSequenceProvider:RegisterKeyframeSequence(ks)
		end)
		if ok and tmp then
			studioIds[rig] = tmp
			return tmp
		end
	end
	return nil
end

local function setControls(enabled)
	pcall(function()
		local playerModule = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
		local controls = playerModule:GetControls()
		if enabled then
			controls:Enable()
		else
			controls:Disable()
		end
	end)
end

local function grabEnded()
	if GA.Lock ~= false then
		setControls(true)
	end
	if not mg then
		setPromptsVisible(true)
	end
end

local function stopGrab()
	if grabToken % 2 == 1 then
		grabToken += 1
		grabEnded()
	end
	if grabTrack and grabTrack.track.IsPlaying then
		grabTrack.track:Stop(0.15)
	end
end

local function playGrab(at)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not root or hum.Health <= 0 or hum.SeatPart or hum.PlatformStand then
		return
	end
	if player:GetAttribute("Algemado") or player:GetAttribute("Atordoado") then
		return
	end
	local rig = hum.RigType == Enum.HumanoidRigType.R6 and "R6" or "R15"
	local id = grabAnimId(rig)
	local animator = hum:FindFirstChildOfClass("Animator")
	if not id or not animator then
		return
	end
	if not grabTrack or grabTrack.char ~= char or grabTrack.id ~= id then
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local ok, track = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		if not ok or not track then
			warn("[JewelryController] Não deu para carregar a animação de pegar joias: " .. tostring(track))
			return
		end
		track.Priority = Enum.AnimationPriority.Action4
		track.Looped = false
		grabTrack = { char = char, id = id, track = track }
	end
	-- vira de frente para a vitrine
	if typeof(at) == "Vector3" then
		local p = root.Position
		local flat = Vector3.new(at.X, p.Y, at.Z)
		if (flat - p).Magnitude > 0.5 then
			root.CFrame = CFrame.lookAt(p, flat)
		end
	end
	stopGrab()
	grabToken += 1 -- ímpar = tocando
	local my = grabToken
	if GA.Lock ~= false then
		setControls(false)
		hum:Move(Vector3.zero)
	end
	setPromptsVisible(false) -- sem abrir outra vitrine no meio da animação
	-- Marco 10.15: guarda a arma. Com arma na mão a pose da arma (WeaponPose) segura os braços
	-- todo quadro e a animação não aparecia
	hum:UnequipTools()
	local track = grabTrack.track
	track:Play(0.1)
	task.delay(1.2, function()
		if track.Length <= 0 and not grabWarned then
			grabWarned = true
			warn("[JewelryController] A animação de pegar joias não carregou (" .. tostring(id) .. "). Ela precisa ser da mesma conta ou grupo dono do jogo.")
			if RunService:IsStudio() then
				HudController.toast("Animação das joias não carregou: veja o Output", RED)
			end
		end
	end)
	local length = (track.Length > 0 and track.Length) or GA.Length or 3.5
	local function done()
		if grabToken == my then
			grabToken += 1
			grabEnded()
		end
	end
	track.Stopped:Once(done)
	task.delay(length + 0.4, done) -- garantia: nunca fica preso
end

function JewelryController.handle(kind, data)
	if kind == "JoiaStatus" then
		status = data
		statusAt = os.clock()
	elseif kind == "JoiaAchado" then
		MochilaController.offer("joia", data)
	elseif kind == "JoiaBolsa" then
		bag = data
		bagAt = os.clock()
		MochilaController.update("joia", data)
		if (data.value or 0) <= 0 then
			copNear = false
		end
	elseif kind == "JoiaPolicia" then
		copNear = data.near == true
	elseif kind == "JoiaPegou" then
		task.spawn(playGrab, data.at)
		popup(("+$%d  %s"):format(data.value or 0, tostring(data.name or "")), data.diamond and Color3.fromRGB(170, 220, 255) or GOLD)
		if data.diamond then
			bigCard("💎 DIAMANTE ESTRELA!", "A peça mais cara da loja está na sua bolsa.", Color3.fromRGB(170, 220, 255))
		end
	elseif kind == "JoiaAviso" then
		HudController.toast(tostring(data.text or ""), data.color == "red" and RED or Color3.fromRGB(190, 140, 50))
	elseif kind == "JoiaEvento" then
		bigCard(("%s %s"):format(data.icon or "⚡", tostring(data.name or "EVENTO"):upper()), tostring(data.text or ""), YELLOW)
	elseif kind == "JoiaFuga" then
		bigCard("💰 JOIAS VENDIDAS", ("O receptador pagou $%d por %d peça(s). Assalto concluído!"):format(data.value or 0, data.count or 0), GREEN)
	elseif kind == "JoiaMinigame" then
		openMini(data)
	elseif kind == "JoiaMinigameFim" then
		if mg and mg.id == data.id then
			closeMini()
			if not data.ok and data.why then
				HudController.toast("❌ " .. tostring(data.why), RED)
			end
		end
	elseif kind == "JoiaRecon" then
		startRecon(data)
	elseif kind == "JoiaReconAchou" then
		markFound(data.id)
		HudController.toast(("📸 Anotado: %s (%d/%d)"):format(tostring(data.name), data.n or 0, data.total or 6), Color3.fromRGB(60, 120, 210))
	elseif kind == "JoiaReconFim" then
		endRecon()
		if data.ok then
			bigCard("📋 RECONHECIMENTO FEITO", ("%s achou tudo. Plano silencioso liberado por %d min: gás no duto do telhado."):format(tostring(data.by or "Alguém"), data.minutes or 20), BLUE)
		else
			HudController.toast("O tempo do reconhecimento acabou. Tente de novo no catálogo da loja.", RED)
		end
	end
end

function JewelryController.init()
	request = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(GameConfig.Remotes.JewelryRequest)
	build()
	refreshPrompts()
	Workspace.DescendantAdded:Connect(function(d)
		if d:IsA("ProximityPrompt") and WATCH[d.Name] then
			task.defer(watchPrompt, d)
		end
	end)
	-- receptador (chefes das favelas): o servidor marca com a tag "JoiaReceptador"
	for _, prompt in ipairs(CollectionService:GetTagged("JoiaReceptador")) do
		watchPrompt(prompt)
	end
	CollectionService:GetInstanceAddedSignal("JoiaReceptador"):Connect(watchPrompt)
	for _, key in ipairs({ "Gang", "Job", "JoiasNaBolsa" }) do
		player:GetAttributeChangedSignal(key):Connect(refreshPrompts)
	end
	miniButton.Activated:Connect(press)
	UserInputService.InputBegan:Connect(function(input)
		if not mg or UserInputService:GetFocusedTextBox() then
			return
		end
		-- clique no mundo não conta (com arma na mão ele atiraria): só E, controle ou o botão AGORA
		if input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonX then
			press()
		end
	end)
	player.CharacterRemoving:Connect(function()
		if mg then
			closeMini()
		end
		stopGrab()
		grabTrack = nil
	end)
	-- levou taser ou algema no meio da animação: para na hora
	for _, key in ipairs({ "Algemado", "Atordoado" }) do
		player:GetAttributeChangedSignal(key):Connect(function()
			if player:GetAttribute(key) then
				stopGrab()
			end
		end)
	end
	task.spawn(function()
		while true do
			task.wait(0.3)
			local g = hasGun()
			if g ~= gunNow then
				gunNow = g
				refreshPrompts()
			end
			if recon and os.clock() > recon.endsAt + 2 then
				endRecon()
			end
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		reconStep(dt)
		miniStep(dt)
		render()
	end)
	request:FireServer("Status")
end

-- Marco 10.20: o banco usa a mesma animação de pegar
JewelryController.playGrab = function(at)
	task.spawn(playGrab, at)
end

return JewelryController
