-- Equipamentos públicos e acessos: lotes reservados antes dos imóveis gerados.
local CivicConfig = {}
CivicConfig.SentenceSeconds = 60
CivicConfig.CellLockSeconds = 5
CivicConfig.Station = {
 Name = "Centro Policial de Little Little Kinder",
 CFrame = CFrame.new(100, 0, -440) * CFrame.Angles(0, math.pi / 2, 0),
 LotSize = Vector3.new(124, 0, 148),
}
CivicConfig.Taxi = {
 Name = "LXR Táxis",
 CFrame = CFrame.new(-100, 0, 440) * CFrame.Angles(0, -math.pi / 2, 0),
 LotSize = Vector3.new(124, 0, 148),
}
CivicConfig.Fuel = {
 Name = "Parada da Serra",
 CFrame = CFrame.new(-420, 0, -830) * CFrame.Angles(0, math.pi, 0),
 LotSize = Vector3.new(110, 0, 100),
}
CivicConfig.Prison = {
 Name = "Centro de Reintegração Kinder",
 CFrame = CFrame.new(0, 0, -1000) * CFrame.Angles(0, math.pi, 0),
 LotSize = Vector3.new(540, 0, 340),
 BoundsCenter = Vector3.new(20, 25, 5),
 BoundsHalf = Vector3.new(170, 45, 165),
}
CivicConfig.Roads = {
 { name = "Acesso ao Centro Policial", a = Vector3.new(0, 0, -440), b = Vector3.new(32, 0, -440), width = 14 },
 { name = "Acesso LXR Táxis", a = Vector3.new(0, 0, 440), b = Vector3.new(-32, 0, 440), width = 14 },
 { name = "Estrada da Serra", a = Vector3.new(0, 0, -610), b = Vector3.new(0, 0, -835), width = 22 },
 { name = "Estrada da Conveniência", a = Vector3.new(0, 0, -780), b = Vector3.new(-420, 0, -780), width = 18 },
 { name = "Entrada Parada da Serra", a = Vector3.new(-420, 0, -780), b = Vector3.new(-420, 0, -800), width = 18 },
}
CivicConfig.TaxiStops = {
 { name = "Praça Central", position = Vector3.new(20, 0.8, -112) },
 { name = "Avenida das Palmeiras", position = Vector3.new(20, 0.8, -280) },
 { name = "Avenida Central", position = Vector3.new(-20, 0.8, 280) },
 { name = "Comércio Leste", position = Vector3.new(280, 0.8, 20) },
 { name = "Bairro Oeste", position = Vector3.new(-280, 0.8, -20) },
 { name = "Terminal LXR", position = Vector3.new(20, 0.8, 480) },
}
CivicConfig.CivicReservations = {
 { cf = CivicConfig.Station.CFrame, size = CivicConfig.Station.LotSize },
 { cf = CivicConfig.Taxi.CFrame, size = CivicConfig.Taxi.LotSize },
 { cf = CivicConfig.Fuel.CFrame, size = CivicConfig.Fuel.LotSize },
}
return CivicConfig
