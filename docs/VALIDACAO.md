# Validação — Marco 5.2

Verificação final executada com o compilador e interpretador oficiais do Luau 0.698,
revisão `ff6d381e57bcd1799d850d7fabe543c0f0980a5d`.

- **42/42 scripts compilados**.
- **42 verificações de PrisonRules** e **34 de PoliceRules**.
- **117 verificações de ciclo prisional**, executando o serviço real com relógio e
  eventos controlados: 16 celas, lotação, 15 s de lacre, pena de 60 s, reset, fuga,
  controles policiais, passagem ocupada e recuperação da velocidade após captura.
- **74 verificações de PoliceService**: três vagas, equipamentos, alcance, estados
  de suspeito, água, algemas, visibilidade, rádio, informes, portas, treino e
  preservação do dinheiro. Os serviços reais são executados com objetos simulados.
- **59.487 verificações geométricas**, executando os construtores reais contra
  simulações de Vector3, CFrame e Instance. Incluem celas fisicamente fechadas,
  saídas com a porta aberta, recepção, armaria, controle, fuga e subida às quatro
  torres, com 48 degraus baixos por torre.
- Limite de 2.048 studs por eixo e cobertura das quatro placas de terreno verificados.
- 237 árvores no cenário simulado, com raízes/copas sem colisão e até 16 peças cada.
- O gerador relê o XML e compara os 42 scripts com os arquivos-fonte.

## Limites importantes

Não houve execução no Roblox Studio. Os testes não simulam o motor físico,
renderização, Humanoid real, rede, DataStore ou desempenho em dispositivos. O teste
geométrico usa um envelope de personagem, permite degraus de até 0,8 stud nas rotas
marcadas como escadaria e verifica paredes/tetos, mas não comprova que o Humanoid
subirá sem ajustes no Studio. O gerador aleatório de testes difere do Roblox.

A aparência, a circulação com avatar real, o clique/toque nas ferramentas,
replicação, salvamento e desempenho precisam do roteiro `TESTE_NO_STUDIO.md`.

## Reproduzir

```sh
python tools/validate_luau.py --luau-dir /workspace/tooling/luau-0.698/source
python tools/build_rbxlx.py src dist/LittleLife_Marco5_2.rbxlx
```

Em outra máquina, ajuste o caminho das ferramentas. `tools/VALIDACAO.md` explica
como preparar o Luau oficial. Para abrir o jogo basta o arquivo `.rbxlx` e o Studio.
