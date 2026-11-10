-- MiniJogos (ModuleScript)
-- Caminho: StarterPlayer > StarterPlayerScripts > Controllers > MiniJogos
-- Marco 10.27: minigames além da barra. O JewelryController abre a janela e o servidor conta os acertos;
-- aqui fica só o jogo em si. Cada jogo chama report(true) a cada etapa vencida e report(false) a cada erro.
--   setas    digita a fileira de setas antes do tempo acabar
--   memoria  repete a sequência que os botões piscaram (cresce a cada rodada)
--   fios     corta os fios na ordem pedida
--   segurar  segura para manter o ponteiro na faixa verde, que anda sozinha
-- Tudo funciona por teclado (câmera travada não deixa clicar), mouse, toque e controle.

local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")

local MiniJogos = {}

local ACTION = "MiniJogoTeclas"
local GREEN = Color3.fromRGB(70, 200, 110)
local RED = Color3.fromRGB(225, 70, 70)
local GOLD = Color3.fromRGB(235, 190, 80)
local PANEL = Color3.fromRGB(40, 42, 52)
local TEXT = Color3.fromRGB(240, 240, 245)
local DONE = Color3.fromRGB(70, 72, 84)

local DIRS = {
	{ label = "▲", color = Color3.fromRGB(70, 150, 240), keys = { Enum.KeyCode.W, Enum.KeyCode.Up, Enum.KeyCode.DPadUp } },
	{ label = "◀", color = Color3.fromRGB(235, 190, 60), keys = { Enum.KeyCode.A, Enum.KeyCode.Left, Enum.KeyCode.DPadLeft } },
	{ label = "▼", color = Color3.fromRGB(80, 200, 110), keys = { Enum.KeyCode.S, Enum.KeyCode.Down, Enum.KeyCode.DPadDown } },
	{ label = "▶", color = Color3.fromRGB(230, 80, 80), keys = { Enum.KeyCode.D, Enum.KeyCode.Right, Enum.KeyCode.DPadRight } },
}
local ACTION_KEYS = { Enum.KeyCode.E, Enum.KeyCode.ButtonX }
local WIRES = {
	{ name = "VERMELHO", color = Color3.fromRGB(225, 60, 60), hex = "#e13c3c" },
	{ name = "AZUL", color = Color3.fromRGB(70, 140, 240), hex = "#5f9cf5" },
	{ name = "AMARELO", color = Color3.fromRGB(240, 205, 60), hex = "#f0cd3c" },
	{ name = "VERDE", color = Color3.fromRGB(70, 200, 100), hex = "#46c864" },
	{ name = "BRANCO", color = Color3.fromRGB(235, 235, 240), hex = "#ebebf0" },
	{ name = "ROXO", color = Color3.fromRGB(170, 90, 230), hex = "#b46ee8" },
}

local cur -- o jogo aberto
local rng = Random.new()

local function make(class, parent, props)
	local o = Instance.new(class)
	if o:IsA("GuiObject") then
		o.BorderSizePixel = 0
	end
	for k, v in pairs(props) do
		o[k] = v
	end
	o.Parent = parent
	return o
end

local function round(o, r)
	make("UICorner", o, { CornerRadius = UDim.new(0, r or 8) })
	return o
end

local function text(parent, props)
	props.BackgroundTransparency = 1
	props.Font = props.Font or Enum.Font.GothamBold
	props.TextColor3 = props.TextColor3 or TEXT
	props.TextSize = props.TextSize or 14
	return make("TextLabel", parent, props)
end

local function button(parent, props)
	props.AutoButtonColor = false
	props.Font = Enum.Font.GothamBlack
	props.TextColor3 = props.TextColor3 or TEXT
	props.TextSize = props.TextSize or 26
	return round(make("TextButton", parent, props))
end

local function blink(o, color, back)
	o.BackgroundColor3 = color
	TweenService:Create(o, TweenInfo.new(0.3), { BackgroundColor3 = back }):Play()
end

-- os 4 botões de direção, em cruz: setas e memória usam os mesmos
local function makePads(game_, area, colored)
	local pads = {}
	local at = { { 0, -1 }, { -1, 0 }, { 0, 0 }, { 1, 0 } }
	local holder = make("Frame", area, { Name = "Pads", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.fromOffset(150, 96) })
	for i, d in ipairs(DIRS) do
		local base = colored and d.color:Lerp(Color3.new(0, 0, 0), 0.55) or PANEL
		local b = button(holder, {
			Name = "Pad" .. i,
			Size = UDim2.fromOffset(46, 46),
			Position = UDim2.fromOffset(52 + at[i][1] * 52, 50 + at[i][2] * 50),
			BackgroundColor3 = base,
			Text = d.label,
		})
		pads[i] = { button = b, base = base, color = d.color }
		b.Activated:Connect(function()
			if cur == game_ then
				game_.onDir(i)
			end
		end)
	end
	return pads
