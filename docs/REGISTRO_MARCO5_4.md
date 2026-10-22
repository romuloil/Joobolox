# Registro de continuidade — Marco 5.4

## Pedido e referências

Organizar os interiores da prisão, tornar objetos funcionais, adaptar o uniforme
policial e vestir/restaurar automaticamente o uniforme laranja do preso. As imagens
e os trechos enviados sobre Jailbreak foram usados como referência de organização,
cores e interações. Os anexos repetidos foram lidos como material de referência;
descrições de bugs e conteúdo removido daquele jogo não viraram requisitos.

## Arquitetura e interiores

`PrisonBuilder` agora constrói três pavimentos reais na base policial: recepção,
operações e comando. Há escadas de dois lances, pisos com aberturas, guarda-corpos,
vidraças, faixas ciano e cobertura acessível com heliponto cenográfico. Os terminais
superiores usam as APIs existentes de informes e controle de portas.

O pavilhão de visitas tem identidade vermelho/branco, recepção, bancos, mesas e
vidros divisórios. A garagem tem três vagas cobertas; as 16 celas receberam gavetas,
mesas e cadeiras. Refeitório, enfermaria e área de exercícios têm pontos funcionais.
A parte interna continua separada por portões físicos. A saída legal fica fora dos
limites de custódia, junto ao acesso rodoviário. Os limites incluem os novos andares.

## Roupas

`PrisonOutfitService` monta macacão laranja original para R 6/R 15 com costuras, gola,
bolsos e zíper. Guarda as propriedades originais das roupas clássicas e dos acessórios
em camadas, reaplica a roupa após carregar a aparência e restaura os objetos ao sair.
`PrisonService` controla a aplicação, a recaptura, os resets e a devolução. A roupa
profissional é removida antes de vestir a roupa de custódia.

O uniforme policial usa camisa azul, calça preta, gravata, bolsos, distintivo e quepe.
Permanece disponível somente no vestiário e para quem tem o emprego correspondente.

## Atividades e cartão

`PrisonActivityConfig`, `PrisonActivityRules` e `PrisonActivityService` concentram
as funções. Não há remoto para conceder cartão, cura ou crime. Prompts nativos são
validados com personagem vivo, estado, distância, visibilidade e intervalo.

Refeição cura 10 com intervalo 30 s; atendimento cura 25 com intervalo 45 s; série de
exercício dura 4 s com intervalo 20 s. A série é cancelada ao se afastar; não paga dinheiro.
A visita registra presença local e oferece assentos, sem liberar áreas protegidas.

Furtar cartão exige segurar E por 2,5 s atrás de policial em serviço, até 4,5 studs,
olhando para ele e sem parede. Posição e direção são verificadas durante o gesto.
O policial recebe aviso após 1 s. Um preso não acumula cartões. A gaveta é vinculada
à própria cela e só guarda o cartão. Soltura, morte e recaptura removem os objetos.

Leitores abrem portas por 6 s, aguardando a passagem desocupada para fechar. Polícia e
leitores compartilham os mesmos descritores de portas; ações novas cancelam fechamentos
antigos. A entrada física em áreas restritas é monitorada, inclusive ao seguir alguém
por uma porta aberta. Cartão não concede cargo, uniforme, armas ou viatura.

## Abordagem e polícia

O bloqueio inicial da cela passou a 5 s; a pena continua 60 s. Água e taser imobilizam
procurados. Algemas exigem proximidade e visibilidade e iniciam custódia de 10 s antes
da transferência. Recaptura interna retorna à mesma cela sem reiniciar a pena.
Morte, troca de personagem e fim do plantão cancelam custódias pendentes. Reset não
apaga uma ocorrência ativa; soltura normal apaga, fuga registra nova ocorrência.

A pistola causa 18 de dano em procurados e nenhum dano em inocentes. Tentativas
indevidas com algemas/taser/pistola geram multa de até 25, limitada ao saldo, e três
advertências retiram o cargo e solicitam detenção. Alvos mortos não podem ser presos.
O kit também inclui água, lanterna, rádio e barreira de pneus.

A barreira dura 40 s e afeta apenas o carro de um procurado, limitando a velocidade
horizontal a 12 studs/s durante 8 s. `VehicleService` valida o motorista real, limita o
atuador e a velocidade no servidor; o controlador do carro apresenta o efeito.
Algemas retiram um procurado próximo de um assento de veículo registrado.

Recompensas usam ocorrências criadas no servidor, teto 100 e consumo antes do pagamento.
Simulações no Studio e recapturas internas não pagam; a interface anuncia o pagamento
válido para os jogadores. Não há envio de mensagens a serviços externos.

## Continuidade e limites

O Marco 5.3 completo permanece incluído, com LXR, uniformes por emprego, carros,
moradores, posto afastado e trilha de fuga. O heliponto é cenográfico. Não há helicóptero,
jetpack, ala de segurança máxima, resgate de algemas, compra de itens, armas para presos
ou sistema completo de assaltos. A visita é cadastro e assentos; o exercício registra
uma série sem animar automaticamente o avatar. Cartões e custódia são estado de sessão.

O Roblox Studio não foi executado na nuvem. Testes de geometria e serviços usam
objetos simulados; aparência, física, rede e desempenho exigem teste no Studio.
