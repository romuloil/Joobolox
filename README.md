# Little Life: Minha Cidade — Marco 5.3

Continuação do Marco 5.2: delegacia em lote aberto, posto afastado da fuga, moradores
fixos, LXR Táxis e regras comuns de uniformes e veículos de trabalho.

## Downloads

- [Jogo para abrir no Roblox Studio](https://github.com/romuloil/Joobolox/raw/refs/heads/entrega-marco5-3/entregas/Marco5_3/LittleLife_Marco5_3.rbxlx)
- [Pacote com jogo, códigos e instruções](https://github.com/romuloil/Joobolox/raw/refs/heads/entrega-marco5-3/entregas/Marco5_3/LittleLife_Marco5_3_Pacote.zip)

Abra o `.rbxlx` no Roblox Studio e use **Play / F5**. O cenário é construído ao iniciar.
**M** abre o mapa, **B** controla a bike, **V** entra/sai de um carro próximo ou usa o
carro pessoal. As interações usam **E** e têm botões equivalentes no celular.

## Cidade e locais novos

A delegacia fica de frente para a avenida norte, em terreno reservado entre os anéis,
com fachada azul/branca, vidraças, vestiário e pátio de viaturas. A sede amarela da
**LXR Táxis**, com identificação azul, fica junto da avenida sul, também em lote livre.

O posto foi deslocado: fica a cerca de **374 studs** do último ponto da fuga, com
estrada própria e garagem de carro pessoal. A passagem técnica ficou mais larga e
neutra, seguida de uma trilha mais discreta. O posto não fornece veículos de emprego.
O Vortex é o carro pessoal já disponível no protótipo; não foi criado um sistema de
compra ou coleção de veículos.

Oito moradores parados nas calçadas reutilizam o `NPCKit` existente. Use **Conversar**
para ouvir dicas sobre a rua, o mapa e as profissões. Eles respeitam o limite de NPCs
compartilhado com os demais sistemas.

## Uniformes e carros profissionais

A profissão é validada pelo servidor. Uniforme só sai do vestiário correspondente e
veículo profissional só sai da garagem do emprego enquanto o jogador trabalha nele.
Sair ou trocar de emprego recolhe o uniforme e o veículo vinculado. Não é possível
ter duas profissões ao mesmo tempo.

Há uniformes próprios de policial, taxista, pizzaiolo, atendente e entregador.
As roupas originais do avatar são restauradas ao devolver o uniforme. Após morrer ou
resetar, é necessário retirar a roupa novamente; o plantão policial/táxi é encerrado.
Nas profissões antigas, o emprego pode continuar, como no marco anterior.

A LXR tem um sedã amarelo próprio, identificação azul, faixa xadrez e letreiro de táxi.
A polícia tem viatura azul/branca com giroflex visual. Não há sirene de áudio nesta
versão. **V não transporta um carro de trabalho até o jogador**: volte ao veículo ou
à garagem da profissão. Motorista e carro são vinculados ao mesmo dono e profissão.

## Trabalhar como taxista

1. Vá à sede LXR e use **Trabalhar como taxista**. Há duas vagas no protótipo.
2. Retire o uniforme no vestiário e o táxi na garagem externa.
3. Saia do carro com V, volte ao balcão de despacho e aceite uma corrida.
4. Retorne ao seu táxi e siga o destino laranja no mapa.
5. Pare junto ao passageiro, permaneça ao volante e use **Embarcar passageiro**.
6. Dirija ao destino, pare e use **Concluir corrida**. A viagem é validada pelo servidor
   e paga uma vez. O bônus diário existente pode ser resgatado após uma corrida válida.
7. Volte ao despacho para outra corrida. Há cancelamento e saída do turno na interface.

São seis pontos de origem/destino. Corridas são de NPCs nesta etapa: não há chamada de
táxi por outros jogadores, taxímetro comercial ou sistema de compra de frota.
A remuneração é provisória e configurável em `TaxiConfig`.

## Polícia e prisão

O plantão, arsenal, informes, rádio, rondas, treino e controles continuam disponíveis.
Retire o uniforme no vestiário e a viatura na garagem da delegacia ou da prisão.
As 16 celas, lacre inicial de 15 s, pena de 60 s e rota de fuga seguem funcionando.
Banco/assaltos completos ainda são uma etapa futura; não se prende um civil livremente.
As simulações voluntárias de prisão/suspeito permanecem exclusivas do Studio.

## Código e testes

```sh
python3 tools/build_rbxlx.py src dist/LittleLife_Marco5_3.rbxlx
```

O gerador só precisa de Python 3. No Windows, use `python` se `python3` não existir.
Os scripts seguem os caminhos do Roblox em `src/`. Confira `docs/TESTE_NO_STUDIO.md`,
`docs/VALIDACAO.md` e `docs/REGISTRO_MARCO5_3.md`.

Não houve execução do Roblox Studio no ambiente Linux. Testes automatizados verificam
código e decisões com objetos simulados; aparência, física, rede e desempenho precisam
ser conferidos no Studio, especialmente os sedãs, os uniformes e o passageiro sentado.
