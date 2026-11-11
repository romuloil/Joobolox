-- CameraController (ModuleScript)
-- Caminho: StarterPlayer > StarterPlayerScripts > Controllers > CameraController
-- Marco 10.8:
--   * Mira travada (padrão no PC): o mouse fica no meio da tela, a câmera um pouco à direita do
--     ombro e o boneco vira para onde a câmera olha, como nos jogos de tiro.
--     O mouse solta sozinho quando uma tela grande está aberta (mapa, mochila, lojas...), quando o
--     menu do Roblox abre, ou enquanto você segura Alt. No carro, na bike ou sentado ela desliga.
--     Marco 10.9: solta também quando aparece QUALQUER botão ou caixa de texto de interação (o hack do
--     caixa eletrônico, conversa com NPC, revista...) e trava de novo sozinha quando ele some. Os botões
--     fixos do HUD não contam (telas em HUD_GUIS ou botões com o atributo "HudFixo").
--   * Câmera padrão (a do Roblox): escolhida no seletor do topo (Marco 10.29: o botão ⚙ saiu).
--     Fica salva (atributo "CamLivre", que o SettingsService guarda nos dados do jogador).
--   * No celular não muda nada (lá a câmera já é por toque).
--   * O zoom (sem 1ª pessoa, afastando pouco) é limitado pelo servidor (SettingsService).
-- Marco 10.12 (pedido do Luís: mira "travadinha", ponteiro no meio da tela sem arma):
--   * O boneco vira com a câmera do jeito do próprio Roblox (RotationType CameraRelative, igual ao
--     shift lock), sem forçar a posição a cada quadro: bem mais liso.
--   * Ombro, zoom (FOV) e sensibilidade mudam suave; mirando (botão direito / "Mirar" no celular)
--     a câmera chega mais perto do ombro, dá zoom e o mouse fica mais lento, como no GTA.
--   * Recuo: cada tiro dá um tranquinho para cima na câmera, que volta sozinho.
--   * A mira (bolinha) só aparece com arma, taser ou algema na mão; a setinha do mouse some
--     enquanto ele está travado no meio.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local CameraController = {}

local player = Players.LocalPlayer
local CAM = GameConfig.Camera
local settingsRequest

local gui, crosshair, crossRing
local shoulderFree = 1 -- Marco 10.29: quanto do ombro cabe sem bater na parede (0 a 1), suavizado
local active = false -- mira travada valendo neste quadro
local centered = false -- Marco 10.12: o tiro sai do meio da tela (mira travada ou mirando)
local weaponUse -- "gun", "taser", "algema" ou nil (o que está na mão)
local weaponKind -- "pistola" / "fuzil"
local adsOn = false -- mirando (zoom)
local recoil = 0 -- graus de tranco para aplicar no próximo quadro
local recoilBack = 0 -- graus que ainda faltam voltar
local rotMode -- RotationType que nós colocamos (para devolver)
local offsetNow = Vector3.zero
local fovBase -- FOV normal (o que estava antes de mirar)
local sensSet = false
local uiOpen = false -- tem tela grande aberta (calculado a cada 0,25 s)
local lastHumanoid

