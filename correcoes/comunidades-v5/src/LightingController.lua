-- LightingController (ModuleScript)
-- Caminho: StarterPlayer > StarterPlayerScripts > Controllers > LightingController
-- Marco 7.4: dentro das casas (os cômodos ficam longe da cidade, em X maior que 3500) o céu e o
-- sol são desligados só neste aparelho. Antes, depois de uns passos o motor de luz do Roblox
-- deixava as paredes "brancão", como se a luz do céu entrasse no cômodo fechado.
-- Saiu da casa, volta tudo como era.
-- Marco 7.5: enquanto está dentro, os valores são conferidos a cada quadro (se algo mudar a luz,
-- volta na hora), o brilho (Bloom) desliga e a exposição fica um pouco mais baixa. As lâmpadas
-- das casas também ficaram mais fracas (HomeService / FurnitureArt).

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LightingController = {}

-- Marco 9.14: prédios grandes (o quartel) marcam uma caixa invisível com o atributo "Indoor".
-- Dentro dela o céu não é desligado, só abaixado: o Luís achou o quartel "estourado" de tão claro.
local INTERIOR_X = 3500
local SOFT = {
	Brightness = 0.35, -- Marco 9.14: ainda mais fraco (o Luís achou o quartel um pouco estourado)
	OutdoorAmbient = Color3.fromRGB(55, 55, 60),
	EnvironmentDiffuseScale = 0.12,
	EnvironmentSpecularScale = 0.05,
	ExposureCompensation = -0.7,
}
local INSIDE = {
	Brightness = 0,
	OutdoorAmbient = Color3.fromRGB(0, 0, 0),
	EnvironmentDiffuseScale = 0,
	EnvironmentSpecularScale = 0,
	ExposureCompensation = -0.25,
}

-- Marco 10.6: luzes "piscando" quando a gente anda (vídeo do Luís). O motor de luz do Roblox só
-- desenha um tanto de luzes (PointLight, SpotLight, SurfaceLight) por pedaço da tela; com muitas
-- juntas (postes, saguões, mansões, apartamentos) ele escolhe sozinho quais aparecem e a escolha
-- muda a cada passo. Aqui, só neste aparelho, ficam acesas só as mais perto da câmera (sem passar
-- do limite) e as outras apagam de vez. Quem liga/desliga uma luz de verdade (interruptor, alarme)
-- é o servidor: ele marca o atributo "Off" na luz e isso é respeitado aqui.
local LIGHT_BUDGET = 14 -- luzes acesas ao mesmo tempo (as mais perto)
local LIGHT_RADIUS = 170 -- longe disso a luz nem aparece de dia
local LIGHT_KEEP = 10 -- folga para a luz acesa não ficar trocando com a vizinha
local lights = {} -- [Light] = true

local function trackLight(d)
	-- só as luzes da cidade e das casas (carro, personagem e pet ficam de fora)
	if d:IsA("Light") and not d:GetAttribute("SemLimite") then
		local map, rooms = Workspace:FindFirstChild("Map"), Workspace:FindFirstChild("Interiores")
		if (map and d:IsDescendantOf(map)) or (rooms and d:IsDescendantOf(rooms)) then
			lights[d] = true
		end
	end
end

local function lightPos(l)
	local p = l.Parent
	if p and p:IsA("BasePart") then
		return p.Position
	elseif p and p:IsA("Attachment") then
		return p.WorldPosition
	end
	return nil
end

local function cullLights(camPos)
	local list = {}
	for l in pairs(lights) do
		if not l:IsDescendantOf(Workspace) then
			lights[l] = nil -- Marco 10.22: saiu do aparelho (streaming) ou foi apagada
		elseif not l:GetAttribute("Off") then
			local pos = lightPos(l)
			if pos then
				local d = (pos - camPos).Magnitude - l.Range * 0.3
				if l.Enabled then
					d -= LIGHT_KEEP
				end
				if d < LIGHT_RADIUS then
					table.insert(list, { l, d })
				else
					l.Enabled = false
				end
			end
		elseif l.Enabled then
			l.Enabled = false
		end
	end
	table.sort(list, function(a, b)
		return a[2] < b[2]
	end)
	for i, e in ipairs(list) do
		local want = i <= LIGHT_BUDGET
		if e[1].Enabled ~= want then
			e[1].Enabled = want
		end
	end
end

local saved -- valores de fora, guardados ao entrar

local bloomWas

local function setInside(values)
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	if values then
		if not saved then
			saved = {}
			for k in pairs(INSIDE) do
				saved[k] = Lighting[k]
			end
			bloomWas = bloom and bloom.Enabled
		end
		for k, v in pairs(values) do
			if Lighting[k] ~= v then
				Lighting[k] = v
			end
		end
		if bloom and bloom.Enabled then
			bloom.Enabled = false
		end
	elseif saved then
		for k, v in pairs(saved) do
			Lighting[k] = v
		end
		if bloom and bloomWas ~= nil then
			bloom.Enabled = bloomWas
		end
		saved = nil
	end
end

-- caixas "Indoor" (o quartel): a câmera dentro de uma delas usa a luz mais fraca
local zones = {}

local function addZone(part)
	if part:IsA("BasePart") and part:GetAttribute("Indoor") then
		table.insert(zones, part)
	end
end

local function inZone(position)
	for i = #zones, 1, -1 do
		local part = zones[i]
		if not part.Parent then
			table.remove(zones, i)
		else
			local rel = part.CFrame:PointToObjectSpace(position)
			local half = part.Size / 2
			if math.abs(rel.X) < half.X and math.abs(rel.Y) < half.Y and math.abs(rel.Z) < half.Z then
				return true
			end
		end
	end
	return false
end

function LightingController.init()
	task.spawn(function()
		local map = Workspace:WaitForChild("Map")
		for _, d in ipairs(map:GetDescendants()) do
			addZone(d)
		end
		map.DescendantAdded:Connect(addZone)
	end)
	task.spawn(function()
		Workspace:WaitForChild("Map")
		for _, d in ipairs(Workspace:GetDescendants()) do
			trackLight(d)
		end
		Workspace.DescendantAdded:Connect(trackLight)
		while true do
			local cam = Workspace.CurrentCamera
			if cam then
				cullLights(cam.CFrame.Position)
			end
			task.wait(0.3)
		end
	end)
	RunService.Heartbeat:Connect(function()
		local cam = Workspace.CurrentCamera
		if cam then
			local pos = cam.CFrame.Position
			setInside(pos.X > INTERIOR_X and INSIDE or (inZone(pos) and SOFT or nil))
		end
	end)
end

return LightingController
