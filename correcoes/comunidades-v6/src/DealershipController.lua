-- DealershipController (ModuleScript)
-- Caminho: StarterPlayer > StarterPlayerScripts > Controllers > DealershipController
-- Marco 10.31: gira os carros de exposição da concessionária (tag "VitrineGiratoria").
-- Gira só no aparelho (o servidor não gasta nada), só quando o jogador está perto, e todo mundo
-- vê o carro na mesma posição (usa o relógio do servidor).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DealershipController = {}

local offsets = {} -- offsets[carro] = posição do carro em relação ao centro da plataforma
local NEAR = 320
local acc = 0

local function step(dt)
	acc += dt
	if acc < 1 / 30 then
		return
	end
	acc = 0
	local char = Players.LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local cam = Workspace.CurrentCamera
	local eye = (root and root.Position) or (cam and cam.CFrame.Position)
	if not eye then
		return
	end
	local now = Workspace:GetServerTimeNow()
	for _, car in ipairs(CollectionService:GetTagged("VitrineGiratoria")) do
		local center = car:GetAttribute("Centro")
		if car:IsA("Model") and typeof(center) == "Vector3" and (center - eye).Magnitude < NEAR then
			local base = CFrame.new(center)
			if not offsets[car] then
				offsets[car] = base:Inverse() * car:GetPivot()
				car.Destroying:Once(function()
					offsets[car] = nil
				end)
			end
			local angle = (now * (car:GetAttribute("Velocidade") or 0.25)) % (math.pi * 2)
			car:PivotTo(base * CFrame.Angles(0, angle, 0) * offsets[car])
		end
	end
end

function DealershipController.init()
	CollectionService:GetInstanceRemovedSignal("VitrineGiratoria"):Connect(function(car)
		offsets[car] = nil -- saiu do streaming: quando voltar, pega a posição de novo
	end)
	RunService.Heartbeat:Connect(step)
end

return DealershipController
