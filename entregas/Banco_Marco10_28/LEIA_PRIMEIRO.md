# Little Life — correção do banco

Base: **modeloprochat.rbxl**, enviado pelo Luís, com GameConfig **Marco 10.28**. Entrega: 06/11/2026.

## Abrir e testar

1. Baixe **LittleLife_Banco_Corrigido.rbxl**. Ele já contém o mapa completo e os códigos atualizados.
2. Abra o **Roblox Studio → Arquivo → Abrir do arquivo** e selecione esse `.rbxl`.
3. Clique em **Jogar / Play (F5)**, para entrar com seu personagem. Aguarde a construção do mapa e o carregamento dos modelos.
4. Entre em uma gangue pelo chefe da comunidade e equipe uma arma do jogo. Uma arma na mochila precisa ser colocada na mão para anunciar.

A configuração enviada já permite **um assaltante e nenhum policial online**. Ela foi mantida. O banco continua na Estrada do Vale.

## Roteiro do assalto

| Etapa | O que fazer |
|---|---|
| Preparação opcional | No beco a leste do banco, aproxime-se do funcionário Beto e segure **E** para pegar o crachá. No transformador, use o painel externo voltado para o estacionamento e segure **E** por 6 segundos. A preparação vale 15 minutos para sua gangue. |
| Anúncio | Entre no meio do salão com a **arma equipada**. Segure **E** por 1 segundo em **Anunciar o assalto**. O painel passa a mostrar o assalto e a equipe. Sem arma ou gangue, aparece a explicação do requisito. |
| Vigilantes e gerente | Mire nos vigilantes para rendê-los e use **E** para amarrá-los. Se não trouxer o crachá do beco, renda a gerente Marta e pegue o dela. O botão de pânico pode antecipar o alarme mesmo com a energia cortada. |
| Porta de segurança | Com o crachá, use **E** no leitor, no fundo do salão. Sem crachá, há a alternativa de arrombar a porta. |
| Terminal e chaves | Na sala de segurança, use **E** no terminal e complete o minigame. Gire as duas chaves: sozinho, até **12 segundos** entre elas; em equipe, duas pessoas devem girá-las com até **2,5 segundos** de diferença. Se passar do prazo, tente novamente. |
| Subsolo | Desça a escada. Use o quadro vermelho e complete o minigame para cortar os lasers, ou atravesse sem encostar. |
| Cofre | Monte a furadeira com **E**. A perfuração leva cerca de **75 segundos**, com variações pelos eventos. Se travar, destrave pelo minigame. Depois segure **E** em **Girar o volante** e aguarde a porta abrir. |
| Coleta | Entre pelos degraus. Use **E** nos maços, barras de ouro e cofrinhos. O malote tem 14 espaços; ouro ocupa 2. A troca com a bolsa cheia precisa ser confirmada perto do item. |
| Saída | Volte pelos degraus e use a saída de serviço. Durante o cerco, force a trava. Após abrir o cofre, também é possível plantar C4 na parede do túnel, aguardar 6 segundos e usar **E** na saída do bueiro. |
| Porta fechou com você dentro | Use a **alavanca vermelha de emergência** e aguarde a reabertura. Quem está fora pode usar o volante. |
| Concluir | Despiste a polícia e leve o malote ao chefe da sua gangue. Segure **F** para vender. Se houver rastreador, espere ele apagar. |

Quando a equipe sai, o banco fecha para perícia. O intervalo original é de **45 minutos**. Para repetir rapidamente um teste local, pare o Play e inicie outra sessão.

## O que foi corrigido

- Ativação dos botões no servidor, com filtro por função e condição no cliente; atualização após mudanças de gangue, emprego, crachá e incapacitação.
- Crachá ligado ao ponto permanente do funcionário, funcionando também após a reabertura do banco ou durante o carregamento dos NPCs.
- Painel de interação acessível no transformador e confirmação imediata da preparação.
- Reconhecimento da arma equipada, verificação da posição no salão e validação das etapas e do tempo de interação no servidor.
- Seleção dos botões da porta: crachá, arrombamento e abertura por dentro deixam de oferecer a ação errada para aquele lado da porta.
- Expiração e tentativa novamente das chaves; controle duplo com participantes distintos em equipe.
- Minigames e trocas vinculados ao assalto atual: afastamento, incapacitação ou conclusão atrasada não avançam outro assalto.
- Degraus contínuos na entrada e na saída do cofre; porta de serviço aguarda a passagem do personagem e respeita uma nova abertura.
- Limpeza de interações temporárias e furadeira ao encerrar; reaproveitamento correto das interações no próximo assalto.
- Receptador ativo no servidor, pagamento único e conferência da gangue do malote.

Somente **BankBuilder**, **BankService** e **BankController** foram modificados no arquivo enviado. Os outros **98 scripts**, os **3.621 objetos**, modelos, recursos e propriedades foram preservados. O mapa não foi substituído por uma versão antiga do GitHub.

## Verificação realizada

- Compilação dos **101 scripts** do arquivo final com Luau 0.698, sem erros.
- **156 verificações automatizadas** dos módulos do banco: fluxo completo, solo e equipe, reabertura, restrições, minigames atrasados, malote, furadeira travada, alavanca de emergência e interface.
- Verificação geométrica conservadora da passagem do cofre usando posições e dimensões extraídas do modelo enviado.
- Comparação binária: apenas um bloco `Source` mudou; **1.490 blocos restantes são idênticos** aos do arquivo original.

Os testes usam substitutos controlados dos serviços Roblox e do minigame compartilhado. **Ainda é necessário testar no Roblox Studio** a física real, aparência, replicação entre jogadores, uso no celular e carregamento de recursos. Não foi realizada uma sessão de jogo no Studio neste ambiente.

Os fontes alterados estão na pasta `src` do pacote. Não é necessário colá-los manualmente: o `.rbxl` já os inclui.
