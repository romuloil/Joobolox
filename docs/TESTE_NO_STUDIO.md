# Teste no Roblox Studio — Marco 5.2

Abra `LittleLife_Marco5_2.rbxlx` e use **Play / F5**, com o painel **Output / Saída**
aberto. O cenário é gerado ao iniciar. Use Play com personagem, não apenas Run.

## Primeiro passeio

1. Confira praça, árvore com raízes, bicicleta/B, carro/V e mapa/M.
2. Visite a delegacia na cidade. A interação **Plantão policial** abre o painel.
3. Entre em serviço e retire os quatro equipamentos na armaria. Confira o colete.
4. Siga a avenida para fora da cidade até a prisão. Confira muros, cores, quatro
   torres, recepção, celas, armaria, controle, quadra, refeitório e enfermaria.
5. Como policial, use E nos acessos para abrir os portões e salas. Suba cada torre:
   confira passagem da porta, lances de escada, patamares e chegada à cabine.
6. No controle, opere portas e celas. O fechamento deve ser recusado se a passagem
   estiver ocupada. Celas ocupadas respeitam os 15 s iniciais de lacre.

## Equipamentos e trabalho

- Selecione ferramentas pela mochila/teclas numéricas. No celular, use o botão de
  ferramenta e mire pelo centro da tela.
- Confira a lanterna acendendo/apagando e o rádio consultando os informes.
- No terminal de ocorrências, registre um informe por categoria e confira no rádio.
  Longe do terminal, a consulta pelo rádio não deve oferecer escrita.
- Registre a ronda nos quatro setores em ordem. Ao terminar, deve aparecer um informe.
- Na área de treinamento, use **Iniciar treino**. Equipe o lançador, acerte o alvo
  laranja, aproxime-se e equipe/use as algemas antes de acabar a imobilização.
- Um mesmo policial não deve duplicar o kit ou seu alvo de treino. Sair do plantão
  deve retirar uniforme, ferramentas e alvo; a vaga é liberada.

## Cela e soltura

1. Saia do plantão. Na delegacia, use **Simular prisão (Studio)**.
2. Confira que vai para uma cela individual, com porta fechada e identificação.
3. Antes de 15 s, não deve alcançar o corredor nem iniciar a fuga.
4. Aos 15 s, a porta deve abrir e liberar o acesso ao pátio.
5. Aguarde a pena total de 60 s: a soltura deve acontecer uma vez, no exterior,
   e o personagem deve voltar a andar normalmente. O dinheiro não muda.
6. Em outra tentativa, conclua as três interações de manutenção em ordem: a fuga
   deve liberar imediatamente. Pular/repetir etapas não deve liberar novamente.
7. Resete o personagem durante o lacre: mesma cela e mesmos prazos, sem reinício.
8. Teste bike, carro e carona durante a detenção: devem permanecer bloqueados.

## Dois ou mais jogadores

- Use o teste com servidor e clientes do Studio. Há três vagas policiais; o quarto
  candidato deve receber recusa e conseguir entrar quando outro sair.
- Um civil usa **Simular suspeito (Studio)** na recepção da prisão. Outro jogador,
  policial com kit, usa água, aproxima-se e algema: o suspeito vai para uma cela.
- Cidadão sem suspeita válida não deve ser imobilizado/preso; através de parede,
  longe demais ou sem algemas equipadas, a captura também deve falhar.
- Durante a água, B/V/sentar não podem permitir fuga por veículo. Depois da pena,
  confira movimento e pulo normais, inclusive se o alvo estava de bicicleta antes.
- As celas e os prazos dos detidos devem ser independentes. Uma porta fechada pelo
  policial não prolonga a pena. Desconexão libera vaga de policial/cela.
- As duas simulações voluntárias de jogador só devem aparecer no Studio.

## Regressão e celular

Conclua pedidos de pizza, mercado e entrega; confira NPCs, mapa, carro e bike.
Use o emulador de celular para verificar painéis, mira, botão de ferramenta,
interações e sobreposição de botões. Registre desempenho e erros completos do Output.

O heliponto, a conveniência, a quadra e os móveis são cenográficos; não há voo,
combustível, minigame de basquete ou sistema médico nesta etapa. Eventos de banco
continuam futuros: o treino e a simulação permitem testar a polícia já implementada.
