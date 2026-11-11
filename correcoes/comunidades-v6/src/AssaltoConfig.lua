-- AssaltoConfig (ModuleScript)
-- Caminho: ReplicatedStorage > Shared > AssaltoConfig
-- Marco 10.30: as duas formas de abrir a porta do cofre do banco (fica separado do GameConfig para
-- não mexer nos IDs do Luís). Números PROVISÓRIOS: o Luís ajusta depois de testar.
--   * PERFURATRIZ: uma só no servidor, escondida num ponto sorteado da obra do Residencial Vale
--     Alto (Estrada do Vale). Quem é de gangue pega; vai para a mochila (não fica salva). No cofre,
--     a pessoa SEGURA a perfuratriz na porta: segura o clique para furar e solta para esfriar.
--   * C4: o chefe da gangue vende (fica salva na mochila). Plantar na porta = contagem e explosão:
--     a porta é arrancada na hora, mas o barulho traz a polícia mais cedo.

local AssaltoConfig = {}

AssaltoConfig.Perfuratriz = {
	FirstDelay = 20, -- segundos depois do servidor abrir até a primeira aparecer
	-- Pedido do Luís: "40 em 40 minutos?". Escolha: 30 min DEPOIS que alguém pega (o banco fica
	-- fechado 45 min depois de cada assalto: dá tempo de achar a próxima sem ela sobrar)
	RespawnAfterTaken = 1800,
	Relocate = 900, -- ninguém achou em 15 min: muda de lugar (não dá para decorar)
	LostRespawn = 300, -- perdida (preso, apreendida, saiu do jogo, desistiu caído): volta à obra em 5 min
	PickupTime = 1.2, -- segurar E para pegar
	-- no cofre
	Time = 60, -- segundos FURANDO (segurando o clique) para romper a fechadura
	HeatUp = 1 / 13, -- calor por segundo furando (13 s seguidos = superaqueceu)
	CoolDown = 1 / 3.5, -- calor que sai por segundo parado
	OverheatLock = 4, -- superaqueceu: trava esses segundos (fumaça) e volta com metade do calor
	Range = 8, -- distância máxima do ponto de furar
	Points = 4, -- pontos de procurado ao começar a furar
}

AssaltoConfig.C4 = {
	Price = 12000, -- no chefe da gangue (cada uma)
	Max = 2, -- máximo na mochila
	PlantTime = 3, -- segurar E para plantar na porta
	Fuse = 10, -- segundos de contagem (bip cada vez mais rápido)
	Radius = 16, -- quem estiver perto leva dano (proporcional à distância)
	Damage = 70,
	Points = 10, -- pontos de procurado para quem plantou
	SiegeSooner = 45, -- o estrondo: o cerco chega esses segundos mais cedo
}

return AssaltoConfig
