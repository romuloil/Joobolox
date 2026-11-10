-- PrisonController (ModuleScript)
-- Caminho: StarterPlayer > StarterPlayerScripts > Controllers > PrisonController
-- Marco 8.1: quadrinho do Presidiário (canto de cima, embaixo do saldo): tempo de pena que falta
-- e quantas tarefas faltam para a pena diminuir. Só aparece para quem está preso.
-- Lê os atributos que o PrisonService coloca no jogador (Preso, PrisonLeft, PrisonTasks, PrisonNeed).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local UIScaler = require(script.Parent:WaitForChild("UIScaler"))

local PrisonController = {}

local player = Players.LocalPlayer
local ORANGE = Color3.fromRGB(235, 120, 30)

local frame, timeLabel, taskLabel, cellLabel

local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = props.Font or Enum.Font.GothamBold
	l.TextScaled = true
	l.TextColor3 = props.Color or Color3.new(1, 1, 1)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Size = props.Size
	l.Position = props.Position
	l.Text = ""
	l.Parent = parent
	return l
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "PrisonUI"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	frame = Instance.new("Frame")
	frame.Name = "Presidiario"
	frame.Size = UDim2.fromOffset(260, 74)
	frame.Position = UDim2.fromOffset(12, 78)
	frame.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
	frame.BackgroundTransparency = 0.1
	frame.Visible = false
	frame.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 12)
	c.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = ORANGE
	stroke.Thickness = 2
	stroke.Parent = frame
	UIScaler.attach(frame)

	local title = label(frame, { Size = UDim2.new(1, -16, 0, 18), Position = UDim2.fromOffset(8, 4), Font = Enum.Font.GothamBlack, Color = ORANGE })
	title.Text = "🔒 PRESIDIÁRIO"
	cellLabel = label(frame, { Size = UDim2.new(0.5, -8, 0, 18), Position = UDim2.new(0.5, 0, 0, 4), Font = Enum.Font.Gotham, Color = Color3.fromRGB(200, 200, 200) })
	cellLabel.TextXAlignment = Enum.TextXAlignment.Right
	timeLabel = label(frame, { Size = UDim2.new(1, -16, 0, 24), Position = UDim2.fromOffset(8, 24) })
	taskLabel = label(frame, { Size = UDim2.new(1, -16, 0, 18), Position = UDim2.fromOffset(8, 51), Font = Enum.Font.Gotham, Color = Color3.fromRGB(220, 220, 220) })
end

local function refresh()
	local preso = player:GetAttribute("Preso") == true
	frame.Visible = preso
	if not preso then
		return
	end
	local left = tonumber(player:GetAttribute("PrisonLeft")) or 0
	timeLabel.Text = ("Pena: %d:%02d"):format(math.floor(left / 60), left % 60)
	local done = tonumber(player:GetAttribute("PrisonTasks")) or 0
	local need = tonumber(player:GetAttribute("PrisonNeed")) or 0
	taskLabel.Text = ("Tarefas: %d/%d  (−%ds de pena)"):format(done, need, GameConfig.Prison.TaskReduction)
	local cell = player:GetAttribute("PrisonCell")
	cellLabel.Text = cell and ("Cela " .. tostring(cell)) or ""
end

function PrisonController.init()
	build()
	for _, key in ipairs({ "Preso", "PrisonLeft", "PrisonTasks", "PrisonNeed", "PrisonCell" }) do
		player:GetAttributeChangedSignal(key):Connect(refresh)
	end
	refresh()
end

return PrisonController
