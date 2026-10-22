# Validação — Marco 5.3

Ferramentas oficiais do Luau 0.698, revisão
`ff6d381e57bcd1799d850d7fabe543c0f0980a5d`.

- **53/53 scripts compilados**.
- **134 verificações de regras**: prisão42, polícia34, profissão/uniforme39 e táxi19.
- **344 verificações de serviços**: prisão117, polícia74, uniformes87, veículos25 e
  táxi41. Executam os módulos reais com relógio, eventos e instâncias simulados.
- **85 verificações de moradores**: fábrica NPCKit compartilhada, oito posições,
  espaço nas calçadas, limite de NPCs, conversa próxima, inicialização assíncrona
  e rejeição de chamadas inválidas.
- **73.227 verificações geométricas**: delegacia/LXR em lotes reservados, acesso a
  recepção/vestiário/garagem, 11 vagas para veículos sem obstáculos, posto afastado,
  trilha após a fuga, celas/túnel/torres, terreno e 237 árvores no cenário simulado.
- O gerador relê o XML e compara o conteúdo de todos os scripts com os fontes.

Os testes de uniforme cobrem R6/R15, restauração de roupas/chapéus, distância do
vestiário, exclusividade de profissão, atributos falsos, reset e falha de construção.
Os testes de carro executam também o CarBuilder real; verificam retirada por cargo,
local, vaga ocupada, motorista/dono, perda do emprego, morte e garagem pessoal.
Os testes de táxi verificam embarque, viagem plausível, pagamento único, banco
reservado, criação assíncrona do NPC, cancelamento e transição de emprego.

## Limites

Não houve execução do Roblox Studio. Os testes não simulam o motor físico,
renderização, avatares reais, rede, animações online ou DataStore. O gerador aleatório
simulado é diferente do Roblox. A validação de espaço usa envelopes de personagem
ou carro e não substitui atravessar os locais e dirigir no motor real.

Ainda precisam de teste no Studio: proporções e aparência, roupas em avatares variados,
sedãs, portas e giroflex visual, NPC sentado, ferramentas no celular, salvamento,
replicação e desempenho. O roteiro está em `TESTE_NO_STUDIO.md`.

## Reproduzir

```sh
python tools/validate_luau.py --luau-dir /workspace/tooling/luau-0.698/source
python tools/build_rbxlx.py src dist/LittleLife_Marco5_3.rbxlx
```

Em outra máquina, ajuste o caminho das ferramentas; veja `tools/VALIDACAO.md`.
Para jogar no Studio, basta o `.rbxlx` entregue.
