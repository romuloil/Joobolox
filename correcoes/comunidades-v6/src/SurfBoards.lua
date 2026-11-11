-- SurfBoards (ModuleScript)
-- Caminho: ServerScriptService > Services > SurfBoards
-- Marco 10.32: pranchas de surfe feitas de peças (4 modelos x várias cores). Se existir o modelo 3D em
-- ServerStorage > SurfModels > Prancha (Prancha.glb do Luís), ele é usado no lugar: no tamanho de cada
-- modelo e pintado com as cores da paleta (Corpo = cor 1, Pad = cor 2, Logo = cor 3).
-- A prancha fica centrada no zero, com o bico para -Z e o deck (em cima) para +Y.

local ServerStorage = game:GetService("ServerStorage")

local SurfBoards = {}

SurfBoards.STYLES = {
	{ id = "long", name = "Longboard", length = 9.2, width = 2.1, nose = "round", tail = "square" },
	{ id = "fun", name = "Funboard", length = 7.4, width = 2, nose = "round", tail = "round" },
	{ id = "short", name = "Pranchinha", length = 6.1, width = 1.65, nose = "point", tail = "square" },
	{ id = "fish", name = "Fish", length = 5.6, width = 1.95, nose = "point", tail = "swallow" },
}

SurfBoards.PALETTES = {
	{ Color3.fromRGB(250, 250, 245), Color3.fromRGB(230, 70, 60), Color3.fromRGB(40, 110, 200) },
	{ Color3.fromRGB(255, 205, 60), Color3.fromRGB(30, 30, 34), Color3.fromRGB(255, 255, 255) },
	{ Color3.fromRGB(70, 200, 210), Color3.fromRGB(255, 255, 255), Color3.fromRGB(250, 120, 60) },
	{ Color3.fromRGB(240, 110, 160), Color3.fromRGB(255, 230, 120), Color3.fromRGB(120, 60, 160) },
	{ Color3.fromRGB(30, 34, 44), Color3.fromRGB(60, 220, 120), Color3.fromRGB(240, 240, 240) },
	{ Color3.fromRGB(255, 140, 40), Color3.fromRGB(250, 250, 240), Color3.fromRGB(40, 60, 120) },
	{ Color3.fromRGB(140, 210, 120), Color3.fromRGB(30, 120, 80), Color3.fromRGB(255, 240, 200) },
	{ Color3.fromRGB(60, 90, 200), Color3.fromRGB(255, 220, 60), Color3.fromRGB(255, 255, 255) },
	{ Color3.fromRGB(200, 40, 50), Color3.fromRGB(20, 20, 24), Color3.fromRGB(240, 240, 240) },
	{ Color3.fromRGB(240, 235, 220), Color3.fromRGB(150, 110, 70), Color3.fromRGB(70, 160, 200) },
}