local function corner(parent, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

local function isTouchOnly()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function wantsAimLock()
	if isTouchOnly() then
		return false
	end
	local free = player:GetAttribute("CamLivre")
	if free == nil then
		return CAM.AimLockDefault
	end
	return not free
end

-- Marco 10.9: telas que ficam sempre na tela (os botões delas não soltam o mouse)
local HUD_GUIS = {
	GameUI = true,
	HudUI = true,
	MapButtonUI = true,
	MiniMapUI = true, -- Marco 10.12
	StatusUI = true, -- Marco 10.12
	HomeButtonUI = true,
	CameraUI = true,
	InventoryUI = true, -- a barra de atalhos; a mochila aberta é tela grande (conta embaixo)
	WeaponUI = true,
}
-- Marco 10.29: o "tem tela aberta?" ficou bem mais leve. Antes ele olhava TODOS os botões do PlayerGui
-- (centenas: mapa, lojas, mochila...) a cada 0,25 s, subindo pelos pais de cada um, e isso dava um
-- tranquinho na câmera. Agora desce só pelos ramos visíveis (o que está escondido é pulado inteiro)
-- e para no primeiro botão ou tela grande que achar.
local function scanBranch(obj, limit, checkButtons, depth)
	for _, child in ipairs(obj:GetChildren()) do
		if child:IsA("GuiObject") then
			-- (Marco 10.30: painel fixo de assalto com HudFixo também não conta como tela aberta)
			if child.Visible and not child:GetAttribute("HudFixo") then
				if depth <= 2 then
					local s = child.AbsoluteSize
					if s.X * s.Y > limit and (child.BackgroundTransparency < 0.9 or (depth == 1 and child:IsA("ScrollingFrame"))) then
						return true
					end
				end
				local buttons = checkButtons and not child:GetAttribute("HudFixo")
				if buttons and (child:IsA("GuiButton") or child:IsA("TextBox")) and child.AbsoluteSize.X > 4 then
					return true
				end
				if (buttons or depth < 2) and scanBranch(child, limit, buttons, depth + 1) then
					return true
				end
			end
		elseif child:IsA("Folder") then
			if scanBranch(child, limit, checkButtons, depth) then
				return true
			end
		end
	end
	return false
end

-- Tem tela grande aberta, ou algum botão/caixa de interação aparecendo fora do HUD?
local function screenBusy()
	local pg = player:FindFirstChild("PlayerGui")
	local camera = Workspace.CurrentCamera
	if not pg or not camera then
		return false
	end
	local vp = camera.ViewportSize
	local limit = vp.X * vp.Y * 0.05
	for _, sg in ipairs(pg:GetChildren()) do
		if sg:IsA("ScreenGui") and sg.Enabled and sg ~= gui then
			if scanBranch(sg, limit, not HUD_GUIS[sg.Name], 1) then
				return true
			end
		end
	end
	return false
end
local function userSettings()
	local ok, gs = pcall(function()
		return UserSettings():GetService("UserGameSettings")
	end)
	return ok and gs or nil
end

-- Marco 10.12: o boneco vira junto com a câmera pelo próprio Roblox (igual ao shift lock)
local function setCameraRelative(on)
	local gs = userSettings()
	if not gs then
		return false
	end
	if on then
		if gs.RotationType ~= Enum.RotationType.CameraRelative then
			local ok = pcall(function()
				gs.RotationType = Enum.RotationType.CameraRelative
			end)
			if not ok then
				return false
			end
		end
		rotMode = Enum.RotationType.CameraRelative
		return true
	elseif rotMode then
		rotMode = nil
		pcall(function()
			gs.RotationType = Enum.RotationType.MovementRelative
		end)
	end
	return true
end

-- Marco 10.29: a sensibilidade muda aos poucos ao mirar/desmirar (antes pulava de uma vez)
local sensNow = 1
local function setSensitivity(scale, dt)
	if math.abs(sensNow - scale) < 0.005 then
		sensNow = scale
	else
		sensNow += (scale - sensNow) * math.min(1, (dt or 1 / 60) * 12)
	end
	if sensNow ~= 1 or sensSet then
		pcall(function()
			UserInputService.MouseDeltaSensitivity = sensNow
		end)
		sensSet = sensNow ~= 1
	end
end

local function stopAim(humanoid)
	if active then
		active = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
	setCameraRelative(false)
	-- Marco 10.30: furando o cofre, quem vira o boneco é o FerramentasController (de frente pra porta)
	if humanoid and humanoid.Parent and not humanoid.Parent:GetAttribute("Perfurando") then
		humanoid.AutoRotate = true
	end
	if crosshair then
		crosshair.Visible = false
	end
end

-- o que a câmera deveria estar fazendo agora (mira travada no PC ou mirando com arma)
local function canAim(humanoid, root, camera)
	return humanoid and root and camera
		and humanoid.Health > 0
		and not humanoid.Sit and not humanoid.SeatPart
		and humanoid:GetState() ~= Enum.HumanoidStateType.Swimming
		and humanoid:GetState() ~= Enum.HumanoidStateType.Climbing
		and camera.CameraType == Enum.CameraType.Custom
		and camera.CameraSubject == humanoid
		and not uiOpen
		and not GuiService.MenuIsOpen
		and not UserInputService:GetFocusedTextBox()
		and not root.Anchored
		and not root.Parent:GetAttribute("Perfurando") -- Marco 10.30: furando o cofre (mouse solto)
end

local shoulderParams = RaycastParams.new()
shoulderParams.FilterType = Enum.RaycastFilterType.Exclude
shoulderParams.IgnoreWater = true
shoulderParams.RespectCanCollide = true -- caixas invisíveis (zonas) não empurram a câmera

local function approach(current, target, dt, speed)
	return current + (target - current) * math.min(1, dt * speed)
end

local function step(dt)
	dt = dt or 1 / 60
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if lastHumanoid and lastHumanoid ~= humanoid then
		active = false
		offsetNow = Vector3.zero
	end
	lastHumanoid = humanoid
	local camera = Workspace.CurrentCamera
	local allowed = canAim(humanoid, root, camera)
	-- Marco 10.20: no celular, com arma na mão, a mira fica sempre no meio da tela (modo combate:
	-- o boneco vira junto com a câmera e o tiro sai na bolinha). Atira pelo botão "Atirar".
	local touchCombat = isTouchOnly() and weaponUse == "gun"
	local lock = allowed and (wantsAimLock() or touchCombat) and not UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) and not Players.LocalPlayer:GetAttribute("MochilaAberta") -- Marco 10.26: mochila aberta solta o mouse
	local ads = allowed and adsOn and weaponUse == "gun"
	centered = lock or ads
	-- câmera/ombro/zoom (suave), também saindo da mira
	local wantOffset = Vector3.zero
	if ads then
		wantOffset = CAM.AimShoulder or CAM.Shoulder
	elseif lock then
		wantOffset = CAM.Shoulder
	end
	offsetNow = offsetNow:Lerp(wantOffset, math.min(1, dt * 10))
	-- Marco 10.12b: o ombro NÃO usa mais o Humanoid.CameraOffset (ele gira junto com o boneco, que
	-- vira um passo de física depois da câmera: dava aquele "travadinho"). Agora a câmera é que anda
	-- para o lado, no espaço dela, depois do Roblox posicionar (igual o shift lock do próprio Roblox).
	if humanoid and humanoid.Parent and humanoid.CameraOffset ~= Vector3.zero then
		humanoid.CameraOffset = Vector3.zero
	end
	if camera then
		fovBase = fovBase or camera.FieldOfView
		local wantFov = ads and ((weaponKind == "pistola") and (CAM.AimFovPistol or 55) or (CAM.AimFovRifle or 45)) or fovBase
		if math.abs(camera.FieldOfView - wantFov) > 0.05 then
			camera.FieldOfView = approach(camera.FieldOfView, wantFov, dt, 12)
		end
	end
	setSensitivity(ads and (CAM.AimSensitivity or 0.6) or 1, dt)
	if not centered then
		stopAim(humanoid)
	else
		active = lock
		if lock then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
			UserInputService.MouseIconEnabled = false
		else
			if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			end
			UserInputService.MouseIconEnabled = true
		end
		if setCameraRelative(true) then
			humanoid.AutoRotate = true
		else
			-- sem acesso ao jeito do Roblox: vira o boneco nós mesmos, suave
			humanoid.AutoRotate = false
			local look = camera.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			if flat.Magnitude > 0.01 then
				local pos = root.Position
				local want = CFrame.lookAt(pos, pos + flat.Unit)
				root.CFrame = root.CFrame:Lerp(want, math.min(1, dt * 25))
			end
		end
		-- mira só com algo de mirar na mão
		crosshair.Visible = weaponUse ~= nil
		if crossRing then
			local size = ads and 12 or 18
			crossRing.Size = crossRing.Size:Lerp(UDim2.fromOffset(size, size), math.min(1, dt * 14))
		end
	end
	-- ombro no espaço da câmera, sem atravessar parede
	-- Marco 10.29: chega perto da parede na hora (não atravessa), mas volta para o ombro devagar,
	-- então passar perto de poste, árvore ou porta não dá mais aquele pulo da câmera
	if camera and offsetNow.Magnitude > 0.01 and character then
		local cf = camera.CFrame
		local want = cf * CFrame.new(offsetNow)
		local delta = want.Position - cf.Position
		local len = delta.Magnitude
		shoulderParams.FilterDescendantsInstances = { character }
		local hit = Workspace:Raycast(cf.Position, delta + delta.Unit * 0.4, shoulderParams)
		local free = 1
		if hit and len > 0.01 then
			free = math.clamp(((hit.Position - cf.Position).Magnitude - 0.4) / len, 0, 1)
		end
		if free < shoulderFree then
			shoulderFree = free
		else
			shoulderFree = approach(shoulderFree, free, dt, 6)
		end
		camera.CFrame = CFrame.new(cf.Position + delta * shoulderFree) * cf.Rotation
	else
		shoulderFree = 1
	end
	-- recuo: tranco para cima que volta sozinho (só na imagem: a câmera do Roblox refaz a cada quadro)
	-- recuo (Marco 10.12b): a câmera do Roblox guarda o giro, então o tranco entra UMA vez e depois
	-- volta aos pouquinhos (antes ele era somado todo quadro e subia demais)
	if camera and (recoil > 0.001 or recoilBack > 0.001) then
		local up = recoil
		recoil = 0
		local down = math.min(recoilBack, recoilBack * dt * 9 + dt * 0.5)
		recoilBack -= down
		camera.CFrame = camera.CFrame * CFrame.Angles(math.rad(up - down), 0, 0)
	end
