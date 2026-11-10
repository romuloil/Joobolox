-- ParkController (ModuleScript)
-- Caminho: StarterPlayer > StarterPlayerScripts > Controllers > ParkController
-- Marco 7.4: os brinquedos da MigueLândia agora andam no servidor (dá para sentar em todos).
-- Aqui ficam só as coisas deste aparelho:
--   * camas elásticas: pisou na lona (atributo Trampoline), pula bem alto;
--   * luzinhas das barracas piscando (atributo Blink = 0 ou 1, acendem alternadas).
-- Longe do parque (mais de 700 studs) nada disso roda, para economizar.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ParkController = {}

local player = Players.LocalPlayer
local FAR = 700
local BOUNCE = 72 -- velocidade para cima ao pular na cama elástica
local BLINK_EVERY = 0.5

local parkCenter
local bulbs = {}
local lastBounce = 0
local blinkClock, blinkPhase = 0, 0

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function addBulb(d)
	if d:IsA("BasePart") and d:GetAttribute("Blink") ~= nil then
		table.insert(bulbs, { part = d, phase = d:GetAttribute("Blink"), color = d.Color })
	end
end

local function collect(park)
	parkCenter = (park:GetAttribute("MapaPivot") or park:GetPivot()).Position
	for _, d in ipairs(park:GetDescendants()) do
		addBulb(d)
	end
	park.DescendantAdded:Connect(addBulb) -- peças que chegam depois (streaming)
end

local function step(dt)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or (root.Position - parkCenter).Magnitude > FAR then
		return
	end
	-- cama elástica: olha o que tem embaixo dos pés
	local now = os.clock()
	if now - lastBounce > 0.25 and not humanoid.SeatPart then
		rayParams.FilterDescendantsInstances = { character }
		local hit = Workspace:Raycast(root.Position, Vector3.new(0, -(humanoid.HipHeight + root.Size.Y / 2 + 0.6), 0), rayParams)
		if hit and hit.Instance:GetAttribute("Trampoline") then
			local v = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = Vector3.new(v.X, BOUNCE, v.Z)
			lastBounce = now
		end
	end
	-- luzinhas
	blinkClock += dt
	if blinkClock >= BLINK_EVERY then
		blinkClock = 0
		blinkPhase = 1 - blinkPhase
		for i = #bulbs, 1, -1 do
			local b = bulbs[i]
			if b.part.Parent then
				local on = b.phase == blinkPhase
				b.part.Material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
				b.part.Color = on and b.color or b.color:Lerp(Color3.new(0, 0, 0), 0.5)
			else
				table.remove(bulbs, i) -- saiu do aparelho (streaming)
			end
		end
	end
end

function ParkController.init()
	task.spawn(function()
		local map = Workspace:WaitForChild("Map", 60)
		local park = map and map:WaitForChild("MigueLandia", 30)
		if not park then
			return
		end
		task.wait(1) -- deixa as peças do parque chegarem no aparelho
		collect(park)
		RunService.Heartbeat:Connect(step)
	end)
end

return ParkController
