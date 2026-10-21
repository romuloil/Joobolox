# Registro de continuidade — Marco 5.2

## Pedido e referência

Prisão mais complexa inspirada na imagem enviada: paredes claras com faixas azuis,
blocos de telhado laranja, torres de vigilância e espaços internos organizados.
Também foram solicitados equipamentos, informes e funções policiais.

## Construção

`PrisonBuilder` substitui o bloco simples do Marco 5.1 e conserva a delegacia urbana,
a estrada e as árvores orgânicas. O complexo fica no mesmo ponto afastado da cidade.
Há quatro torres, 16 celas individuais fechadas, recepção/visitas, armaria, controle,
refeitório, enfermaria, quadra, iluminação e sinalização. Heliponto e posto são
cenográficos. O terreno continua dividido em placas dentro do limite do Roblox.

As celas reservam uma vaga individual por jogador. O lacre inicial dura 15 s;
o prazo total permanece 60 s. Reset e recuperação após movimento inválido preservam
ambos os prazos. A manutenção é uma rota fixa de fuga com três interações. Portas
não fecham em cima de personagens e nenhuma ação policial prolonga a pena.

## Polícia

Novo `PoliceService`, com `PoliceConfig`, `PoliceRules` e `PoliceController`:

- Três vagas, colete azul/distintivo, entrada nos balcões da delegacia e prisão.
- Quatro ferramentas originais: lançador de água, algemas, lanterna e rádio.
- Água imobiliza por 6 s; captura exige suspeito marcado por serviço do servidor,
  imobilização válida, equipamento, proximidade e linha de visão.
- Informes por categorias com histórico de até 24 registros na sessão; consulta
  pelo rádio, escrita no terminal.
- Ronda por quatro setores e alvo móvel individual para treino de abordagem.
- Controles de portões e salas por proximidade/painel; celas pelo centro de controle.
- Fora de serviço, reset ou desconexão removem kit e liberam vaga.
- O cliente envia intenções; papel, distância, equipamento, cooldown, porta e captura
  são decididos no servidor. Não há remoto para criar um suspeito arbitrário.

O servidor fornece `markSuspect(player, reason, duration)` para futuros eventos de
crime. Por enquanto, há treino com NPC e cenário voluntário de suspeito no Studio.
Banco/assalto, pagamentos policiais, multas, combate letal, viaturas próprias e voo
não fazem parte desta versão. As simulações de jogadores ficam desabilitadas fora
do Studio. Prisão e plantão são estados da sessão, não dados permanentes.

## Integração e correções

- Novos controles respeitam `PoliceDuty`, `Detained` e `StunnedUntil`.
- Entrar em plantão encerra o emprego anterior. Novo emprego exige sair do plantão.
- Água guarda veículos e retira o jogador do banco antes de imobilizar; B/V/carona
  não contornam o estado.
- A prisão não restaura velocidade temporária zero depois de uma captura por água.
- Foram revisados acessos públicos, armaria, controle, torres, celas e fuga contra
  paredes que poderiam continuar bloqueando portas mesmo depois de abertas.
- O DataStore, o dinheiro e as recompensas das profissões existentes foram preservados.

## Entrega

`LittleLife_Marco5_2.rbxlx` e pacote ZIP separado. A entrega no GitHub usa uma nova
branch, mantendo disponível o Marco 5.1. A validação automatizada está registrada
em `VALIDACAO.md`; a verificação visual/física no Studio continua pendente.
