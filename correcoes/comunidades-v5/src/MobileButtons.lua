-- MobileButtons (ModuleScript)
-- Caminho: StarterPlayer > StarterPlayerScripts > Controllers > MobileButtons
-- Marco 10.14: botões redondos do celular (Correr, Mirar, Freio, Sirene, Grau, Sair do carro...)
-- arrumados em arco em volta do botão de PULO do Roblox, sem nunca ficar em cima dele.
--   * Só existe no celular/tablet (toque sem teclado). No PC nada disso aparece.
--   * Cada botão diz em quais "vagas" prefere ficar; quem está visível ocupa a primeira vaga livre.
--   * O tamanho segue o botão de pulo (celular pequeno = botões menores, tablet = maiores).
-- Uso:
--   MobileButtons.add("correr", { icon = "⚡", title = "Correr", slots = {3, 2}, hold = false,
--       onPress = function(began) ... end })
--   MobileButtons.show("correr", true)  /  MobileButtons.setActive("correr", true)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local MobileButtons = {}

MobileButtons.enabled = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local player = Players.LocalPlayer

-- Vagas em volta do pulo: ângulo (graus; 180 = esquerda, 90 = em cima) e anel (1 = colado, 2 = de fora)
local SLOTS = {
	{ a = 180, ring = 1 }, -- 1: à esquerda do pulo
	{ a = 135, ring = 1 }, -- 2: em cima à esquerda
	{ a = 90, ring = 1 }, -- 3: em cima do pulo
	{ a = 157.5, ring = 2 }, -- 4: de fora, esquerda
	{ a = 112.5, ring = 2 }, -- 5: de fora, em cima
}

local OFF = Color3.fromRGB(12, 14, 20)
local ON = Color3.fromRGB(255, 170, 40)

local gui
local buttons = {} -- id -> info
local order = {} -- ids na ordem em que foram criados (quem chegou primeiro escolhe vaga antes)
local dirty = true

local function ensureGui()
	if gui then
		return gui
	end
	gui = Instance.new("ScreenGui")
	gui.Name = "MobileButtons"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 2
	gui.Parent = player:WaitForChild("PlayerGui")
	return gui
end

-- Onde está o pulo (centro e tamanho), no mesmo espaço de tela do TouchGui do Roblox
local function jumpInfo()
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local touchGui = playerGui and playerGui:FindFirstChild("TouchGui")
	local frame = touchGui and touchGui:FindFirstChild("TouchControlFrame")
	local jump = frame and frame:FindFirstChild("JumpButton")
	if jump and jump.AbsoluteSize.X > 0 then
		pcall(function()
			if gui.ScreenInsets ~= touchGui.ScreenInsets then
				gui.ScreenInsets = touchGui.ScreenInsets
			end
		end)
		return jump.AbsolutePosition + jump.AbsoluteSize / 2, jump.AbsoluteSize.X
	end
	-- sem o pulo do Roblox: mesmo lugar que ele usaria
	local size = gui.AbsoluteSize
	if math.min(size.X, size.Y) <= 500 then
		return Vector2.new(size.X - 60, size.Y - 55), 70
	end
	return Vector2.new(size.X - 110, size.Y - 150), 120
end

local function paint(info)
	info.button.BackgroundColor3 = info.active and ON or OFF
	info.button.BackgroundTransparency = info.active and 0.15 or 0.45
	info.stroke.Transparency = info.active and 0.1 or 0.45
end

local function layout()
	if not gui then
		return
	end
	local center, jumpSize = jumpInfo()
	local b = math.clamp(math.floor(jumpSize * 0.74), 46, 84)
	local r1 = jumpSize / 2 + b / 2 + 12
	local r2 = r1 + b + 8
	local taken = {}
	for _, id in ipairs(order) do
		local info = buttons[id]
		local slot
		if info.visible then
			for _, s in ipairs(info.slots) do
				if not taken[s] then
					slot = s
					break
				end
			end
			if not slot then
				for s = 1, #SLOTS do
					if not taken[s] then
						slot = s
						break
					end
				end
			end
		end
		if slot then
			taken[slot] = true
			local spec = SLOTS[slot]
			local r = spec.ring == 1 and r1 or r2
			local rad = math.rad(spec.a)
			local pos = center + Vector2.new(math.cos(rad) * r, -math.sin(rad) * r)
			info.button.Size = UDim2.fromOffset(b, b)
			info.button.Position = UDim2.fromOffset(math.floor(pos.X + 0.5), math.floor(pos.Y + 0.5))
			info.icon.TextSize = math.floor(b * 0.36)
			info.label.TextSize = math.max(9, math.floor(b * 0.19))
			info.button.Visible = true
		else
			info.button.Visible = false
		end
	end
end

local function release(info)
	if info.touch then
		info.touch = nil
		if info.hold then
			info.onPress(false)
		end
	end
end

function MobileButtons.add(id, opts)
	if not MobileButtons.enabled or buttons[id] then
		return
	end
	ensureGui()
	local button = Instance.new("TextButton")
	button.Name = id
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Text = ""
	button.AutoButtonColor = false
	button.Visible = false
	button.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = 1.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button
	local icon = Instance.new("TextLabel")
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.4)
	icon.Size = UDim2.fromScale(1, 0.5)
	icon.Font = Enum.Font.GothamBold
	icon.Text = opts.icon or ""
	icon.TextColor3 = Color3.new(1, 1, 1)
	icon.Parent = button
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.fromScale(0.5, 0.64)
	label.Size = UDim2.fromScale(0.95, 0.24)
	label.Font = Enum.Font.GothamBold
	label.Text = opts.title or ""
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.6
	label.Parent = button

	local info = {
		button = button,
		stroke = stroke,
		icon = icon,
		label = label,
		slots = opts.slots or { 1, 2, 3, 4, 5 },
		hold = opts.hold == true,
		onPress = opts.onPress or function() end,
		visible = false,
		active = false,
	}
	buttons[id] = info
	table.insert(order, id)
	paint(info)

	button.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		if info.touch then
			return
		end
		info.touch = input
		info.onPress(true)
		if not info.hold then
			info.touch = nil
		end
	end)
	button.InputEnded:Connect(function(input)
		if input == info.touch then
			release(info)
		end
	end)
	dirty = true
end

function MobileButtons.show(id, on)
	local info = buttons[id]
	if not info then
		return
	end
	on = on == true
	if info.visible ~= on then
		info.visible = on
		if not on then
			release(info)
		end
		dirty = true
	end
end

function MobileButtons.setActive(id, on)
	local info = buttons[id]
	if info and info.active ~= (on == true) then
		info.active = on == true
		paint(info)
	end
end

function MobileButtons.setTitle(id, title, icon)
	local info = buttons[id]
	if info then
		info.label.Text = title
		if icon then
			info.icon.Text = icon
		end
	end
end

if MobileButtons.enabled then
	-- o dedo saiu do botão e soltou em outro lugar: solta o botão de segurar (freio, grau)
	UserInputService.TouchEnded:Connect(function(input)
		for _, info in pairs(buttons) do
			if info.touch == input then
				release(info)
			end
		end
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if dirty or acc > 0.5 then -- de vez em quando também (girou a tela, o pulo mudou de tamanho)
			dirty = false
			acc = 0
			layout()
		end
	end)
end

return MobileButtons
