-- WeaponController (ModuleScript)
-- Caminho: StarterPlayer > StarterPlayerScripts > Controllers > WeaponController
-- Marco 10.5: usar o que está na mão.
--   * Arma: clique (ou toque) atira onde você mira; nas automáticas, segure. R recarrega
--     (sem bala, recarrega sozinha). Munição aparece em cima dos atalhos.
--   * Taser e algema (Policial): clique em cima do suspeito (ou perto dele, na frente).
--   * Desenha os tiros de todo mundo (risquinho amarelo) e o choque do taser (azul).
-- O servidor (WeaponService / CrimeService) confere tudo.
-- Marco 10.12: MIRAR com zoom (botão direito do mouse, L2 no controle, botão "Mirar" no celular),
-- tiro sai do meio da tela quando a câmera está travada ou mirando, tranco de recuo na câmera,
-- e a pose da arma (WeaponPose) recebe para onde você está olhando.

local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local UIScaler = require(script.Parent:WaitForChild("UIScaler"))
local CameraController = require(script.Parent:WaitForChild("CameraController"))
local WeaponPose = require(script.Parent:WaitForChild("WeaponPose"))
local MobileButtons = require(script.Parent:WaitForChild("MobileButtons"))

local WeaponController = {}

local W = GameConfig.Weapons
local CR = GameConfig.Crime
local player = Players.LocalPlayer
local mouse = player:GetMouse()
local weaponRequest, crimeRequest
local gui, ammoLabel, hitLabel
local current -- Tool na mão
local holding = false
local AIM_ACTION = "LittleLifeMirar"
local aimHeld = false -- PC/controle: segurando o botão de mirar
local aimToggle = false -- celular: botão "Mirar" liga/desliga
local sent = { p = 999, a = false, t = 0 } -- último "Mira" mandado ao servidor
local surrenderLabel -- "Rendendo..." no meio da tela (atributo Rendendo, Marco 10.24)

local function effectsFolder()
	local f = Workspace:FindFirstChild("EfeitosTiro")
	if not f then
		f = Instance.new("Folder")
		f.Name = "EfeitosTiro"
		f.Parent = Workspace
	end
	return f
end

local function beam(from, to, color, width, life)
	local dist = (to - from).Magnitude
	if dist < 0.1 then
		return
	end
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = 0.25
	p.Size = Vector3.new(width, width, dist)
	p.CFrame = CFrame.lookAt((from + to) / 2, to)
	p.Parent = effectsFolder()
	Debris:AddItem(p, life)
end

local function zap(from, to)
	-- choque em zigue-zague
	local last = from
	for i = 1, 6 do
		local pt = from:Lerp(to, i / 6)
		if i < 6 then
			pt += Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 1.2
		end
		beam(last, pt, Color3.fromRGB(90, 180, 255), 0.12, 0.25)
		last = pt
	end
end

local function playShot(pos)
	if (W.ShotSoundId or 0) <= 0 then
		return
	end
	local a = Instance.new("Attachment")
	a.WorldPosition = pos
	a.Parent = Workspace.Terrain
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. W.ShotSoundId
	s.Volume = 0.3
	s.RollOffMaxDistance = 160
	s.Parent = a
	s:Play()
	Debris:AddItem(a, 3)
end

---------------------------------------------------------------------------
-- Mira e alvo
---------------------------------------------------------------------------

local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude

local function aimPoint()
	-- Marco 10.12: câmera travada ou mirando = o tiro vai para o meio da tela (onde está a mira)
	local camera = Workspace.CurrentCamera
	if CameraController.isCentered() and camera then
		local vp = camera.ViewportSize
		local ray = camera:ViewportPointToRay(vp.X / 2, vp.Y / 2)
		local ignore = { effectsFolder() }
		if player.Character then
			table.insert(ignore, player.Character)
		end
		aimParams.FilterDescendantsInstances = ignore
		local hit = Workspace:Raycast(ray.Origin, ray.Direction * (W.Range or 300), aimParams)
		return hit and hit.Position or (ray.Origin + ray.Direction * (W.Range or 300))
	end
	mouse.TargetFilter = player.Character -- Marco 10.24: o mouse em cima do próprio boneco não vira o alvo
	return mouse.Hit and mouse.Hit.Position
