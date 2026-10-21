# Registro do Projeto — Little Life: Minha Cidade

Copie este registro para a próxima sessão.

## Marco atual
- Marco 0 e 1: entregues e **testados pelo Luís em 2026-10-19: funcionando**. Único ajuste pedido: pose na bike (feito no Marco 2).
- Marco 2: **testado pelo Luís em 2026-10-19: funcionando** (Seu Bento, tutorial, salvamento, bike corrigida). Pedido: interface menor no celular (feito no Marco 3).
- Marco 3: **testado pelo Luís em 2026-10-20: funcionando** (saldo, bônus, tarefa, salvamento, Output). Pedido: indicadores de lojas mais discretos.
- **Marco 3.1 (ajuste): testado pelo Luís em 2026-10-20: funcionando** (mapa, botão-ícone, bike, mãos no guidão). indicadores flutuantes REMOVIDOS a pedido do Luís (poluíam a tela). No lugar: botão Mapa / tecla M com mapa visto de cima (ruas, casas, lojas, seta do jogador, destino da tarefa em laranja) — MapController. Título do jogo removido do HUD; HUD mostra só saldo e bônus. Botão do mapa: redondo (40 px) com ícone desenhado de mapa dobrado + alfinete, na faixa do topo da tela ao lado dos botões do Roblox (ScreenGui com IgnoreGuiInset), centralizado; faixa da tarefa logo abaixo da faixa do topo. Luís testou a versão anterior (botão "Mapa" escrito) e aprovou a direção, pedindo mais para cima e/ou ícone. **Bicicleta nova:** do tamanho do boneco (RigMeasure), rodas com pneu em anel e raios, pedivela com pedais, coroa, corrente, farol e refletor; rodas e pedivela em Motor6D animados no cliente (BikeAnimator) pela velocidade; pernas seguem os pedais e mãos no guidão por cinemática inversa, tronco, cabeça e punhos travados para a mão não balançar (pedido do Luís após teste) (Motor6D.Transform em RunService.Stepped). Animação de sentar removida.
- **Marco 4: testado pelo Luís em 2026-10-20: as 3 profissões funcionam.** Pedidos: itens entravam no corpo (sem segurar) e locais de trabalho mais desenvolvidos.
- **Marco 4.1 entregue em 2026-10-20, não testado:** lojas ocas e maiores (44x36x16, porta 6x8, vitrines, teto com luzes; atributo BaseCFrame = chão de dentro) no MapBuilder; interiores decorados e estações dentro no JobSiteBuilder (Pet Shop só decoração); pose de segurar com as duas mãos (BikeAnimator, IK dos braços até o CarriedItem) e item afastado do corpo. Lighting.Ambient mais claro para interiores.
- **Marco 4.1: testado pelo Luís em 2026-10-20:** interiores ok, vagas com 3 jogadores ok (lotado, saída libera). Problemas: casas dentro das lojas (layout radial apertado) e bancos sem sentar. Pedidos: cidade maior e mais bonita, casas maiores e afastadas, profissões mais completas (sabores de pizza etc.).
- **Marco 4.2 entregue em 2026-10-20, não testado:** MapBuilder refeito: chão 1500, ruas de 560, anel do meio (raio 330) e anel externo (610), lotes conferidos por retângulos (nada sobrepõe; planta simulada em Python: ~150 casas, ~70 prédios, 4 lojas); 3 modelos de casa numerados; prédios 2–9 andares com comércio no térreo. JobConfig com makeOrder por profissão; MissionService com etapas de coleta (escolher itens certos), queimar pizza, revelar sujeira, rotas de entrega, gorjeta por tempo. Bancos são Seat.
- **Marco 4.2: testado pelo Luís em 2026-10-20: aprovado ("gostei").** Pedidos (9): sem bike/briga dentro do trabalho; 1 carro de luxo para andar rápido; cardápio com desenho das pizzas; menos ingredientes; sentar só apertando E; fachadas mais altas (dava para subir nos prédios pelo toldo/frisos); ícone do jogador no mapa melhor; numeração das casas seguindo a rua; mercado mais complexo (cliente NPC no caixa, repor mais).
- **Marco 4.3 entregue em 2026-10-20, não testado:** ZoneService (interior das lojas = zona de trabalho: desce da bike, bloqueia bike/carro, ForceField invisível, sem colisão entre jogadores; grupos de colisão Jogadores/ZonaSegura/NPCs/Veiculos). SeatService (CanTouch=false nos Seat + ProximityPrompt "Sentar"). Carro Vortex S5 (CarBuilder + GameConfig.Cars; chassi invisível flutuando com LinearVelocity + AlignOrientation; CarController no cliente do motorista com dono de rede = motorista; botão Carro/tecla V; banco de carona; servidor trava velocidade estranha). PizzaArt (desenhos de pizza/ingredientes com Frames): cardápio com desenhos, etiquetas com ícone, comanda na tela. Ingredientes 9→7 (BASE: molho, queijo; COBERTURAS: tomate, manjericão, calabresa, presunto, ovo). Prédios com térreo de 11 e no mínimo 3 andares; toldo, letreiro, frisos e janelas sem colisão; lojas de emprego com 21 de altura. Ruas com nome (GameConfig.Map.StreetNames), placas verdes, numeração por rua (ímpar/par, crescendo a partir da praça), endereço "Rua, nº" nas entregas. Marcador do jogador no mapa (bolinha azul, seta, onda, "VOCÊ") e nomes de rua no mapa. Mercado: 2 caixas (um por atendente), cliente NPC (MarketService) entra, compras na esteira, passar um a um, sacola, cobrar, cliente sai; repor 2 ou 3 prateleiras (ficam meio vazias até repor).
- **Marco 4.3: testado pelo Luís em 2026-10-20:** zona de trabalho, mercado com cliente NPC e o resto ok; **o carro não andava** (só esterçava). Pedidos: carro esportivo estilo BMW i8 (outro nome/marca), pagar menos no caixa, praça bem bonita (primeiro contato do jogador), cartão de tarefas do mercado igual ao da pizza, e começar o Marco 5.
- **Marco 4.4 + Marco 5 entregues em 2026-10-20 (`LittleLife_Marco5.rbxlx`), não testados:** carro corrigido (Attachment e LinearVelocity tinham o mesmo nome "Drive"; agora "DriveAttachment" e busca por classe) e refeito como "Vortex Volt" (estilo i8, portas que abrem para cima em Motor6D); caixa paga $8 + $2/produto + $3; praça nova (ilha 50, rotatória 74: chafariz de 3 andares com partículas, letreiro com o nome da cidade, coreto, gramados, palmeiras, postes, 6 bancos, cerca viva, carrinho de sorvete); cartão em lista no HUD para o mercado. **Marco 5:** NPCKit (aparência aleatória, animações padrão R15 do Roblox, balão de fala, emoji de reação, andar com destrava, segurar objeto, limite de 30 NPCs extras, estados desligados); CityNPCService (funcionários nas 4 lojas quando ninguém tem o emprego, cliente da pizzaria com reação por tempo, morador que recebe o pacote, 4 pessoas passeando na praça); Seu Bento acena; MarketService usa o NPCKit.
- Marco 4 (detalhes): quadro de empregos na praça (JobConfig.BoardPosition), JobService (vagas 2/2/2, troca, saída, liberação ao desconectar), JobSiteBuilder (estações na frente da La Paulistana, Minas Market e Sherlex + pontos de entrega nas portas das 20 casas, em Workspace/JobStations), MissionService reescrito como ciclo genérico por etapas (JobConfig.Steps), JobController (painel, destaque laranja da estação atual, prompt ligado só localmente, faixa com botão Sair), item carregado nas mãos, destino no mapa (loja ou casa). Tarefa de teste do Seu Bento removida (opção virou "Empregos"). Mapa: nomes das lojas do lado de fora da rua, sem sobrepor (pedido do Luís).

