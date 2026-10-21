-- CivicConfig: posições e regras comuns da delegacia e da prisão.
-- O saldo do jogador nunca é alterado pelo sistema prisional.
local CivicConfig = {}

CivicConfig.SentenceSeconds = 60
CivicConfig.CellLockSeconds = 15
CivicConfig.Station = {
	Name = "Centro Policial de Little Little Kinder",
	CFrame = CFrame.new(108, 0, -221) * CFrame.Angles(0, math.pi / 2, 0),
	LotSize = Vector3.new(52, 0, 72),
}
CivicConfig.Prison = {
	Name = "Centro de Reintegração Kinder",
	CFrame = CFrame.new(0, 0, -1000) * CFrame.Angles(0, math.pi, 0),
	LotSize = Vector3.new(540, 0, 340),
	BoundsCenter = Vector3.new(20, 20, 30),
	BoundsHalf = Vector3.new(170, 45, 140),
}
CivicConfig.Roads = {
	{ name = "Acesso à Delegacia", a = Vector3.new(0, 0, -241), b = Vector3.new(82, 0, -241), width = 10 },
	{ name = "Estrada da Serra", a = Vector3.new(0, 0, -610), b = Vector3.new(0, 0, -887), width = 22 },
}

return CivicConfig
