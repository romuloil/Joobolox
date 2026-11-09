# Little Life — metrópole com o banco preservado

**Arquivo único:** `LittleLife_Metropole_Banco_Preservado.rbxl`. Abra no Roblox Studio e use **Jogar (F5)**. O cenário é construído durante a inicialização da sessão.

A base desta entrega é **o novo `LittleLife_Banco_Corrigido.rbxl` enviado pelo usuário em 09/11/2026**. Os modelos e demais objetos desse upload foram mantidos.

## Banco: causa e correção

Na expansão anterior, a Estrada do Vale passou de estrada para avenida com calçadas. A faixa de ocupação da rua aumentou de 31 para 37 studs. O lote original do banco passou a intersectar essa faixa em 1,9 stud, e `BankBuilder.plan` recusava a construção. O arquivo ainda continha o código do banco, mas o gerador não o construía ao iniciar o jogo.

Esta revisão restaura a largura de reserva original nesse trecho. **O banco não foi deslocado:** seu lote continua no CFrame calculado pela configuração original, com centro em **X=430, Z=-1006,4**. O código que constrói o banco, interiores, cofre e marcadores foi mantido integralmente. `BankService` e `BankController` não foram alterados.

A reserva de terreno da expansão agora também é protegida por `pcall`; uma falha na expansão não interrompe a construção do banco. O teste de integração chama o planejador e constrói o banco com as reservas de todas as ruas presentes. Ele também reproduz o conflito anterior para evitar sua volta.

## Expansão urbana

Inspirada na densidade, na variação de alturas e na arborização das referências de São Paulo:

- **48 lotes** ao norte e nas laterais do banco: **15 torres**, **19 interiores comerciais**, **7 praças** e **7 estacionamentos**.
- Torres de **12 a 24 andares**, alternando vidro e fachadas claras com sacadas. Os modelos de torres e moradias são os já existentes no jogo.
- **10 ruas**, incluindo o Boulevard Metropolitano com duas pistas, canteiro central e palmeiras; Rua do Banco Oeste, Rua do Banco Leste e Rua do Jardim do Banco, com retorno atrás do banco.
- Térreos visitáveis, coworking, recepções, cafés e espaços empresariais. **66 assentos** nos interiores e praças. Moradias e elevadores usam os sistemas existentes.
- **Três faixas de urbanização no perímetro do banco:** base nivelada, calçadas, canteiros, pequenos taludes de jardim, árvores e iluminação. Os lotes são reservados antes das construções novas para manter esses passeios livres.
- Parque existente, lote do banco, subsolo e rotas de fuga respeitados pelo planejamento.
- As cinco serras distantes e a reserva do litoral de 1.400 × 1.100 studs, com acesso pela LK-102, continuam presentes.

As referências servem à composição urbana. Não foi construída uma réplica exata de São Paulo nem uma via expressa subterrânea ao lado do cofre. Os espaços comerciais são visitáveis; esta entrega não cria novos produtos financeiros ou empregos para suas fachadas.

## Teste no Studio

1. Inicie com F5 e aguarde a geração do cenário.
2. Vá pela Estrada do Vale ao banco e confira a fachada na posição original.
3. Teste o crachá, o transformador e o anúncio com arma equipada e personagem de gangue.
4. Visite as novas quadras, as ruas laterais e o retorno atrás do banco; caminhe pelos jardins sem entrar no terreno do parque vizinho.
5. Teste as entradas dos prédios, os assentos, as moradias e a circulação de carros.
6. Confira o subsolo e a rota de fuga do banco.

## Verificações executadas

- **101 scripts compilados**, sem erros.
- **82 verificações do distrito**, incluindo o problema do banco, sua posição, sua construção com as ruas, separação de lotes, parque existente, interiores, passeios e conexões de GPS.
- **156 verificações do banco** continuam passando.
- Somente `BankBuilder`, `MapBuilder` e `CityRoads` foram alterados em relação ao novo upload. **98 scripts**, **3.627 objetos armazenados** e **1.520 blocos binários** foram preservados; o relatório JSON e os hashes acompanham a entrega.

A validação usa Luau e serviços Roblox simulados. **Aparência, física, streaming, desempenho e replicação reais ainda precisam ser conferidos no Roblox Studio.** Não foi executada uma sessão do Studio neste ambiente.
