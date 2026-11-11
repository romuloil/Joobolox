-- BankController (ModuleScript)
-- Caminho: StarterPlayer > StarterPlayerScripts > Controllers > BankController
-- Marco 10.20: telas do ASSALTO AO BANCO (o BankService decide tudo; aqui só mostra).
--   * Painel (mesmo lugar do da joalheria): fase N/6, relógios (alarme, cerco, tomada do prédio),
--     furadeira, lista de objetivos, equipe com o valor de cada bolsa, eventos acontecendo, bolsa,
--     rastreador e "polícia perto".
--   * Perto do banco (gangue): mostra a PREPARAÇÃO (crachá, energia) e se tem obra (Reforma).
--   * Botões: "BancoPrompt" só para quem é de gangue (não policial) e quando o servidor marca
--     "Ativo"; "BancoPolicia" só para a PM (e "Ativo"); "BancoReceptador" (chefe da gangue) só para
--     quem é daquela gangue e tem malote.
--   * O minigame é a mesma janela da joalheria (JewelryController).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local HudController = require(script.Parent:WaitForChild("HudController"))
local UIScaler = require(script.Parent:WaitForChild("UIScaler"))
local MobileButtons = require(script.Parent:WaitForChild("MobileButtons"))
local UserInputService = game:GetService("UserInputService")
local tensionRow, tensionLabel, tensionFill
local MochilaController = require(script.Parent:WaitForChild("MochilaController"))
local ProximityPromptService = game:GetService("ProximityPromptService")
local JewelryController = require(script.Parent:WaitForChild("JewelryController"))

local BankController = {}

local B = GameConfig.Bank
local player = Players.LocalPlayer
local request
local gui, panel, chip, phaseLabel, timerRow, timerLabel, timerFill, drillRow, drillLabel, drillFill
local goalsRow, goalLabels, crewLabel, eventsRow, eventLabels, bagLabel, escapeRow, escapeLabel, escapeFill, copLabel, hintLabel
local prepRow, prepLabel
local status
local statusAt = 0
local bag = { value = 0, slots = 0, max = B.BagSlots, count = 0 }
local bagAt = 0
local copNear = false

local DARK = Color3.fromRGB(13, 16, 22)
local ROW = Color3.fromRGB(27, 32, 42)
local STEEL = Color3.fromRGB(150, 185, 220)
local GOLD = Color3.fromRGB(232, 186, 88)
local RED = Color3.fromRGB(225, 60, 60)
local GREEN = Color3.fromRGB(70, 190, 110)
local MUTED = Color3.fromRGB(150, 156, 172)
local YELLOW = Color3.fromRGB(250, 205, 70)
local WHITE = Color3.fromRGB(225, 228, 236)

local MAX_GOALS = 8
local MAX_EVENTS = 4

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
	b.BackgroundColor3 = Color3.fromRGB(45, 50, 62)
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

local function row(height, order)
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.Size = UDim2.new(1, 0, 0, height)
	f.LayoutOrder = order
	f.Parent = panel
	return f
end

local function box(parent)
	local bg = Instance.new("Frame")
	bg.Position = UDim2.fromOffset(10, 2)
	bg.Size = UDim2.new(1, -20, 1, -4)
	bg.BackgroundColor3 = ROW
	bg.BackgroundTransparency = 0.25
	bg.Parent = parent
	corner(bg, 8)
	return bg
end

