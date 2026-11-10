-- HomeConfig (ModuleScript)
-- Caminho: ReplicatedStorage > Shared > HomeConfig
-- Marco 6: dados da moradia (servidor e cliente leem daqui).
-- Valores de preço são PROVISÓRIOS (ajustar depois de testar a economia).

local HomeConfig = {}

-- Níveis de casa (Marco 6.1). Todo jogador começa com a "basica" (casinha da Vila Esperança,
-- grátis). Casas da cidade ficam à venda: compra-se o NÍVEL; em cada jogo o jogador recebe uma
-- fachada livre desse nível (a mesma da última vez, se estiver livre). Ninguém perde a casa.
-- Marco 10.1 (decidido pelo Luís): o jogador pode ter VÁRIAS casas, uma de cada nível. Comprar
-- outro nível soma (não troca). Quem entra numa gangue ganha o "barraco" na favela dela e perde
-- só a casinha da Vila Esperança (volta se sair da gangue).
-- Room = tamanho do interior (X, Z, altura); MaxItems = limite de móveis.
HomeConfig.Tiers = {
	basica = { order = 1, label = "Casinha", price = 0, Room = { Width = 26, Depth = 20, Height = 10 }, MaxItems = 15 },
	-- Marco 10.1: barraco da favela (só para quem é de gangue). Bem simples: chão de cimento,
	-- poucos móveis. NÃO está à venda (Free): o HomeService dá um para cada membro.
	barraco = { order = 0, label = "Barraco", price = 0, Free = true, Room = { Width = 24, Depth = 18, Height = 9 }, MaxItems = 10, Owner = "Barraco de",
		Style = { Floor = Color3.fromRGB(150, 148, 142), FloorMaterial = Enum.Material.Concrete, View = "favela" },
		DefaultItems = {
			{ id = "Cama", x = 7, z = 3, r = 0 },
			{ id = "Cadeira", x = -6, z = 5, r = 0 },
			{ id = "Mesinha", x = -8.5, z = 5, r = 0 },
		} },
	media = { order = 2, label = "Casa média", price = 50000, Room = { Width = 44, Depth = 32, Height = 12 }, MaxItems = 40 },
	sobrado = { order = 3, label = "Sobrado", price = 150000, Room = { Width = 56, Depth = 40, Height = 14 }, MaxItems = 60 },
	-- Marco 10: Bairro Horizonte (cidade moderna). Apartamentos e coberturas ficam nos prédios
	-- (a "porta" é o elevador no saguão); as casas modernas ficam nas ruas do bairro e as mansões
	-- no condomínio Jardins do Horizonte.
	-- Preços PROVISÓRIOS (decidir com o Luís depois de testar quanto se ganha por hora).
	-- Marco 10.2: apartamento, cobertura e mansão ficam NO LUGAR (InPlace): o apartamento é um andar
	-- do prédio com vidro de verdade, a cobertura é o último andar com terraço e a mansão é a casa
	-- inteira (3 andares). Room = só a área dos móveis do dono (o resto já vem montado).
	apartamento = { order = 4, label = "Apartamento", price = 300000, Room = { Width = 56, Depth = 37, Height = 9.2 }, MaxItems = 80, Owner = "Apê de",
		Style = { InPlace = true, Exit = "Elevador" },
		DefaultItems = {
			{ id = "SofaCanto", x = -14, z = 4, r = 2 },
			{ id = "Tapete", x = -14, z = 10, r = 0 },
			{ id = "MesaCentro", x = -14, z = 10, r = 0 },
			{ id = "TVGrande", x = -14, z = 16.5, r = 0 },
			{ id = "Luminaria", x = -24, z = 4, r = 0 },
			{ id = "MesaJantar", x = 4, z = -6, r = 0 },
			{ id = "CamaCasal", x = 21, z = 12.5, r = 2 },
			{ id = "Abajur", x = 26, z = 7, r = 0 },
			{ id = "Armario", x = 25.5, z = -4, r = 1 },
			{ id = "Escrivaninha", x = 10, z = 15, r = 0 },
			{ id = "Estante", x = -26, z = -8, r = 3 },
			{ id = "PlantaGrande", x = -25.5, z = 16, r = 0 },
			{ id = "PlantaGrande", x = 3, z = 16, r = 0 },
		} },
	-- Marco 10.6: a casa moderna também fica NO LUGAR (2 andares, varanda e piscina já montados).
	-- Room = a sala do térreo (o resto já vem mobiliado).
	casamoderna = { order = 5, label = "Casa moderna", price = 500000, Room = { Width = 17, Depth = 19, Height = 11 }, MaxItems = 90, Owner = "Casa de", DataV = 3,
		Style = { InPlace = true, Exit = "Porta" },
		DefaultItems = {
			{ id = "TVGrande", x = 0, z = 7.5, r = 0 },
			{ id = "SofaCanto", x = 0, z = -1, r = 2 },
			{ id = "Tapete", x = 0, z = 3.5, r = 0 },
			{ id = "MesaCentro", x = 0, z = 4.5, r = 0 },
			{ id = "Armario", x = -6.3, z = 4, r = 3 },
			{ id = "Luminaria", x = -6.5, z = -2.5, r = 0 },
			{ id = "PlantaGrande", x = 6, z = 7.5, r = 0 },
			{ id = "PlantaGrande", x = 6.5, z = -5, r = 0 },
		} },
	cobertura = { order = 6, label = "Cobertura", price = 800000, Room = { Width = 56, Depth = 37, Height = 12.8 }, MaxItems = 110, Owner = "Cobertura de",
		Style = { InPlace = true, Exit = "Elevador" },
		DefaultItems = {
			{ id = "SofaCanto", x = -14, z = 4, r = 2 },
			{ id = "Tapete", x = -14, z = 10, r = 0 },
			{ id = "MesaCentro", x = -14, z = 10, r = 0 },
			{ id = "TVGrande", x = -14, z = 16.5, r = 0 },
			{ id = "Piano", x = -23.5, z = -6, r = 1 },
			{ id = "Bar", x = 2, z = -8, r = 0 },
			{ id = "MesaJantar", x = 4, z = 6, r = 0 },
			{ id = "CamaCasal", x = 21, z = 12.5, r = 2 },
			{ id = "Abajur", x = 26, z = 7, r = 0 },
			{ id = "Closet", x = 24.3, z = -4, r = 1 }, -- 10.18: cofre (fundo 4.8) encostado na mesma parede
			{ id = "Aquario", x = -26, z = 4, r = 3 },
			{ id = "PlantaGrande", x = -25.5, z = 16, r = 0 },
			{ id = "PlantaGrande", x = 14, z = 16, r = 0 },
		} },
	mansao = { order = 7, label = "Mansão", price = 1500000, Room = { Width = 23, Depth = 34, Height = 13 }, MaxItems = 150, Owner = "Mansão de",
		Style = { InPlace = true, Exit = "Porta" },
		DefaultItems = {
			{ id = "TVGrande", x = -9.5, z = 0, r = 3 },
			{ id = "SofaCanto", x = 3, z = 0, r = 1 },
			{ id = "Tapete", x = -3, z = 0, r = 1 },
			{ id = "MesaCentro", x = -3, z = 0, r = 1 },
			{ id = "Lareira", x = 0, z = 14.5, r = 0 },
			{ id = "PlantaGrande", x = -9, z = 14.5, r = 0 },
			{ id = "PlantaGrande", x = 9, z = 14.5, r = 0 },
			{ id = "Poltrona", x = 8, z = -10, r = 1 },
			{ id = "Luminaria", x = 8.5, z = -6, r = 0 },
			{ id = "Aquario", x = 9.5, z = 8, r = 1 },
		} },
}
-- Casas opcionais da comunidade: usa compra, decoração e persistência do HomeService.
-- Uma casa por comunidade; sair da gangue suspende o uso, sem apagar a compra nem os móveis.
for index, id in ipairs({"CDA", "TDE", "CDS"}) do
 HomeConfig.Tiers["comunidade_" .. string.lower(id)] = {
  order = 1 + index / 10, label = "Casa na comunidade " .. id, price = 35000,
  GangRequired = id, Room = { Width = 32, Depth = 26, Height = 10 }, MaxItems = 30,
  Style = { Floor = Color3.fromRGB(160,155,145), FloorMaterial = Enum.Material.Concrete, View = "favela" },
 }