## Arquivos existentes
| Studio | Tipo | Arquivo |
|---|---|---|
| ReplicatedStorage/Shared/GameConfig | ModuleScript | `src/ReplicatedStorage/Shared/GameConfig.lua` |
| ServerScriptService/ServerBootstrap | Script | `src/ServerScriptService/ServerBootstrap.server.lua` |
| ServerScriptService/Services/MapBuilder | ModuleScript | `src/ServerScriptService/Services/MapBuilder.lua` |
| ServerScriptService/Services/SecurityService | ModuleScript | `src/ServerScriptService/Services/SecurityService.lua` |
| ServerScriptService/Services/VehicleService | ModuleScript | `src/ServerScriptService/Services/VehicleService.lua` |
| StarterPlayer/StarterPlayerScripts/ClientBootstrap | LocalScript | `src/StarterPlayer/StarterPlayerScripts/ClientBootstrap.client.lua` |
| ReplicatedStorage/Shared/DialogConfig | ModuleScript | `src/ReplicatedStorage/Shared/DialogConfig.lua` |
| ServerScriptService/Services/PlayerDataService | ModuleScript | `src/ServerScriptService/Services/PlayerDataService.lua` |
| ServerScriptService/Services/NPCService | ModuleScript | `src/ServerScriptService/Services/NPCService.lua` |
| ServerScriptService/Services/TutorialService | ModuleScript | `src/ServerScriptService/Services/TutorialService.lua` |
| StarterPlayerScripts/Controllers/DialogController | ModuleScript | `src/StarterPlayer/StarterPlayerScripts/Controllers/DialogController.lua` |
| StarterPlayerScripts/Controllers/TutorialController | ModuleScript | `src/StarterPlayer/StarterPlayerScripts/Controllers/TutorialController.lua` |
| ServerScriptService/Services/EconomyService | ModuleScript | `src/ServerScriptService/Services/EconomyService.lua` |
| ServerScriptService/Services/DailyBonusService | ModuleScript | `src/ServerScriptService/Services/DailyBonusService.lua` |
| ServerScriptService/Services/MissionService | ModuleScript | `src/ServerScriptService/Services/MissionService.lua` |
| StarterPlayerScripts/Controllers/HudController | ModuleScript | `src/StarterPlayer/StarterPlayerScripts/Controllers/HudController.lua` |
| StarterPlayerScripts/Controllers/UIScaler | ModuleScript | `src/StarterPlayer/StarterPlayerScripts/Controllers/UIScaler.lua` |
| StarterPlayerScripts/Controllers/MapController | ModuleScript | `src/StarterPlayer/StarterPlayerScripts/Controllers/MapController.lua` |
| StarterPlayerScripts/Controllers/BikeAnimator | ModuleScript | `src/StarterPlayer/StarterPlayerScripts/Controllers/BikeAnimator.lua` |
| ReplicatedStorage/Shared/RigMeasure | ModuleScript | `src/ReplicatedStorage/Shared/RigMeasure.lua` |
| ReplicatedStorage/Shared/JobConfig | ModuleScript | `src/ReplicatedStorage/Shared/JobConfig.lua` |
| ServerScriptService/Services/JobService | ModuleScript | `src/ServerScriptService/Services/JobService.lua` |
| ServerScriptService/Services/JobSiteBuilder | ModuleScript | `src/ServerScriptService/Services/JobSiteBuilder.lua` |
| StarterPlayerScripts/Controllers/JobController | ModuleScript | `src/StarterPlayer/StarterPlayerScripts/Controllers/JobController.lua` |
| ReplicatedStorage/Shared/PizzaArt | ModuleScript | `src/ReplicatedStorage/Shared/PizzaArt.lua` |
| ServerScriptService/Services/ZoneService | ModuleScript | `src/ServerScriptService/Services/ZoneService.lua` |
| ServerScriptService/Services/SeatService | ModuleScript | `src/ServerScriptService/Services/SeatService.lua` |
| ServerScriptService/Services/CarBuilder | ModuleScript | `src/ServerScriptService/Services/CarBuilder.lua` |
| ServerScriptService/Services/MarketService | ModuleScript | `src/ServerScriptService/Services/MarketService.lua` |
| StarterPlayerScripts/Controllers/CarController | ModuleScript | `src/StarterPlayer/StarterPlayerScripts/Controllers/CarController.lua` |
| ServerScriptService/Services/NPCKit | ModuleScript | `src/ServerScriptService/Services/NPCKit.lua` |
| ServerScriptService/Services/CityNPCService | ModuleScript | `src/ServerScriptService/Services/CityNPCService.lua` |

