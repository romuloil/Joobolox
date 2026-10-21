# Validação do código — Marco 5.3

O comando único compila todos os scripts e executa os serviços reais com relógio,
eventos, consultas espaciais e instâncias simuladas. Nenhum teste baixa ferramentas,
roda o Roblox Studio ou publica o jogo.

```sh
python tools/validate_luau.py --luau-dir /workspace/tooling/luau-0.698/source
```

Ferramentas usadas nesta execução: Luau oficial 0.698, revisão
`ff6d381e57bcd1799d850d7fabe543c0f0980a5d`. Para preparar outro ambiente com Git,
GNU Make e compilador C++17, preserve TLS e a revisão:

```sh
git clone --depth 1 --branch 0.698 https://github.com/luau-lang/luau.git luau-tools
git -C luau-tools rev-parse HEAD
# Esperado: ff6d381e57bcd1799d850d7fabe543c0f0980a5d
make -C luau-tools -j2 config=release luau luau-compile
python tools/validate_luau.py --luau-dir /caminho/para/luau-tools
```

Resultado verificado:

- 53/53 scripts compilados.
- Regras: prisão 42, polícia 34, empregos/uniformes 39 e táxi 19 verificações.
- Ciclos reais de serviço: prisão 117, polícia 74, empregos/uniformes 87,
  veículos 25 e táxi 41 verificações.
- Moradores: 85 verificações executando o serviço sobre o mapa real com consultas
  geométricas simuladas e a fábrica NPCKit substituída por um objeto controlado.
- Geometria: 73.227 verificações; prédio da delegacia e LXR acessíveis, celas/portas,
  rota da prisão, quatro torres, trilha espaçada, posto distante e 11 vagas de
  retirada sem obstáculos para um envelope de sedã.

Os testes de uniforme exercitam avatares R6/R15, retirada por proximidade e emprego,
atributos forjados, devolução e restauração de roupas/chapéus. Veículos usam o próprio
CarBuilder e verificam garagem, papel, bloqueio de recolocação pelo V e limpeza ao
sair/morrer. Táxi verifica motorista/veículo correto, passageiro, distância percorrida,
teleporte, reserva de assento, pagamento uma única vez e cancelamento durante criação
de NPC. Moradores verificam imobilidade, limite compartilhado de NPCs, diálogo por
proximidade e troca de ponto quando há obstáculo.

## Limites

Os objetos de `tests/roblox_geometry_mock.luau` e `tests/service_fixture.luau` não
substituem o motor Roblox. Não simulam condução, Humanoid, física, renderização,
replicação, DataStore, carregamento de avatares online nem desempenho. A geometria
usa envelopes e tolerância de degrau de até 0,8 stud; o gerador aleatório de teste
difere do Roblox, portanto posições/contagens de prédios podem variar no Studio.

Teste visual e funcional no Studio continua necessário, principalmente condução dos
sedãs, pose do passageiro, vestimenta em avatares diferentes, interfaces no celular,
diálogos e salvamento do pagamento. Não desabilite validações para ocultar falhas.
