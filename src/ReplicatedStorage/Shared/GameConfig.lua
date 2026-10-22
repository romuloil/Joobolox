-- GameConfig (ModuleScript)
-- Caminho: ReplicatedStorage > Shared > GameConfig
-- Configurações centrais do jogo. Servidor e cliente leem daqui.
-- Mude valores aqui em vez de espalhar números pelos scripts.

local GameConfig = {}

GameConfig.GameName = "Little Life: Minha Cidade"
GameConfig.CityName = "Little Little Kinder"
GameConfig.Version = "Marco 5.4 — Vida na Prisão"

-- Nomes oficiais (documento mestre, seção 5)
GameConfig.Places = {
	Pizzaria = "La Paulistana",
	Mercearia = "Minas Market",
	Entregas = "Sherlex",
	PetShop = "Duto Pet Shop",
	Onibus = "Um Tijo",
	Bombeiros = "Corpo de Bombeiros de Little Little Kinder",
	Policia = "Centro Policial de Little Little Kinder",
	Banco = "Banco Nacional de Little Little Kinder",
	Taxi = "LXR Táxis",
}

-- Nomes dos RemoteEvents (criados pelo servidor em ReplicatedStorage > Remotes)
GameConfig.Remotes = {
	VehicleRequest = "VehicleRequest", -- cliente pede para montar/desmontar a bicicleta
	UIUpdate = "UIUpdate", -- servidor avisa a interface sobre mudanças
	TutorialRequest = "TutorialRequest", -- cliente avisa que está pronto / terminou o tutorial
	JobRequest = "JobRequest", -- cliente pede para entrar/sair de um emprego
	PoliceRequest = "PoliceRequest", -- intenções policiais, sempre validadas no servidor
	TaxiRequest = "TaxiRequest", -- serviço LXR, validado no servidor
}

-- Economia (valores PROVISÓRIOS, ajustar depois de testar)
GameConfig.Economy = {
	CurrencySymbol = "$",
	StartingMoney = 100, -- dinheiro de quem entra pela primeira vez
	MaxMoney = 1000000000, -- limite de segurança
}

-- Bônus diário (regra confirmada: 24h contadas a partir do resgate; o valor é PROVISÓRIO)
GameConfig.DailyBonus = {
	Amount = 50,
	Cooldown = 24 * 60 * 60, -- segundos
}

-- Salvamento (DataStore). Mudar o nome da store APAGA o progresso salvo de todos.
GameConfig.Data = {
	StoreName = "LittleLifePlayerData_v1",
	AutosaveInterval = 120, -- segundos entre salvamentos automáticos
	Retries = 3, -- tentativas antes de desistir de carregar/salvar
}

-- NPC guia da praça
GameConfig.Guide = {
	Name = "Seu Bento",
	Position = Vector3.new(8, 0, 24), -- perto do spawn, na praça (fora do anel de flores)
	TalkDistance = 12, -- distância máxima (studs) para conversar
	SkinColor = Color3.fromRGB(205, 150, 110),
	ShirtColor = Color3.fromRGB(240, 170, 60),
	PantsColor = Color3.fromRGB(60, 80, 120),
}

-- Personagem
GameConfig.WalkSpeed = 16 -- velocidade normal a pé (padrão do Roblox)

-- Bicicleta inicial (gratuita para todos)
GameConfig.Bike = {
	Speed = 30, -- velocidade enquanto pedala
	ToggleCooldown = 1, -- segundos mínimos entre montar e desmontar
	FrameColor = Color3.fromRGB(46, 160, 220), -- quadro
	AccentColor = Color3.fromRGB(60, 45, 35), -- selim e manoplas
	WheelColor = Color3.fromRGB(30, 30, 34), -- pneus e pedais
	MetalColor = Color3.fromRGB(190, 190, 198), -- raios, guidão, pedivela
	WheelRadius = 0.85,
	SeatOffsetY = 0, -- sobe (+) ou desce (-) o selim se o personagem ficar flutuando ou afundado
	PedalSpeed = 0.45, -- voltas do pedal por volta da roda
}