end
HomeConfig.StartTier = "basica"
HomeConfig.GangTier = "barraco" -- Marco 10.1
HomeConfig.Margin = 1 -- distância mínima dos móveis até a parede

function HomeConfig.tier(id)
	return HomeConfig.Tiers[id] or HomeConfig.Tiers[HomeConfig.StartTier]
end

HomeConfig.GoHomeCooldown = 20 -- (sem uso desde o Marco 8.3: "Ir para casa" saiu)

-- Quem pode entrar
HomeConfig.LockModes = {
	{ id = "aberta", label = "Aberta", hint = "Qualquer um pode entrar" },
	{ id = "amigos", label = "Só amigos", hint = "Só seus amigos do Roblox entram" },
	{ id = "trancada", label = "Trancada", hint = "Só você entra" },
}
HomeConfig.DefaultLock = "amigos"

-- Cores da parede (grátis)
HomeConfig.WallColors = {
	Color3.fromRGB(245, 240, 228), -- creme
	Color3.fromRGB(200, 225, 245), -- azul claro
	Color3.fromRGB(215, 240, 205), -- verde claro
	Color3.fromRGB(250, 215, 220), -- rosa
	Color3.fromRGB(250, 235, 180), -- amarelo
	Color3.fromRGB(225, 215, 245), -- lilás
}

