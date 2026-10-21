-- Uniformes originais, sem dependência de roupas ou imagens externas.
-- A profissão pertence ao servidor; atributos replicados servem apenas à interface.
local WorkRoleConfig = {}

WorkRoleConfig.InteractionDistance = 11
WorkRoleConfig.UniformCooldown = 0.75
WorkRoleConfig.Roles = {
	Policial = {
		name = "Policial", style = "Police", label = "LLK",
		shirt = Color3.fromRGB(29, 64, 111), pants = Color3.fromRGB(23, 42, 71),
		cap = Color3.fromRGB(24, 55, 101), trim = Color3.fromRGB(235, 193, 71),
	},
	Taxista = {
		name = "Taxista LXR", style = "Taxi", label = "LXR",
		shirt = Color3.fromRGB(39, 43, 48), pants = Color3.fromRGB(29, 42, 58),
		cap = Color3.fromRGB(249, 197, 42), trim = Color3.fromRGB(249, 197, 42),
	},
	Pizzaiolo = {
		name = "Pizzaiolo", style = "Chef", label = "PIZZA",
		shirt = Color3.fromRGB(244, 242, 232), pants = Color3.fromRGB(58, 61, 65),
		cap = Color3.fromRGB(249, 247, 238), trim = Color3.fromRGB(183, 49, 46),
	},
	Atendente = {
		name = "Atendente Minas Market", style = "Apron", label = "MINAS",
		shirt = Color3.fromRGB(239, 239, 226), pants = Color3.fromRGB(39, 49, 60),
		cap = Color3.fromRGB(39, 131, 69), trim = Color3.fromRGB(39, 131, 69),
	},
	Entregador = {
		name = "Entregador Sherlex", style = "Courier", label = "SHERLEX",
		shirt = Color3.fromRGB(225, 131, 42), pants = Color3.fromRGB(34, 49, 72),
		cap = Color3.fromRGB(33, 51, 81), trim = Color3.fromRGB(238, 225, 167),
	},
}

return WorkRoleConfig
