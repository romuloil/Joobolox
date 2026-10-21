-- PrisonController (ModuleScript)
-- Apenas apresenta o estado enviado pelo servidor. Não solicita soltura nem decide fuga.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local UIScaler = require(script.Parent:WaitForChild("UIScaler"))

local PrisonController = {}
local player = Players.LocalPlayer
local initialized = false
local card, timerLabel, progressLabel, hintLabel
local deadline, cellOpensAt = 0, 0
local cellId, serverHint = "", ""
local detained, completed, totalSteps = false, 0, 3
local escapePrompts = {}
local escapeOrder = { EscapeHatchPrompt = 1, EscapePassagePrompt = 2, EscapeExitPrompt = 3 }

local function refreshPrompts()
	for prompt, index in pairs(escapePrompts) do
		if prompt.Parent then
			-- Somente a próxima interação fica visível neste cliente.
			-- O servidor continua validando estado, distância e ordem das etapas.
			prompt.Enabled = detained and Workspace:GetServerTimeNow() >= cellOpensAt and index == completed + 1
		else
			escapePrompts[prompt] = nil
		end
	end
end

local function watchPrompt(item)
	if not item:IsA("ProximityPrompt") or not escapeOrder[item.Name] then
		return
	end
	local map = Workspace:FindFirstChild("Map")
	local locations = map and map:FindFirstChild("CivicLocations")
	if locations and item:IsDescendantOf(locations) then
		escapePrompts[item] = escapeOrder[item.Name]
		refreshPrompts()
	end
end

local function text(parent, name, value, position, size, color, font, textSize)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = position
	label.Size = size
	label.Font = font or Enum.Font.GothamMedium
	label.TextSize = textSize or 13
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextWrapped = true
	label.Text = value
	label.Parent = parent
	return label
end

local function updateTimer()
	local time = Workspace:GetServerTimeNow()
	local remaining = math.max(0, math.ceil(deadline - time))
	timerLabel.Text = remaining > 0 and ("%02ds"):format(remaining) or "Liberando..."
	local lockRemaining = math.max(0, math.ceil(cellOpensAt - time))
	if lockRemaining > 0 then
		progressLabel.Text = cellId ~= "" and ("CELA " .. cellId .. "  ·  ACESSO AO PÁTIO") or "ACESSO AO PÁTIO"
		hintLabel.Text = ("Porta fechada. Acesso ao pátio em %ds."):format(lockRemaining)
	else
		progressLabel.Text = ("ROTA DE FUGA  ·  %d/%d"):format(completed, totalSteps)
		hintLabel.Text = serverHint
	end
	refreshPrompts()
end

function PrisonController.handle(data)
	if not card or type(data) ~= "table" then
		return
	end
	detained = data.active == true
	completed = type(data.step) == "number" and math.max(0, math.floor(data.step)) or 0
	cellOpensAt = type(data.cellOpensAt) == "number" and data.cellOpensAt or 0
	cellId = type(data.cellId) == "string" and data.cellId or ""
	refreshPrompts()
	card.Visible = detained
	if not card.Visible then
		return
	end
	deadline = type(data.endsAt) == "number" and data.endsAt or 0
	local steps = type(data.steps) == "number" and math.max(0, math.floor(data.steps)) or 0
	totalSteps = math.max(completed, steps)
	local step = type(data.step) == "number" and math.clamp(math.floor(data.step), 0, steps) or 0
	progressLabel.Text = ("ROTA DE FUGA  ·  %d/%d"):format(step, steps)
	serverHint = type(data.hint) == "string" and data.hint or "Siga as placas da passagem de manutenção."
	hintLabel.Text = serverHint
	updateTimer()
end

local function readAttributes()
	PrisonController.handle({
		active = player:GetAttribute("Detained") == true,
		endsAt = player:GetAttribute("PrisonEndsAt"),
		step = player:GetAttribute("PrisonStep"),
		steps = player:GetAttribute("PrisonSteps"),
		hint = player:GetAttribute("PrisonHint"),
		cellId = player:GetAttribute("PrisonCell"),
		cellOpensAt = player:GetAttribute("PrisonCellOpensAt"),
	})
end

function PrisonController.init()
	if initialized then
		return
	end
	initialized = true

	local gui = Instance.new("ScreenGui")
	gui.Name = "PrisonUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 3
	gui.Parent = player:WaitForChild("PlayerGui")

	card = Instance.new("Frame")
	card.Name = "DetentionCard"
	card.AnchorPoint = Vector2.new(0.5, 1)
	card.Position = UDim2.new(0.5, 0, 1, -28)
	card.Size = UDim2.fromOffset(360, 146)
	card.BackgroundColor3 = Color3.fromRGB(20, 31, 46)
	card.BackgroundTransparency = 0.08
	card.BorderSizePixel = 0
	card.Visible = false
	card.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(96, 132, 162)
	stroke.Transparency = 0.35
	stroke.Thickness = 1
	stroke.Parent = card
	UIScaler.attach(card)

	text(card, "Title", "PRISÃO", UDim2.fromOffset(16, 10), UDim2.fromOffset(210, 25),
		Color3.fromRGB(235, 242, 248), Enum.Font.GothamBold, 17)
	timerLabel = text(card, "Time", "", UDim2.fromOffset(240, 10), UDim2.fromOffset(104, 25),
		Color3.fromRGB(255, 204, 118), Enum.Font.GothamBold, 18)
	timerLabel.TextXAlignment = Enum.TextXAlignment.Right
	text(card, "Explanation", "Aguarde a liberação ou siga a passagem de manutenção.",
		UDim2.fromOffset(16, 39), UDim2.fromOffset(328, 34), Color3.fromRGB(201, 215, 229))
	progressLabel = text(card, "Progress", "", UDim2.fromOffset(16, 81), UDim2.fromOffset(328, 18),
		Color3.fromRGB(255, 204, 118), Enum.Font.GothamBold, 11)
	hintLabel = text(card, "Hint", "", UDim2.fromOffset(16, 102), UDim2.fromOffset(328, 34),
		Color3.fromRGB(235, 242, 248), Enum.Font.GothamMedium, 13)

	for _, attribute in ipairs({ "Detained", "PrisonEndsAt", "PrisonStep", "PrisonSteps", "PrisonHint", "PrisonCell", "PrisonCellOpensAt" }) do
		player:GetAttributeChangedSignal(attribute):Connect(readAttributes)
	end
	Workspace.DescendantAdded:Connect(watchPrompt)
	for _, item in ipairs(Workspace:GetDescendants()) do
		watchPrompt(item)
	end
	readAttributes()
	task.spawn(function()
		while gui.Parent do
			if card.Visible then
				updateTimer()
			end
			task.wait(0.2)
		end
	end)
end

return PrisonController
