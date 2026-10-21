-- RigMeasure (ModuleScript)
-- Caminho: ReplicatedStorage > Shared > RigMeasure
-- Mede o boneco do jogador (R15 ou R6): onde ficam quadris e ombros em relação ao
-- HumanoidRootPart e o comprimento de pernas e braços. O servidor usa isso para
-- montar a bicicleta do tamanho certo, e o cliente para animar a pedalada.

local RigMeasure = {}

local function find(character, partName, jointName)
	local part = character:FindFirstChild(partName)
	return part and part:FindFirstChild(jointName)
end

-- Distância do pivô da junta até a ponta da peça (sola do pé / ponta do braço)
local function reachBelow(joint, part)
	return math.max(0, joint.C1.Position.Y + part.Size.Y / 2)
end

local function measureR15(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	local j = {
		Root = find(character, "LowerTorso", "Root"),
		Waist = find(character, "UpperTorso", "Waist"),
		LeftHip = find(character, "LeftUpperLeg", "LeftHip"),
		RightHip = find(character, "RightUpperLeg", "RightHip"),
		LeftKnee = find(character, "LeftLowerLeg", "LeftKnee"),
		RightKnee = find(character, "RightLowerLeg", "RightKnee"),
		LeftAnkle = find(character, "LeftFoot", "LeftAnkle"),
		RightAnkle = find(character, "RightFoot", "RightAnkle"),
		LeftShoulder = find(character, "LeftUpperArm", "LeftShoulder"),
		RightShoulder = find(character, "RightUpperArm", "RightShoulder"),
		LeftElbow = find(character, "LeftLowerArm", "LeftElbow"),
		RightElbow = find(character, "RightLowerArm", "RightElbow"),
		LeftWrist = find(character, "LeftHand", "LeftWrist"),
		RightWrist = find(character, "RightHand", "RightWrist"),
	}
	for _, joint in pairs(j) do
		if not joint then
			return nil
		end
	end

	-- Pose de descanso, calculada só pelas juntas (não depende da animação do momento)
	local lowerTorso = j.Root.C0 * j.Root.C1:Inverse()
	local upperTorso = lowerTorso * j.Waist.C0 * j.Waist.C1:Inverse()

	return {
		rigType = "R15",
		root = root,
		joints = j,
		hip = { Left = (lowerTorso * j.LeftHip.C0).Position, Right = (lowerTorso * j.RightHip.C0).Position },
		shoulder = { Left = (upperTorso * j.LeftShoulder.C0).Position, Right = (upperTorso * j.RightShoulder.C0).Position },
		legL1 = (j.LeftHip.C1.Position - j.LeftKnee.C0.Position).Magnitude,
		legL2 = (j.LeftKnee.C1.Position - j.LeftAnkle.C0.Position).Magnitude + reachBelow(j.LeftAnkle, character.LeftFoot),
		armL1 = (j.LeftShoulder.C1.Position - j.LeftElbow.C0.Position).Magnitude,
		armL2 = (j.LeftElbow.C1.Position - j.LeftWrist.C0.Position).Magnitude + j.LeftWrist.C1.Position.Magnitude,
	}
end

local function measureR6(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	local torso = character:FindFirstChild("Torso")
	local rootJoint = root and root:FindFirstChild("RootJoint")
	if not torso or not rootJoint then
		return nil
	end
	local j = {
		LeftHip = torso:FindFirstChild("Left Hip"),
		RightHip = torso:FindFirstChild("Right Hip"),
		LeftShoulder = torso:FindFirstChild("Left Shoulder"),
		RightShoulder = torso:FindFirstChild("Right Shoulder"),
	}
	local leg, arm = character:FindFirstChild("Left Leg"), character:FindFirstChild("Left Arm")
	if not (j.LeftHip and j.RightHip and j.LeftShoulder and j.RightShoulder and leg and arm) then
		return nil
	end
	local t = rootJoint.C0 * rootJoint.C1:Inverse()
	return {
		rigType = "R6",
		root = root,
		joints = j,
		hip = { Left = (t * j.LeftHip.C0).Position, Right = (t * j.RightHip.C0).Position },
		shoulder = { Left = (t * j.LeftShoulder.C0).Position, Right = (t * j.RightShoulder.C0).Position },
		legL1 = reachBelow(j.LeftHip, leg),
		legL2 = 0, -- R6 não tem joelho
		armL1 = reachBelow(j.LeftShoulder, arm),
		armL2 = 0,
	}
end

-- Retorna a medida do boneco, ou nil se faltar alguma junta (avatar diferente do padrão)
function RigMeasure.measure(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local ok, result = pcall(function()
		if humanoid.RigType == Enum.HumanoidRigType.R15 then
			return measureR15(character)
		end
		return measureR6(character)
	end)
	return ok and result or nil
end

return RigMeasure