-- Móveis à venda. size = X e Z ocupados no chão (sem girar). floor = fica no chão
-- (tapete): pode ter móvel em cima.
HomeConfig.Items = {
	{ id = "Cama", label = "Cama", price = 700, size = Vector2.new(6, 8) },
	{ id = "Sofa", label = "Sofá", price = 600, size = Vector2.new(8, 3.4) },
	{ id = "Poltrona", label = "Poltrona", price = 350, size = Vector2.new(3.6, 3.4) },
	{ id = "Mesa", label = "Mesa", price = 400, size = Vector2.new(6, 4) },
	{ id = "Cadeira", label = "Cadeira", price = 150, size = Vector2.new(2.2, 2.2) },
	{ id = "Estante", label = "Estante", price = 450, size = Vector2.new(6, 1.6) },
	{ id = "TV", label = "TV", price = 900, size = Vector2.new(6, 1.6) },
	{ id = "Geladeira", label = "Geladeira", price = 800, size = Vector2.new(3.2, 3) },
	{ id = "Abajur", label = "Abajur", price = 250, size = Vector2.new(1.6, 1.6) },
	{ id = "Planta", label = "Planta", price = 150, size = Vector2.new(2, 2) },
	{ id = "Tapete", label = "Tapete", price = 200, size = Vector2.new(8, 6), floor = true },
	{ id = "Mesinha", label = "Mesinha", price = 200, size = Vector2.new(2.4, 2.4) },
	-- Marco 10: móveis de luxo (grandes: cabem melhor no apartamento, na cobertura e na mansão)
	{ id = "CamaCasal", label = "Cama king", price = 4000, size = Vector2.new(8, 9), luxo = true },
	{ id = "SofaCanto", label = "Sofá de canto", price = 5000, size = Vector2.new(10, 7), luxo = true },
	{ id = "MesaJantar", label = "Mesa de jantar", price = 6000, size = Vector2.new(10, 8), luxo = true },
	{ id = "Cozinha", label = "Cozinha", price = 10000, size = Vector2.new(12, 3), luxo = true },
	{ id = "TVGrande", label = "TV gigante", price = 9000, size = Vector2.new(10, 1.8), luxo = true },
	{ id = "Aquario", label = "Aquário", price = 7500, size = Vector2.new(6, 2), luxo = true },
	{ id = "Lareira", label = "Lareira", price = 11000, size = Vector2.new(8, 2.4), luxo = true },
	{ id = "Piano", label = "Piano", price = 17500, size = Vector2.new(6, 7), luxo = true },
	{ id = "MesaSinuca", label = "Sinuca", price = 19000, size = Vector2.new(10, 6), luxo = true },
	{ id = "Hidromassagem", label = "Hidromassagem", price = 25000, size = Vector2.new(8, 8), luxo = true },
	-- Marco 10.2: mais variedade
	{ id = "Armario", label = "Guarda-roupa", price = 900, size = Vector2.new(6, 2.4) },
	{ id = "Closet", label = "Armário (70)", price = 9000, size = Vector2.new(4.6, 4.8) }, -- Marco 10.17: cobertura e mansão (10.18: é o cofre antigo)
	{ id = "Escrivaninha", label = "Escrivaninha", price = 700, size = Vector2.new(5, 4.4) },
	{ id = "CamaSolteiro", label = "Cama de solteiro", price = 500, size = Vector2.new(4, 7.5) },
	{ id = "MesaCentro", label = "Mesa de centro", price = 450, size = Vector2.new(5, 3) },
	{ id = "Pufe", label = "Pufe", price = 200, size = Vector2.new(2.4, 2.4) },
	{ id = "Luminaria", label = "Luminária de chão", price = 350, size = Vector2.new(1.8, 1.8) },
	{ id = "PlantaGrande", label = "Planta grande", price = 400, size = Vector2.new(3, 3) },
	{ id = "Bar", label = "Bar com banquetas", price = 6500, size = Vector2.new(8, 5), luxo = true },
	-- Marco 10.7: baú medieval do Luís (guarda até 20 itens nas casas padrão; já vem na casa)
	{ id = "Bau", label = "Baú", price = 600, size = Vector2.new(4.2, 3) },
}