O arquivo `.rbxlx` de cada marco é gerado de `src/` com `python3 tools/build_rbxlx.py src LittleLife_MarcoN.rbxlx`.

Criados pelo servidor ao rodar: `ReplicatedStorage/Remotes/` com `VehicleRequest`, `UIUpdate`, `TutorialRequest`, `JobRequest` (RemoteEvents), `leaderstats/Dinheiro` em cada jogador, atributos `Money`, `BonusReadyAt` e `Job` no Player, `Workspace/JobStations` (quadro, estações e pontos de entrega), `CarriedItem` no personagem que carrega algo, `Workspace/Map` (mapa inteiro) e `Workspace/NPCs/Seu Bento`.

## Decisões técnicas desta etapa
- **Mapa gerado por script** (MapBuilder) para o iniciante não precisar montar peça por peça. Se existir `Workspace/Map`, o script não reconstrói, então o mapa pode ser "congelado" e editado à mão depois.
- **Bicicleta inicial = modelo preso ao personagem + velocidade 30.** Simples, funciona em PC e celular. Veículos de verdade (VehicleSeat) ficam para o Marco 7.
- **MapBuilder** é um serviço novo, fora da lista original da arquitetura (seção 16), porque o mapa é gerado.
- **Anel de rua externo** liga o fim das 8 ruas para evitar ruas sem saída (seção 4.4).
- **Marco 2:** conversa via ProximityPrompt (E no PC, botão no celular, nativo do Roblox). Dados salvos em DataStore `LittleLifePlayerData_v1`, chave `Player_<UserId>`, formato `{version=1, tutorialDone=false}`. Se o carregamento falhar, a sessão não salva (não sobrescreve dados bons). Tutorial só começa quando os dados carregaram E o cliente mandou "Ready"; "Finish" só vale se o servidor iniciou o tutorial.
- Bike (desde 3.1): pose de pedalar procedural (sem asset de animação); ajuste fino do selim em `GameConfig.Bike.SeatOffsetY`. R6 não tem joelhos, então a perna fica reta mirando o pedal.
- **Marco 3:** dinheiro só muda pelo EconomyService (valida inteiro positivo e limite). Dados: `money` (inicial 100) e `lastBonusClaim` (os.time()). Bônus pago na primeira tarefa válida, salvo na hora, cooldown 24h desde o resgate. MissionService encerra a tarefa ANTES de pagar (sem pagamento duplo), checa distância e tempo mínimo de 5 s. Prompt de entrega é desligado no servidor e ligado localmente só para quem tem a tarefa.
- Interface escala com a menor dimensão da tela (720 px = 100%, mínimo 60%) via UIScaler.
- Atualização do jogo publicado: copiar as pastas Shared, ServerBootstrap+Services e ClientBootstrap+Controllers do .rbxlx para o jogo aberto e Ctrl+S. "Salvar na Roblox como" a partir dos .rbxlx gerados trava no upload (mesmo com Studio atualizado e disco livre); salvar o jogo já aberto da nuvem funciona. Causa não confirmada; hipótese: re-salvar como .rbxl antes de subir.
- NPC guia se chama **Seu Bento** (nome escolhido pelo Claude; pode trocar em GameConfig.Guide.Name).
- **Marco 4:** um único ciclo de tarefas (MissionService) para todas as profissões; cada profissão é só dados em JobConfig (estação, texto, tempo de segurar, espera, item carregado). Servidor valida: etapa atual, ponto certo, distância (12), tempo mínimo por etapa, espera do forno e, na entrega, tempo mínimo de viagem (distância / 45 studs/s) contra teleporte. Ciclo encerra ANTES de pagar. Profissão e tarefa são estado de sessão (não salvam). Prompts das estações desligados no servidor; o cliente liga só o da sua etapa. Morrer no meio recomeça o pedido.
- **Marco 4.3:** carro é físico mas "arcade": o chassi flutua (raycast para o chão) e quem dirige controla a física (SetNetworkOwner ao sentar); o servidor só cria, confere o dono e trava velocidade acima de 1,6× a máxima. Etapas podem ter ações especiais (onBegin/onDone/onCollect) registradas por outros serviços no MissionService (usado pelo MarketService). Profissões com `Lanes` dão um posto fixo para cada trabalhador (caixa 1/2). Viagem mínima nas entregas agora 95 studs/s (carro faz até 80).
- **Marco 5:** todo NPC passa pelo NPCKit. NPCs ficam no grupo de colisão "NPCs" (não esbarram em jogador nem carro) e o servidor é o dono da física deles. Animações tocadas pelo servidor com os ids padrão R15 do Roblox (idle 507766388, walk 507777826, wave 507770239, cheer 507770677, point 507770453). Reações do cliente ligadas às etapas por onDone em JobConfig (pizzaCustomerCome, pizzaCustomerReceive, deliveryThanks). Posições de funcionário/cliente por loja em JobSiteBuilder (SHOP_SPOTS → JobSiteBuilder.shops). Nomes dos funcionários (Giovanni, Dona Lúcia, Rafa, Bia) escolhidos pelo Claude: PROVISÓRIO.
- Remotes recebem só a intenção ("ToggleBike", "ToggleCar"); o servidor valida frequência, tipo e estado do personagem.