end

-- Marco 10.12: o WeaponController avisa o que está na mão e se está mirando
function CameraController.setWeapon(use, kind)
	weaponUse = use
	weaponKind = kind
	if use ~= "gun" then
		adsOn = false
	end
end

function CameraController.setAiming(on)
	adsOn = on == true and weaponUse == "gun"
end

function CameraController.isAiming()
	return adsOn and centered
end

-- o tiro sai do meio da tela?
function CameraController.isCentered()
	return centered
end

function CameraController.kick(degrees)
	local d = degrees or 1
	recoil += d
	recoilBack = math.min(recoilBack + d * 0.85, 8) -- volta quase tudo (sobra um pouquinho, como de verdade)
end

---------------------------------------------------------------------------
-- Interface: mira no meio da tela
---------------------------------------------------------------------------

local function buildCrosshair()
	crosshair = Instance.new("Frame")
	crosshair.Name = "Mira"
	crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
	crosshair.Position = UDim2.fromScale(0.5, 0.5)
	crosshair.Size = UDim2.fromOffset(22, 22)
	crosshair.BackgroundTransparency = 1
	crosshair.Visible = false
	crosshair.Parent = gui
	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(4, 4)
	dot.BackgroundColor3 = Color3.new(1, 1, 1)
	dot.BorderSizePixel = 0
	dot.Parent = crosshair
	corner(dot, 2)
	local st = Instance.new("UIStroke")
	st.Color = Color3.new(0, 0, 0)
	st.Transparency = 0.4
	st.Parent = dot
	local ring = Instance.new("Frame")
	crossRing = ring
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromOffset(18, 18)
	ring.BackgroundTransparency = 1
	ring.Parent = crosshair
	corner(ring, 9)
	local rs = Instance.new("UIStroke")
	rs.Color = Color3.new(1, 1, 1)
	rs.Transparency = 0.55
	rs.Thickness = 1.5
	rs.Parent = ring
