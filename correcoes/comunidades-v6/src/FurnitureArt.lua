-- FurnitureArt (ModuleScript)
-- Caminho: ReplicatedStorage > Shared > FurnitureArt
-- Marco 6: desenha os móveis da casa só com peças (sem modelos da loja).
-- Usado pelo servidor (móvel de verdade) e pelo cliente (prévia transparente no modo Decorar).
-- O móvel é montado com o centro do chão em (0, 0, 0) e a frente virada para -Z.
-- Marco 10.2: dá para sentar (assentos são Seat) e mexer (atributo Toggle: TV, Luz, Fogo),
-- ligados pelo PropService.

local FurnitureArt = {}

local WOOD = Color3.fromRGB(150, 100, 60)
local WOOD_DARK = Color3.fromRGB(95, 62, 38)
local WHITE = Color3.fromRGB(245, 245, 240)
local DARK = Color3.fromRGB(35, 35, 40)

local function part(model, name, size, x, y, z, color, extra)
	extra = extra or {}
	local p = Instance.new(extra.class or "Part")
	p.Name = name
	p.Size = size
	p.CFrame = CFrame.new(x, y, z) * (extra.rot or CFrame.new())
	p.Color = color
	p.Material = extra.material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = true
	p.CanCollide = extra.collide ~= false
	if extra.shape then
		p.Shape = extra.shape
	end
	p.Parent = model
	return p
end

local Builders = {}

-- Peça que liga e desliga (começa ligada)
local function toggle(p, kind, label)
	p:SetAttribute("Toggle", kind)
	p:SetAttribute("Label", label)
	p:SetAttribute("On", true)
	return p
end

local function seatOf(p, text)
	p:SetAttribute("SeatText", text)
	return p
end

function Builders.Cama(m)
	part(m, "Frame", Vector3.new(6, 1.4, 8), 0, 0.7, 0, WOOD)
	part(m, "Mattress", Vector3.new(5.6, 0.8, 7.4), 0, 1.8, 0.1, WHITE, { material = Enum.Material.Fabric })
	part(m, "Blanket", Vector3.new(5.7, 0.85, 4.6), 0, 1.85, -1.3, Color3.fromRGB(70, 120, 200), { material = Enum.Material.Fabric })
	part(m, "Pillow", Vector3.new(2.2, 0.5, 1.2), -1.3, 2.4, 2.9, WHITE, { material = Enum.Material.Fabric })
	part(m, "Pillow", Vector3.new(2.2, 0.5, 1.2), 1.3, 2.4, 2.9, WHITE, { material = Enum.Material.Fabric })
	part(m, "Headboard", Vector3.new(6, 4, 0.5), 0, 2, 3.8, WOOD_DARK)
end

function Builders.Sofa(m)
	local c = Color3.fromRGB(90, 110, 140)
	part(m, "Base", Vector3.new(8, 1.4, 3.4), 0, 0.9, 0, c, { material = Enum.Material.Fabric })
	part(m, "Back", Vector3.new(8, 2.2, 0.8), 0, 2.4, 1.3, c, { material = Enum.Material.Fabric })
	for _, x in ipairs({ -3.6, 3.6 }) do
		part(m, "Arm", Vector3.new(0.8, 1.2, 3.4), x, 2.1, 0, c, { material = Enum.Material.Fabric })
	end
	for _, x in ipairs({ -1.9, 1.9 }) do
		seatOf(part(m, "Cushion", Vector3.new(3.6, 0.4, 2.5), x, 1.8, -0.35, Color3.fromRGB(110, 130, 165), { material = Enum.Material.Fabric, class = "Seat" }), "Sofá")
	end
	part(m, "Feet", Vector3.new(7.6, 0.2, 3), 0, 0.1, 0, WOOD_DARK)
end

function Builders.Poltrona(m)
	local c = Color3.fromRGB(190, 110, 70)
	part(m, "Base", Vector3.new(3.6, 1.4, 3.4), 0, 0.9, 0, c, { material = Enum.Material.Fabric })
	seatOf(part(m, "Cushion", Vector3.new(2.4, 0.3, 2.4), 0, 1.75, -0.3, c, { material = Enum.Material.Fabric, class = "Seat" }), "Poltrona")
	part(m, "Back", Vector3.new(3.6, 2.4, 0.8), 0, 2.5, 1.3, c, { material = Enum.Material.Fabric })
	for _, x in ipairs({ -1.5, 1.5 }) do
		part(m, "Arm", Vector3.new(0.6, 1.1, 3.4), x, 2.1, 0, c, { material = Enum.Material.Fabric })
	end
	part(m, "Feet", Vector3.new(3.2, 0.2, 3), 0, 0.1, 0, WOOD_DARK)
end

function Builders.Mesa(m)
	part(m, "Top", Vector3.new(6, 0.3, 4), 0, 3.05, 0, WOOD)
	for _, x in ipairs({ -2.6, 2.6 }) do
		for _, z in ipairs({ -1.6, 1.6 }) do
			part(m, "Leg", Vector3.new(0.35, 2.9, 0.35), x, 1.45, z, WOOD_DARK)
		end
	end
	part(m, "Vase", Vector3.new(0.6, 0.9, 0.6), 0, 3.65, 0, Color3.fromRGB(80, 160, 200), { shape = Enum.PartType.Cylinder, rot = CFrame.Angles(0, 0, math.rad(90)), collide = false })
end