## Decisões confirmadas (do documento mestre)
Nomes oficiais dos locais; 16 jogadores e 16 vagas com a distribuição definida; bônus diário com cooldown de 24h após resgate, sem punir ausência; assalto com 2 a 3 ladrões e até 3 policiais; prisão de 60 s; fuga libera e preserva a recompensa; captura remove só a recompensa do assalto atual; sem caixas pagas aleatórias; profissões especiais com caminho gratuito.

## Decisões PROVISÓRIAS (pendentes)
1. Salários, valor do bônus diário e preços internos. Usando por enquanto: saldo inicial $100, bônus $50, pizza $30/$35 + gorjeta $10, mercearia: caixa $8 + $2/produto (+$3), repor $14/prateleira, limpeza $20 (+ gorjeta), entrega $12 por pacote + 0,03/stud + gorjeta.
2. Nível/condição do desbloqueio gratuito de Policial, Bombeiro e Ladrão.
3. Assalto: 10 min de duração e 15 min de cooldown (valores de teste).
4. Condição final de extração do assalto (recomendação: zona de fuga antes do tempo acabar).
5. Fórmula de divisão da recompensa e critérios do bônus policial.
6. Nome da joalheria (sugestões: Brilho de Kinder, Joias Estrela, Ouro da Praça).
7. Preços em Robux (tabelas de referência).
8. Escala do mapa (20 casas no bairro inicial já implementadas como fachadas).
10. Nome do jogo no mundo: letreiro colorido com GameConfig.CityName na praça (feito na 4.4); texto pode mudar.
12. Carro: 1 modelo grátis para todos por enquanto (para testes); compra/garagem e outros modelos depois (Marco 7). Nomes das ruas escolhidos pelo Claude (trocar em GameConfig.Map.StreetNames).
11. Layout dos interiores das lojas; entrega na porta das casas (destinatário NPC no Marco 5); sem fila para vaga lotada; tempo do forno 5 s.
9. Velocidade da bicicleta (30) e posições das lojas: valores do Marco 1, ajustar após teste.

