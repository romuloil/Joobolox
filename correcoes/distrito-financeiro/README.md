# Expansão do Distrito Financeiro

Base: `LittleLife_Banco_Corrigido.rbxl` da branch `correcao-banco-marco10-28`.

Três módulos alterados: `src/BankBuilder.lua` (planejamento e construção), `src/MapBuilder.lua` (integração e reutilização de construtores), `src/CityRoads.lua` (ruas e acesso litorâneo compartilhados pelo mapa e GPS).

Os lotes são reservados antes do campo e das árvores aleatórias, respeitando `isFree`/`occupy`. As novas moradias são construídas depois das antigas. Nenhum modelo externo foi importado. Os interiores de torres e lojas usam os construtores existentes; as referências originais de torres/moradias em `tests/reference` servem apenas aos testes.

Com Python 3.10+, `zstandard==0.25.0` e Luau 0.698:

```sh
LUAU=/caminho/luau python tests/run.py
LUAU=/caminho/luau python tests/run.py --bank
LUAU_COMPILE=/caminho/luau-compile python tools/build.py LittleLife_Banco_Corrigido.rbxl LittleLife_Distrito_Financeiro.rbxl
```

A suíte reutiliza as fixtures em `../banco-marco10-28` (ou `../bank-fix` no workspace). Renderização, física, streaming e replicação reais precisam ser verificados no Studio. Veja o guia na entrega para localização e roteiro de teste.
