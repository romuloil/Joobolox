-- StatusController (ModuleScript)
-- Caminho: StarterPlayer > StarterPlayerScripts > Controllers > StatusController
-- Marco 10.12: barras de VIDA e STAMINA (embaixo do minimapa, canto de cima à direita) e CORRER.
--   * Correr: segure Shift (PC), L3 no controle ou o botão "Correr" no celular (liga/desliga).
--   * A stamina (0 a 100) cai rápido correndo e recarrega sozinha depois de 1 s sem correr
--     (GameConfig.Stamina). Zerou: só corre de novo quando tiver um pouquinho (MinToRun).
--   * Não corre de bike, sentado, nadando, algemado, mirando ou carregando a bolsa cheia (o peso da
--     bolsa de joias continua deixando mais lento, correndo ou não).
--   * A vida é a do Roblox (100); a barra do Roblox no topo fica escondida.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local UIScaler = require(script.Parent:WaitForChild("UIScaler"))
local CameraController = require(script.Parent:WaitForChild("CameraController"))
local MobileButtons = require(script.Parent:WaitForChild("MobileButtons"))

local StatusController = {}

local S = GameConfig.Stamina
local player = Players.LocalPlayer
local RUN_ACTION = "LittleLifeCorrer"

-- Lugar das barras: embaixo do minimapa (MapController usa os mesmos números)
StatusController.MAP_SIZE = 150
StatusController.TOP = 6
StatusController.BARS_H = 30
-- altura (px, sem escala) ocupada no canto direito: minimapa + barras
StatusController.RIGHT_COLUMN = StatusController.TOP + StatusController.MAP_SIZE + 6 + StatusController.BARS_H + 8

local stamina = S.Max
local lastRun = 0
local exhausted = false
local runHeld, runToggle = false, false
local running = false
local ourSpeed -- velocidade que nós colocamos (correndo)
local baseSpeed -- velocidade "normal" de agora (o servidor muda: bike, bolsa...)
local holder, healthFill, healthText, staminaFill, staminaText
local watched -- humanoid observado

local function corner(parent, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

local function barRow(y, icon, color)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(0, y)
	row.Size = UDim2.new(1, 0, 0, 13)
	row.Parent = holder
	local ic = Instance.new("TextLabel")
	ic.BackgroundTransparency = 1
	ic.Size = UDim2.fromOffset(14, 13)
	ic.Font = Enum.Font.GothamBold
	ic.TextSize = 11
	ic.Text = icon
	ic.TextColor3 = color
	ic.Parent = row
	local back = Instance.new("Frame")
	back.Position = UDim2.fromOffset(17, 3)
	back.Size = UDim2.new(1, -46, 0, 7)
	back.BackgroundColor3 = Color3.fromRGB(10, 12, 18)
	back.BackgroundTransparency = 0.25
	back.BorderSizePixel = 0
	back.Parent = row
	corner(back, 4)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = back
	corner(fill, 4)
	local num = Instance.new("TextLabel")
	num.BackgroundTransparency = 1
	num.AnchorPoint = Vector2.new(1, 0)
	num.Position = UDim2.new(1, 0, 0, 0)
	num.Size = UDim2.fromOffset(26, 13)
	num.Font = Enum.Font.GothamBold
	num.TextSize = 11
	num.TextXAlignment = Enum.TextXAlignment.Right
	num.TextColor3 = Color3.new(1, 1, 1)
	num.TextStrokeTransparency = 0.5
	num.Parent = row
	return fill, num
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "StatusUI"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets -- Marco 10.14: igual ao minimapa
	gui.Parent = player:WaitForChild("PlayerGui")
	holder = Instance.new("Frame")
	holder.Name = "Barras"
	holder.AnchorPoint = Vector2.new(1, 0)
	holder.Size = UDim2.fromOffset(StatusController.MAP_SIZE, StatusController.BARS_H)
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	UIScaler.attach(holder)
	UIScaler.onChanged(function(s)
		holder.Position = UDim2.new(1, -6, 0, (StatusController.TOP + StatusController.MAP_SIZE + 6) * s)
	end)
	healthFill, healthText = barRow(0, "❤", Color3.fromRGB(90, 200, 110))
	staminaFill, staminaText = barRow(16, "⚡", Color3.fromRGB(250, 200, 60))
end

local function humanoidNow()
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function watchHumanoid(humanoid)
	if watched == humanoid then
		return
	end
	watched = humanoid
	ourSpeed = nil
	baseSpeed = humanoid.WalkSpeed
	humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		if not ourSpeed or math.abs(humanoid.WalkSpeed - ourSpeed) > 0.01 then
			baseSpeed = humanoid.WalkSpeed -- quem mudou foi o jogo (bike, bolsa, etc.)
			ourSpeed = nil
		end
	end)