end

local function timerBar(area, y)
	local track = round(make("Frame", area, { Name = "Tempo", Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = PANEL }), 3)
	return round(make("Frame", track, { Name = "Resta", Size = UDim2.fromScale(1, 1), BackgroundColor3 = GOLD }), 3)
end

---------------------------------------------------------------------------
-- Setas: uma fileira por etapa; errou, a fileira recomeça diferente
---------------------------------------------------------------------------
local function setas(g)
	local len = g.rule.len or 5
	local total = g.rule.time or 6
	local row = make("Frame", g.area, { Name = "Fileira", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36) })
	local bar = timerBar(g.area, 40)
	local tiles = {}
	for i = 1, len do
		tiles[i] = round(text(row, {
			Name = "Seta" .. i,
			BackgroundTransparency = 0,
			BackgroundColor3 = PANEL,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, (i - (len + 1) / 2) * 42, 0, 0),
			Size = UDim2.fromOffset(36, 36),
			TextSize = 24,
		}))
		tiles[i].BackgroundTransparency = 0
	end
	local seq, idx, left
	local function newRow()
		seq, idx, left = {}, 1, total
		for i = 1, len do
			seq[i] = rng:NextInteger(1, 4)
			tiles[i].Text = DIRS[seq[i]].label
			tiles[i].BackgroundColor3 = PANEL
			tiles[i].TextColor3 = TEXT
		end
		tiles[1].BackgroundColor3 = DONE
	end
	local pads = makePads(g, g.area, false)
	g.onDir = function(i)
		if i ~= seq[idx] then
			blink(pads[i].button, RED, PANEL)
			g.report(false)
			return newRow()
		end
		tiles[idx].BackgroundColor3 = GREEN
		tiles[idx].TextColor3 = Color3.new(0.05, 0.1, 0.05)
		blink(pads[i].button, DONE, PANEL)
		idx += 1
		if idx > len then
			g.report(true)
			return newRow()
		end
		tiles[idx].BackgroundColor3 = DONE
	end
	g.step = function(dt)
		left -= dt
		bar.Size = UDim2.fromScale(math.max(left / total, 0), 1)
		if left <= 0 then
			g.report(false)
			newRow()
		end
	end
	newRow()
	return "Digite as setas na ordem (WASD ou setas)"
end

---------------------------------------------------------------------------
-- Memória: pisca a sequência e o jogador repete; cada rodada vencida é uma etapa
---------------------------------------------------------------------------
local function memoria(g)
	local status = text(g.area, { Name = "Status", Size = UDim2.new(1, 0, 0, 30), TextSize = 16, Text = "" })
	local pads = makePads(g, g.area, true)
	local seq = {}
	for _ = 1, g.rule.len or 3 do
		table.insert(seq, rng:NextInteger(1, 4))
	end
	local idx, listening = 1, false
	local gap = 0.55 / math.max(g.rule.speed or 1, 0.5)
	local function play()
		listening = false
		status.Text = "Observe…"
		status.TextColor3 = GOLD
		for _, p in ipairs(pads) do
			p.button.Text = ""
		end
		task.spawn(function()
			task.wait(0.6)
			for _, i in ipairs(seq) do
				if cur ~= g then
					return
				end
				local p = pads[i]
				p.button.BackgroundColor3 = p.color
				task.wait(gap * 0.65)
				if cur ~= g then
					return
				end
				p.button.BackgroundColor3 = p.base
				task.wait(gap * 0.35)
			end
			if cur == g then
				idx, listening = 1, true
				status.Text = "Sua vez!"
				status.TextColor3 = GREEN
				for i, p in ipairs(pads) do
					p.button.Text = DIRS[i].label
				end
			end
		end)
	end
	g.onDir = function(i)
		if not listening then
			return
		end
		local p = pads[i]
		blink(p.button, p.color, p.base)
		if i ~= seq[idx] then
			g.report(false)
			return play() -- mesma sequência de novo
		end
		idx += 1
		if idx > #seq then
			g.report(true)
			table.insert(seq, rng:NextInteger(1, 4))
			play()
		end
	end
	play()
	return "Repita a sequência (WASD, setas ou clique)"