end

---------------------------------------------------------------------------
-- Marco 10.29: seletor da mira (sem o botão ⚙). Uma pílula pequena no topo, à direita da casinha,
-- com os dois modos lado a lado: "Travada" (aim-lock) e "Padrão" (a câmera normal do Roblox).
-- Clique num lado (ou aperte L) e a faixa desliza até ele; a escolha vale na hora e fica salva.
-- Só aparece no PC/controle: no celular a câmera já é por toque.
---------------------------------------------------------------------------

local TweenService = game:GetService("TweenService")

local selector -- a pílula
local highlight -- a faixa colorida que desliza
local segments = {} -- segments.lock / segments.free = { button, icon, label }
local toast -- aviso curto embaixo da pílula
local toastToken = 0

local PILL_W, PILL_H = 188, 32
local SEG_W = PILL_W / 2
local COLOR_LOCK = Color3.fromRGB(46, 160, 100)
local COLOR_FREE = Color3.fromRGB(70, 110, 190)
local FAST = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function showToast(text)
	if not toast then
		return
	end
	toastToken += 1
	local token = toastToken
	toast.Text = text
	toast.Visible = true
	toast.TextTransparency = 1
	toast.BackgroundTransparency = 1
	TweenService:Create(toast, FAST, { TextTransparency = 0, BackgroundTransparency = 0.35 }):Play()
	task.delay(1.6, function()
		if token == toastToken and toast then
			local out = TweenService:Create(toast, TweenInfo.new(0.35), { TextTransparency = 1, BackgroundTransparency = 1 })
			out:Play()
			out.Completed:Connect(function()
				if token == toastToken then
					toast.Visible = false
				end
			end)
		end
	end)
