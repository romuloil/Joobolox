-- PaintController (ModuleScript)
-- Caminho: StarterPlayer > StarterPlayerScripts > Controllers > PaintController
-- Marco 6.4: tela da loja de pintura (aviso "Pintar carro" no totem da cabine).
-- O jogador escolhe uma cor pronta da paleta ou qualquer cor nas duas barras (cor e tom)
-- e toca em "Pintar". O servidor confere se o carro está na cabine e pinta (de graça por enquanto).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local UIScaler = require(script.Parent:WaitForChild("UIScaler"))

local PaintController = {}

local player = Players.LocalPlayer
local vehicleRequest
local gui, panel
local openedAt -- onde o jogador estava ao abrir (longe disso a tela fecha sozinha)

local DARK = Color3.fromRGB(20, 30, 50)
local GREEN = Color3.fromRGB(60, 170, 80)
local RED = Color3.fromRGB(200, 70, 60)

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 10)
	c.Parent = parent
end

local function label(parent, text, size, pos, textSize, color)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = pos
	l.Font = Enum.Font.GothamBold
	l.TextSize = textSize or 16
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.Text = text
	l.Parent = parent
	return l
end

local function close()
	if panel then
		panel:Destroy()
		panel = nil
	end
	openedAt = nil
end

local function rootPosition()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root and root.Position
end

-- Barra em que tocar escolhe um valor de 0 a 1 (da esquerda para a direita)
local function pickBar(parent, pos, onPick)
	local bar = Instance.new("TextButton")
	bar.Text = ""
	bar.AutoButtonColor = false
	bar.BackgroundColor3 = Color3.new(1, 1, 1)
	bar.Size = UDim2.new(1, -24, 0, 26)
	bar.Position = pos
	bar.Parent = parent
	corner(bar, 8)
	local marker = Instance.new("Frame")
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Size = UDim2.fromOffset(6, 32)
	marker.Position = UDim2.fromScale(0.5, 0.5)
	marker.BackgroundColor3 = Color3.new(1, 1, 1)
	marker.BorderSizePixel = 0
	marker.Parent = bar
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = marker
	local held = false
	local function pick(x)
		local t = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
		marker.Position = UDim2.fromScale(t, 0.5)
		onPick(t)
	end
	bar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			held = true
			pick(input.Position.X)
		end
	end)
	bar.InputChanged:Connect(function(input)
		if held and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			pick(input.Position.X)
		end
	end)
	bar.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			held = false
		end
	end)
	return bar, marker
end