end

---------------------------------------------------------------------------
-- Fios: corta na ordem pedida, contra o tempo; cada fio certo é uma etapa
---------------------------------------------------------------------------
local function fios(g)
	local count = math.clamp(g.rule.len or 5, math.min(g.hits + 1, #WIRES), #WIRES)
	local total = g.rule.time or 10
	local order = text(g.area, { Name = "Ordem", Size = UDim2.new(1, 0, 0, 24), TextSize = 14, RichText = true, TextWrapped = true })
	local bar = timerBar(g.area, 26)
	local box = make("Frame", g.area, { Name = "Fios", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 1, -38) })
	local wires, wanted, nextIdx, sel, left = {}, nil, 1, 1, total
	local drawSel

	local function drawOrder()
		local parts = {}
		for i, w in ipairs(wanted) do
			local name = ("<font color=\"%s\">%s</font>"):format(w.def.hex, w.def.name)
			parts[i] = i < nextIdx and ("<s>%s</s>"):format(name) or (i == nextIdx and ("<b><u>%s</u></b>"):format(name) or name)
		end
		order.Text = "Corte: " .. table.concat(parts, "  ›  ")
	end

	local function newPanel()
		for _, w in ipairs(wires) do
			w.button:Destroy()
		end
		wires, wanted, nextIdx, sel, left = {}, {}, 1, 1, total
		local pool = table.clone(WIRES)
		for i = 1, count do
			local def = table.remove(pool, rng:NextInteger(1, #pool))
			local b = button(box, {
				Name = "Fio" .. i,
				BackgroundTransparency = 1,
				Text = "",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new((i - 0.5) / count, 0, 0, 0),
				Size = UDim2.new(1 / count, -6, 1, 0),
			})
			local cable = make("Frame", b, { Name = "Cabo", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0, 12, 1, -22), BackgroundColor3 = def.color })
			local gap = make("Frame", b, { Name = "Corte", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.45, 0), Size = UDim2.new(0, 20, 0, 16), BackgroundColor3 = Color3.fromRGB(22, 23, 30), Visible = false })
			local tag = text(b, { Name = "Nome", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.new(1, 0, 0, 18), TextSize = 10, Text = def.name, TextColor3 = def.color })
			local wire = { button = b, def = def, cable = cable, gap = gap, tag = tag, index = i }
			wires[i] = wire
			b.Activated:Connect(function()
				if cur == g then
					sel = wire.index
					drawSel()
					g.onAction(true)
				end
			end)
		end
		local shuffled = table.clone(wires)
		for i = 1, math.min(g.hits - g.done(), count) do
			wanted[i] = table.remove(shuffled, rng:NextInteger(1, #shuffled))
		end
		drawSel()
		drawOrder()
	end

	drawSel = function()
		for i, w in ipairs(wires) do
			w.button.BackgroundTransparency = i == sel and 0.75 or 1
			w.button.BackgroundColor3 = GOLD
		end
	end

	g.onDir = function(i)
		if i == 2 or i == 4 then
			sel = (sel - 1 + (i == 2 and -1 or 1)) % count + 1
			drawSel()
		end
	end
	g.onAction = function(down)
		if not down then
			return
		end
		local w = wires[sel]
		if not w or w.gap.Visible then
			return
		end
		if w == wanted[nextIdx] then
			w.gap.Visible = true
			w.cable.BackgroundColor3 = w.def.color:Lerp(Color3.new(0, 0, 0), 0.45)
			nextIdx += 1
			drawOrder()
			g.report(true)
		else
			blink(w.button, RED, GOLD)
			g.report(false)
		end
	end
	g.step = function(dt)
		left -= dt
		bar.Size = UDim2.fromScale(math.max(left / total, 0), 1)
		if left <= 0 then
			g.report(false)
			newPanel()
		end
	end
	newPanel()
	return "A/D escolhe e E corta (ou clique no fio)"
end

---------------------------------------------------------------------------
-- Segurar: subir com o botão, cair sem ele. Na faixa enche; fora dela por muito tempo é erro
---------------------------------------------------------------------------
local function segurar(g)
	local zone = math.max(g.rule.zone or 0.2, 0.1) + 0.08 -- a faixa anda: precisa ser mais larga que a da barra
	local track = round(make("Frame", g.area, { Name = "Pressao", Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = PANEL, ClipsDescendants = true }), 6)
	local band = round(make("Frame", track, { Name = "Faixa", AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromScale(zone, 1), BackgroundColor3 = GREEN }), 4)
	local needle = make("Frame", track, { Name = "Ponteiro", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.1, 0.5), Size = UDim2.new(0, 5, 1, 8), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 3 })
	local fillTrack = round(make("Frame", g.area, { Name = "Progresso", Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 0, 10), BackgroundColor3 = PANEL }), 4)
	local fill = round(make("Frame", fillTrack, { Size = UDim2.fromScale(0, 1), BackgroundColor3 = GOLD }), 4)
	local hold = button(g.area, { Name = "Segurar", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.fromOffset(190, 62), BackgroundColor3 = Color3.fromRGB(200, 150, 50), TextColor3 = Color3.fromRGB(20, 16, 8), Text = "SEGURE" })
	-- o botão acompanha o dedo mesmo se ele escorregar para fora
	local down = false
	hold.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			down = true
		end
	end)
	hold.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			down = false
		end
	end)
	g.onAction = function(isDown)
		down = isDown
	end

	local speed = g.rule.speed or 1
	local pos, vel, progress, outside, t = 0.1, 0, 0, 0, rng:NextNumber() * 10
	local perStep = (g.rule.time or 2.2) -- segundos na faixa para cada etapa
	g.step = function(dt)
		t += dt
		vel = math.clamp(vel + (down and 2.6 or -2.6) * dt, -1.1, 1.1)
		pos += vel * dt
		if pos <= 0 or pos >= 1 then
			pos, vel = math.clamp(pos, 0, 1), 0
		end
		-- soma de senos: a faixa anda sem padrão fácil de decorar
		local center = 0.5 + (0.5 - zone / 2 - 0.02) * (math.sin(t * 0.7 * speed) * 0.6 + math.sin(t * 1.63 * speed + 1) * 0.4)
		local inside = math.abs(pos - center) <= zone / 2
		band.Position = UDim2.fromScale(center, 0)
		band.BackgroundColor3 = inside and GREEN or GREEN:Lerp(RED, math.min(outside / 1.5, 1))
		needle.Position = UDim2.fromScale(pos, 0.5)
		if inside then
			outside = 0
			progress += dt / perStep
			if progress >= 1 then
				progress = 0
				g.report(true)
			end
		else
			outside += dt
			progress = math.max(progress - dt / (perStep * 3), 0)
			if outside >= 1.5 then
				outside = 0
				g.report(false)
			end
		end
		fill.Size = UDim2.fromScale(progress, 1)
	end
	return "Segure E (ou o botão) e mantenha o ponteiro no verde"