end

local function canRun(humanoid)
	if humanoid.Health <= 0 or humanoid.Sit or humanoid.SeatPart or humanoid.PlatformStand then
		return false
	end
	local state = humanoid:GetState()
	if state == Enum.HumanoidStateType.Swimming or state == Enum.HumanoidStateType.Climbing then
		return false
	end
	if player:GetAttribute("Algemado") or player:GetAttribute("Atordoado") or player:GetAttribute("Preso") then
		return false
	end
	if CameraController.isAiming() then
		return false
	end
	-- de bike (ou outra coisa que deixou mais rápido) não corre
	if (baseSpeed or GameConfig.WalkSpeed) > GameConfig.WalkSpeed + 0.1 then
		return false
	end
	return humanoid.MoveDirection.Magnitude > 0.1
end

local function step(dt)
	local humanoid = humanoidNow()
	if humanoid then
		watchHumanoid(humanoid)
	end
	local want = (runHeld or runToggle) and humanoid ~= nil and canRun(humanoid)
	if exhausted and stamina >= S.MinToRun then
		exhausted = false
	end
	if want and (exhausted or stamina <= 0) then
		want = false
	end
	if want then
		stamina = math.max(0, stamina - S.Drain * dt)
		lastRun = os.clock()
		if stamina <= 0 then
			exhausted = true
			runToggle = false
		end
	elseif os.clock() - lastRun > S.Delay then
		stamina = math.min(S.Max, stamina + S.Regen * dt)
	end
	running = want
	MobileButtons.show(
		"correr",
		humanoid ~= nil
			and humanoid.Health > 0
			and not humanoid.SeatPart
			and (baseSpeed or GameConfig.WalkSpeed) <= GameConfig.WalkSpeed + 0.1 -- de bike some
	)
	MobileButtons.setActive("correr", runToggle)
	if humanoid then
		local base = baseSpeed or GameConfig.WalkSpeed
		if running then
			-- a bolsa deixa mais lento também correndo (mesma proporção)
			local speed = S.RunSpeed * math.clamp(base / GameConfig.WalkSpeed, 0.4, 1)
			if not ourSpeed or math.abs(humanoid.WalkSpeed - speed) > 0.01 then
				ourSpeed = speed
				humanoid.WalkSpeed = speed
			end
		elseif ourSpeed then
			ourSpeed = nil
			humanoid.WalkSpeed = base
		end
		-- barras
		local hp = math.clamp(humanoid.Health / math.max(1, humanoid.MaxHealth), 0, 1)
		healthFill.Size = UDim2.fromScale(hp, 1)
		healthFill.BackgroundColor3 = hp > 0.35 and Color3.fromRGB(90, 200, 110) or Color3.fromRGB(230, 70, 60)
		healthText.Text = tostring(math.ceil(humanoid.Health))
	end
	local st = stamina / S.Max
	staminaFill.Size = UDim2.fromScale(st, 1)
	staminaFill.BackgroundColor3 = exhausted and Color3.fromRGB(200, 110, 60) or Color3.fromRGB(250, 200, 60)
	staminaText.Text = tostring(math.floor(stamina + 0.5))
end

function StatusController.isRunning()
	return running
end

function StatusController.init()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	end)
	build()
	ContextActionService:BindAction(RUN_ACTION, function(_, state, input)
		if input.UserInputType == Enum.UserInputType.Touch then
			if state == Enum.UserInputState.Begin then
				runToggle = not runToggle
			end
		else
			runHeld = state == Enum.UserInputState.Begin
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
	-- Marco 10.14: no celular o botão é o redondo em cima do pulo (MobileButtons)
	MobileButtons.add("correr", {
		icon = "⚡",
		title = "Correr",
		slots = { 3, 2 },
		onPress = function()
			runToggle = not runToggle
		end,
	})
	UserInputService.WindowFocusReleased:Connect(function()
		runHeld = false
	end)
	player.CharacterAdded:Connect(function()
		stamina = S.Max
		exhausted = false
		runToggle = false
	end)
	RunService.RenderStepped:Connect(step)
end

return StatusController