-- Veículo pessoal do protótipo e sedãs exclusivos dos empregos.
-- Cada carro é só dados: o CarBuilder monta pelo tamanho e cores daqui. Novos carros = nova entrada.
-- Esportivo baixo em cunha inspirado no BMW i8 (pedido do Luís), com nome e marca próprios
-- (o Roblox não deixa usar marcas reais).
GameConfig.Cars = {
	Vortex = {
		Name = "Vortex Volt",
		Length = 17.5,
		Width = 7.6,
		BodyColor = Color3.fromRGB(38, 40, 46), -- grafite fosco
		TrimColor = Color3.fromRGB(12, 12, 14), -- teto, asas, para-choques (preto brilhante)
		AccentColor = Color3.fromRGB(0, 150, 255), -- detalhes azuis
		GlassColor = Color3.fromRGB(30, 38, 48),
		RimColor = Color3.fromRGB(200, 30, 35), -- rodas vermelhas
		CaliperColor = Color3.fromRGB(60, 60, 66),
		SeatColor = Color3.fromRGB(60, 45, 40),
		Reflectance = 0.05,
		WheelRadius = 1.5,
		MaxSpeed = 85, -- studs/s (a bike faz 30)
		ReverseSpeed = 22,
		Acceleration = 32,
		Brake = 70,
		Drag = 14, -- quanto perde de velocidade sem acelerar
		TurnRate = 1.8, -- giro em radianos/s
		Hover = 2.0, -- altura do centro do chassi acima do chão
	},
}
-- Sedãs de serviço: somente as garagens dos respectivos empregos os liberam.
local function serviceSedan(name, role, bodyColor, maxSpeed)
	return {
		Name = name, Role = role, Style = "Sedan", Length = 18.6, Width = 7.6,
		BodyColor = bodyColor, TrimColor = Color3.fromRGB(25, 29, 34),
		AccentColor = role == "Taxista" and Color3.fromRGB(27, 79, 150) or Color3.fromRGB(235, 237, 240),
		GlassColor = Color3.fromRGB(112, 153, 180), RimColor = Color3.fromRGB(193, 200, 207),
		CaliperColor = Color3.fromRGB(60, 65, 70), SeatColor = Color3.fromRGB(37, 42, 47),
		Reflectance = 0.04, WheelRadius = 1.35, MaxSpeed = maxSpeed, ReverseSpeed = 19,
		Acceleration = 28, Brake = 72, Drag = 15, TurnRate = 1.65, Hover = 2.1,
	}
end
GameConfig.Cars.Taxi = serviceSedan("LXR Táxi Cidade", "Taxista", Color3.fromRGB(246, 193, 38), 70)
GameConfig.Cars.Police = serviceSedan("Kinder Patrulha", "Policial", Color3.fromRGB(24, 66, 115), 80)
GameConfig.WorkCars = { Taxista = "Taxi", Policial = "Police" }
GameConfig.CarModel = "Vortex" -- carro que o botão "Carro" chama
GameConfig.CarCooldown = 2 -- segundos entre pedidos de chamar/sair do carro

-- Mapa do bairro inicial (medidas em studs; 1 stud ≈ 28 cm)
GameConfig.Map = {
	GroundSize = 2400, -- inclui a prisão afastada e sua estrada de acesso
	RoundaboutOuterRadius = 74, -- borda externa do asfalto da rotatória
	RoundaboutIslandRadius = 50, -- praça no meio (primeiro lugar que o jogador vê)
	RoadWidth = 24,
	RoadLength = 560, -- comprimento de cada rua que sai da rotatória (até o anel externo)
	InnerRingRadius = 330, -- anel de rua do meio (forma os quarteirões)
	SidewalkWidth = 6,
	TreeSeed = 2026, -- muda a posição das árvores aleatórias
	RandomTrees = 160,
	-- Nomes das ruas (1 a 8 = ruas que saem da praça; ímpares comerciais, pares residenciais)
	StreetNames = {
		"Avenida das Palmeiras", "Rua das Flores", "Avenida do Comércio", "Rua dos Ipês",
		"Avenida Central", "Rua das Acácias", "Avenida da Paz", "Rua do Sol",
	},
	InnerRingName = "Avenida Circular",
	OuterRingName = "Rua do Contorno",
}

-- Paleta (documento mestre, seção 3)
GameConfig.Colors = {
	Grass = Color3.fromRGB(106, 170, 74),
	GrassDark = Color3.fromRGB(84, 145, 60),
	Asphalt = Color3.fromRGB(70, 72, 78),
	Sidewalk = Color3.fromRGB(200, 196, 186),
	RoadLine = Color3.fromRGB(245, 245, 240),
	Trunk = Color3.fromRGB(110, 78, 50),
	Leaves = { Color3.fromRGB(70, 150, 60), Color3.fromRGB(90, 170, 70), Color3.fromRGB(60, 130, 55) },
	Walls = {
		Color3.fromRGB(245, 235, 215),
		Color3.fromRGB(240, 220, 190),
		Color3.fromRGB(215, 230, 240),
		Color3.fromRGB(240, 210, 200),
		Color3.fromRGB(225, 235, 210),
	},
	Roofs = {
		Color3.fromRGB(180, 70, 55),
		Color3.fromRGB(150, 90, 60),
		Color3.fromRGB(80, 90, 110),
		Color3.fromRGB(170, 110, 70),
	},
	Door = Color3.fromRGB(120, 80, 50),
	Window = Color3.fromRGB(160, 210, 240),
	Water = Color3.fromRGB(90, 170, 230),
	Flowers = { Color3.fromRGB(240, 90, 110), Color3.fromRGB(250, 210, 70), Color3.fromRGB(180, 110, 220) },
}

return GameConfig