end

local function refreshToggle(animate)
	if not selector then
		return
	end
	local lock = wantsAimLock()
	local goal = {
		Position = UDim2.fromOffset(lock and 3 or SEG_W + 1, 3),
		BackgroundColor3 = lock and COLOR_LOCK or COLOR_FREE,
	}
	if animate then
		TweenService:Create(highlight, FAST, goal):Play()
	else
		highlight.Position = goal.Position
		highlight.BackgroundColor3 = goal.BackgroundColor3
	end
	for key, seg in pairs(segments) do
		local on = (key == "lock") == lock
		local color = on and Color3.new(1, 1, 1) or Color3.fromRGB(175, 185, 205)
		if animate then
			TweenService:Create(seg.label, FAST, { TextColor3 = color }):Play()
		else
			seg.label.TextColor3 = color
		end
	end
end

local function setMode(lock, fromKey)
	if wantsAimLock() == lock then
		if fromKey then
			showToast(lock and "🎯 Mira travada" or "🖱️ Câmera padrão")
		end
		return
	end
	player:SetAttribute("CamLivre", not lock) -- já vale agora; o servidor guarda
	settingsRequest:FireServer("freeCam", not lock)
	refreshToggle(true)
	showToast(lock and "🎯 Mira travada: o boneco vira para onde você olha" or "🖱️ Câmera padrão: segure o botão direito para girar")
end