local function fmt(sec)
	sec = math.max(0, math.ceil(sec))
	return ("%d:%02d"):format(sec // 60, sec % 60)
end

local function money(n)
	return "$" .. tostring(math.floor(n or 0))
end

local function isPolice()
	return player:GetAttribute("Job") == "Policial"
end

local function canRob()
	return player:GetAttribute("Gang") ~= nil and not isPolice()
end

---------------------------------------------------------------------------
-- Botões
---------------------------------------------------------------------------

-- Marco 10.30: botão que precisa de um item (Perfuratriz, C4): só aparece para quem tem
local function hasItem(id)
	for _, holder in ipairs({ player.Character, player:FindFirstChildOfClass("Backpack") }) do
		if holder then
			for _, t in ipairs(holder:GetChildren()) do
				if t:IsA("Tool") and t:GetAttribute("ItemId") == id then
					return true
				end
			end
		end
	end
	return false
end

-- Marco 10.30: perfuratriz e C4 abrem a mesma porta, as duas no E. Quem tiver as duas vê só o botão
-- da que está na mão (sem nenhuma na mão: a perfuratriz)
local function canUse(id)
	if not hasItem(id) then
		return false
	end
	local other = (id == "C4" and "Perfuratriz") or (id == "Perfuratriz" and "C4") or nil
	if not other or not hasItem(other) then
		return true
	end
	local tool = player.Character and player.Character:FindFirstChildOfClass("Tool")
	local inHand = tool and tool:GetAttribute("ItemId")
	if inHand == id then
		return true
	elseif inHand == other then
		return false
	end
	return id == "Perfuratriz"
end

local function setPrompt(prompt)
	local free = not player:GetAttribute("Preso") and not player:GetAttribute("Algemado") and not player:GetAttribute("Caido")
	if prompt.Name == "BancoPrompt" then
		-- Sem gangue o servidor explica o requisito, em vez de o E simplesmente desaparecer.
		local on = free and not isPolice() and prompt:GetAttribute("Ativo") == true
		local need = prompt:GetAttribute("Precisa")
		if need ~= nil then
			on = on and canUse(need)
		end
		local action = prompt:GetAttribute("BancoAcao")
		if action == "Passar o crachá" then
			on = on and player:GetAttribute("CrachaBanco") == true
		elseif action == "Arrombar a porta" then
			on = on and player:GetAttribute("CrachaBanco") ~= true
		elseif action == "Abrir por dentro" then
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local bank = CollectionService:GetTagged("Banco")[1]
			local area = bank and bank:FindFirstChild("AreaRestrita", true)
			local pos = root and area and area.CFrame:PointToObjectSpace(root.Position)
			on = on and pos ~= nil and math.abs(pos.X) <= area.Size.X / 2 and math.abs(pos.Z) <= area.Size.Z / 2
		end
		prompt.Enabled = on
	elseif prompt.Name == "BancoPolicia" then
		prompt.Enabled = free and isPolice() and prompt:GetAttribute("Ativo") == true
	elseif prompt.Name == "BancoReceptador" then
		prompt.Enabled = free and canRob() and player:GetAttribute("Gang") == prompt:GetAttribute("Gang") and (player:GetAttribute("MaloteBanco") or 0) > 0
	end
end

local WATCH = { BancoPrompt = true, BancoPolicia = true, BancoReceptador = true }
local watched = {}
local function watchPrompt(prompt)
	if watched[prompt] then
		return
	end
	watched[prompt] = true
	prompt:GetAttributeChangedSignal("Ativo"):Connect(function()
		setPrompt(prompt)
	end)
	prompt:GetAttributeChangedSignal("Gang"):Connect(function() setPrompt(prompt) end)
	prompt:GetPropertyChangedSignal("Enabled"):Connect(function() setPrompt(prompt) end)
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
end

---------------------------------------------------------------------------
-- Painel
---------------------------------------------------------------------------

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "BancoUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 3
	gui.Parent = player:WaitForChild("PlayerGui")

	panel = Instance.new("Frame")
	panel.Name = "PainelBanco"
	panel:SetAttribute("HudFixo", true) -- Marco 10.30: o painel do assalto não solta a mira travada
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -14, 0, 206)
	UIScaler.onChanged(function(sc)
		panel.Position = UDim2.new(1, -14, 0, 206 * sc)
	end)
	panel.Size = UDim2.fromOffset(278, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = DARK
	panel.BackgroundTransparency = 0.08
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 14)
	stroke(panel, STEEL, 0.5)
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(26, 34, 46), Color3.fromRGB(11, 13, 18))
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
	label(head, { Text = "🏦  " .. string.upper(B.Short or B.Name), Position = UDim2.fromOffset(14, 2), Size = UDim2.new(1, -120, 0, 18), Font = Enum.Font.GothamBlack, TextSize = 14, Color = STEEL })
	chip = Instance.new("TextLabel")
	chip.AnchorPoint = Vector2.new(1, 0)
	chip.Position = UDim2.new(1, -12, 0, 1)
	chip.Size = UDim2.fromOffset(104, 20)
	chip.BackgroundColor3 = ROW
	chip.Font = Enum.Font.GothamBold
	chip.TextSize = 11
	chip.TextColor3 = Color3.new(1, 1, 1)
	chip.Text = ""
	chip.Parent = head
	corner(chip, 10)

	phaseLabel = label(row(16, 2), { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -28, 1, 0), TextSize = 12, Color = MUTED })

	prepRow = row(38, 3)
	prepLabel = label(box(prepRow), { Position = UDim2.fromOffset(8, 2), Size = UDim2.new(1, -14, 1, -4), TextSize = 11, Font = Enum.Font.GothamMedium, Wrap = true, Color = WHITE })

	timerRow = row(34, 4)
	timerLabel = label(timerRow, { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -28, 0, 22), Font = Enum.Font.GothamBlack, TextSize = 17 })
	local _, tf = bar(timerRow, UDim2.fromOffset(14, 26), YELLOW)
	timerFill = tf

	-- Marco 10.25: tensão dos reféns (G para gritar)
	tensionRow = row(28, 5)
	tensionLabel = label(tensionRow, { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -28, 0, 14), TextSize = 11 })
	local _, tnf = bar(tensionRow, UDim2.fromOffset(14, 16), YELLOW)
	tensionFill = tnf

	drillRow = row(30, 5)
	drillLabel = label(drillRow, { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -28, 0, 16), TextSize = 12 })
	local _, df = bar(drillRow, UDim2.fromOffset(14, 19), Color3.fromRGB(255, 150, 50), UDim2.new(1, -28, 0, 8))
	drillFill = df

	goalsRow = row(MAX_GOALS * 17 + 6, 6)
	local gb = box(goalsRow)
	goalLabels = {}
	for i = 1, MAX_GOALS do
		goalLabels[i] = label(gb, { Position = UDim2.fromOffset(8, 2 + (i - 1) * 17), Size = UDim2.new(1, -14, 0, 16), TextSize = 11, Font = Enum.Font.GothamMedium })
	end

	eventsRow = row(MAX_EVENTS * 30 + 6, 7)
	local eb = box(eventsRow)
	eb.BackgroundColor3 = Color3.fromRGB(46, 38, 18)
	eventLabels = {}
	for i = 1, MAX_EVENTS do
		eventLabels[i] = label(eb, { Position = UDim2.fromOffset(8, 2 + (i - 1) * 30), Size = UDim2.new(1, -14, 0, 28), TextSize = 11, Font = Enum.Font.GothamMedium, Wrap = true, Color = YELLOW })
	end

	crewLabel = label(row(30, 8), { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -28, 1, 0), TextSize = 11, Color = MUTED, Wrap = true })

	bagLabel = label(row(20, 9), { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -28, 1, 0), TextSize = 14, Font = Enum.Font.GothamBlack })

	escapeRow = row(64, 10)
	escapeLabel = label(escapeRow, { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -28, 0, 16), TextSize = 12 })
	local _, ef = bar(escapeRow, UDim2.fromOffset(14, 20), RED)
	escapeFill = ef
	hintLabel = label(escapeRow, { Position = UDim2.fromOffset(14, 30), Size = UDim2.new(1, -28, 0, 16), TextSize = 11, Color = MUTED })
	copLabel = label(escapeRow, { Position = UDim2.fromOffset(14, 46), Size = UDim2.new(1, -28, 0, 16), TextSize = 12, Color = RED, Text = "🚓 Polícia perto! Despiste primeiro." })
