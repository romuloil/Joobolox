-- NPCService (ModuleScript)
-- Caminho: ServerScriptService > Services > NPCService
-- Marco 2: cria o NPC guia (Seu Bento) na praça.
-- A conversa usa ProximityPrompt: no PC aparece "E", no celular um botão para tocar.
-- O servidor confere distância e frequência antes de mandar o diálogo ao cliente.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local SecurityService = require(script.Parent:WaitForChild("SecurityService"))
local NPCKit = require(script.Parent:WaitForChild("NPCKit"))

local NPCService = {}

local GUIDE = GameConfig.Guide
local uiUpdate
local guideRoot -- HumanoidRootPart do Seu Bento

local function groundHeightAt(position)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local map = Workspace:FindFirstChild("Map")
	params.FilterDescendantsInstances = map and { map } or {}
	local result = Workspace:Raycast(position + Vector3.new(0, 50, 0), Vector3.new(0, -100, 0), params)
	return result and result.Position.Y or 0
end

local function createGuide()
	local desc = Instance.new("HumanoidDescription")
	desc.HeadColor = GUIDE.SkinColor
	desc.LeftArmColor = GUIDE.SkinColor
	desc.RightArmColor = GUIDE.SkinColor
	desc.TorsoColor = GUIDE.ShirtColor
	desc.LeftLegColor = GUIDE.PantsColor
	desc.RightLegColor = GUIDE.PantsColor

	local npc = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	npc.Name = GUIDE.Name

	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	local root = npc:FindFirstChild("HumanoidRootPart")
	humanoid.DisplayName = GUIDE.Name
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	humanoid.NameDisplayDistance = 60
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	root.Anchored = true
	guideRoot = root

	-- Em pé no chão, olhando para o spawn
	local ground = groundHeightAt(GUIDE.Position)
	local height = humanoid.HipHeight + root.Size.Y / 2
	local pos = Vector3.new(GUIDE.Position.X, ground + height, GUIDE.Position.Z)
	local lookAt = Vector3.new(0, pos.Y, 20)
	npc:PivotTo(CFrame.lookAt(pos, lookAt))

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Conversar"
	prompt.ObjectText = GUIDE.Name
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = root

	local npcFolder = Workspace:FindFirstChild("NPCs") or Instance.new("Folder")
	npcFolder.Name = "NPCs"
	npcFolder.Parent = Workspace
	npc.Parent = npcFolder
	NPCKit.animate(npc, true) -- respira parado e acena quando alguém conversa

	prompt.Triggered:Connect(function(player)
		if not SecurityService.checkRate(player, "TalkGuide", 1) then
			return
		end
		if not NPCService.isNearGuide(player) then
			return
		end
		NPCKit.emote(npc, "wave")
		uiUpdate:FireClient(player, "GuideDialog", {})
	end)
end

-- true se o jogador está perto o bastante do Seu Bento para conversar
function NPCService.isNearGuide(player)
	local _, _, playerRoot = SecurityService.getLivingCharacter(player)
	if not playerRoot or not guideRoot then
		return false
	end
	return (playerRoot.Position - guideRoot.Position).Magnitude <= GUIDE.TalkDistance
end

function NPCService.init(remotes)
	uiUpdate = remotes[GameConfig.Remotes.UIUpdate]
	local ok, err = pcall(createGuide)
	if not ok then
		warn("[NPCService] Erro ao criar o Seu Bento: " .. tostring(err))
	end
end

return NPCService