local function makeSegment(key, x, icon, text)
	local b = Instance.new("TextButton")
	b.Name = key == "lock" and "ModoTravada" or "ModoPadrao"
	b.BackgroundTransparency = 1
	b.Position = UDim2.fromOffset(x, 0)
	b.Size = UDim2.fromOffset(SEG_W, PILL_H)
	b.Text = ""
	b.AutoButtonColor = false
	b.ZIndex = 3
	b:SetAttribute("HudFixo", true) -- não solta o mouse só por existir
	b.Parent = selector
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.Text = icon .. "  " .. text
	label.TextColor3 = Color3.fromRGB(175, 185, 205)
	label.ZIndex = 4
	label.Parent = b
	local scale = Instance.new("UIScale")
	scale.Parent = label
	b.MouseEnter:Connect(function()
		TweenService:Create(scale, FAST, { Scale = 1.06 }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(scale, FAST, { Scale = 1 }):Play()
	end)
	b.MouseButton1Down:Connect(function()
		TweenService:Create(scale, FAST, { Scale = 0.94 }):Play()
	end)
	b.Activated:Connect(function()
		TweenService:Create(scale, FAST, { Scale = 1 }):Play()
		setMode(key == "lock")
	end)
	segments[key] = { button = b, label = label }
end

local function buildSettings()
	-- tecla L troca o modo (PC); funciona mesmo sem a pílula na tela
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.L and not UserInputService:GetFocusedTextBox() and not isTouchOnly() then
			setMode(not wantsAimLock(), true)
		end
	end)
	player:GetAttributeChangedSignal("CamLivre"):Connect(function()
		refreshToggle(true)
	end)

	local topbar = GuiService:GetGuiInset().Y
	local top = math.max(4, (topbar - 40) / 2) + (40 - PILL_H) / 2 -- alinhada com a casinha (40 px)

	selector = Instance.new("Frame")
	selector.Name = "SeletorMira"
	selector.AnchorPoint = Vector2.new(0, 0)
	selector.Position = UDim2.new(0.5, 6, 0, top) -- a casinha fica em (0.5, -25), 40 px de largura
	selector.Size = UDim2.fromOffset(PILL_W, PILL_H)
	selector.BackgroundColor3 = Color3.new(0, 0, 0)
	selector.BackgroundTransparency = 0.4
	selector.Parent = gui
	corner(selector, PILL_H / 2)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Transparency = 0.85
	stroke.Parent = selector
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = selector
	local function fit()
		local camera = Workspace.CurrentCamera
		local vp = camera and camera.ViewportSize or Vector2.new(1280, 720)
		uiScale.Scale = math.clamp(math.min(vp.X, vp.Y) / 720, 0.75, 1)
	end
	fit()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end

	highlight = Instance.new("Frame")
	highlight.Name = "Faixa"
	highlight.Size = UDim2.fromOffset(SEG_W - 4, PILL_H - 6)
	highlight.BackgroundColor3 = COLOR_LOCK
	highlight.ZIndex = 2
	highlight.Parent = selector
	corner(highlight, (PILL_H - 6) / 2)

	makeSegment("lock", 0, "🎯", "Travada")
	makeSegment("free", SEG_W, "🖱️", "Padrão")

	local key = Instance.new("TextLabel")
	key.Name = "TeclaL"
	key.BackgroundTransparency = 1
	key.AnchorPoint = Vector2.new(0, 0.5)
	key.Position = UDim2.new(1, 6, 0.5, 0)
	key.Size = UDim2.fromOffset(16, 16)
	key.Font = Enum.Font.GothamBlack
	key.TextSize = 11
	key.TextColor3 = Color3.fromRGB(255, 230, 150)
	key.TextStrokeTransparency = 0.4
	key.Text = "L"
	key.Parent = selector

	toast = Instance.new("TextLabel")
	toast.Name = "AvisoMira"
	toast.AnchorPoint = Vector2.new(0.5, 0)
	toast.Position = UDim2.new(0.5, 0, 0, top + PILL_H + 10)
	toast.AutomaticSize = Enum.AutomaticSize.X
	toast.Size = UDim2.fromOffset(0, 26)
	toast.BackgroundColor3 = Color3.new(0, 0, 0)
	toast.BackgroundTransparency = 1
	toast.Font = Enum.Font.GothamBold
	toast.TextSize = 14
	toast.TextColor3 = Color3.new(1, 1, 1)
	toast.TextTransparency = 1
	toast.Visible = false
	toast.Parent = gui
	corner(toast, 13)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = toast

	-- no celular (só toque) a pílula some: lá a câmera é por toque e a mira centraliza com arma na mão
	local function platform()
		selector.Visible = not isTouchOnly()
	end
	platform()
	UserInputService.LastInputTypeChanged:Connect(platform)
	refreshToggle(false)
end

function CameraController.init()
	settingsRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(GameConfig.Remotes.SettingsRequest)
	gui = Instance.new("ScreenGui")
	gui.Name = "CameraUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 4
	gui.Parent = player:WaitForChild("PlayerGui")
	buildCrosshair()
	buildSettings()
	-- Marco 10.29: conferido a cada 0,15 s, mas só pelos ramos visíveis (bem mais leve que antes)
	task.spawn(function()
		while true do
			local ok, busy = pcall(screenBusy)
			uiOpen = ok and busy or false
			task.wait(0.15)
		end
	end)
	RunService:BindToRenderStep("LittleLifeAimLock", Enum.RenderPriority.Camera.Value + 1, step)
end

return CameraController
