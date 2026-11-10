-- FerramentasController (ModuleScript)
-- Caminho: StarterPlayer > StarterPlayerScripts > Controllers > FerramentasController
-- Marco 10.30: o lado do jogador das ferramentas do assalto ao banco.
--   * PERFURATRIZ na porta do cofre: painel com o progresso e o CALOR. Segure o clique (no celular,
--     o botão 🛠️; no controle, R2) para furar; solte para esfriar. Superaqueceu = trava uns
--     segundos. Pular ou apertar X larga a perfuratriz.
--   * O boneco fica de frente para a porta enquanto fura; a câmera treme de leve.
--   * A cabeça de corte gira (em todos os bonecos com a perfuratriz na mão; mais rápido furando).
--   * EXPLOSÃO (C4): clarão, câmera tremendo e borrão conforme a distância; quem estava perto é
--     jogado para trás.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local MobileButtons = require(script.Parent:WaitForChild("MobileButtons"))

local FerramentasController = {}

local player = Players.LocalPlayer
local request
local gui, panel, title, progFill, progLabel, heatFill, heatLabel, stateLabel, hintLabel, panelScale
local drilling = false
local pushing = false
local lastKeep = 0
local data = {}
local shakeAmp, shakeUntil = 0, 0
local spins = {} -- spins[character] = { angle, speed }

local ORANGE = Color3.fromRGB(255, 150, 50)
local DARK = Color3.fromRGB(16, 18, 24)
local GREEN = Color3.fromRGB(70, 200, 110)
local RED = Color3.fromRGB(235, 60, 50)
local WHITE = Color3.new(1, 1, 1)
local MUTED = Color3.fromRGB(170, 176, 190)

local function corner(obj, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = obj
end

local function text(parent, str, size, font, color)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = str
	l.TextSize = size
	l.Font = font or Enum.Font.GothamBold
	l.TextColor3 = color or WHITE
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

local function bar(parent, y, color)
	local track = Instance.new("Frame")
	track.Position = UDim2.fromOffset(16, y)
	track.Size = UDim2.new(1, -32, 0, 14)
	track.BackgroundColor3 = Color3.fromRGB(40, 44, 54)
	track.BorderSizePixel = 0
	track.Parent = parent
	corner(track, 7)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = track
	corner(fill, 7)
	return track, fill
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "PerfuratrizUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 6
	gui.Parent = player:WaitForChild("PlayerGui")
	panel = Instance.new("Frame")
	panel.Name = "PainelPerfuratriz"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -110)
	panel.Size = UDim2.fromOffset(360, 150)
	panel.BackgroundColor3 = DARK
	panel.BackgroundTransparency = 0.08
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 16)
	local stroke = Instance.new("UIStroke")
	stroke.Color = ORANGE
	stroke.Thickness = 2
	stroke.Transparency = 0.3
	stroke.Parent = panel
	panelScale = Instance.new("UIScale")
	panelScale.Parent = panel
	title = text(panel, "🛠️  PERFURANDO O COFRE", 16, Enum.Font.GothamBlack)
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -32, 0, 20)
	progLabel = text(panel, "0%", 14, Enum.Font.GothamBlack, ORANGE)
	progLabel.TextXAlignment = Enum.TextXAlignment.Right
	progLabel.Position = UDim2.fromOffset(16, 10)
	progLabel.Size = UDim2.new(1, -32, 0, 20)
	local _, pf = bar(panel, 36, ORANGE)
	progFill = pf
	heatLabel = text(panel, "CALOR", 11, Enum.Font.GothamBold, MUTED)
	heatLabel.Position = UDim2.fromOffset(16, 54)
	heatLabel.Size = UDim2.new(1, -32, 0, 14)
	local _, hf = bar(panel, 70, GREEN)
	heatFill = hf
	stateLabel = text(panel, "SEGURE O CLIQUE PARA FURAR", 15, Enum.Font.GothamBlack)
	stateLabel.TextXAlignment = Enum.TextXAlignment.Center
	stateLabel.Position = UDim2.fromOffset(16, 92)
	stateLabel.Size = UDim2.new(1, -32, 0, 20)
	hintLabel = text(panel, "", 11, Enum.Font.Gotham, MUTED)
	hintLabel.TextXAlignment = Enum.TextXAlignment.Center
	hintLabel.Position = UDim2.fromOffset(16, 118)
	hintLabel.Size = UDim2.new(1, -32, 0, 16)
	local function fit()
		local cam = Workspace.CurrentCamera
		local w = cam and cam.ViewportSize.X or 800
		panelScale.Scale = math.clamp(w / 900, 0.7, 1)
	end
	fit()
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
end

local function touchOnly()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function setPush(on)
	if pushing == on then
		return
	end
	pushing = on
	lastKeep = os.clock()
	request:FireServer("Perfurar", on)
