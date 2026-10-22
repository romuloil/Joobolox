# Little Life: Minha Cidade — Marco 5.4

Prisão reorganizada com interiores acessíveis, roupa de custódia automática,
atividades e novas funções policiais. A cidade, a LXR Táxis e os empregos do Marco
5.3 continuam incluídos.

## Baixar e testar

- [Baixar o jogo .rbxlx](https://github.com/romuloil/Joobolox/raw/refs/heads/entrega-marco5-4/entregas/Marco5_4/LittleLife_Marco5_4.rbxlx)
- [Baixar jogo, códigos e instruções .zip](https://github.com/romuloil/Joobolox/raw/refs/heads/entrega-marco5-4/entregas/Marco5_4/LittleLife_Marco5_4_Pacote.zip)

Abra o arquivo no **Roblox Studio → Arquivo → Abrir do arquivo** e pressione **Play / F5**.
O cenário é construído quando o teste inicia; a cena pode aparecer vazia antes disso.
O aplicativo Roblox Player não abre arquivos `.rbxlx` diretamente.

**M** abre o mapa, **B** usa a bicicleta, **V** usa o carro. Interações locais usam
**E** ou toque no celular. Para testar captura e furto de cartão, use o teste de
servidor com dois jogadores no Studio; há um roteiro em `docs/TESTE_NO_STUDIO.md`.

## Prisão

- Base policial azul com faixas ciano, três pavimentos acessíveis, escadas, sala de
  operações, comando, terminais e cobertura com heliponto cenográfico.
- Pavilhão de visitas vermelho/branco com cadastro local, bancos e divisórias;
  garagem coberta com três vagas e saídas livres para viaturas.
- Dezesseis celas individuais fechadas, com roupa laranja automática ao ser preso.
  A roupa civil é restaurada ao cumprir a pena ou concluir a fuga. Resetar conserva
  a pena e reaplica o uniforme, inclusive após carregar a aparência do avatar.
- Bloqueio inicial da cela de **5 segundos**, seguido de circulação pelo complexo.
  A pena continua em **60 segundos**, configurável em `CivicConfig`.
- Refeitório serve refeições (+10 de saúde, intervalo de 30 s), enfermaria oferece
  atendimento (+25, intervalo de 45 s) e exercícios têm séries de 4 s. A saúde nunca
  ultrapassa o máximo do personagem. Exercícios registram a série, sem dinheiro.
- Segure E atrás de um policial para tentar pegar o cartão de acesso. O servidor
  confere posição, direção, visibilidade e duração. O policial recebe aviso após
  um segundo. Guarde ou retire o cartão na gaveta da sua própria cela.
- Leitores liberam portas por alguns segundos e aguardam a passagem ficar livre
  para fechar. Entrar em áreas restritas gera ocorrência mesmo por uma porta aberta.

## Polícia

Retire uniforme no vestiário e equipamentos no arsenal, após entrar em plantão.
O uniforme tem camisa azul, calça preta, gravata, distintivo e quepe. O kit inclui
pistola, taser, algemas, barreira de pneus, lançador de água, lanterna e rádio.
Uniformes, armas e viaturas permanecem vinculados ao emprego.

Taser/água imobilizam procurados; algemas de perto iniciam transferência de **10 s**.
A pistola causa dano em procurados; alvos mortos não podem ser capturados. Civis e
presos sem infração não recebem dano. Tentativas indevidas com algemas, taser ou
pistola geram multa de até $25; três advertências encerram o plantão e levam à prisão.

Algemas também retiram procurados de veículos próximos. A barreira reduz por 8 s a
velocidade do carro de um procurado que passa sobre ela. Informes, rondas, treino,
rádio e painel de portas/celas continuam disponíveis.

Fuga e infrações são registradas no servidor. A recompensa só é paga uma vez após
uma captura externa concluída; recaptura interna e simulação do Studio não pagam.
O aviso aparece na interface dos jogadores. Valores e tempos são provisórios.

## Código e validação

```sh
python3 tools/build_rbxlx.py src dist/LittleLife_Marco5_4.rbxlx
python3 tools/validate_luau.py --luau-dir /caminho/para/luau
```

O gerador precisa apenas de Python 3. No Windows, use `python` se necessário.
Consulte `docs/VALIDACAO.md`, `docs/REGISTRO_MARCO5_4.md` e o roteiro de teste.

O Roblox Studio não está disponível no ambiente Linux: os testes automatizados
usam objetos simulados. Aparência, física, rede, celular e desempenho ainda precisam
ser conferidos no Studio. As imagens enviadas serviram como referência para uma
adaptação própria. O heliponto não fornece helicóptero; não há nova ala de segurança
máxima, jetpack, resgate de algemas por amigos ou inventário de itens compráveis.
As gavetas guardam somente o cartão durante a pena, sem persistência entre sessões.
