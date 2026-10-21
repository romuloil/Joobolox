-- PizzaArt (ModuleScript)
-- Caminho: ReplicatedStorage > Shared > PizzaArt
-- Desenhos simples de pizza e de ingredientes feitos só com Frames (sem imagens enviadas).
-- Usado no cardápio da pizzaria (SurfaceGui, servidor) e na comanda da tela (cliente).
-- Tudo em escala: o desenho ocupa o Frame "parent" inteiro, de qualquer tamanho.

local PizzaArt = {}

local CRUST = Color3.fromRGB(215, 150, 70)
local SAUCE = Color3.fromRGB(200, 45, 35)
local CHEESE = Color3.fromRGB(250, 215, 100)

local function circle(parent, cx, cy, size, color, z)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(cx, cy)
	f.Size = UDim2.fromScale(size, size)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = z or 2
	f.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = f
	return f
end

local function rect(parent, cx, cy, w, h, color, rotation, z, round)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(cx, cy)
	f.Size = UDim2.fromScale(w, h)
	f.Rotation = rotation or 0
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = z or 2
	f.Parent = parent
	if round then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(round, 0)
		c.Parent = f
	end
	return f
end

local function ring(parent, cx, cy, size, color, z)
	local f = circle(parent, cx, cy, size, color, z)
	f.BackgroundTransparency = 1
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = 2
	s.Parent = f
	return f
end

-- Mantém o desenho quadrado dentro de qualquer Frame
local function square(parent)
	local holder = Instance.new("Frame")
	holder.Name = "Art"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = parent
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 1
	ratio.Parent = holder
	return holder
end

---------------------------------------------------------------------------
-- Cada ingrediente desenhado num ponto (cx, cy) com tamanho s (frações do desenho)
---------------------------------------------------------------------------

local DRAW = {
	Molho = function(p, cx, cy, s, z)
		circle(p, cx, cy, s, SAUCE, z)
		circle(p, cx - s * 0.18, cy - s * 0.18, s * 0.25, Color3.fromRGB(235, 90, 70), z + 1)
	end,
	Queijo = function(p, cx, cy, s, z)
		rect(p, cx, cy, s, s * 0.75, CHEESE, -10, z, 0.15)
		circle(p, cx - s * 0.2, cy, s * 0.18, Color3.fromRGB(225, 180, 60), z + 1)
		circle(p, cx + s * 0.22, cy - s * 0.15, s * 0.13, Color3.fromRGB(225, 180, 60), z + 1)
	end,
	Tomate = function(p, cx, cy, s, z)
		circle(p, cx, cy, s, Color3.fromRGB(225, 50, 45), z)
		circle(p, cx, cy, s * 0.6, Color3.fromRGB(245, 110, 90), z + 1)
		circle(p, cx, cy, s * 0.15, Color3.fromRGB(250, 220, 140), z + 2)
	end,
	Manjericao = function(p, cx, cy, s, z)
		rect(p, cx, cy, s * 0.55, s, Color3.fromRGB(50, 150, 55), 40, z, 1)
		rect(p, cx, cy, s * 0.06, s * 0.8, Color3.fromRGB(90, 190, 90), 40, z + 1)
	end,
	Calabresa = function(p, cx, cy, s, z)
		circle(p, cx, cy, s, Color3.fromRGB(150, 45, 40), z)
		circle(p, cx, cy, s * 0.78, Color3.fromRGB(190, 70, 60), z + 1)
		circle(p, cx - s * 0.15, cy - s * 0.1, s * 0.14, Color3.fromRGB(240, 200, 180), z + 2)
		circle(p, cx + s * 0.18, cy + s * 0.12, s * 0.12, Color3.fromRGB(240, 200, 180), z + 2)
	end,
	Presunto = function(p, cx, cy, s, z)
		rect(p, cx, cy, s, s * 0.8, Color3.fromRGB(240, 150, 160), 15, z, 0.3)
		rect(p, cx, cy, s * 0.7, s * 0.12, Color3.fromRGB(250, 205, 210), 15, z + 1, 1)
	end,
	Ovo = function(p, cx, cy, s, z)
		circle(p, cx, cy, s, Color3.fromRGB(255, 252, 245), z)
		circle(p, cx + s * 0.05, cy - s * 0.05, s * 0.45, Color3.fromRGB(250, 185, 40), z + 1)
	end,
	Cebola = function(p, cx, cy, s, z)
		ring(p, cx, cy, s, Color3.fromRGB(245, 235, 250), z)
	end,
}

-- Posições das coberturas em cima da pizza (frações do desenho)
local SPOTS = {
	{ 0.5, 0.3 }, { 0.3, 0.42 }, { 0.7, 0.42 }, { 0.38, 0.66 }, { 0.62, 0.66 }, { 0.5, 0.5 }, { 0.26, 0.6 }, { 0.74, 0.6 },
}

-- Desenha uma pizza do sabor (lista de ingredientes) dentro de parent
function PizzaArt.pizza(parent, ingredients)
	local p = square(parent)
	circle(p, 0.5, 0.5, 1, CRUST, 2)
	circle(p, 0.5, 0.5, 0.86, SAUCE, 3)
	circle(p, 0.5, 0.5, 0.78, CHEESE, 4)
	-- só as coberturas (molho e queijo já são a base)
	local toppings = {}
	for _, id in ipairs(ingredients) do
		if id ~= "Molho" and id ~= "Queijo" then
			table.insert(toppings, id)
		end
	end
	local spot = 1
	local per = #toppings > 0 and math.floor(#SPOTS / #toppings) or 0
	for t, id in ipairs(toppings) do
		local draw = DRAW[id]
		for k = 1, per do
			local pos = SPOTS[((spot - 1) % #SPOTS) + 1]
			spot += 1
			if draw then
				draw(p, pos[1] + (t - 1) * 0.02, pos[2], 0.17, 6 + t * 3)
			end
		end
	end
	-- linhas das fatias
	for _, angle in ipairs({ 0, 60, 120 }) do
		local line = rect(p, 0.5, 0.5, 0.78, 0.012, Color3.fromRGB(190, 120, 50), angle, 20)
		line.BackgroundTransparency = 0.3
	end
	return p
end

-- Desenha só um ingrediente (para etiquetas e para a comanda)
function PizzaArt.ingredient(parent, id)
	local p = square(parent)
	local draw = DRAW[id]
	if draw then
		draw(p, 0.5, 0.5, 0.8, 2)
	end
	return p
end

return PizzaArt