function Builders.Cadeira(m)
	seatOf(part(m, "Seat", Vector3.new(2, 0.3, 2), 0, 1.9, 0, WOOD, { class = "Seat" }), "Cadeira")
	part(m, "Back", Vector3.new(2, 2.2, 0.25), 0, 3.1, 0.88, WOOD)
	for _, x in ipairs({ -0.8, 0.8 }) do
		for _, z in ipairs({ -0.8, 0.8 }) do
			part(m, "Leg", Vector3.new(0.25, 1.8, 0.25), x, 0.9, z, WOOD_DARK)
		end
	end
end

function Builders.Estante(m)
	part(m, "Body", Vector3.new(6, 7, 0.3), 0, 3.5, 0.65, WOOD_DARK)
	for _, x in ipairs({ -2.85, 2.85 }) do
		part(m, "Side", Vector3.new(0.3, 7, 1.6), x, 3.5, 0, WOOD)
	end
	local colors = { Color3.fromRGB(200, 60, 60), Color3.fromRGB(60, 120, 200), Color3.fromRGB(240, 200, 60), Color3.fromRGB(80, 170, 90) }
	for k, y in ipairs({ 0.15, 2.4, 4.65, 6.85 }) do
		part(m, "Shelf", Vector3.new(5.4, 0.25, 1.5), 0, y, 0, WOOD)
		if k < 4 then
			for b = 0, 5 do
				part(m, "Book", Vector3.new(0.5, 1.5, 1.1), -2.2 + b * 0.75, y + 0.9, 0.05, colors[(b + k) % #colors + 1], { collide = false })
			end
		end
	end
end

function Builders.TV(m)
	part(m, "Rack", Vector3.new(6, 1.6, 1.6), 0, 0.8, 0, WOOD_DARK)
	part(m, "Stand", Vector3.new(1, 0.6, 0.6), 0, 1.9, 0.2, DARK)
	part(m, "Screen", Vector3.new(5.4, 3.2, 0.25), 0, 3.8, 0.2, DARK)
	toggle(part(m, "Image", Vector3.new(5, 2.8, 0.05), 0, 3.8, 0.05, Color3.fromRGB(70, 150, 230), { material = Enum.Material.Neon, collide = false }), "TV", "TV")
end

function Builders.Geladeira(m)
	part(m, "Body", Vector3.new(3.2, 7, 3), 0, 3.5, 0, WHITE)
	part(m, "Line", Vector3.new(3.22, 0.1, 3.02), 0, 4.6, 0, Color3.fromRGB(180, 180, 185), { collide = false })
	for _, y in ipairs({ 3.2, 5.6 }) do
		part(m, "Handle", Vector3.new(0.2, 1.2, 0.2), 1.2, y, -1.6, Color3.fromRGB(150, 150, 155), { collide = false })
	end
end

function Builders.Abajur(m)
	part(m, "Base", Vector3.new(0.3, 1.4, 1.4), 0, 0.15, 0, DARK, { shape = Enum.PartType.Cylinder, rot = CFrame.Angles(0, 0, math.rad(90)) })
	part(m, "Pole", Vector3.new(0.2, 4.6, 0.2), 0, 2.6, 0, DARK)
	local shade = toggle(part(m, "Shade", Vector3.new(1.6, 1.4, 1.6), 0, 5.4, 0, Color3.fromRGB(255, 235, 190), { material = Enum.Material.Neon, collide = false }), "Luz", "Abajur")
	local light = Instance.new("PointLight")
	light.Range = 12
	light.Brightness = 0.5
	light.Color = Color3.fromRGB(255, 225, 170)
	light.Parent = shade
end

function Builders.Planta(m)
	part(m, "Pot", Vector3.new(1.6, 1.6, 1.6), 0, 0.8, 0, Color3.fromRGB(190, 100, 60), { material = Enum.Material.Slate })
	part(m, "Leaves", Vector3.new(2.4, 2.8, 2.4), 0, 3, 0, Color3.fromRGB(70, 150, 60), { shape = Enum.PartType.Ball, material = Enum.Material.Grass, collide = false })
	part(m, "Leaves2", Vector3.new(1.6, 1.8, 1.6), 0.3, 4.4, 0.2, Color3.fromRGB(90, 170, 70), { shape = Enum.PartType.Ball, material = Enum.Material.Grass, collide = false })
end

function Builders.Tapete(m)
	part(m, "Rug", Vector3.new(8, 0.1, 6), 0, 0.05, 0, Color3.fromRGB(180, 60, 70), { material = Enum.Material.Fabric, collide = false })
	part(m, "Border", Vector3.new(7, 0.11, 5), 0, 0.055, 0, Color3.fromRGB(230, 190, 120), { material = Enum.Material.Fabric, collide = false })
	part(m, "Center", Vector3.new(6.4, 0.12, 4.4), 0, 0.06, 0, Color3.fromRGB(180, 60, 70), { material = Enum.Material.Fabric, collide = false })
end

function Builders.Mesinha(m)
	part(m, "Top", Vector3.new(0.3, 2.4, 2.4), 0, 2.2, 0, WOOD, { shape = Enum.PartType.Cylinder, rot = CFrame.Angles(0, 0, math.rad(90)) })
	part(m, "Leg", Vector3.new(0.4, 2.05, 0.4), 0, 1.03, 0, WOOD_DARK)
	part(m, "Foot", Vector3.new(0.2, 1.4, 1.4), 0, 0.1, 0, WOOD_DARK, { shape = Enum.PartType.Cylinder, rot = CFrame.Angles(0, 0, math.rad(90)) })
	part(m, "Cup", Vector3.new(0.5, 0.5, 0.5), 0.4, 2.6, 0.2, WHITE, { collide = false })
end

---------------------------------------------------------------------------
-- Marco 10: móveis de luxo
---------------------------------------------------------------------------

local GRAPHITE = Color3.fromRGB(70, 70, 78)
local GOLD = Color3.fromRGB(215, 175, 80)
local CYL = Enum.PartType.Cylinder
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- cilindro em pé (eixo vertical)

function Builders.CamaCasal(m)
	part(m, "Frame", Vector3.new(8, 1.4, 9), 0, 0.7, 0, WOOD_DARK)
	part(m, "Mattress", Vector3.new(7.6, 0.9, 8.4), 0, 1.85, 0.1, WHITE, { material = Enum.Material.Fabric })
	part(m, "Blanket", Vector3.new(7.7, 0.95, 5.2), 0, 1.9, -1.5, Color3.fromRGB(150, 60, 70), { material = Enum.Material.Fabric })
	part(m, "Throw", Vector3.new(7.8, 1, 1.2), 0, 1.92, -3.6, Color3.fromRGB(235, 215, 180), { material = Enum.Material.Fabric })
	for _, x in ipairs({ -2.4, 0, 2.4 }) do
		part(m, "Pillow", Vector3.new(2.2, 0.6, 1.3), x, 2.55, 3.4, WHITE, { material = Enum.Material.Fabric })
	end
	part(m, "Headboard", Vector3.new(8.6, 5, 0.6), 0, 2.5, 4.2, GRAPHITE, { material = Enum.Material.Fabric })
	part(m, "HeadboardTrim", Vector3.new(8.8, 0.3, 0.7), 0, 5.1, 4.2, GOLD, { material = Enum.Material.Metal, collide = false })
end

function Builders.SofaCanto(m)
	local c = GRAPHITE
	local cushion = Color3.fromRGB(95, 95, 105)
	part(m, "Base", Vector3.new(10, 1.4, 3.4), 0, 0.9, 1.8, c, { material = Enum.Material.Fabric })
	part(m, "Back", Vector3.new(10, 2.2, 0.8), 0, 2.4, 3.1, c, { material = Enum.Material.Fabric })
	part(m, "Chaise", Vector3.new(3.4, 1.4, 3.6), -3.3, 0.9, -1.7, c, { material = Enum.Material.Fabric })
	part(m, "Arm", Vector3.new(0.8, 1.2, 3.4), 4.6, 2.1, 1.8, c, { material = Enum.Material.Fabric })
	for _, x in ipairs({ -3.2, 0, 3 }) do
		seatOf(part(m, "Cushion", Vector3.new(3, 0.4, 2.5), x, 1.8, 1.45, cushion, { material = Enum.Material.Fabric, class = "Seat" }), "Sofá")
	end
	seatOf(part(m, "ChaiseCushion", Vector3.new(3, 0.4, 3.4), -3.3, 1.8, -1.7, cushion, { material = Enum.Material.Fabric, class = "Seat" }), "Sofá")
	part(m, "Pillow", Vector3.new(1.6, 1.4, 0.5), -3.6, 2.6, 2.5, Color3.fromRGB(220, 160, 70), { material = Enum.Material.Fabric, collide = false })
	part(m, "Pillow", Vector3.new(1.6, 1.4, 0.5), 3.4, 2.6, 2.5, Color3.fromRGB(220, 160, 70), { material = Enum.Material.Fabric, collide = false })
end

local function chair(m, x, z, facing)
	local back = facing * 0.88
	seatOf(part(m, "Seat", Vector3.new(2, 0.3, 2), x, 1.9, z, WHITE, { material = Enum.Material.Fabric, class = "Seat" }), "Cadeira")
	part(m, "Back", Vector3.new(2, 2.2, 0.25), x, 3.1, z + back, WHITE, { material = Enum.Material.Fabric })
	part(m, "Leg", Vector3.new(1.6, 1.75, 1.6), x, 0.88, z, DARK, { collide = false })
end

function Builders.MesaJantar(m)
	part(m, "Top", Vector3.new(8, 0.3, 4), 0, 3.05, 0, WOOD_DARK)
	for _, x in ipairs({ -3.2, 3.2 }) do
		part(m, "Leg", Vector3.new(0.5, 2.9, 3), x, 1.45, 0, DARK)
	end
	for _, x in ipairs({ -2.8, 0, 2.8 }) do
		chair(m, x, -3, -1)
		chair(m, x, 3, 1)
	end
	part(m, "Bowl", Vector3.new(0.6, 1.6, 1.6), 0, 3.5, 0, GOLD, { shape = CYL, rot = UPRIGHT, collide = false })
	part(m, "Fruit", Vector3.new(0.6, 0.6, 0.6), 0.3, 3.9, 0, Color3.fromRGB(220, 60, 50), { shape = Enum.PartType.Ball, collide = false })
	part(m, "Fruit", Vector3.new(0.6, 0.6, 0.6), -0.3, 3.9, 0.2, Color3.fromRGB(240, 190, 40), { shape = Enum.PartType.Ball, collide = false })
end

function Builders.Cozinha(m)
	part(m, "Cabinets", Vector3.new(12, 3.2, 3), 0, 1.6, 0, WHITE)
	part(m, "Counter", Vector3.new(12.2, 0.3, 3.1), 0, 3.35, 0, Color3.fromRGB(45, 45, 50), { material = Enum.Material.Granite })
	for x = -5, 5, 2.5 do
		part(m, "Handle", Vector3.new(1, 0.15, 0.1), x, 2.8, -1.55, Color3.fromRGB(170, 170, 175), { material = Enum.Material.Metal, collide = false })
	end
	part(m, "Sink", Vector3.new(2.4, 0.12, 1.8), -3, 3.52, -0.1, Color3.fromRGB(190, 195, 200), { material = Enum.Material.Metal, collide = false })
	part(m, "Faucet", Vector3.new(0.25, 1.4, 0.25), -3, 4.2, 1, Color3.fromRGB(200, 200, 205), { material = Enum.Material.Metal, collide = false })
	part(m, "Spout", Vector3.new(0.25, 0.25, 1), -3, 4.85, 0.6, Color3.fromRGB(200, 200, 205), { material = Enum.Material.Metal, collide = false })
	part(m, "Stove", Vector3.new(2.8, 0.1, 2.2), 3, 3.55, -0.1, DARK, { collide = false })
	for _, x in ipairs({ 2.3, 3.7 }) do
		for _, z in ipairs({ -0.7, 0.5 }) do
			part(m, "Burner", Vector3.new(0.08, 0.8, 0.8), x, 3.62, z, Color3.fromRGB(90, 90, 95), { shape = CYL, rot = UPRIGHT, collide = false })
		end
	end
	part(m, "Backsplash", Vector3.new(12, 2.6, 0.2), 0, 4.8, 1.45, Color3.fromRGB(215, 225, 230), { material = Enum.Material.CeramicTiles, collide = false })
	part(m, "UpperCabinets", Vector3.new(12, 2.4, 1.4), 0, 7.4, 0.8, WHITE, { collide = false })
	part(m, "Hood", Vector3.new(2.8, 1, 1.6), 3, 5.9, 0.7, Color3.fromRGB(180, 182, 186), { material = Enum.Material.Metal, collide = false })
end

function Builders.TVGrande(m)
	part(m, "Rack", Vector3.new(10, 1.6, 1.8), 0, 0.8, 0, WOOD_DARK)
	part(m, "RackTrim", Vector3.new(10.1, 0.15, 1.85), 0, 1.65, 0, GOLD, { material = Enum.Material.Metal, collide = false })
	part(m, "Stand", Vector3.new(1.2, 1, 0.6), 0, 2.2, 0.3, DARK)
	part(m, "Screen", Vector3.new(8.4, 4.8, 0.3), 0, 5, 0.3, Color3.fromRGB(20, 20, 25))
	toggle(part(m, "Picture", Vector3.new(8, 4.4, 0.05), 0, 5, 0.13, Color3.fromRGB(40, 95, 160), { material = Enum.Material.Neon, collide = false }), "TV", "TV")
	part(m, "Soundbar", Vector3.new(5, 0.5, 0.6), 0, 1.95, -0.4, DARK, { collide = false })
end

function Builders.Aquario(m)
	part(m, "Stand", Vector3.new(6, 3, 2), 0, 1.5, 0, WOOD_DARK)
	part(m, "Glass", Vector3.new(5.8, 3.4, 1.8), 0, 4.7, 0, Color3.fromRGB(180, 225, 245), { collide = true }).Transparency = 0.7
	part(m, "Water", Vector3.new(5.6, 3, 1.6), 0, 4.6, 0, Color3.fromRGB(60, 160, 220), { collide = false }).Transparency = 0.45
	part(m, "Sand", Vector3.new(5.6, 0.3, 1.6), 0, 3.2, 0, Color3.fromRGB(230, 210, 160), { material = Enum.Material.Sand, collide = false })
	for i, c in ipairs({ Color3.fromRGB(255, 140, 30), Color3.fromRGB(250, 220, 50), Color3.fromRGB(80, 170, 255) }) do
		part(m, "Fish", Vector3.new(0.6, 0.35, 0.2), -1.8 + i * 1.1, 3.9 + (i % 2) * 0.9, -0.2 + (i % 2) * 0.3, c, { collide = false })
	end
	part(m, "Weed", Vector3.new(0.3, 1.8, 0.3), -2.3, 4.2, 0.4, Color3.fromRGB(60, 150, 70), { material = Enum.Material.Grass, collide = false })
	part(m, "Weed", Vector3.new(0.3, 1.3, 0.3), 2.2, 3.95, 0.3, Color3.fromRGB(60, 150, 70), { material = Enum.Material.Grass, collide = false })
	local lid = part(m, "Lid", Vector3.new(6, 0.3, 2), 0, 6.55, 0, DARK)
	local light = Instance.new("PointLight")
	light.Range = 8
	light.Brightness = 0.4
	light.Color = Color3.fromRGB(150, 210, 255)
	light.Parent = lid
end

function Builders.Lareira(m)
	local stone = Color3.fromRGB(150, 145, 140)
	part(m, "Hearth", Vector3.new(8, 0.4, 2.4), 0, 0.2, 0, Color3.fromRGB(90, 88, 86), { material = Enum.Material.Slate })
	for _, x in ipairs({ -3, 3 }) do
		part(m, "Side", Vector3.new(2, 7, 2), x, 3.9, 0.2, stone, { material = Enum.Material.Slate })
	end
	part(m, "Top", Vector3.new(4, 2.5, 2), 0, 6.15, 0.2, stone, { material = Enum.Material.Slate })
	part(m, "Mantel", Vector3.new(8.4, 0.4, 2.4), 0, 7.6, 0, WOOD_DARK)
	part(m, "Back", Vector3.new(4, 4.5, 0.4), 0, 2.65, 1, Color3.fromRGB(30, 25, 22))
	for _, z in ipairs({ -0.2, 0.3 }) do
		part(m, "Log", Vector3.new(3, 0.5, 0.5), 0, 0.65, z, WOOD, { collide = false })
	end
	local flame = toggle(part(m, "Flame", Vector3.new(2.4, 0.4, 0.6), 0, 1, 0, Color3.fromRGB(255, 140, 40), { material = Enum.Material.Neon, collide = false }), "Fogo", "Lareira")
	local fire = Instance.new("Fire")
	fire.Size = 3
	fire.Heat = 3
	fire.Color = Color3.fromRGB(255, 130, 40)
	fire.SecondaryColor = Color3.fromRGB(255, 220, 90)
	fire.Parent = flame
	local light = Instance.new("PointLight")
	light.Range = 12
	light.Brightness = 0.6
	light.Color = Color3.fromRGB(255, 170, 90)
	light.Parent = flame
end

function Builders.Piano(m)
	local black = Color3.fromRGB(18, 18, 22)
	part(m, "Body", Vector3.new(5, 1.6, 4.6), 0, 3.3, 1, black).Reflectance = 0.15
	part(m, "Tail", Vector3.new(3, 1.6, 1.4), -1, 3.3, 3, black).Reflectance = 0.15
	part(m, "Lid", Vector3.new(4.8, 0.15, 4.4), 0.3, 5, 1.2, black, { rot = CFrame.Angles(0, 0, math.rad(-22)), collide = false })
	part(m, "Keys", Vector3.new(4.8, 0.3, 1), 0, 3.4, -1.8, WHITE)
	for x = -2, 2, 0.6 do
		part(m, "BlackKey", Vector3.new(0.25, 0.15, 0.55), x, 3.6, -1.6, black, { collide = false })
	end
	for _, p in ipairs({ { -2.2, -0.9 }, { 2.2, -0.9 }, { -1, 3.2 } }) do
		part(m, "Leg", Vector3.new(0.5, 2.5, 0.5), p[1], 1.25, p[2], black)
	end
	seatOf(part(m, "Bench", Vector3.new(3, 0.5, 1.2), 0, 2.2, -3, black, { class = "Seat" }), "Banco do piano")
	part(m, "BenchLeg", Vector3.new(2.6, 1.95, 0.9), 0, 0.98, -3, black, { collide = false })
end

function Builders.MesaSinuca(m)
	part(m, "Frame", Vector3.new(9, 1, 5), 0, 2.8, 0, WOOD_DARK)
	part(m, "Felt", Vector3.new(8, 0.15, 4), 0, 3.35, 0, Color3.fromRGB(30, 120, 70), { material = Enum.Material.Fabric })
	for _, x in ipairs({ -4.2, 4.2 }) do
		part(m, "Rail", Vector3.new(0.6, 0.4, 5), x, 3.5, 0, WOOD_DARK, { collide = false })
	end
	for _, z in ipairs({ -2.2, 2.2 }) do
		part(m, "Rail", Vector3.new(9, 0.4, 0.6), 0, 3.5, z, WOOD_DARK, { collide = false })
	end
	for _, x in ipairs({ -3.8, 3.8 }) do
		for _, z in ipairs({ -1.9, 1.9 }) do
			part(m, "Leg", Vector3.new(0.9, 2.3, 0.9), x, 1.15, z, WOOD_DARK)
		end
	end
	local balls = { WHITE, Color3.fromRGB(240, 200, 40), Color3.fromRGB(40, 80, 200), Color3.fromRGB(210, 40, 40), Color3.fromRGB(20, 20, 20) }
	for i, c in ipairs(balls) do
		part(m, "Ball", Vector3.new(0.4, 0.4, 0.4), -2.5 + i * 0.9, 3.63, (i % 2) * 0.6 - 0.3, c, { shape = Enum.PartType.Ball, collide = false })
	end
	part(m, "Cue", Vector3.new(6, 0.12, 0.12), 0.5, 3.75, 1.5, Color3.fromRGB(200, 160, 110), { collide = false, rot = CFrame.Angles(0, math.rad(8), 0) })
end

function Builders.Hidromassagem(m)
	part(m, "Shell", Vector3.new(8, 2.4, 7), 0, 1.2, 0.5, WHITE, { material = Enum.Material.Marble })
	part(m, "Inside", Vector3.new(6.8, 0.1, 5.8), 0, 2.42, 0.5, Color3.fromRGB(40, 120, 190), { collide = false })
	local water = part(m, "Water", Vector3.new(6.8, 0.2, 5.8), 0, 2.5, 0.5, Color3.fromRGB(90, 190, 240), { collide = false })
	water.Transparency = 0.35
	part(m, "Step", Vector3.new(3, 0.8, 1), 0, 0.4, -3.5, WHITE, { material = Enum.Material.Marble })
	local glow = part(m, "Glow", Vector3.new(6.9, 0.12, 5.9), 0, 2.36, 0.5, Color3.fromRGB(90, 220, 255), { material = Enum.Material.Neon, collide = false })
	glow.Transparency = 0.6
	local light = Instance.new("PointLight")
	light.Range = 9
	light.Brightness = 0.35
	light.Color = Color3.fromRGB(110, 210, 255)
	light.Parent = glow
end

---------------------------------------------------------------------------
-- Marco 10.2: mais variedade
---------------------------------------------------------------------------

-- Marco 10.18: guarda-roupa = closet nórdico do Luís (MoveisModelos > GuardaRoupaNordico);
-- sem o modelo, o guarda-roupa de peças.
local GUARDA_FIT = Vector3.new(6, 8.4, 2.4) -- tamanho do item: 6 x 2.4
local modelFrom -- carregador de modelo 3D (mais abaixo, junto do baú)

function Builders.Armario(m)
	local folder = game:GetService("ReplicatedStorage"):FindFirstChild("MoveisModelos")
	local tpl = folder and folder:FindFirstChild("GuardaRoupaNordico")
	if tpl and modelFrom(m, tpl, GUARDA_FIT) then
		return
	end
	part(m, "Body", Vector3.new(6, 8, 2.4), 0, 4, 0, WOOD)
	part(m, "Line", Vector3.new(0.1, 7.6, 0.05), 0, 4, -1.22, WOOD_DARK, { collide = false })
	for _, x in ipairs({ -0.4, 0.4 }) do
		part(m, "Handle", Vector3.new(0.15, 1.4, 0.15), x, 4.2, -1.3, Color3.fromRGB(200, 200, 205), { material = Enum.Material.Metal, collide = false })
	end
	part(m, "Top", Vector3.new(6.2, 0.2, 2.6), 0, 8.1, 0, WOOD_DARK)
end

function Builders.Escrivaninha(m)
	part(m, "Top", Vector3.new(5, 0.25, 2.4), 0, 3, 1, WHITE)
	part(m, "Drawers", Vector3.new(1.6, 2.9, 2.2), 1.6, 1.45, 1, WOOD)
	part(m, "Leg", Vector3.new(0.25, 2.9, 2.2), -2.3, 1.45, 1, WHITE)
	part(m, "Monitor", Vector3.new(2.6, 1.6, 0.15), -0.4, 4.2, 1.8, DARK)
	part(m, "MonitorStand", Vector3.new(0.3, 0.9, 0.3), -0.4, 3.5, 1.9, DARK, { collide = false })
	part(m, "Screen", Vector3.new(2.4, 1.4, 0.05), -0.4, 4.2, 1.71, Color3.fromRGB(80, 160, 230), { material = Enum.Material.Neon, collide = false })
	part(m, "Keyboard", Vector3.new(1.6, 0.1, 0.5), -0.4, 3.18, 0.6, Color3.fromRGB(60, 60, 66), { collide = false })
	seatOf(part(m, "Seat", Vector3.new(1.9, 0.4, 1.9), -0.4, 1.9, -1.1, DARK, { class = "Seat" }), "Cadeira")
	part(m, "ChairBack", Vector3.new(1.9, 2, 0.25), -0.4, 3.1, -2.0, DARK, { collide = false })
	part(m, "ChairLeg", Vector3.new(0.4, 1.7, 0.4), -0.4, 0.85, -1.1, Color3.fromRGB(150, 150, 155), { material = Enum.Material.Metal, collide = false })
end

function Builders.CamaSolteiro(m)
	part(m, "Frame", Vector3.new(4, 1.4, 7.5), 0, 0.7, 0, WOOD)
	part(m, "Mattress", Vector3.new(3.6, 0.8, 7), 0, 1.8, 0.1, WHITE, { material = Enum.Material.Fabric })
	part(m, "Blanket", Vector3.new(3.7, 0.85, 4.2), 0, 1.85, -1.3, Color3.fromRGB(90, 170, 120), { material = Enum.Material.Fabric })
	part(m, "Pillow", Vector3.new(2.4, 0.5, 1.2), 0, 2.4, 2.8, WHITE, { material = Enum.Material.Fabric })
	part(m, "Headboard", Vector3.new(4, 3.6, 0.4), 0, 1.8, 3.6, WOOD_DARK)
end

function Builders.MesaCentro(m)
	part(m, "Top", Vector3.new(5, 0.3, 3), 0, 1.5, 0, WOOD_DARK)
	part(m, "Glass", Vector3.new(4.6, 0.1, 2.6), 0, 1.7, 0, Color3.fromRGB(190, 220, 235), { collide = false }).Transparency = 0.5
	for _, x in ipairs({ -2.2, 2.2 }) do
		part(m, "Leg", Vector3.new(0.3, 1.35, 2.6), x, 0.68, 0, DARK)
	end
	part(m, "Book", Vector3.new(1.2, 0.3, 0.9), -1, 1.9, 0.3, Color3.fromRGB(200, 60, 60), { collide = false })
	part(m, "Cup", Vector3.new(0.4, 0.5, 0.4), 1.2, 1.9, -0.4, WHITE, { collide = false })
end

function Builders.Pufe(m)
	local c = Color3.fromRGB(220, 160, 70)
	part(m, "Body", Vector3.new(2.2, 1.4, 2.2), 0, 0.7, 0, c, { material = Enum.Material.Fabric })
	seatOf(part(m, "Seat", Vector3.new(2, 0.3, 2), 0, 1.55, 0, c, { material = Enum.Material.Fabric, class = "Seat" }), "Pufe")
end

function Builders.Luminaria(m)
	part(m, "Base", Vector3.new(0.3, 1.6, 1.6), 0, 0.15, 0, DARK, { shape = Enum.PartType.Cylinder, rot = CFrame.Angles(0, 0, math.rad(90)) })
	part(m, "Pole", Vector3.new(0.2, 6.6, 0.2), 0, 3.5, 0, DARK)
	part(m, "Arm", Vector3.new(0.2, 0.2, 1.6), 0, 6.8, -0.7, DARK, { collide = false })
	local shade = toggle(part(m, "Shade", Vector3.new(1.6, 1, 1.6), 0, 6.5, -1.4, Color3.fromRGB(255, 235, 190), { material = Enum.Material.Neon, collide = false }), "Luz", "Luminária")
	local light = Instance.new("PointLight")
	light.Range = 14
	light.Brightness = 0.5
	light.Color = Color3.fromRGB(255, 225, 170)
	light.Parent = shade
end

function Builders.PlantaGrande(m)
	part(m, "Pot", Vector3.new(2.4, 2.2, 2.4), 0, 1.1, 0, Color3.fromRGB(230, 228, 222), { material = Enum.Material.Slate })
	part(m, "Trunk", Vector3.new(0.4, 4, 0.4), 0, 4, 0, Color3.fromRGB(120, 90, 60), { material = Enum.Material.Wood })
	for i = 0, 5 do
		local a = i * math.pi / 3
		part(m, "Leaf", Vector3.new(0.8, 0.15, 3), math.cos(a) * 1.2, 6, math.sin(a) * 1.2, Color3.fromRGB(60, 150 + (i % 2) * 20, 70), { material = Enum.Material.Grass, collide = false, rot = CFrame.Angles(0, -a + math.pi / 2, 0) * CFrame.Angles(math.rad(-20), 0, 0) })
	end
	part(m, "Leaves", Vector3.new(2.2, 2, 2.2), 0, 6.6, 0, Color3.fromRGB(70, 160, 70), { shape = Enum.PartType.Ball, material = Enum.Material.Grass, collide = false })
end

function Builders.Bar(m)
	part(m, "Counter", Vector3.new(8, 3.4, 1.8), 0, 1.7, 0.8, Color3.fromRGB(40, 30, 25), { material = Enum.Material.Wood })
	part(m, "Top", Vector3.new(8.2, 0.25, 2.2), 0, 3.5, 0.7, Color3.fromRGB(236, 233, 228), { material = Enum.Material.Marble })
	part(m, "Trim", Vector3.new(8.1, 0.15, 0.05), 0, 3.1, -0.12, GOLD, { material = Enum.Material.Metal, collide = false })
	local bottles = { Color3.fromRGB(60, 140, 70), Color3.fromRGB(150, 60, 40), Color3.fromRGB(220, 200, 120), Color3.fromRGB(60, 90, 160) }
	for i, c in ipairs(bottles) do
		part(m, "Bottle", Vector3.new(0.35, 1.2, 0.35), -3 + i * 1.2, 4.2, 1.2, c, { collide = false })
	end
	for _, x in ipairs({ -2.6, 0, 2.6 }) do
		part(m, "StoolLeg", Vector3.new(0.35, 2.4, 0.35), x, 1.2, -1.3, DARK, { material = Enum.Material.Metal })
		seatOf(part(m, "Stool", Vector3.new(1.6, 0.4, 1.6), x, 2.6, -1.3, Color3.fromRGB(150, 40, 45), { material = Enum.Material.Fabric, class = "Seat" }), "Banqueta")
	end
end

-- Marco 10.7: baú medieval do Luís (tools/bauprep.py). O modelo 3D vem de ReplicatedStorage >
-- MoveisModelos > BauMedieval (o HomeService copia de ServerStorage > FurnitureModels). As peças
-- "Lid..." são a tampa, que o InventoryService abre girando na dobradiça ("PivotLid").
-- Sem o modelo, sai um baú de peças com as mesmas partes.
-- Marco 10.18: o mesmo carregador serve os armários do Luís (cofre antigo e closet nórdico).
-- fit = tamanho máximo (largura, altura, fundo) em studs; o modelo é escalado para caber.
-- Peças "Lid..." giram na dobradiça "PivotLid" (eixo deitado); peças "Door..." giram em volta
-- da "PivotDoor" (eixo em pé), como porta de armário.
local BAU_FIT = Vector3.new(4, math.huge, math.huge) -- largura do baú: cabe no tamanho do item (4.2 x 3)

function modelFrom(m, tpl, fit) -- (declarada lá em cima: o guarda-roupa usa antes)
	local c = tpl:Clone()
	if not c:IsA("Model") then
		local holder = Instance.new("Model")
		c.Parent = holder
		c = holder
	end
	local parts, marker, pivot = {}, nil, nil
	for _, d in ipairs(c:GetDescendants()) do
		if d:IsA("BasePart") then
			local nm = d.Name .. " " .. (d.Parent and d.Parent.Name or "")
			if nm:find("FrontMarker") then
				marker = d
			elseif nm:find("PivotLid") or nm:find("PivotDoor") then
				pivot = d
			else
				table.insert(parts, d)
			end
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	if #parts == 0 then
		c:Destroy()
		return false
	end
	local function bounds()
		local mn = Vector3.new(math.huge, math.huge, math.huge)
		local mx = -mn
		for _, p in ipairs(parts) do
			local half = p.Size / 2
			for _, corner in ipairs({ p.CFrame * -half, p.CFrame * half }) do
				mn = mn:Min(corner)
				mx = mx:Max(corner)
			end
		end
		return mn, mx
	end
	local mn, mx = bounds()
	local center = (mn + mx) / 2
	local front = Vector3.new(0, 0, -1)
	if marker then
		local d = marker.Position - center
		front = math.abs(d.X) > math.abs(d.Z) and Vector3.new(math.sign(d.X), 0, 0) or Vector3.new(0, 0, math.sign(d.Z))
	end
	local width = front.X ~= 0 and (mx.Z - mn.Z) or (mx.X - mn.X)
	local depth = front.X ~= 0 and (mx.X - mn.X) or (mx.Z - mn.Z)
	local k = math.min(fit.X / math.max(width, 0.01), fit.Y / math.max(mx.Y - mn.Y, 0.01), fit.Z / math.max(depth, 0.01))
	c:ScaleTo(c:GetScale() * k)
	mn, mx = bounds()
	center = (mn + mx) / 2
	local ground = Vector3.new(center.X, mn.Y, center.Z)
	local base = CFrame.lookAt(ground, ground + front) -- frente do baú = -Z do móvel
	local body, best = nil, 0
	for _, p in ipairs(parts) do
		p.CFrame = base:ToObjectSpace(p.CFrame)
		p.Anchored = true
		local function named(prefix)
			return p.Name:find("^" .. prefix) ~= nil or (p.Parent and p.Parent.Name:find("^" .. prefix) ~= nil)
		end
		local lid = named("Lid") and "Lid" or named("Door") and "Door" or nil
		p.CanCollide = not lid
		if lid then
			p.Name = lid
		else
			local v = p.Size.X * p.Size.Y * p.Size.Z
			if v > best then
				body, best = p, v
			end
		end
		p.Parent = m
	end
	if body then
		body.Name = "Body"
	end
	if pivot then
		local door = (pivot.Name .. " " .. (pivot.Parent and pivot.Parent.Name or "")):find("PivotDoor") ~= nil
		pivot.CFrame = base:ToObjectSpace(pivot.CFrame)
		pivot.Name = door and "PivotDoor" or "PivotLid"
		pivot.Anchored = true
		pivot.CanCollide = false
		pivot.CanQuery = false
		pivot.CanTouch = false
		pivot.Transparency = 1
		pivot.Parent = m
	end
	c:Destroy()
	return true
end

function Builders.Bau(m)
	local folder = game:GetService("ReplicatedStorage"):FindFirstChild("MoveisModelos")
	local tpl = folder and folder:FindFirstChild("BauMedieval")
	if tpl and modelFrom(m, tpl, BAU_FIT) then
		return
	end
	local iron = Color3.fromRGB(60, 60, 66)
	part(m, "Body", Vector3.new(4, 1.9, 2.5), 0, 0.95, 0, WOOD, { material = Enum.Material.WoodPlanks })
	part(m, "Lid", Vector3.new(4, 0.8, 2.5), 0, 2.3, 0, WOOD_DARK, { material = Enum.Material.WoodPlanks, collide = false })
	for _, x in ipairs({ -1.4, 1.4 }) do
		part(m, "Faixa", Vector3.new(0.3, 1.95, 2.55), x, 0.95, 0, iron, { material = Enum.Material.Metal })
		part(m, "Lid", Vector3.new(0.3, 0.85, 2.55), x, 2.3, 0, iron, { material = Enum.Material.Metal, collide = false })
	end
	part(m, "Fechadura", Vector3.new(0.6, 0.6, 0.15), 0, 1.7, -1.3, iron, { material = Enum.Material.Metal })
	local pv = part(m, "PivotLid", Vector3.new(0.2, 0.2, 0.2), 0, 1.9, 1.25, WOOD, { collide = false })
	pv.Transparency = 1
	pv.CanQuery = false
end

-- Marco 10.17/10.18: Armário de 70 (cobertura e mansão) = o cofre antigo do Luís
-- (tools/armarioprep.py -> MoveisModelos > CofreAntigo). A porta abre quando alguém abre o armário.
-- Sem o modelo, sai um cofre de peças com porta.
local COFRE_FIT = Vector3.new(4.4, 6.6, 4.6) -- cabe no tamanho do item (4.6 x 4.8)

function Builders.Closet(m)
	local folder = game:GetService("ReplicatedStorage"):FindFirstChild("MoveisModelos")
	local tpl = folder and folder:FindFirstChild("CofreAntigo")
	if tpl and modelFrom(m, tpl, COFRE_FIT) then
		return
	end
	local iron = Color3.fromRGB(38, 38, 42)
	part(m, "Body", Vector3.new(4.2, 5.6, 4), 0, 3.4, 0.1, iron, { material = Enum.Material.Metal })
	part(m, "Base", Vector3.new(4.4, 0.6, 4.2), 0, 0.3, 0.1, DARK)
	part(m, "Door", Vector3.new(3.4, 4.6, 0.25), 0, 3.4, -1.98, iron, { material = Enum.Material.Metal, collide = false })
	part(m, "Door", Vector3.new(0.8, 0.8, 0.12), 0.4, 3.9, -2.15, GOLD, { material = Enum.Material.Metal, collide = false, shape = Enum.PartType.Cylinder, rot = CFrame.Angles(0, math.rad(90), 0) })
	part(m, "Door", Vector3.new(0.2, 1.2, 0.2), 1.2, 3.4, -2.2, GOLD, { material = Enum.Material.Metal, collide = false })
	local pv = part(m, "PivotDoor", Vector3.new(0.2, 0.2, 0.2), -1.7, 3.4, -1.98, iron, { collide = false })
	pv.Transparency = 1
	pv.CanQuery = false
end

-- Cria o móvel (Model) com o pivô no centro do chão. ghost = prévia transparente sem colisão.

function FurnitureArt.build(id, ghost)
	local builder = Builders[id]
	if not builder then
		return nil
	end
	local m = Instance.new("Model")
	m.Name = id
	builder(m)
	m.WorldPivot = CFrame.new()
	if ghost then
		for _, p in ipairs(m:GetDescendants()) do
			if p:IsA("BasePart") then
				p.CanCollide = false
				p.CanQuery = false
				p.CanTouch = false
				p.CastShadow = false
				p.Transparency = 0.5
			elseif p:IsA("Light") or p:IsA("Fire") then
				p:Destroy()
			end
		end
	end
	return m
end

-- CFrame do móvel dentro do interior (origin = centro do chão do cômodo)
function FurnitureArt.placement(origin, x, z, r)
	return origin * CFrame.new(x, 0, z) * CFrame.Angles(0, r * math.pi / 2, 0)
end

return FurnitureArt
