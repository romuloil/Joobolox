-- Polícia cartunesca: ferramentas não letais, três vagas e ações validadas no servidor.
local PoliceConfig = {}
PoliceConfig.Slots = 3
PoliceConfig.InteractionDistance = 11
PoliceConfig.SprayRange = 65
PoliceConfig.SprayCooldown = 1.1
PoliceConfig.StunSeconds = 6
PoliceConfig.CuffDistance = 8
PoliceConfig.SuspectSeconds = 120
PoliceConfig.TrainingSeconds = 75
PoliceConfig.TrainingCooldown = 15
PoliceConfig.ReportCooldown = 10
PoliceConfig.MaxReports = 24
PoliceConfig.DoorSeconds = 0.65
PoliceConfig.Gear = {
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
