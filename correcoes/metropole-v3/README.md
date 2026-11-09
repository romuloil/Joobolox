# Metrópole V3 — concessionária e propriedade de veículos

Base: upload `LittleLife_Metropole_Banco_Preservado.rbxl`, SHA-256 `3aa1a08873b95bacbcb0411f830b260d803144b89e398c5d381a1dd495b34388`.

O banco e os 48 lotes existentes são preservados. O planejamento acrescenta 40 lotes, reserva a concessionária completa antes dos novos lotes e mantém desobstruídas as estradas existentes, inclusive a Estrada do Sol. O template físico está em `dealership.rbxm`; nenhum código de jogo do arquivo de referência acompanha o template. A compra reutiliza a economia, o perfil persistente e os veículos do Little Life.

`DealershipBuilder` aplica uma transformação rígida ao modelo, integra balcões ao VehicleService e adiciona portas interativas. `VehicleService` separa catálogo de venda e inventário da garagem, valida compra no servidor e mantém o desbloqueio temporário do Studio. `GarageController` confirma a compra e trata garagem vazia. `MapController` identifica os novos pontos, inclusive quando as peças estão fora do streaming. `PlayerDataService.canPersist` evita comprar em um perfil temporário após falha de carregamento.

## Reproduzir

Python com `zstandard` e `lz4`, Luau 0.698; Rust/Cargo apenas para extrair novamente o template ou conferir o binário por outra biblioteca. Os testes reutilizam as fixtures da correção anterior em `../banco-marco10-28` (ou `../bank-fix` no workspace).

```sh
LUAU=/caminho/luau python tests/run.py
LUAU=/caminho/luau python tests/run.py --bank
LUAU=/caminho/luau python tests/run.py --vehicles
LUAU=/caminho/luau python tests/run.py --dealer
LUAU_COMPILE=/caminho/luau-compile python tools/build.py LittleLife_Metropole_Banco_Preservado.rbxl LittleLife_Metropole_Concessionaria.rbxl
cargo run --manifest-path tools/placekit/Cargo.toml -- LittleLife_Metropole_Concessionaria.rbxl --verify
```

Extração opcional a partir do arquivo de referência fornecido pelo usuário:

```sh
cargo run --manifest-path tools/placekit/Cargo.toml -- referencia.rbxl dealership.rbxm
```

O extrator seleciona o Model `Dealership` contendo `Dealer` e `ParkingLot`, remove scripts e os prompts antigos e ancora a estrutura. As propriedades visuais e o conteúdo dos assets são preservados. O arquivo completo de referência não é necessário para jogar nem é redistribuído aqui.

`tools/build.py` exige o SHA da base correta, preserva os chunks originais exceto fontes e as tabelas necessárias à junção, remapeia IDs, referências e shared strings e compila todos os scripts. Os testes geométricos usam uma captura da árvore física real em `tests/reference/dealership_geometry.json`.

Verificações automatizadas não substituem renderização, física e persistência reais no Studio. Consulte o guia da entrega para os passos de Play.