end

local GAMES = { setas = setas, memoria = memoria, fios = fios, segurar = segurar }

local function onInput(_, state, input)
	if not cur then
		return Enum.ContextActionResult.Pass
	end
	local isAction = input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonX
	if state == Enum.UserInputState.Begin or (isAction and state == Enum.UserInputState.End) then
		if isAction then
			if cur.onAction then
				cur.onAction(state == Enum.UserInputState.Begin)
			end
		elseif cur.onDir then
			for i, d in ipairs(DIRS) do
				if table.find(d.keys, input.KeyCode) then
					cur.onDir(i)
				end
			end
		end
	end
	return Enum.ContextActionResult.Sink -- senão WASD anda e tira o boneco do lugar
end

function MiniJogos.has(kind)
	return GAMES[kind] ~= nil
end

-- rule = { hits, zone, speed, len, time }; done() = etapas já vencidas; report(acertou); devolve a dica de teclas
function MiniJogos.open(kind, area, rule, hits, done, report)
	MiniJogos.close()
	cur = { area = area, rule = rule, hits = hits, done = done, report = report }
	local help = GAMES[kind](cur)
	local keys = table.clone(ACTION_KEYS)
	for _, d in ipairs(DIRS) do
		table.move(d.keys, 1, #d.keys, #keys + 1, keys)
	end
	ContextActionService:BindActionAtPriority(ACTION, onInput, false, Enum.ContextActionPriority.High.Value, table.unpack(keys))
	return help
end

function MiniJogos.step(dt)
	if cur and cur.step then
		cur.step(dt)
	end
end

function MiniJogos.close()
	if cur then
		local area = cur.area
		cur = nil
		ContextActionService:UnbindAction(ACTION)
		area:ClearAllChildren()
	end
end

return MiniJogos
