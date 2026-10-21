# Validação do código

Os testes usam o compilador e o interpretador oficiais do Luau. Eles verificam
sintaxe, regras de detenção/fuga/polícia e decisões dos serviços com relógio,
eventos, ferramentas e raycasts controlados. Não executam o motor Roblox:
visual, colisões reais, animações, replicação e desempenho ainda precisam de
teste no Roblox Studio.

No ambiente usado para esta entrega:

```sh
python tools/validate_luau.py --luau-dir /workspace/tooling/luau-0.698/source
```

Para preparar as ferramentas em outra máquina com Git, GNU Make e um compilador
C++17, use o código oficial, preservando TLS e a revisão abaixo:

```sh
git clone --depth 1 --branch 0.698 https://github.com/luau-lang/luau.git luau-tools
git -C luau-tools rev-parse HEAD
# Revisão esperada: ff6d381e57bcd1799d850d7fabe543c0f0980a5d
make -C luau-tools -j2 config=release luau luau-compile
python tools/validate_luau.py --luau-dir /caminho/para/luau-tools
```

Os stubs em `tests/roblox_geometry_mock.luau` implementam apenas o subconjunto de
valores e objetos usado pelos testes. O gerador pseudoaleatório do stub não é o
gerador interno do Roblox; resultados de contagem de lotes não são uma previsão
exata da cena no Studio. A geometria fixa, os pontos da prisão e suas distâncias
podem ser verificados sem renderização.

Os testes do serviço prisional executam `PrisonService` com relógio controlado:
pena de 60 segundos, 16 celas individuais, bloqueio inicial de 15 segundos,
abertura automática, reset sem renovar prazos, lotação, reutilização de celas,
controle manual de portas e impedimento de fechar uma porta sobre o personagem.
Incluem o caso de um suspeito imobilizado chegar com velocidade zero e precisar
sair da prisão andando normalmente.

Os testes policiais executam `PoliceService`, incluindo três vagas, retirada e
devolução de equipamentos, informes com categorias permitidas, distância dos
terminais, controle seguro de acessos e celas, ordem da ronda, treino com alvo e
captura exigindo suspeita interna, imobilização, algemas equipadas e visibilidade.
Os raycasts são respostas programadas, não simulação de física; validam a decisão
do serviço diante de um acerto, uma parede ou ausência de alvo. Tweens de porta
aplicam o destino final no stub e não demonstram a animação real.

Nenhum teste converte publicação no GitHub, geração de XML ou aprovação de regras
em comprovação de que o jogo foi executado no Roblox Studio.