end

-- Marco 10.24: o objetivo de agora em letra grande no topo, com seta e marcador no mundo
local goalMarkers, goalKey, goalAt = {}, nil, nil
local lastGoalStep -- etapa anterior, para avisar quando conclui

local popupFn, pingFn -- definidas mais abaixo
local flyNotes

local function setGoalMarkers(list, mark)
	local key = tostring(mark)
	for _, pos in ipairs(list or {}) do
		key ..= ("|%d,%d,%d"):format(pos.X // 3, pos.Y // 3, pos.Z // 3)
	end
	if key == goalKey then
		return
	end
	goalKey = key
	for _, m in ipairs(goalMarkers) do
		m:Destroy()
	end
	goalMarkers = {}
	for _, pos in ipairs(list or {}) do
		table.insert(goalMarkers, HudController.newMarker(pos, mark))
	end
end

local function updateGoal(active, carrying, nearPrep)
	if active and status.goalText then
		if goalAt == statusAt then
			return
		end
		goalAt = statusAt
		local steps, step = {}, nil
		for i, g in ipairs(status.goals or {}) do
			steps[i] = g.t
			if not g.d and not step then
				step = i
			end
		end
		-- Marco 10.25: resposta na hora quando uma etapa fecha
		if step and lastGoalStep and step > lastGoalStep then
			popupFn("✅ Etapa concluída!", GREEN)
			pingFn()
		end
		lastGoalStep = step
		HudController.setHeistTask({
			head = ("🏦 Assalto ao banco · Fase %d de 7"):format(status.phase or 2),
			text = status.goalText,
			hint = status.goalHint,
			targets = status.goalPos or {},
			steps = steps,
			step = step or #steps,
			total = #steps,
			next = step and steps[step + 1] or nil,
		})
		setGoalMarkers(status.goalPos, status.goalMark)
	elseif carrying then
		setGoalMarkers(nil)
		HudController.setHeistTask({
			head = "🏦 Fuga com o malote",
			text = "Leve o malote ao chefe da sua gangue e venda (F)",
			hint = "Fuja da polícia: perto dela o chefe não compra",
			steps = {},
			step = 1,
			total = 1,
		})
	elseif nearPrep and status.state ~= "fechado" and status.state ~= "assalto" and typeof(status.startPos) == "Vector3" then
		setGoalMarkers(nil)
		HudController.setHeistTask({
			head = "🏦 Banco Central · como começar",
			text = "Com a arma na mão, anuncie o assalto no meio do salão",
			hint = "Segure E: \"Anunciar o assalto\"",
			targets = { status.startPos },
			steps = {},
			step = 1,
			total = 1,
		})
	else
		setGoalMarkers(nil)
		HudController.setHeistTask(nil)
	end
end

local function render()
	local now = os.clock()
	local dt = now - statusAt
	local fresh = status ~= nil and dt < 4
	local active = fresh and status.state == "assalto" and status.member == true
	local carrying = (bag.value or 0) > 0
	local nearPrep = fresh and not active and canRob() and status.state ~= nil
	updateGoal(active, carrying, nearPrep)
	panel.Visible = active or carrying or nearPrep
	if not panel.Visible then
		return
	end
	prepRow.Visible = nearPrep
	timerRow.Visible = active
	drillRow.Visible = active and status.drill ~= nil
	goalsRow.Visible = active
	tensionRow.Visible = active and status.tension ~= nil
	MobileButtons.show("gritar", active == true)
	if active and status.tension then
		local t = status.tension
		tensionLabel.Text = ("😱 Reféns: %d%%%s"):format(t, t >= 75 and "  •  APERTE G!" or "  •  G grita")
		tensionLabel.TextColor3 = t >= 75 and RED or MUTED
		tensionFill.Size = UDim2.fromScale(math.clamp(t / 100, 0, 1), 1)
		tensionFill.BackgroundColor3 = t >= 75 and RED or YELLOW
	end
	crewLabel.Parent.Visible = active
	local evs = fresh and status.events or {}
	eventsRow.Visible = (active or nearPrep) and #evs > 0
	if nearPrep then
		local pr = status.prep or {}
		if status.state == "fechado" then
			chip.Text = "🔒 Fechado"
			chip.BackgroundColor3 = Color3.fromRGB(70, 70, 80)
			phaseLabel.Text = ("Perícia: reabre em %s"):format(fmt((status.closedIn or 0) - dt))
		elseif status.state == "assalto" then
			chip.Text = "🚨 Em assalto"
			chip.BackgroundColor3 = Color3.fromRGB(120, 40, 40)
			phaseLabel.Text = "Outra equipe está assaltando o banco."
		else
			chip.Text = "Fase 1/7"
			chip.BackgroundColor3 = Color3.fromRGB(40, 70, 120)
			phaseLabel.Text = "Preparação (opcional)"
		end
		local lines = {
			pr.cracha and ("✅ 🪪 Crachá da gangue: vale %s"):format(fmt(pr.cracha - dt)) or "🪪 Crachá: funcionário que fuma no beco (leste)",
			pr.energia and ("✅ ⚡ Energia cortada: vale %s"):format(fmt(pr.energia - dt)) or "⚡ Energia: transformador do beco (alarme atrasa)",
		}
		prepLabel.Text = table.concat(lines, "\n") .. ("\n👥 Anúncio: arma na mão + %d da gangue no salão"):format(B.MinCrew)
		prepRow.Size = UDim2.new(1, 0, 0, 54)
	elseif active then
		local ph = status.phase or 2
		chip.Text = ("Fase %d/7"):format(ph)
		chip.BackgroundColor3 = status.sieged and Color3.fromRGB(150, 30, 30) or (ph >= 5 and Color3.fromRGB(40, 110, 70) or Color3.fromRGB(120, 40, 40))
		phaseLabel.Text = ("%s%s%s"):format(tostring(status.phaseName or ""), status.cams and "  •  📷 câmeras gravando" or "  •  📷 câmeras mudas", status.solo and "  •  sozinho" or "")
		-- relógio principal
		if status.sieged then
			local left = (status.takeIn or 0) - dt
			timerLabel.Text = "🚔 CERCO! Tomada em " .. fmt(left)
			timerLabel.TextColor3 = (math.floor(now * 2) % 2 == 0) and RED or Color3.fromRGB(255, 140, 140)
			timerFill.Size = UDim2.fromScale(math.clamp(left / B.SiegeFinal, 0, 1), 1)
			timerFill.BackgroundColor3 = RED
		elseif status.alarmIn then
			local left = status.alarmIn - dt
			timerLabel.Text = "⚡ Alarme chega na PM em " .. fmt(left)
			timerLabel.TextColor3 = YELLOW
			timerFill.Size = UDim2.fromScale(math.clamp(left / math.max(1, B.PowerAlarmDelay + 15), 0, 1), 1)
			timerFill.BackgroundColor3 = YELLOW
		elseif status.siegeIn then
			local left = status.siegeIn - dt
			timerLabel.Text = "🚨 Cerco em " .. fmt(left)
			timerLabel.TextColor3 = left < 60 and RED or WHITE
			timerFill.Size = UDim2.fromScale(math.clamp(left / B.SiegeTime, 0, 1), 1)
			timerFill.BackgroundColor3 = left < 60 and RED or YELLOW
		end
		-- furadeira
		if status.drill then
			local pct = math.clamp(status.drill, 0, 1)
			drillLabel.Text = status.jam and "🔥 BROCA TRAVOU! Destrave (segure E na porta)" or ("🛠️ Perfuratriz: %d%%"):format(math.floor(pct * 100))
			drillLabel.TextColor3 = status.jam and RED or WHITE
			drillFill.Size = UDim2.fromScale(pct, 1)
			drillFill.BackgroundColor3 = status.jam and RED or Color3.fromRGB(255, 150, 50)
		end
		-- objetivos
		local goals = status.goals or {}
		for i = 1, MAX_GOALS do
			local g = goals[i]
			local l = goalLabels[i]
			if g then
				l.Text = (g.d and "✅ " or (g.h and "▶ " or "○ ")) .. tostring(g.t)
				l.TextColor3 = g.d and GREEN or (g.h and ((math.floor(now * 2) % 2 == 0) and YELLOW or WHITE) or MUTED)
			else
				l.Text = ""
			end
		end
		-- equipe
		local parts = {}
		local total = 0
		for _, c in ipairs(status.crew or {}) do
			table.insert(parts, ("%s %s"):format(tostring(c.name), money(c.value)))
			total += c.value or 0
		end
		crewLabel.Text = ("👥 Equipe (%s): %s"):format(money(total), table.concat(parts, " • "))
	else
		chip.Text = "🏃 Fuga"
		chip.BackgroundColor3 = Color3.fromRGB(40, 110, 70)
		phaseLabel.Text = "Fase 7/7: leve o malote ao chefe da sua gangue"
	end
	-- eventos
	for i = 1, MAX_EVENTS do
		local ev = evs[i]
		local l = eventLabels[i]
		if ev then
			local left = ev.left and (ev.left - dt) or nil
			l.Text = ("%s %s%s\n%s"):format(ev.icon or "⚡", tostring(ev.name or ""), left and left > 0 and ("  " .. fmt(left)) or "", tostring(ev.hint or ""))
		else
			l.Text = ""
		end
	end
	eventsRow.Size = UDim2.new(1, 0, 0, math.min(#evs, MAX_EVENTS) * 30 + 6)
	-- bolsa
	bagLabel.Parent.Visible = active or carrying
	local heavy = (bag.slots or 0) >= math.ceil((bag.max or B.BagSlots) * 0.6)
	bagLabel.Text = ("🎒 Malote %d/%d  •  %s%s%s"):format(bag.slots or 0, bag.max or B.BagSlots, money(bag.value), heavy and "  •  pesado" or "", bag.marked and "  •  🎯 marcado" or "")
	bagLabel.TextColor3 = bag.marked and Color3.fromRGB(120, 170, 255) or Color3.new(1, 1, 1)
	escapeRow.Visible = carrying
	if carrying then
		local left = bag.trackerIn and (bag.trackerIn - (now - bagAt)) or 0
		if bag.tracked and left > 0 then
			escapeLabel.Text = ("📡 Rastreador ligado: %s (a PM vê você)"):format(fmt(left))
			escapeLabel.TextColor3 = (math.floor(now * 2) % 2 == 0) and RED or Color3.fromRGB(255, 160, 160)
			escapeFill.Size = UDim2.fromScale(math.clamp(left / B.TrackerTime, 0, 1), 1)
			hintLabel.Text = "O chefe não compra enquanto ele estiver ligado."
		else
			escapeLabel.Text = "🤝 Venda ao chefe da sua gangue (F)"
			escapeLabel.TextColor3 = GREEN
			escapeFill.Size = UDim2.fromScale(0, 1)
			hintLabel.Text = active and (status.sieged and "Saída de serviço (leste): segure E para forçar!" or "Saia do banco antes do cerco!") or "Vá até a sua favela sem a polícia perto."
		end
		copLabel.Visible = copNear
	end
end

---------------------------------------------------------------------------
-- Avisos
---------------------------------------------------------------------------

local function popup(text, color)
	local l = Instance.new("TextLabel")
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position = UDim2.new(0.5, 0, 0.58, 0)
	l.Size = UDim2.fromOffset(380, 34)
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

popupFn = popup
pingFn = function()
	local s = Instance.new("Sound")
	s.SoundId = "rbxasset://sounds/electronicpingshort.wav"
	s.Volume = 0.5
	s.Parent = gui
	s:Play()
	task.delay(2, function()
		s:Destroy()
	end)
end

local cardBusyUntil = 0
local showCard
-- Marco 10.26: um cartão de cada vez (vários eventos juntos ficavam um em cima do outro)
local function bigCard(title, sub, color)
	local now = os.clock()
	local at = math.max(now, cardBusyUntil)
	cardBusyUntil = at + 3.5
	task.delay(at - now, showCard, title, sub, color)
end

showCard = function(title, sub, color)
	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.32)
	card.Size = UDim2.fromOffset(420, 104)
	card.BackgroundColor3 = DARK
	card.BackgroundTransparency = 0.05
	card.Parent = gui
	corner(card, 16)
	stroke(card, color, 0.3)
	local scale = Instance.new("UIScale")
	scale.Scale = 0.6
	scale.Parent = card
	label(card, { Text = title, Position = UDim2.fromOffset(0, 14), Size = UDim2.new(1, 0, 0, 34), Align = Enum.TextXAlignment.Center, Font = Enum.Font.GothamBlack, TextSize = 26, Color = color })
	label(card, { Text = sub, Position = UDim2.fromOffset(16, 52), Size = UDim2.new(1, -32, 0, 44), Align = Enum.TextXAlignment.Center, TextSize = 14, Wrap = true, Color = WHITE })
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(3.2, function()
		TweenService:Create(card, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		task.wait(0.4)
		card:Destroy()
	end)
end

-- Marco 10.26: notas voando para a mochila ao pegar dinheiro
flyNotes = function(at)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	for i = 1, 8 do
		local note = Instance.new("Part")
		note.Name = "NotaVoando"
		note.Size = Vector3.new(0.7, 0.04, 0.35)
		note.Color = Color3.fromRGB(96, 170, 104)
		note.Anchored = true
		note.CanCollide = false
		note.CanQuery = false
		note.CanTouch = false
		note.CFrame = CFrame.new(at + Vector3.new(math.random() - 0.5, math.random(), math.random() - 0.5)) * CFrame.Angles(math.random() * 6, math.random() * 6, 0)
		note.Parent = Workspace
		task.delay(i * 0.05, function()
			local tw = TweenService:Create(note, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = root.CFrame * CFrame.new(0, 0.5, 1) * CFrame.Angles(math.random() * 6, 0, math.random() * 6), Size = Vector3.new(0.2, 0.02, 0.1) })
			tw:Play()
			tw.Completed:Once(function()
				note:Destroy()
			end)
		end)
	end
end

-- Marco 10.25: resposta forte na tela (clarão e tremida)
local function flash(color, alpha)
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 1 - alpha
	f.BorderSizePixel = 0
	f.ZIndex = 50
	f.Parent = gui
	TweenService:Create(f, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
	task.delay(0.65, function()
		f:Destroy()
	end)
end

local function shake(power, seconds)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < seconds do
			local k = power * (1 - (os.clock() - t0) / seconds)
			hum.CameraOffset = Vector3.new((math.random() - 0.5) * k, (math.random() - 0.5) * k, 0)
			task.wait()
		end
		hum.CameraOffset = Vector3.zero
	end)
end

function BankController.handle(kind, data)
	if kind == "BancoStatus" then
		status = data
		statusAt = os.clock()
	elseif kind == "BancoAchado" then
		MochilaController.offer("banco", data)
	elseif kind == "BancoBolsa" then
		bag = data
		bagAt = os.clock()
		MochilaController.update("banco", data)
		if (data.value or 0) <= 0 then
			copNear = false
		end
		refreshPrompts()
	elseif kind == "BancoPolicia" then
		copNear = data.near == true
	elseif kind == "BancoPegou" then
		if data.at then
			JewelryController.playGrab(data.at)
			flyNotes(data.at)
		end
		popup(("+%s  %s"):format(money(data.value), tostring(data.name or "")), data.big and Color3.fromRGB(255, 215, 110) or GOLD)
	elseif kind == "BancoAviso" then
		HudController.toast(tostring(data.text or ""), data.color == "red" and RED or Color3.fromRGB(70, 110, 170))
	elseif kind == "BancoEvento" then
		bigCard(("%s %s"):format(data.icon or "⚡", tostring(data.name or "EVENTO"):upper()), tostring(data.text or ""), data.id == "inicio" and RED or YELLOW)
	elseif kind == "BancoFx" then
		if data.kind == "explosao" then
			flash(Color3.fromRGB(255, 200, 120), 0.35)
			shake(1.2, 0.8)
		elseif data.kind == "laser" then
			flash(RED, 0.35)
			shake(0.3, 0.25)
		elseif data.kind == "alarme" or data.kind == "cerco" then
			flash(RED, 0.5)
		end
	elseif kind == "BancoFuga" then
		bigCard("💰 MALOTE VENDIDO", ("O chefe pagou %s por %d item(ns) do banco. Assalto concluído!"):format(money(data.value), data.count or 0), GREEN)
	end
end

function BankController.init()
	request = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(GameConfig.Remotes.BankRequest)
	build()
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("ProximityPrompt") and WATCH[d.Name] then
			watchPrompt(d)
		end
	end
	Workspace.DescendantAdded:Connect(function(d)
		if d:IsA("ProximityPrompt") and WATCH[d.Name] then
			task.defer(watchPrompt, d)
		end
	end)
	for _, prompt in ipairs(CollectionService:GetTagged("BancoReceptador")) do
		watchPrompt(prompt)
	end
	CollectionService:GetInstanceAddedSignal("BancoReceptador"):Connect(watchPrompt)
	for _, key in ipairs({ "Gang", "Job", "MaloteBanco", "CrachaBanco", "Preso", "Algemado", "Caido" }) do
		player:GetAttributeChangedSignal(key):Connect(refreshPrompts)
	end
	-- Marco 10.30: pegou/largou a perfuratriz ou a C4 (botões da porta do cofre)
	local function watchHolder(holder)
		if holder then
			holder.ChildAdded:Connect(function(c)
				if c:IsA("Tool") then
					task.defer(refreshPrompts)
				end
			end)
			holder.ChildRemoved:Connect(function(c)
				if c:IsA("Tool") then
					task.defer(refreshPrompts)
				end
			end)
		end
	end
	watchHolder(player.Character)
	player.CharacterAdded:Connect(watchHolder)
	task.spawn(function()
		watchHolder(player:WaitForChild("Backpack", 30))
		player.ChildAdded:Connect(function(c)
			if c:IsA("Backpack") then
				watchHolder(c)
			end
		end)
	end)
	player.CharacterAdded:Connect(function()
		task.defer(refreshPrompts)
		task.delay(1, function() request:FireServer("Status") end)
	end)
	-- Marco 10.26: enquanto segura o E num botão do assalto, o boneco faz a ação (todos veem)
	local function poseOf(prompt)
		return prompt:GetAttribute("Pose") or (prompt.Name == "JoiaPrompt" and "pegar") or nil
	end
	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt)
		local pose = poseOf(prompt)
		if pose then
			request:FireServer("Pose", pose)
		end
	end)
	ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt)
		if poseOf(prompt) then
			request:FireServer("Pose")
		end
	end)
	-- Marco 10.25: gritar com os reféns (G, ou botão no celular)
	local function doShout()
		request:FireServer("Gritar")
		popup("📢 NINGUÉM SE MEXE!", YELLOW)
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.G and status and status.state == "assalto" and status.member then
			doShout()
		end
	end)
	MobileButtons.add("gritar", { icon = "📢", title = "Gritar", slots = { 4 }, onPress = doShout })
	MobileButtons.show("gritar", false)
	local promptTime = 0
	RunService.RenderStepped:Connect(function(dt)
		promptTime += dt
		if promptTime >= 0.2 then promptTime = 0; refreshPrompts() end
		render()
	end)
	-- O ClientBootstrap conecta UIUpdate depois de init; adiar evita perder a resposta inicial.
	task.defer(function() request:FireServer("Status") end)
end

return BankController