end

-- Jogador embaixo do mouse; senão o mais perto na frente (até "range")
local function targetPlayer(range)
	local t = mouse.Target
	local model = t and t:FindFirstAncestorOfClass("Model")
	while model do
		local p = Players:GetPlayerFromCharacter(model)
		if p and p ~= player then
			return p
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local best, bestD
	for _, p in ipairs(Players:GetPlayers()) do
		local r = p ~= player and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if r then
			local v = r.Position - root.Position
			local d = v.Magnitude
			if d <= range and (d < 6 or v.Unit:Dot(root.CFrame.LookVector) > 0.5) and (not bestD or d < bestD) then
				best, bestD = p, d
			end
		end
	end
	return best
end

---------------------------------------------------------------------------
-- Usar
---------------------------------------------------------------------------

local function updateAmmo()
	if not ammoLabel then
		return
	end
	local use = current and current:GetAttribute("Use")
	if use == "gun" then
		ammoLabel.Visible = true
		-- Marco 10.6: + a munição guardada (a arma do emprego tem à vontade)
		local spare = current:GetAttribute("Servico") and "∞" or tostring(player:GetAttribute("Municao_" .. (current:GetAttribute("AmmoKind") or "fuzil")) or 0)
		ammoLabel.Text = current:GetAttribute("Reloading") and "Recarregando..." or ("%s  %d/%d  +%s"):format(current.Name, current:GetAttribute("Ammo") or 0, current:GetAttribute("Mag") or 0, spare)
	elseif use == "taser" then
		ammoLabel.Visible = true
		ammoLabel.Text = "Taser: clique no procurado"
	elseif use == "algema" then
		ammoLabel.Visible = true
		ammoLabel.Text = player:GetAttribute("Escoltando") and "Algema: clique para soltar" or "Algema: atordoe com o taser e clique nele"
	else
		ammoLabel.Visible = false
	end
end

local function shootOnce(tool)
	if tool:GetAttribute("Reloading") then
		return
	end
	if (tool:GetAttribute("Ammo") or 0) <= 0 then
		weaponRequest:FireServer("Reload")
		return
	end
	local aim = aimPoint()
	if aim then
		weaponRequest:FireServer("Fire", aim)
		WeaponPose.shot(player.UserId)
		local kind = tool:GetAttribute("Kind") or (tool:GetAttribute("AmmoKind") == "pistola" and "pistola" or "fuzil")
		local rec = GameConfig.Camera.Recoil
		CameraController.kick(rec and rec[kind] or 0.8)
	end
end

local function onActivated(tool)
	local use = tool:GetAttribute("Use")
	if use == "gun" then
		holding = true
		local rate = tool:GetAttribute("Rate") or 0.3
		if tool:GetAttribute("Auto") then
			task.spawn(function()
				while holding and current == tool and tool.Parent == player.Character do
					shootOnce(tool)
					task.wait(rate)
				end
			end)
		else
			shootOnce(tool)
		end
	elseif use == "taser" then
		local target = targetPlayer(CR.TaserRange)
		if target then
			crimeRequest:FireServer("Taser", target)
		end
	elseif use == "algema" then
		if player:GetAttribute("Escoltando") then
			crimeRequest:FireServer("Cuff", player) -- o servidor entende como "soltar"
			return
		end
		local target = targetPlayer(CR.CuffRange)
		if target then
			crimeRequest:FireServer("Cuff", target)
		end
	end
end