-- Casinha nova já vem com alguns móveis (grátis); cabem no menor interior
HomeConfig.DefaultItems = {
	{ id = "Cama", x = 8, z = 4, r = 0 },
	{ id = "Tapete", x = -5, z = 1, r = 0 },
	{ id = "Sofa", x = -5, z = 5, r = 0 },
	{ id = "Abajur", x = 11, z = -2, r = 0 },
	{ id = "Planta", x = -11, z = 7, r = 0 },
}

local byId = {}
for _, item in ipairs(HomeConfig.Items) do
	byId[item.id] = item
end
function HomeConfig.item(id)
	return byId[id]
end

-- Tamanho no chão depois de girar (r = 0..3, passos de 90°)
function HomeConfig.footprint(item, r)
	if r % 2 == 1 then
		return Vector2.new(item.size.Y, item.size.X)
	end
	return item.size
end

-- Confere se o móvel cabe dentro do cômodo do nível "tierId" (coordenadas locais do interior)
function HomeConfig.insideRoom(item, x, z, r, tierId)
	local f = HomeConfig.footprint(item, r)
	local room = HomeConfig.tier(tierId).Room
	local hx = room.Width / 2 - HomeConfig.Margin - f.X / 2
	local hz = room.Depth / 2 - HomeConfig.Margin - f.Y / 2
	-- a frente da porta (lado -Z, no meio) fica sempre livre
	local doorBlocked = math.abs(x) < 4 + f.X / 2 and z - f.Y / 2 < -room.Depth / 2 + 5
	return math.abs(x) <= hx and math.abs(z) <= hz and not doorBlocked
end

-- true se dois móveis se sobrepõem (tapete só conflita com outro tapete)
function HomeConfig.overlaps(a, b)
	local ia, ib = byId[a.id], byId[b.id]
	if not ia or not ib then
		return false
	end
	if (ia.floor and true or false) ~= (ib.floor and true or false) then
		return false
	end
	local fa, fb = HomeConfig.footprint(ia, a.r), HomeConfig.footprint(ib, b.r)
	return math.abs(a.x - b.x) < (fa.X + fb.X) / 2 - 0.05 and math.abs(a.z - b.z) < (fa.Y + fb.Y) / 2 - 0.05
end

return HomeConfig
