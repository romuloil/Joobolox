# Registro de continuidade — Marco 5.3

## Pedido

Afastar o posto da fuga, tornar a saída mais espaçosa e discreta; realocar e remodelar
a delegacia em terreno visível; adicionar moradores parados com interação; criar sede,
emprego e veículo LXR Táxis; relacionar uniformes e veículos à profissão de cada jogador.
Foram utilizadas as imagens enviadas como referência de cores, volumes e identidade.

## Mapa

- Delegacia em `(100, 0, -440)`, de frente para a avenida, com lote reservado antes da
  geração de imóveis. Fachada azul/branca, painéis de vidro, vestiário e três vagas.
- LXR em `(-100, 0, 440)`, amarela, com nome azul, despacho, vestiário e três vagas.
- Posto em `(-420, 0, -830)`, a aproximadamente 374 studs da última etapa da fuga.
  Estrada separada, conveniência acessível e duas vagas de garagem pessoal.
- Passagem técnica mais larga e neutra; trilha entre a saída e o posto, sem ligá-los
  diretamente por um corredor exposto. Estradas não atravessam a recepção da prisão.
- Seis pontos de táxi e oito moradores fixos distribuídos pelas ruas radiais.

## Autoridade de emprego e uniforme

`WorkRoleService` é a fonte do servidor para a profissão. `JobService`, `PoliceService`
e `TaxiService` atribuem e removem o cargo. Atributos do cliente não concedem acesso.
`WorkplaceBuilder` acrescenta vestiários aos três empregos antigos; `CivicBuilder`
fornece os vestiários/garagens da polícia e da LXR.

Uniformes originais são montados para R6/R15, sem IDs de roupas externos. Há roupa e
chapéu de policial, taxista, pizzaiolo, atendente e entregador. Roupas clássicas e
acessórios de cabeça substituídos temporariamente são restaurados ao devolver a roupa.
Troca, desligamento e detenção encerram o empréstimo; morte/reset removem a roupa.
O comportamento de emprego dos serviços antigos durante reset foi preservado.

## Veículos

O Vortex permanece pessoal. Táxi e viatura usam sedãs próprios de quatro portas,
com física arcade baseada no controlador existente. Apenas as garagens da profissão
fornecem esses modelos; dono, cargo e estado do jogador são conferidos no servidor.
O botão V não realoca carro profissional. A garagem do posto entrega só o carro
pessoal já concedido no protótipo; não cria compras nem posse de outros modelos.
Veículos profissionais são recolhidos ao encerrar o cargo, morrer ou ser detido.

## Táxi e NPCs

Duas vagas de taxista. Despacho gera um passageiro e um trajeto entre pontos distintos.
Embarque/desembarque exigem táxi correto, motorista ao volante, proximidade e carro
parado. O servidor verifica tempo e deslocamento e encerra o pedido antes de pagar.
O bônus diário é chamado somente após pagamento válido. Valores são provisórios.
O passageiro visual acompanha o banco sem soldar ou ancorar o carro, e o banco fica
reservado durante a corrida. Sair do turno, perder carro/emprego, resetar ou cancelar
remove o passageiro e a corrida.

Moradores usam o NPCKit já existente, ficam parados nas calçadas reais e têm conversas
por proximidade, com falas preparadas e gestos. Inicialização assíncrona e limite
compartilhado de 30 NPCs preservado. Não há criação de NPC por comando do cliente.

## Limites e continuação

O táxi é um protótipo com passageiros NPCs e despacho na sede. Não há chamadas de
jogadores, frota comprável, sirene de áudio, combustível ou novo sistema de posse.
A aparência, dirigibilidade, roupas e passageiro precisam de teste no Studio.
Os resultados automatizados estão em `VALIDACAO.md` e o roteiro em `TESTE_NO_STUDIO.md`.
A nova entrega preserva os arquivos dos Marcos 5.1 e 5.2 no GitHub.