## Testes executados
- Marco 1: testado no Studio pelo Luís, tudo funcionou. Aviso `FoundationProvider not found` (UIBlox) é do próprio Roblox, ignorar.
- Marco 2: testado no Studio (PC e emulador de celular) pelo Luís, tudo funcionou.
- Marco 3: testado no Studio pelo Luís, tudo funcionou.
- Marco 3.1: testado pelo Luís em 2026-10-20 (mapa, botão-ícone, bike, mãos fixas): funcionando.
- Marco 4: testado pelo Luís (3 profissões ok). Teste de vagas com 3 jogadores ainda não confirmado.
- Marco 4.1: testado pelo Luís (interiores e vagas ok).
- Marco 4.2: testado pelo Luís (aprovado, com 9 pedidos de ajuste).
- Marco 4.3: testado pelo Luís (carro não andava; resto ok).
- Marco 4.4 + 5: checagem de sintaxe (lupa) + variáveis indefinidas (luaparser). Não testado no Studio.

## Próximos passos
1. Luís testa o Marco 5 (carro andando e portas, praça nova, funcionários, cliente da pizzaria, morador na entrega, pessoas na praça, desempenho no celular). Riscos: dirigibilidade do carro (GameConfig.Cars), cabeça no teto do carro, telhado do coreto (WedgeParts), NPC travando no caminho, animações padrão não tocando no NPC, desempenho (~10 mil peças + NPCs).
2. Marco 6 — Moradia (propriedade persistente, interior reutilizável), depois de aprovado o 5.