local function setAimButton(on)
	if on then
		ContextActionService:BindAction(AIM_ACTION, function(_, state)
			aimHeld = state == Enum.UserInputState.Begin
			return Enum.ContextActionResult.Pass
		end, false, Enum.UserInputType.MouseButton2, Enum.KeyCode.ButtonL2)
		-- Marco 10.14: no celular o Mirar é o botão redondo ao lado do pulo (MobileButtons)
		-- Marco 10.20: no celular o toque na tela NÃO atira mais (girar a câmera disparava sem
		-- querer). Atira segurando o botão "Atirar" (colado no pulo); o tiro vai na bolinha do meio.
		MobileButtons.add("atirar", {
			icon = "🔥",
			title = "Atirar",
			slots = { 1 },
			hold = true,
			onPress = function(began)
				if began then
					if current and current:GetAttribute("Use") == "gun" then
						onActivated(current)
					end
				else
					holding = false
				end
			end,
		})
		MobileButtons.show("atirar", true)
		MobileButtons.add("mirar", {
			icon = "🎯",
			title = "Mirar",
			slots = { 2, 3 },
			onPress = function()
				aimToggle = not aimToggle
				MobileButtons.setActive("mirar", aimToggle)
				MobileButtons.setTitle("mirar", aimToggle and "Soltar" or "Mirar")
			end,
		})
		MobileButtons.show("mirar", true)
	else
		ContextActionService:UnbindAction(AIM_ACTION)
		aimHeld, aimToggle = false, false
		MobileButtons.show("mirar", false)
		MobileButtons.show("atirar", false)
		MobileButtons.setActive("mirar", false)
		MobileButtons.setTitle("mirar", "Mirar")
	end
end

local function watchTool(tool)
	current = tool
	holding = false
	local use = tool:GetAttribute("Use")
	if use == "gun" then
		mouse.Icon = "rbxasset://textures/GunCursor.png"
		if MobileButtons.enabled then
			tool.ManualActivationOnly = true -- celular: só o botão Atirar dispara
		end
		setAimButton(true)
	end
	-- Marco 10.30: perfuratriz e C4 não são de mirar (sem a bolinha da mira)
	local aimUse = (use == "gun" or use == "taser" or use == "algema") and use or nil
	CameraController.setWeapon(aimUse, tool:GetAttribute("Kind") or (tool:GetAttribute("AmmoKind") == "pistola" and "pistola" or "fuzil"))
	local conns = {}
	table.insert(conns, tool.Activated:Connect(function()
		onActivated(tool)
	end))
	table.insert(conns, tool.Deactivated:Connect(function()
		holding = false
	end))
	table.insert(conns, tool.AttributeChanged:Connect(updateAmmo))
	table.insert(conns, tool.AncestryChanged:Connect(function()
		if tool.Parent ~= player.Character then
			for _, c in ipairs(conns) do
				c:Disconnect()
			end
			if current == tool then
				current = nil
				holding = false
				mouse.Icon = ""
				setAimButton(false)
				CameraController.setWeapon(nil)
				CameraController.setAiming(false)
				updateAmmo()
			end
		end
	end))
	updateAmmo()
end

function WeaponController.handle(kind, data)
	if kind == "Shot" then
		WeaponPose.shot(data.by)
		if typeof(data.from) == "Vector3" and typeof(data.to) == "Vector3" then
			beam(data.from, data.to, Color3.fromRGB(255, 220, 120), 0.08, 0.07)
			playShot(data.from)
		end
	elseif kind == "HitMark" then
		if hitLabel then
			hitLabel.Text = "✕ " .. tostring(data.dmg or "")
			hitLabel.Visible = true
			task.delay(0.25, function()
				hitLabel.Visible = false
			end)
		end
	elseif kind == "CrimeZap" then
		if typeof(data.from) == "Vector3" and typeof(data.to) == "Vector3" then
			zap(data.from, data.to)
		end
	end
end