end

local function stopLocal()
	drilling = false
	setPush(false)
	ContextActionService:UnbindAction("PerfurarCofre")
	ContextActionService:UnbindAction("LargarPerfuratriz")
	MobileButtons.show("perfurar", false)
	if panel then
		TweenService:Create(panel, TweenInfo.new(0.25), { Position = UDim2.new(0.5, 0, 1, 40) }):Play()
		task.delay(0.26, function()
			if not drilling then
				panel.Visible = false
			end
		end)
	end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.AutoRotate = true
	end
end

local function startLocal()
	if drilling then
		return
	end
	drilling = true
	panel.Visible = true
	panel.Position = UDim2.new(0.5, 0, 1, 40)
	TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Position = UDim2.new(0.5, 0, 1, -110) }):Play()
	ContextActionService:BindAction("PerfurarCofre", function(_, state)
		if state == Enum.UserInputState.Begin then
			setPush(true)
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			setPush(false)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
	ContextActionService:BindAction("LargarPerfuratriz", function(_, state)
		if state == Enum.UserInputState.Begin then
			request:FireServer("Soltar")
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.X, Enum.KeyCode.ButtonB)
	MobileButtons.show("perfurar", true)
	hintLabel.Text = touchOnly() and "Segure o botão 🛠️  •  Pular larga a perfuratriz" or "Segure o CLIQUE (R2)  •  Solte para esfriar  •  X larga"
end

local function render()
	if not drilling then
		return
	end
	local p = math.clamp(data.p or 0, 0, 1)
	local heat = math.clamp(data.heat or 0, 0, 1)
	progFill.Size = UDim2.fromScale(p, 1)
	progLabel.Text = ("%d%%"):format(math.floor(p * 100))
	heatFill.Size = UDim2.fromScale(heat, 1)
	heatFill.BackgroundColor3 = GREEN:Lerp(Color3.fromRGB(255, 200, 40), math.min(1, heat * 1.6)):Lerp(RED, math.max(0, heat - 0.6) / 0.4)
	if data.jam then
		stateLabel.Text = "⚠️ A BROCA TRAVOU! Alguém destrave (E na porta)"
		stateLabel.TextColor3 = RED
	elseif data.lock then
		stateLabel.Text = ("🔥 SUPERAQUECEU! Esfriando... %d"):format(math.ceil(data.lock))
		stateLabel.TextColor3 = RED
	elseif heat > 0.8 then
		stateLabel.Text = "SOLTE! VAI SUPERAQUECER"
		stateLabel.TextColor3 = Color3.fromRGB(255, 200, 40)
	elseif data.push then
		stateLabel.Text = "FURANDO..."
		stateLabel.TextColor3 = ORANGE
	else
		stateLabel.Text = touchOnly() and "SEGURE O BOTÃO 🛠️ PARA FURAR" or "SEGURE O CLIQUE PARA FURAR"
		stateLabel.TextColor3 = WHITE
	end
	heatLabel.Text = heat > 0.8 and "CALOR  ⚠" or "CALOR"
end

local function flash(color, alpha, seconds)
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 1 - alpha
	f.BorderSizePixel = 0
	f.ZIndex = 50
	f.Parent = gui
	TweenService:Create(f, TweenInfo.new(seconds or 0.7), { BackgroundTransparency = 1 }):Play()
	task.delay((seconds or 0.7) + 0.05, function()
		f:Destroy()
	end)
end

local function shake(amp, seconds)
	if amp > shakeAmp or os.clock() > shakeUntil then
		shakeAmp = amp
		shakeUntil = os.clock() + seconds
	end
end

local function explosion(info)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local pos = typeof(info.pos) == "Vector3" and info.pos or nil
	if not root or not pos then
		return
	end
	local d = (root.Position - pos).Magnitude
	local k = math.clamp(1 - d / 140, 0, 1) * (info.big and 1 or 0.65)
	if k <= 0 then
		return
	end
	flash(Color3.fromRGB(255, 220, 170), 0.85 * k, 0.9)
	shake(2.2 * k, 0.4 + 0.9 * k)
	local cam = Workspace.CurrentCamera
	if cam and k > 0.25 then
		local blur = Instance.new("BlurEffect")
		blur.Size = 20 * k
		blur.Parent = cam
		TweenService:Create(blur, TweenInfo.new(1.6), { Size = 0 }):Play()
		task.delay(1.7, function()
			blur:Destroy()
		end)
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Brightness = 0.25 * k
		cc.Saturation = -0.5 * k
		cc.Parent = cam
		TweenService:Create(cc, TweenInfo.new(2), { Brightness = 0, Saturation = 0 }):Play()
		task.delay(2.1, function()
			cc:Destroy()
		end)
	end
	-- perto: o impacto joga para trás
	local r = (info.r or 14) * 1.4
	if d < r then
		local away = root.Position - pos
		away = Vector3.new(away.X, 0, away.Z)
		away = away.Magnitude > 0.1 and away.Unit or -root.CFrame.LookVector
		local power = 1 - d / r
		root.AssemblyLinearVelocity = root.AssemblyLinearVelocity + away * (70 * power) + Vector3.new(0, 30 * power, 0)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and power > 0.45 then
			humanoid:ChangeState(Enum.HumanoidStateType.FallingDown)
		end
	end
end

-- cabeça de corte girando (Motor6D "GiraCabeca" que o servidor pôs no Handle)
local function stepSpins(dt)
	for _, p in ipairs(Players:GetPlayers()) do
		local character = p.Character
		local tool = character and character:FindFirstChildOfClass("Tool")
		local handle = tool and tool:GetAttribute("Use") == "perfuratriz" and tool:FindFirstChild("Handle")
		local motor = handle and handle:FindFirstChild("GiraCabeca")
		if motor and motor:IsA("Motor6D") then
			local s = spins[character]
			if not s then
				s = { angle = 0, speed = 0 }
				spins[character] = s
				character.AncestryChanged:Connect(function()
					if not character.Parent then
						spins[character] = nil
					end
				end)
			end
			local want = character:GetAttribute("Empurrando") and 30 or (character:GetAttribute("Perfurando") and 5 or 0)
			s.speed += (want - s.speed) * math.min(1, dt * (want > s.speed and 3 or 1.2))
			s.angle = (s.angle + s.speed * dt) % (math.pi * 2)
			motor.Transform = CFrame.Angles(0, 0, s.angle)
		end
	end
end

-- o seu boneco de frente para o ponto do corte enquanto fura
local function faceDoor()
	local character = player.Character
	if not character or not character:GetAttribute("Perfurando") then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local target = character:GetAttribute("AlvoFuro")
	if not (root and humanoid and typeof(target) == "Vector3") then
		return
	end
	humanoid.AutoRotate = false
	local flat = Vector3.new(target.X - root.Position.X, 0, target.Z - root.Position.Z)
	if flat.Magnitude > 0.2 then
		local want = CFrame.lookAt(root.Position, root.Position + flat.Unit)
		if root.CFrame.LookVector:Dot(want.LookVector) < 0.9995 then
			root.CFrame = root.CFrame:Lerp(want, 0.35)
		end
	end
end

function FerramentasController.init()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	request = remotes:WaitForChild(GameConfig.Remotes.BankRequest)
	local uiUpdate = remotes:WaitForChild(GameConfig.Remotes.UIUpdate)
	build()
	MobileButtons.add("perfurar", {
		icon = "🛠️",
		title = "Furar",
		slots = { 1 },
		hold = true,
		onPress = function(began)
			if drilling then
				setPush(began == true)
			end
		end,
	})
	MobileButtons.show("perfurar", false)
	uiUpdate.OnClientEvent:Connect(function(kind, info)
		if kind == "BancoFuro" then
			info = type(info) == "table" and info or {}
			if info.on then
				startLocal()
				data = info
				render()
			else
				data = {}
				if drilling then
					stopLocal()
				end
			end
		elseif kind == "BancoExplosao" then
			if type(info) == "table" then
				explosion(info)
			end
		end
	end)
	-- pular larga a perfuratriz
	local function watchCharacter(character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid then
			humanoid.StateChanged:Connect(function(_, new)
				if drilling and new == Enum.HumanoidStateType.Jumping then
					request:FireServer("Soltar")
				end
			end)
		end
		if drilling then
			stopLocal()
		end
	end
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)
	RunService.Heartbeat:Connect(function(dt)
		stepSpins(dt)
		if drilling then
			faceDoor()
			-- segurando: avisa o servidor de novo de tempos em tempos (se um aviso se perder)
			if pushing and os.clock() - lastKeep > 0.4 then
				lastKeep = os.clock()
				request:FireServer("Perfurar", true)
			end
			if data.push then
				shake(0.12, 0.2)
			end
		end
	end)
	RunService:BindToRenderStep("TremorFerramentas", Enum.RenderPriority.Camera.Value + 3, function()
		local now = os.clock()
		if now < shakeUntil and shakeAmp > 0 then
			local cam = Workspace.CurrentCamera
			local k = shakeAmp * math.clamp((shakeUntil - now) / 0.4, 0.3, 1)
			cam.CFrame = cam.CFrame * CFrame.Angles(math.rad((math.random() - 0.5) * k * 2), math.rad((math.random() - 0.5) * k * 2), 0)
		elseif shakeAmp > 0 then
			shakeAmp = 0
		end
	end)
end

return FerramentasController
