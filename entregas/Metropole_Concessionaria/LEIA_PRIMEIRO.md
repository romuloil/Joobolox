# Little Life — distrito ampliado e Concessionária do Vale

Abra **LittleLife_Metropole_Concessionaria.rbxl** no Roblox Studio e pressione **F5**. O mapa é montado pelos scripts durante a execução. Não é necessário instalar plugins nem importar modelos manualmente.

## O que foi entregue

- Distrito ampliado de 48 para **88 lotes**: 41 torres, 33 estabelecimentos com interior, 7 praças e 7 estacionamentos. Os 48 lotes anteriores mantêm ordem e posição; os novos prédios reutilizam os construtores do jogo, com alturas menores nos quarteirões de preenchimento.
- Quatro novas ruas, incluindo a **Avenida da Concessionária**, registradas na mesma fonte usada pelo mapa e pelo GPS.
- Conjunto físico da concessionária enviada: **8.618 objetos**, incluindo 6.012 peças físicas, 140 assentos, interior, móveis, oficinas, fachada, iluminação, texturas e o estacionamento aberto completo. Mantida a escala original; o conjunto foi nivelado e deslocado para um lote reservado ao norte/leste do distrito.
- Balcão de vendas na recepção, confirmação de compra, catálogo com preços e miniaturas, ponto de retirada externo e três vagas compartilhadas. Três carros do Little Life ficam expostos no pátio. Dez portas internas e seis portões de oficina têm interação com **E**.
- Banco preservado na posição original. Os scripts BankService e BankController não foram alterados. As serras e a área reservada para o litoral continuam presentes.

## Encontrar e testar

1. Entre em Play e aguarde a montagem do mapa.
2. Abra o mapa com **M** e procure **Concessionária do Vale**. Siga a Avenida da Concessionária até o estacionamento; as placas levam ao showroom.
3. Na recepção, aproxime-se do balcão e pressione **E** para abrir o catálogo.
4. O botão de compra pede uma segunda confirmação antes de gastar. Após comprar, o veículo aparece na garagem pessoal e pode ser retirado nas vagas da concessionária ou em outra garagem pública.
5. Há um segundo ponto, **Retirada da concessionária**, no estacionamento, dedicado aos veículos disponíveis para aquele jogador.

**No Studio**, `GameConfig.Garage.FreeInStudio = true` mantém os veículos liberados para teste, conforme solicitado. Isso não adiciona carros à propriedade salva. Para simular a economia dentro do Studio, altere temporariamente essa opção para `false` em `ReplicatedStorage > Shared > GameConfig`. Os veículos de serviço mantêm suas regras de profissão no jogo publicado; a configuração preexistente `ServiceInStudio` continua permitindo testes no Studio.

**No jogo publicado**, a garagem pessoal lista os carros comprados. O catálogo da concessionária lista os veículos pessoais disponíveis, sem vender veículos exclusivos de emprego ou administração. O servidor verifica presença no local, estado do personagem, preço configurado, saldo e propriedade anterior. Solicitações repetidas não cobram outra compra do mesmo carro.

A compra usa o `ownedCars` e o dinheiro do PlayerDataService existente; ambos são salvos no mesmo perfil. Compras ficam bloqueadas se um perfil de produção não carregou com segurança. Se o salvamento falhar depois da compra, o jogador recebe aviso e o salvamento automático existente tenta novamente. Para testar persistência no Studio, publique uma experiência de teste e habilite o acesso do Studio às APIs; sem isso, o teste é somente da sessão.

## Validação e limites

Passaram **328 verificações automatizadas**: 128 do distrito, 156 do banco, 29 de compra/garagem/persistência simulada e 15 da construção da concessionária. Os **102 scripts** foram compilados. Uma biblioteca independente leu o arquivo final com 12.246 instâncias; as 3.627 instâncias originais foram preservadas, e nenhum script do mapa de referência foi importado.

Não foi possível executar o Roblox Studio neste ambiente. Ainda é necessário conferir renderização, física, desempenho, multiplayer e salvamento real nas APIs Roblox. As malhas e texturas da concessionária mantêm os IDs do arquivo fornecido; seu carregamento depende da disponibilidade e das permissões desses assets no Roblox.

As verificações usam os construtores reais e serviços Roblox simulados, incluindo uma simulação de saída/retorno do jogador. Isso não equivale a uma sessão real de Play ou a um teste de carga. Os logs e o relatório de integridade acompanham a entrega no GitHub.
