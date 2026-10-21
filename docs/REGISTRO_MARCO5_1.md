# Registro de continuidade — Marco 5.1

## Base utilizada

Os 32 scripts foram recuperados do arquivo `LittleLife_Marco5.rbxlx` enviado pelo
usuário. O repositório `romuloil/Joobolox` estava sem commits e sem arquivos.
O arquivo anterior e seus anexos não foram sobrescritos. Esta entrega é uma nova versão.

Foram consultados o registro até o Marco 5, a Documentação Mestre v0.1 e o Prompt
Mestre v0.1 enviados pelo usuário. Esses documentos serviram de referência do jogo;
o pedido atual priorizou delegacia, prisão/sistema prisional e árvores orgânicas.

## Mudanças

- **MapBuilder:** reserva os lotes públicos antes de gerar residências e árvores;
  constrói os equipamentos públicos e substitui árvores simples por árvores com
  troncos curvos, galhos, copas assimétricas e quatro raízes ramificadas.
- **CivicConfig:** posições da delegacia urbana e prisão afastada, estrada e pena de 60 s.
- **CivicBuilder:** delegacia com recepção, apoio e cela cenográfica; prisão com
  alojamentos, pátio, recepção de visitas e passagem de manutenção; posto/conveniência
  cenográficos junto da saída; bancos interativos e marcações no mapa.
- **PrisonRules / PrisonService:** estado temporário do servidor, prazo, liberação
  automática, fuga em três etapas, retorno ao alojamento em deslocamento inválido,
  preservação do prazo após reset e proteção contra resolução duplicada.
- **PrisonController:** contador e próximo passo, com recuperação pelos atributos
  replicados. Somente o servidor resolve a soltura.
- **VehicleService / SeatService / JobService:** detidos não iniciam empregos nem usam
  bike, carro ou carona. Ao entrar, o veículo é removido e a vaga é liberada.
- **MapController:** desenha a estrada e os locais novos, inclusive quando a replicação
  deles chega após o início da interface.
- **Bootstrap:** inicializa as novas funções sem alterar o formato do DataStore.

## Decisões deste marco

- Nenhum jogador é marcado automaticamente como criminoso. O teste de detenção é
  voluntário na recepção da delegacia e só fica disponível no Studio.
- O serviço prisional expõe apenas uma API interna do servidor para futura captura.
  Profissões policiais, imobilização, algemas, assalto e viaturas funcionais ainda
  precisam ser implementados para haver captura real na experiência publicada.
- A documentação original é ambígua sobre recompensa perdida na captura e preservada
  após fuga da prisão. Como o Marco 5 não tem assaltos, não se alterou dinheiro nem
  se decidiu essa regra implicitamente.
- Prisão/desconexão seguem o estado de sessão previsto na referência, sem gravar
  tempo prisional permanente no DataStore.

## Entrega e validação

- `LittleLife_Marco5_1.rbxlx`: versão completa para abrir e testar no Studio.
- Pacote ZIP: fontes, gerador, testes, instruções e registro de continuidade.
- Resultados automatizados e limites em `VALIDACAO.md`; roteiro visual/funcional em
  `TESTE_NO_STUDIO.md`.
- Não publicado no Roblox, não enviado ao GitHub e ainda não testado visualmente
  no Roblox Studio nesta etapa. A aprovação visual pelo usuário está pendente.

## Próximo passo

Executar o roteiro no Studio, começando por entrada da delegacia, detenção sem fuga,
fuga completa e reset durante a pena. Depois conferir profissões, carro e desempenho
no emulador de celular. Corrigir os resultados observados antes de ampliar a polícia
ou implementar o sistema completo de assaltos.
