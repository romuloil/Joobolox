-- PropService (ModuleScript)
-- Caminho: ServerScriptService > Services > PropService
-- Marco 10.2: coisas para mexer dentro das casas (apartamento, cobertura, mansão e os móveis).
-- Toda peça com o atributo "Toggle" ganha um aviso (E) que liga e desliga:
--   TV   = a tela acende (azul) ou apaga (preta)
--   Luz  = interruptor ou abajur: liga/desliga as luzes do modelo "Target" (ou do próprio móvel)
--   Fogo = lareira e fogueira
--   Agua = chuveiro, hidromassagem e jacuzzi (gotas e bolhas)
-- Atributos: Label = nome no aviso; On = começa ligado; Target = modelo das luzes (irmão da peça).
-- Também põe o "Sentar" nos assentos dos móveis (pasta Interiores), como o SeatService faz no mapa.

local Workspace = game:GetService("Workspace")

local SecurityService = require(script.Parent:WaitForChild("SecurityService"))
local SeatService = require(script.Parent:WaitForChild("SeatService"))

local PropService = {}

local TEXTS = {
	TV = { "Ligar", "Desligar" },
	Luz = { "Acender", "Apagar" },
	Fogo = { "Acender", "Apagar" },
	Agua = { "Ligar", "Desligar" },
}
local TV_ON = Color3.fromRGB(70, 150, 235)
local TV_OFF = Color3.fromRGB(20, 20, 24)

local function lightsOf(part)
	local target = part:GetAttribute("Target")
	local holder = (target and part.Parent:FindFirstChild(target)) or part.Parent
	return holder
end

local function apply(part, kind, on)
	if kind == "TV" then
		part.Material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
		part.Color = on and TV_ON or TV_OFF
	elseif kind == "Luz" then
		for _, d in ipairs(lightsOf(part):GetDescendants()) do
			if d:IsA("Light") then
				d.Enabled = on
				d:SetAttribute("Off", not on or nil) -- Marco 10.6: o cliente respeita (LightingController)
			elseif d:IsA("BasePart") and d ~= part and (d.Name == "Lampada" or d.Name == "Lustre" or d.Name == "Abajur" or d.Name == "Shade") then
				d.Material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
			end
		end
		if part.Name == "Shade" then
			part.Material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
		end
	elseif kind == "Fogo" then
		for _, d in ipairs(part:GetDescendants()) do
			if d:IsA("Fire") or d:IsA("Light") then
				d.Enabled = on
				if d:IsA("Light") then
					d:SetAttribute("Off", not on or nil)
				end
			end
		end
		if part.Name == "Flame" then
			part.Transparency = on and 0 or 1
		end
	elseif kind == "Agua" then
		for _, d in ipairs(part:GetDescendants()) do
			if d:IsA("ParticleEmitter") then
				d.Enabled = on
			end
		end
	end
end

local function setup(part)
	local kind = part:GetAttribute("Toggle")
	if not TEXTS[kind] or part:FindFirstChild("TogglePrompt") then
		return
	end
	local on = part:GetAttribute("On") == true
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TogglePrompt"
	prompt.ObjectText = part:GetAttribute("Label") or kind
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt.Parent = part
	local function refresh()
		prompt.ActionText = TEXTS[kind][on and 2 or 1]
		apply(part, kind, on)
	end
	refresh()
	prompt.Triggered:Connect(function(player)
		if not SecurityService.checkRate(player, "Toggle", 0.4) then
			return
		end
		on = not on
		refresh()
	end)
end

local function scan(container)
	for _, d in ipairs(container:GetDescendants()) do
		if d:IsA("BasePart") then
			if d:GetAttribute("Toggle") then
				setup(d)
			end
			if d:IsA("Seat") then
				SeatService.setup(d)
			end
		end
	end
end

function PropService.init()
	local map = Workspace:FindFirstChild("Map")
	if map then
		scan(map)
	end
	-- móveis do dono: aparecem e somem quando alguém entra ou sai da casa
	local interiors = Workspace:FindFirstChild("Interiores")
	if interiors then
		interiors.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") then
				task.defer(function()
					if d.Parent then
						if d:GetAttribute("Toggle") then
							setup(d)
						end
						if d:IsA("Seat") then
							SeatService.setup(d)
						end
					end
				end)
			end
		end)
	end
end

return PropService
