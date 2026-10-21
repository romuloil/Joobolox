-- SeatService (ModuleScript)
-- Caminho: ServerScriptService > Services > SeatService
-- Bancos e banquinhos: o jogador só senta quando QUER, apertando E (ou tocando no botão no celular).
-- O "sentar sozinho ao encostar" do Roblox é desligado (CanTouch = false no assento).
-- Para levantar: pular (Espaço ou botão de pulo).

local Workspace = game:GetService("Workspace")

local SecurityService = require(script.Parent:WaitForChild("SecurityService"))

local SeatService = {}

local SIT_DISTANCE = 9
local beforeSit -- função chamada antes de sentar (ex.: descer da bicicleta)

function SeatService.setup(seat, objectText)
	if not seat:IsA("Seat") or seat:FindFirstChild("SeatPrompt") then
		return
	end
	seat.CanTouch = false -- não senta sozinho ao encostar
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SeatPrompt"
	prompt.ActionText = "Sentar"
	prompt.ObjectText = objectText or "Banco"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 7
	prompt.RequiresLineOfSight = false
	prompt.Parent = seat

	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		prompt.Enabled = seat.Occupant == nil
	end)

	prompt.Triggered:Connect(function(player)
		local stunnedUntil = player:GetAttribute("StunnedUntil")
		if type(stunnedUntil) == "number" and stunnedUntil > Workspace:GetServerTimeNow() then
			return
		end
		local vehicles = Workspace:FindFirstChild("Vehicles")
		if player:GetAttribute("Detained") and vehicles and seat:IsDescendantOf(vehicles) then
			return -- bancos da prisão continuam usáveis; carona não contorna a detenção
		end
		if not SecurityService.checkRate(player, "Sit", 0.5) then
			return
		end
		local _, humanoid, root = SecurityService.getLivingCharacter(player)
		if not humanoid or seat.Occupant or humanoid.SeatPart then
			return
		end
		if (root.Position - seat.Position).Magnitude > SIT_DISTANCE then
			return
		end
		if beforeSit then
			beforeSit(player)
		end
		seat:Sit(humanoid)
	end)
end

function SeatService.init(onBeforeSit)
	beforeSit = onBeforeSit
	for _, container in ipairs({ Workspace:FindFirstChild("Map"), Workspace:FindFirstChild("JobStations") }) do
		for _, d in ipairs(container and container:GetDescendants() or {}) do
			if d:IsA("Seat") then
				SeatService.setup(d)
			end
		end
	end
end

return SeatService
