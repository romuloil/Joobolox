# Metrópole V2 — banco preservado

Base obrigatória: upload `LittleLife_Banco_Corrigido.rbxl` de 09/11/2026, SHA-256 `b661211ad11988c2c2f90b99a5ca880575ff420f7ae46c6c61f9d13a5adf4dca`.

Corrige a reserva da Estrada do Vale que impedia a construção do banco. Amplia o distrito e urbaniza o perímetro sem mover o banco. O construtor original do banco permanece intacto, seguido das funções da expansão. `MapBuilder` isola falhas da expansão para permitir a construção do banco.

Pré-requisitos: Python, `zstandard==0.25.0`, Luau 0.698. A suíte reutiliza as fixtures de `../banco-marco10-28` (ou `../bank-fix` no workspace).

```sh
LUAU=/caminho/luau python tests/run.py
LUAU=/caminho/luau python tests/run.py --bank
LUAU_COMPILE=/caminho/luau-compile python tools/build.py LittleLife_Banco_Corrigido.rbxl LittleLife_Metropole_Banco_Preservado.rbxl
```

82 verificações da expansão, 156 do banco e compilação dos 101 scripts do arquivo final. Testes usam serviços Roblox simulados; verificação visual e física no Studio permanece necessária. Consulte o guia na pasta da entrega.