function WeaponController.init()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	weaponRequest = remotes:WaitForChild(GameConfig.Remotes.WeaponRequest)
	crimeRequest = remotes:WaitForChild(GameConfig.Remotes.CrimeRequest)

	gui = Instance.new("ScreenGui")
	gui.Name = "WeaponUI"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")
	ammoLabel = Instance.new("TextLabel")
	ammoLabel.AnchorPoint = Vector2.new(0.5, 1)
	ammoLabel.Position = UDim2.new(0.5, 0, 1, -142)
	ammoLabel.Size = UDim2.fromOffset(260, 28)
	ammoLabel.BackgroundColor3 = Color3.fromRGB(24, 32, 58)
	ammoLabel.BackgroundTransparency = 0.2
	ammoLabel.Font = Enum.Font.GothamBlack
	ammoLabel.TextScaled = true
	ammoLabel.TextColor3 = Color3.fromRGB(255, 220, 120)
	ammoLabel.Visible = false
	ammoLabel.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = ammoLabel
	UIScaler.attach(ammoLabel)
	hitLabel = Instance.new("TextLabel")
	hitLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	hitLabel.Position = UDim2.fromScale(0.5, 0.42)
	hitLabel.Size = UDim2.fromOffset(80, 30)
	hitLabel.BackgroundTransparency = 1
	hitLabel.Font = Enum.Font.GothamBlack
	hitLabel.TextScaled = true
	hitLabel.TextColor3 = Color3.fromRGB(255, 70, 70)
	hitLabel.Visible = false
	hitLabel.Parent = gui
	surrenderLabel = Instance.new("TextLabel")
	surrenderLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	surrenderLabel.Position = UDim2.fromScale(0.5, 0.6)
	surrenderLabel.Size = UDim2.fromOffset(300, 30)
	surrenderLabel.BackgroundTransparency = 1
	surrenderLabel.Font = Enum.Font.GothamBlack
	surrenderLabel.TextSize = 22
	surrenderLabel.TextColor3 = Color3.fromRGB(255, 220, 120)
	surrenderLabel.TextStrokeTransparency = 0.3
	surrenderLabel.Visible = false
	surrenderLabel.Parent = gui
	player:GetAttributeChangedSignal("Rendendo"):Connect(function()
		local pct = player:GetAttribute("Rendendo")
		surrenderLabel.Visible = pct ~= nil
		surrenderLabel.Text = pct and ("🔫 Rendendo... %d%%"):format(pct) or ""
	end)

	local function watchCharacter(character)
		character.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then
				watchTool(child)
			end
		end)
	end
	if player.Character then
		watchCharacter(player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)
	player:GetAttributeChangedSignal("Escoltando"):Connect(updateAmmo)
	player:GetAttributeChangedSignal("Municao_pistola"):Connect(updateAmmo)
	player:GetAttributeChangedSignal("Municao_fuzil"):Connect(updateAmmo)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == Enum.KeyCode.R and current and current:GetAttribute("Use") == "gun" then
			weaponRequest:FireServer("Reload")
		end
	end)
	-- Marco 10.12: mirando + para onde olha (pose da arma; o servidor repassa para os outros)
	RunService.RenderStepped:Connect(function()
		local gun = current and current:GetAttribute("Use") == "gun"
		CameraController.setAiming(gun and (aimHeld or aimToggle))
		local camera = Workspace.CurrentCamera
		local pitch = 0
		if camera then
			pitch = math.deg(math.asin(math.clamp(camera.CFrame.LookVector.Y, -1, 1)))
		end
		local aiming = gun and CameraController.isAiming() or false
		WeaponPose.setLocal(pitch, aiming)
		if not gun and not sent.a then
			return
		end
		local now = os.clock()
		if now - sent.t >= 0.12 then
			-- Marco 10.24: o servidor agora sabe para onde a arma mira (render NPC), não só o corpo
			-- (pelo raio da câmera/mouse: o ponto batido pode ser o próprio boneco ou o pet)
			local dir = gun and camera and (CameraController.isCentered() and camera.CFrame.LookVector or mouse.UnitRay.Direction) or nil
			if math.abs(pitch - sent.p) >= 2 or aiming ~= sent.a or (dir and (not sent.d or dir:Dot(sent.d) < 0.998)) then
				sent.t, sent.p, sent.a, sent.d = now, pitch, aiming, dir
				weaponRequest:FireServer("Mira", { p = pitch, a = aiming, d = dir })
			end
		end
	end)
end

return WeaponController
