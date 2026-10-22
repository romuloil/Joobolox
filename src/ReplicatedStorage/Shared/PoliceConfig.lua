-- Regras policiais do servidor: equipamento local, ocorrências e custódia validada.
local PoliceConfig = {}
PoliceConfig.Slots = 3
PoliceConfig.InteractionDistance = 11
PoliceConfig.SprayRange = 65
PoliceConfig.SprayCooldown = 1.1
PoliceConfig.StunSeconds = 6
PoliceConfig.CustodySeconds = 10
PoliceConfig.TaserRange = 40
PoliceConfig.TaserCooldown = 2
PoliceConfig.PistolRange = 90
PoliceConfig.PistolCooldown = 0.65
PoliceConfig.PistolDamage = 18
PoliceConfig.InnocentFine = 25
PoliceConfig.MisconductLimit = 3
PoliceConfig.SpikeSeconds = 40
PoliceConfig.SpikeSlowSeconds = 8
PoliceConfig.SpikeCooldown = 12
PoliceConfig.Bounty = { ["Furto de cartão"] = 25, ["Área restrita"] = 25, ["Fuga da prisão"] = 75 }
PoliceConfig.MaxBounty = 100
PoliceConfig.CuffDistance = 8
PoliceConfig.SuspectSeconds = 120
PoliceConfig.TrainingSeconds = 75
PoliceConfig.TrainingCooldown = 15
PoliceConfig.ReportCooldown = 10
PoliceConfig.MaxReports = 24
PoliceConfig.DoorSeconds = 0.65
PoliceConfig.Gear = {
	{ id = "Pistol", name = "Pistola de serviço", color = Color3.fromRGB(40, 49, 63) },
	{ id = "Taser", name = "Taser", color = Color3.fromRGB(230, 191, 54) },
	{ id = "Spike", name = "Barreira de pneus", color = Color3.fromRGB(50, 60, 72) },
	{ id = "Spray", name = "Lançador de água", color = Color3.fromRGB(33, 125, 205) },
	{ id = "Cuff", name = "Algemas", color = Color3.fromRGB(160, 172, 184) },
	{ id = "Flashlight", name = "Lanterna", color = Color3.fromRGB(45, 55, 72) },
	{ id = "Radio", name = "Rádio", color = Color3.fromRGB(38, 45, 60) },
}
PoliceConfig.ReportCategories = {
	Seguranca = "Inspeção de segurança concluída",
	Patrulha = "Ronda e pontos de controle verificados",
	Manutencao = "Solicitação de manutenção nas instalações",
}
return PoliceConfig