local function part(model, name, size, cf, color, shape, class)
	local p = Instance.new(class or "Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = true
	p.Anchored = true
	p.Parent = model
	return p
end

-- disco achatado (bico/rabeta redondos)
local function disc(model, name, diameter, thick, cf, color)
	return part(model, name, Vector3.new(thick, diameter, diameter), cf * CFrame.Angles(0, 0, math.rad(90)), color, Enum.PartType.Cylinder)
end

-- ponta triangular vista de cima: duas cunhas deitadas (meia largura cada)
local function point(model, name, halfW, len, thick, cf, color)
	-- cunha deitada: triângulo no plano X-Z, alto na base (lado do corpo), fino na ponta
	part(model, name, Vector3.new(thick, halfW, len), cf * CFrame.new(halfW / 2, 0, 0) * CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(0, math.pi, 0), color, nil, "WedgePart")
	part(model, name, Vector3.new(thick, halfW, len), cf * CFrame.new(-halfW / 2, 0, 0) * CFrame.Angles(0, 0, math.rad(-90)) * CFrame.Angles(0, math.pi, 0), color, nil, "WedgePart")
end

-- cor de cada peça do modelo 3D (Prancha.glb: Corpo, Pad, Logo, Stringer, Quilhas)
local FIXED = {
	Stringer = Color3.fromRGB(176, 128, 80),
	Quilhas = Color3.fromRGB(28, 30, 34),
}
local function roleColor(name, palette, single)
	if single or name:find("Corpo") then
		return palette[1]
	elseif name:find("Pad") then
		return palette[2]
	elseif name:find("Logo") or name:find("Faixa") then
		return palette[3]
	end
	for key, color in pairs(FIXED) do
		if name:find(key) then
			return color
		end
	end
	return nil
end

-- Marco 10.32: prancha 3D do Luís (ServerStorage > SurfModels > Prancha, importada do Prancha.glb).
-- Funciona com o modelo virado de qualquer jeito: o lado mais comprido do Corpo vira o comprimento,
-- as quilhas mostram onde é a rabeta (+Z) e o fundo (-Y).
local function fromTemplate(style, palette)
	local folder = ServerStorage:FindFirstChild("SurfModels")
	local tpl = folder and folder:FindFirstChild("Prancha")
	if not tpl then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "Prancha"
	local copy = tpl:Clone()
	if copy:IsA("BasePart") then
		copy.Name = "Corpo"
		copy.Parent = model
	else
		for _, d in ipairs(copy:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Parent = model
			end
		end
		copy:Destroy()
	end
	local parts = {}
	local body, fins
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
			if d.Name:find("Corpo") or (not body and d.Name:find("Prancha")) then
				body = d
			elseif d.Name:find("Quilha") then
				fins = d
			end
		end
	end
	if #parts == 0 then
		model:Destroy()
		return nil
	end
	if not body then
		-- sem nome: a peça maior é o corpo
		for _, d in ipairs(parts) do
			if not body or d.Size.Magnitude > body.Size.Magnitude then
				body = d
			end
		end
	end
	for _, d in ipairs(parts) do
		d.Anchored = true
		d.CanCollide = false
		d.CanTouch = false
		d.CanQuery = false
		d.Massless = true
		for _, k in ipairs(d:GetChildren()) do
			if k:IsA("SurfaceAppearance") or k:IsA("Decal") or k:IsA("Texture") then
				k:Destroy()
			end
		end
		if d:IsA("MeshPart") then
			pcall(function()
				d.TextureID = ""
			end)
		end
		local color = roleColor(d.Name, palette, #parts == 1)
		if color then
			d.Color = color
		end
		d.Material = Enum.Material.SmoothPlastic
	end
	-- descobre os eixos do Corpo: comprido = comprimento, fino = espessura
	local cf, size = body.CFrame, body.Size
	local axes = { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis }
	local dims = { size.X, size.Y, size.Z }
	local long, thin = 1, 1
	for i = 2, 3 do
		if dims[i] > dims[long] then
			long = i
		end
		if dims[i] < dims[thin] then
			thin = i
		end
	end
	local tail, up = axes[long], axes[thin]
	if fins then
		local rel = cf:PointToObjectSpace(fins.Position)
		if rel:Dot(tail) < 0 then
			tail = -tail
		end
		if rel:Dot(up) > 0 then
			up = -up
		end
	end
	local right = up:Cross(tail)
	local frame = CFrame.fromMatrix(cf.Position, cf:VectorToWorldSpace(right), cf:VectorToWorldSpace(up), cf:VectorToWorldSpace(tail))
	-- (sem PrimaryPart ainda: com ela o Roblox ignora o WorldPivot)
	model.WorldPivot = frame
	model:PivotTo(CFrame.identity)
	-- tamanho de cada modelo (Longboard maior, Fish menor)
	if dims[long] > 0.1 then
		pcall(function()
			model:ScaleTo(style.length / dims[long])
		end)
	end
	model:PivotTo(CFrame.identity)
	model.PrimaryPart = body
	body.PivotOffset = body.CFrame:Inverse() -- o pivô do modelo continua no centro da prancha
	return model
end

-- style: índice ou tabela de STYLES; palette: índice ou tabela de PALETTES
function SurfBoards.build(styleIndex, paletteIndex)
	local style = SurfBoards.STYLES[styleIndex] or SurfBoards.STYLES[1]
	local palette = SurfBoards.PALETTES[paletteIndex] or SurfBoards.PALETTES[1]
	local tpl = fromTemplate(style, palette)
	if tpl then
		tpl:SetAttribute("Modelo", style.name)
		return tpl, style
	end
	local model = Instance.new("Model")
	model.Name = "Prancha"
	local L, W, T = style.length, style.width, 0.32
	local noseLen = style.nose == "point" and W * 0.9 or W / 2
	local tailLen = style.tail == "square" and 0.1 or W / 2.2
	local bodyLen = L - noseLen - tailLen
	local zMid = (tailLen - noseLen) / 2 -- centro do corpo (bico em -Z)
	local base = palette[1]
	local body = part(model, "Corpo", Vector3.new(W, T, bodyLen), CFrame.new(0, 0, zMid), base)
	model.PrimaryPart = body
	local zNose = zMid - bodyLen / 2
	local zTail = zMid + bodyLen / 2
	if style.nose == "round" then
		disc(model, "Bico", W, T, CFrame.new(0, 0, zNose), base)
	else
		point(model, "Bico", W / 2, noseLen, T, CFrame.new(0, 0, zNose - noseLen / 2), base)
	end
	if style.tail == "round" then
		disc(model, "Rabeta", W, T, CFrame.new(0, 0, zTail), base)
	elseif style.tail == "swallow" then
		-- rabeta de peixe: duas pontas com um corte no meio
		for _, sx in ipairs({ -1, 1 }) do
			part(model, "Rabeta", Vector3.new(W * 0.42, T, tailLen), CFrame.new(sx * W * 0.29, 0, zTail + tailLen / 2), base)
		end
	else
		part(model, "Rabeta", Vector3.new(W * 0.9, T, 0.3), CFrame.new(0, 0, zTail + 0.1), base)
	end
	-- faixas e longarina (decoração por cima)
	part(model, "Faixa", Vector3.new(W * 1.002, T + 0.02, 0.45), CFrame.new(0, 0, zMid - bodyLen * 0.18), palette[2])
	part(model, "Faixa", Vector3.new(W * 1.002, T + 0.02, 0.18), CFrame.new(0, 0, zMid - bodyLen * 0.18 + 0.42), palette[3])
	part(model, "Longarina", Vector3.new(0.06, T + 0.03, bodyLen + noseLen * 0.6), CFrame.new(0, 0, zMid - noseLen * 0.3), palette[3])
	-- deck (borracha) na rabeta e quilhas embaixo
	part(model, "Deck", Vector3.new(W * 0.7, 0.05, 1.3), CFrame.new(0, T / 2 + 0.02, zTail - 0.75), Color3.fromRGB(35, 35, 40))
	local fins = style.id == "long" and { 0 } or { -W * 0.3, 0, W * 0.3 }
	for _, fx in ipairs(fins) do
		local h = style.id == "long" and 0.75 or 0.5
		part(model, "Quilha", Vector3.new(0.08, h, 0.6), CFrame.new(fx, -T / 2 - h / 2, zTail - 0.4), palette[2], nil, "WedgePart")
	end
	model:SetAttribute("Modelo", style.name)
	return model, style
end

return SurfBoards
