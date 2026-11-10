# Little Life — distrito e comunidades

Base: **atual.rbxl**, enviado pelo usuário. O litoral Costa do Sol, o píer, o parque, a concessionária na posição escolhida pelo amigo, a obra e os sistemas atuais foram mantidos. Não use a entrega antiga para testar esta atualização.

## Abrir

1. Baixe **LittleLife_Atual_Distrito_Comunidades.rbxl** desta pasta.
2. No Roblox Studio, use **File → Open from File** e escolha o arquivo.
3. Pressione **F5** e aguarde a montagem procedural. O cenário é criado ao iniciar o teste.
4. Abra o mapa com **M** para localizar o banco e as três comunidades.

## Distrito

Distrito financeiro restaurado ao redor do banco, com torres, comércio acessível, praças, estacionamentos e jardins. No ensaio de reservas, 75 lotes couberam sem sobrepor o banco, a obra e a área atual da concessionária. O lote da obra conserva a primeira posição original. A avenida norte termina no distrito; não restaura a concessionária no lugar antigo.

## Comunidades

Morro da Nebulosa (CDA), Complexo da Lua Negra (TDE) e Favela Horizonte Solar (CDS) continuam nas mesmas reservas do mapa. Cada uma tem cinco patamares, ladeiras em curvas, duas escadarias transversais, vielas e mirante. Casas variam em altura, tijolo aparente, reboco, cores, varandas, grades, telhados, caixas d’água, antenas e varais.

Chefes, bares, paredões, campo e bola mantêm os pontos de integração do GangService. As 30 moradias gratuitas de cada comunidade continuam disponíveis.

Há **6 casas à venda em cada comunidade** (18 no total), por **$35.000**, preço provisório configurado em HomeConfig. É necessário pertencer à gangue da comunidade, ter saldo e estar perto da porta. Pressione **E** na porta com a placa de venda. A compra usa o sistema existente de casas, móveis, trancas e dados do jogador. É possível ter uma casa comprada por comunidade; mudar para outra fachada desse mesmo nível é grátis.

Sair da gangue suspende a ocupação da casa comprada, mantendo a compra e os móveis nos dados. Voltar à gangue restaura a moradia em uma fachada livre. A persistência entre servidores depende do funcionamento do DataStore já existente no jogo.

## Roteiro de teste no Studio

- Confira o litoral e a concessionária antes de visitar o distrito.
- Vá ao banco e confira a entrada, o acesso à obra e os caminhos ao redor.
- Percorra as ladeiras e as duas escadarias de cada comunidade até o mirante.
- Interaja com o chefe e com os equipamentos comunitários.
- Teste a compra sem gangue, com outra gangue, sem saldo e com a gangue correta.
- Entre na casa comprada, use os móveis e saia pela porta. Teste com dois jogadores para verificar propriedade e trancas.
- Em uma experiência publicada de teste, confira a compra e os móveis após reconectar.

## Validação realizada

- 128 verificações de geometria, reservas e integração dos construtores.
- 20 verificações do fluxo de moradia: permissões, saldo, distância, compra, mudança, interior, saída, troca de gangue e reconexão simulada.
- 158 scripts compilados sem erro.
- 12.350 instâncias originais preservadas e 1 módulo novo; 2.008 blocos de propriedades não relacionadas aos códigos permanecem idênticos.
- 152 scripts originais intactos, incluindo os sistemas do banco, litoral e concessionária.
- Leitura independente do arquivo binário: 12.351 instâncias.

Os testes usam Luau e simulações dos serviços Roblox. **Não houve execução no Roblox Studio nesta máquina.** Aparência final, física, streaming, desempenho e DataStore real precisam do teste no Studio.
