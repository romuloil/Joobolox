# Roteiro de teste — Marco 5.4

Abra `LittleLife_Marco5_4.rbxlx` no Roblox Studio e pressione F5. Mantenha
**Output / Saída** aberto. O mapa é gerado ao iniciar.

## Primeiro teste, sozinho

1. Use M e vá à delegacia da avenida norte. O terminal **Simular prisão (Studio)**
   fica na recepção e leva seu jogador à primeira cela disponível.
2. Confira roupa laranja, uniforme civil oculto e contagem de 60 s. Nos primeiros
   5 s a porta está fechada; depois abre para circular pelo pátio.
3. Vá ao refeitório e use **Pegar refeição**. Teste a enfermaria após reduzir a
   saúde no teste local. Ambos têm intervalo e respeitam a saúde máxima.
4. Inicie uma série no pátio e permaneça perto do aparelho por 4 s. Repita saindo
   do local: a série deve ser cancelada. Não há recompensa monetária por exercício.
5. Espere a pena terminar: roupa normal restaurada e jogador liberado na recepção.
6. Repita a simulação e use Reset durante a pena: a roupa laranja volta, mas o
   prazo original da pena permanece. Teste R6, R15 e roupas em camadas do avatar.
7. Repita e conclua os três pontos da fuga. A roupa civil volta e o jogador fica
   procurado por 120 s. A fuga de uma simulação não concede recompensa de captura.

## Visitar como policial

1. Entre em plantão no balcão da delegacia ou da prisão. Pegue uniforme no vestiário,
   kit no arsenal e viatura na garagem. Verifique que cada retirada exige o cargo.
2. Na base da prisão, abra o acesso às escadas. Suba ao segundo pavimento, use o
   painel de operações, siga ao comando e registre um informe. Suba à cobertura.
3. Teste portas pelo leitor e pelo painel. Afaste o personagem antes de fechar.
   Abra/feche uma cela após o bloqueio de 5 s; o painel não deve estender a pena.
4. Retire viatura em cada uma das três vagas e confira a saída pela frente da garagem.
5. Visite o pavilhão vermelho/branco e registre uma visita; use os bancos.
6. Faça a ronda e o treino de abordagem. Ambos devem continuar funcionando.

## Dois jogadores

Use a opção de teste com servidor local e dois clientes do Roblox Studio.

1. A entra como policial, pega uniforme e kit; B usa a simulação de prisão.
2. Após abrir a cela, B fica atrás de A e segura E por 2,5 s. Deve receber um cartão
   e ficar procurado. A recebe o aviso depois de 1 s. Tente de frente, através de
   parede e interrompendo o gesto: o cartão não deve ser concedido.
3. B guarda/retira o cartão na própria gaveta. A gaveta de outro preso não funciona.
4. B usa o leitor da armaria ou do controle. O cartão abre a porta, mas não fornece
   roupa, arma nem viatura. Entrar pela porta já aberta também gera ocorrência.
5. A usa taser/água em B, aproxima-se e algema. A transferência leva 10 s; volta à
   mesma cela, conserva o prazo original e recolhe o cartão, sem pagar recompensa.
6. Teste A encerrando o plantão durante a transferência: B deve ser desalgemado.
7. Fora da prisão, B pode usar o terminal **Simular suspeito (Studio)** na base.
   Teste taser, algemas e transferência para a cela; simulações não pagam recompensa.
8. Para a barreira, B dirige o carro pessoal enquanto procurado. A equipa a barreira
   e a coloca na pista, a pé. B passa sobre ela: o carro fica lento por 8 s. Carros
   de inocentes e policiais não devem ser afetados. Teste expulsão do carro com E
   enquanto A segura algemas e está perto de B.
9. Teste pistola contra procurado (18 de dano por acerto) e inocente (sem dano).
   Três tentativas indevidas penalizam A, retiram o cargo e o prendem. O saldo não
   fica negativo. Um personagem morto não deve ser preso.
10. Para verificar recompensa de fuga fora da simulação, use uma captura normal ou
    a detenção por abuso, conclua a fuga e recapture. O pagamento ocorre uma vez;
    repetir o comando não paga de novo. Confira também lotação das 16 celas.

## Regressão e celular

Execute também `TESTE_MARCO5_3.md`, considerando agora cela fechada por 5 s.
Confira táxi, NPCs, pizza/mercado/entregas, bike, Vortex, mapa e salvamento.
Teste no emulador de celular as ferramentas, os leitores, o furto e os uniformes.
Observe câmera, colisões de avatares, roupas em camadas, dirigibilidade e desempenho.
Copie erros completos do Output para correção.

O heliponto é cenográfico; os visitantes têm cadastro e assentos, sem agenda ou
conversa privada entre jogadores. Não foram implementados helicóptero, jetpack,
segurança máxima, assalto ao banco, resgate de algemas ou compra de itens.
