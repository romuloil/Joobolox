-- FireController (ModuleScript)
-- Caminho: StarterPlayer > StarterPlayerScripts > Controllers > FireController
-- Marco 10.16: o fogo do incêndio da equipe (FireService) é desenhado no cliente para TODO MUNDO
-- (Marco 10.16b: o Luís quer que todos vejam). A faixinha do incêndio é só para bombeiros. Lê os atributos de Workspace.Incendios.Incendio:
-- Estado ("fogo", "apagado", "queimou"), Spot1..5 / Size1..5, Hp / MaxHp, Deadline, Crew, Endereco.
-- Também mostra a faixinha do incêndio (força do fogo, tempo para queimar e quantos bombeiros).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local UIScaler = require(script.Parent:WaitForChild("UIScaler"))

local FireController = {}

local JOB = "Bombeiro"
local player = Players.LocalPlayer

local drawn = {} -- [obj] = { parts = { {part, fire, smoke, light, base} }, estado }
local localFolder
local banner, bannerText, bannerFill

local function isFirefighter()
	return player:GetAttribute("Job") == JOB
end

local function flame(position, size)
	local p = Instance.new("Part")
	p.Name = "Chama"
	p.Size = Vector3.new(size, 1, size)
	p.CFrame = CFrame.new(position)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Parent = localFolder
	local fire = Instance.new("Fire")
	fire.Size = size * 1.6
	fire.Heat = 12
	fire.Color = Color3.fromRGB(255, 120, 30)
	fire.SecondaryColor = Color3.fromRGB(255, 220, 80)
	fire.Parent = p
	local smoke = Instance.new("Smoke")
	smoke.Color = Color3.fromRGB(60, 60, 60)
	smoke.Opacity = 0.35
	smoke.RiseVelocity = 8
	smoke.Size = size * 1.4
	smoke.Parent = p
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 140, 50)
	light.Range = 22
	light.Brightness = 2
	light.Parent = p
	return { part = p, fire = fire, smoke = smoke, light = light, base = size }
end

local function undraw(obj)
	local d = drawn[obj]
	drawn[obj] = nil
	if d then
		for _, f in ipairs(d.parts) do
			f.part:Destroy()
		end
	end
end

local function draw(obj)
	local d = { parts = {} }
	for n = 1, 8 do
		local pos = obj:GetAttribute("Spot" .. n)
		if typeof(pos) ~= "Vector3" then
			break
		end
		table.insert(d.parts, flame(pos, obj:GetAttribute("Size" .. n) or 4))
	end
	drawn[obj] = d
	return d
end

local function update(obj, d)
	local estado = obj:GetAttribute("Estado")
	local hp = obj:GetAttribute("Hp") or 50
	local max = math.max(1, obj:GetAttribute("MaxHp") or 100)
	local k = math.clamp(hp / max, 0, 1)
	if estado == "apagado" then
		if d.estado ~= estado then
			for _, f in ipairs(d.parts) do
				f.fire.Enabled = false
				f.light.Enabled = false
				f.smoke.Color = Color3.fromRGB(215, 215, 215) -- vapor branco
				f.smoke.Opacity = 0.2
				local water = Instance.new("ParticleEmitter")
				water.Color = ColorSequence.new(Color3.fromRGB(150, 200, 255))
				water.Size = NumberSequence.new(0.6, 1.4)
				water.Transparency = NumberSequence.new(0.2, 1)
				water.Lifetime = NumberRange.new(0.6, 1)
				water.Speed = NumberRange.new(4, 8)
				water.SpreadAngle = Vector2.new(50, 50)
				water.Rate = 40
				water.Parent = f.part
				task.delay(2, function()
					water.Enabled = false
				end)
			end
		end
	elseif estado == "queimou" then
		if d.estado ~= estado then
			for _, f in ipairs(d.parts) do
				f.fire.Size = f.base * 2.4
				f.smoke.Color = Color3.fromRGB(25, 25, 25) -- fumaça preta
				f.smoke.Opacity = 0.7
				f.smoke.Size = f.base * 3
			end
		end
	else
		-- a chama acompanha a força do fogo
		for _, f in ipairs(d.parts) do
			f.fire.Size = f.base * (0.6 + 1.4 * k)
			f.fire.Heat = 6 + 10 * k
			f.light.Brightness = 0.8 + 2 * k
			f.smoke.Opacity = 0.15 + 0.35 * k
		end
	end
	d.estado = estado
end

local function buildBanner()
	local gui = Instance.new("ScreenGui")
	gui.Name = "IncendioUI"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")
	banner = Instance.new("Frame")
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 82)
	banner.Size = UDim2.fromOffset(330, 38)
	banner.BackgroundColor3 = Color3.fromRGB(40, 12, 10)
	banner.BackgroundTransparency = 0.15
	banner.Visible = false
	banner.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = banner
	UIScaler.attach(banner)
	bannerText = Instance.new("TextLabel")
	bannerText.BackgroundTransparency = 1
	bannerText.Position = UDim2.fromOffset(8, 2)
	bannerText.Size = UDim2.new(1, -16, 0, 22)
	bannerText.Font = Enum.Font.GothamBold
	bannerText.TextSize = 13
	bannerText.TextColor3 = Color3.new(1, 1, 1)
	bannerText.Parent = banner
	local back = Instance.new("Frame")
	back.Position = UDim2.new(0, 10, 0, 26)
	back.Size = UDim2.new(1, -20, 0, 6)
	back.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	back.BorderSizePixel = 0
	back.Parent = banner
	bannerFill = Instance.new("Frame")
	bannerFill.Size = UDim2.fromScale(0.5, 1)
	bannerFill.BackgroundColor3 = Color3.fromRGB(255, 120, 30)
	bannerFill.BorderSizePixel = 0
	bannerFill.Parent = back
end

local function step()
	local folder = Workspace:FindFirstChild("Incendios")
	local show = true -- todo mundo vê o fogo
	local active
	if folder then
		for _, obj in ipairs(folder:GetChildren()) do
			if obj.Name == "Incendio" then
				if show then
					local d = drawn[obj] or draw(obj)
					update(obj, d)
					if obj:GetAttribute("Estado") == "fogo" then
						active = obj
					end
				elseif drawn[obj] then
					undraw(obj)
				end
			end
		end
	end
	for obj in pairs(drawn) do
		if not obj.Parent then
			undraw(obj)
		end
	end
	if not isFirefighter() then
		active = nil -- a faixinha (força/tempo) é só para os bombeiros
	end
	banner.Visible = active ~= nil
	if active then
		local hp = active:GetAttribute("Hp") or 0
		local max = math.max(1, active:GetAttribute("MaxHp") or 100)
		local left = math.max(0, math.floor((active:GetAttribute("Deadline") or 0) - Workspace:GetServerTimeNow()))
		bannerText.Text = ("🔥 Fogo %d%% · queima em %d:%02d · 🚒 %d bombeiro(s)"):format(math.ceil(hp / max * 100), left // 60, left % 60, active:GetAttribute("Crew") or 0)
		bannerFill.Size = UDim2.fromScale(math.clamp(hp / max, 0, 1), 1)
		bannerText.TextColor3 = left <= 30 and Color3.fromRGB(255, 120, 110) or Color3.new(1, 1, 1)
	end
end

function FireController.init()
	localFolder = Instance.new("Folder")
	localFolder.Name = "FogoLocal"
	localFolder.Parent = Workspace
	buildBanner()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.25 then
			acc = 0
			step()
		end
	end)
end

return FireController