function PaintController.open(data)
	close()
	if type(data) ~= "table" or type(data.palette) ~= "table" then
		return
	end
	openedAt = rootPosition()
	local current = type(data.current) == "table" and data.current or { 255, 255, 255 }
	local chosen = Color3.fromRGB(tonumber(current[1]) or 255, tonumber(current[2]) or 255, tonumber(current[3]) or 255)

	panel = Instance.new("Frame")
	panel.Name = "Pintura"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(380, 430)
	panel.BackgroundColor3 = DARK
	panel.BackgroundTransparency = 0.05
	panel.Parent = gui
	corner(panel, 14)
	UIScaler.attach(panel)

	label(panel, "Pintura", UDim2.new(1, -70, 0, 30), UDim2.fromOffset(16, 10), 24)
	local price = (tonumber(data.price) or 0) > 0 and (GameConfig.Economy.CurrencySymbol .. " " .. tostring(data.price)) or "Grátis"
	label(panel, tostring(data.car or "Seu carro") .. "  •  " .. price, UDim2.new(1, -70, 0, 18), UDim2.fromOffset(16, 38), 14, Color3.fromRGB(180, 200, 230))
	local x = Instance.new("TextButton")
	x.Size = UDim2.fromOffset(36, 32)
	x.Position = UDim2.new(1, -46, 0, 10)
	x.BackgroundColor3 = RED
	x.Font = Enum.Font.GothamBold
	x.TextSize = 16
	x.TextColor3 = Color3.new(1, 1, 1)
	x.Text = "X"
	x.Parent = panel
	corner(x, 8)
	x.Activated:Connect(close)

	-- Amostra da cor escolhida
	local preview = Instance.new("Frame")
	preview.Size = UDim2.new(1, -24, 0, 40)
	preview.Position = UDim2.fromOffset(12, 64)
	preview.BackgroundColor3 = chosen
	preview.Parent = panel
	corner(preview, 10)
	local function choose(color)
		chosen = color
		preview.BackgroundColor3 = color
	end

	-- Paleta pronta (5 por linha)
	local y = 114
	for i, rgb in ipairs(data.palette) do
		if type(rgb) == "table" then
			local col = Color3.fromRGB(tonumber(rgb[1]) or 0, tonumber(rgb[2]) or 0, tonumber(rgb[3]) or 0)
			local b = Instance.new("TextButton")
			b.Text = ""
			b.Size = UDim2.fromOffset(62, 34)
			b.Position = UDim2.fromOffset(12 + ((i - 1) % 5) * 72, y + math.floor((i - 1) / 5) * 42)
			b.BackgroundColor3 = col
			b.AutoButtonColor = true
			b.Parent = panel
			corner(b, 8)
			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.fromRGB(200, 210, 230)
			stroke.Thickness = 1
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			stroke.Parent = b
			b.Activated:Connect(function()
				choose(col)
			end)
		end
	end
	y += math.ceil(#data.palette / 5) * 42 + 4

	-- Qualquer cor: barra de cor (arco-íris) e barra de tom (escuro -> cor -> claro)
	local hue = 0
	local tone = 0.5
	local toneBar
	local function fromBars()
		local pure = Color3.fromHSV(hue, 1, 1)
		if toneBar then
			local g = toneBar:FindFirstChildOfClass("UIGradient")
			g.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.new(0, 0, 0)),
				ColorSequenceKeypoint.new(0.5, pure),
				ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
			})
		end
		if tone < 0.5 then
			return Color3.new(0, 0, 0):Lerp(pure, tone * 2)
		end
		return pure:Lerp(Color3.new(1, 1, 1), (tone - 0.5) * 2)
	end
	label(panel, "Ou escolha qualquer cor:", UDim2.new(1, -24, 0, 16), UDim2.fromOffset(12, y), 13, Color3.fromRGB(180, 200, 230))
	local hueBar = pickBar(panel, UDim2.fromOffset(12, y + 20), function(t)
		hue = math.min(t, 0.999)
		choose(fromBars())
	end)
	local keys = {}
	for k = 0, 6 do
		table.insert(keys, ColorSequenceKeypoint.new(k / 6, Color3.fromHSV((k % 6) / 6, 1, 1)))
	end
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(keys)
	g.Parent = hueBar
	toneBar = pickBar(panel, UDim2.fromOffset(12, y + 54), function(t)
		tone = t
		choose(fromBars())
	end)
	local g2 = Instance.new("UIGradient")
	g2.Parent = toneBar
	fromBars()

	local paint = Instance.new("TextButton")
	paint.Size = UDim2.new(1, -24, 0, 40)
	paint.Position = UDim2.fromOffset(12, y + 92)
	paint.BackgroundColor3 = GREEN
	paint.Font = Enum.Font.GothamBold
	paint.TextSize = 18
	paint.TextColor3 = Color3.new(1, 1, 1)
	paint.Text = "Pintar"
	paint.Parent = panel
	corner(paint, 10)
	paint.Activated:Connect(function()
		vehicleRequest:FireServer("Paint", {
			color = { math.floor(chosen.R * 255 + 0.5), math.floor(chosen.G * 255 + 0.5), math.floor(chosen.B * 255 + 0.5) },
		})
		close()
	end)
	local bottom = y + 146
	-- Placa (Marco 7.5): até 7 letras e números, aparece para todo mundo
	if data.canPlate then
		local max = tonumber(data.plateMax) or 7
		label(panel, "Placa (até " .. max .. " letras e números):", UDim2.new(1, -24, 0, 16), UDim2.fromOffset(12, bottom - 4), 13, Color3.fromRGB(180, 200, 230))
		local box = Instance.new("TextBox")
		box.Size = UDim2.new(1, -150, 0, 40)
		box.Position = UDim2.fromOffset(12, bottom + 16)
		box.BackgroundColor3 = Color3.fromRGB(245, 245, 245)
		box.Font = Enum.Font.GothamBlack
		box.TextSize = 22
		box.TextColor3 = Color3.fromRGB(15, 15, 18)
		box.PlaceholderText = "ABC1D23"
		box.ClearTextOnFocus = false
		box.Text = type(data.plate) == "string" and data.plate or ""
		box.Parent = panel
		corner(box, 8)
		box:GetPropertyChangedSignal("Text"):Connect(function()
			local s = box.Text:upper():gsub("[^A-Z0-9 ]", ""):sub(1, max)
			if s ~= box.Text then
				box.Text = s
			end
		end)
		local save = Instance.new("TextButton")
		save.Size = UDim2.fromOffset(118, 40)
		save.Position = UDim2.new(1, -130, 0, bottom + 16)
		save.BackgroundColor3 = Color3.fromRGB(40, 110, 200)
		save.Font = Enum.Font.GothamBold
		save.TextSize = 16
		save.TextColor3 = Color3.new(1, 1, 1)
		save.Text = "Pôr placa"
		save.Parent = panel
		corner(save, 10)
		save.Activated:Connect(function()
			vehicleRequest:FireServer("Paint", { plate = box.Text })
			close()
		end)
		bottom += 70
	end
	panel.Size = UDim2.fromOffset(380, bottom)
end

function PaintController.init()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	vehicleRequest = remotes:WaitForChild(GameConfig.Remotes.VehicleRequest)
	gui = Instance.new("ScreenGui")
	gui.Name = "PaintUI"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")
	-- saiu da cabine: fecha a tela
	RunService.Heartbeat:Connect(function()
		if not panel or not openedAt then
			return
		end
		local pos = rootPosition()
		if not pos or (pos - openedAt).Magnitude > 20 then
			close()
		end
	end)
end

return PaintController
