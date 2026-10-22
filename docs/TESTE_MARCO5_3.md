# Roteiro de teste — Marco 5.3

Abra `LittleLife_Marco5_3.rbxlx` no Roblox Studio e use **Play / F5**, com
**Output / Saída** aberto. O mapa é gerado ao iniciar.

## Locais

- Use M: delegacia ao norte e LXR Táxis ao sul, em terrenos de frente para avenidas.
- Entre na nova delegacia, visite recepção, informes, armaria, vestiário e pátio.
- Confira sede LXR amarela, nome azul, recepção, vestiário, despacho e vagas.
- Refaça a fuga da prisão: corredor mais largo, aparência neutra e trilha discreta.
  O posto deve estar separado da saída, com estrada própria.
- No posto, use a garagem pessoal. Deve receber o Vortex disponível no protótipo,
  sem ganhar uma viatura ou táxi profissional.

## Uniformes e profissões

1. Entre como pizzaiolo pelo quadro da praça e retire roupa no vestiário da pizzaria.
2. Tente retirar roupa do mercado, polícia ou LXR: deve receber recusa.
3. Troque para atendente: uniforme antigo devolvido; o novo só sai no mercado.
4. Repita como entregador e confira roupa/boné diferentes.
5. Entre em plantão policial e retire o uniforme azul no vestiário, kit na armaria
   e viatura na garagem. A roupa não deve aparecer automaticamente longe do vestiário.
6. Encerre o plantão: uniforme, ferramentas e viatura são recolhidos. Confira que as
   roupas originais do avatar voltam, inclusive após reset e detenção.
7. Teste R6 e R15, chapéus/cabelos e roupas de seu avatar para identificar recortes.

## LXR Táxis

1. Entre no emprego no balcão LXR; retire uniforme e táxi amarelo na empresa.
2. Confira nome/cores, quatro portas, placa de teto e dirigibilidade.
3. Use V para sair do carro, vá ao despacho e aceite uma corrida; volte ao táxi.
4. Siga o ponto laranja no mapa. Pare perto do passageiro, ao volante, e use E/toque
   em **Embarcar passageiro**. O NPC deve ficar sentado no banco direito.
5. Dirija ao destino, pare e use **Concluir corrida**. Confira pagamento uma vez,
   passageiro saindo e bônus diário apenas se ele já estiver disponível.
6. Repita a interação: não pode pagar novamente. Volte ao despacho para outra corrida.
7. Cancele uma corrida, saia do emprego e resete: passageiro/estado são removidos.
8. Com NPC embarcado, outro jogador não deve ocupar o mesmo banco.

## Garagens e autorização

- Sem emprego, tente retirar táxi/viatura: deve ser recusado.
- Como taxista, não pode retirar viatura; como policial, não pode retirar táxi.
- V pode entrar/sair de um veículo de trabalho próximo, mas não trazê-lo de longe.
- Saia do cargo longe da garagem: o carro de trabalho é recolhido.
- Ocupação das vagas deve impedir sobreposição de carros. Teste com dois clientes.
- A garagem pessoal não concede modelos comprados nem veículos de outros empregos.

## Moradores

Percorra as oito ruas e converse com os moradores parados nas calçadas. Confira
falas, gestos, orientação e variedade. Eles não devem surgir em portas, acessos ou
na pista, andar pela cidade, duplicar ao reiniciar serviços ou bloquear jogadores.

## Multiplayer, regressão e celular

Há duas vagas de táxi e três policiais. Confira lotação e liberação ao sair.
Uma profissão não pode coexistir com outra. Finalize uma tarefa de pizza, mercado
e entrega; teste as funções da polícia, as 16 celas, o lacre de 15 s e a pena de 60 s.
Use o emulador de celular para painéis, mira, botões de ferramenta, uniforme e corrida.
Confira NPCs, bike, Vortex, mapa, salvamento e desempenho. Copie erros completos do Output.

O táxi é um protótipo com passageiros NPCs. Não há chamadas de jogadores, frota
comprável, combustível, sirene de áudio ou sistema completo de assaltos nesta etapa.
