# Litoral V4 e estacionamento compacto

Base exata: `LittleLife_Metropole_Concessionaria.rbxl`, SHA-256 `69229da83a262d6fbfc5e480b1ff8665c102aae3e77ecac721b4f94474a85dbe`.

`DealershipBuilder` mantém o subtree `Dealer` e recorta exclusivamente `ParkingLot` durante a construção. Peças planas que cruzam o limite são aparadas; ornamentos externos são removidos e o novo meio-fio finaliza a borda. O template binário original não é modificado. Edifício deslocado 400 studs ao sul, mantendo a escala. O distrito conserva os 88 lotes.

`CityRoads.Coast` é a fonte da rodovia, acessos, praias e futuro acesso à ponte. `CoastBuilder` recorta somente os tiles de chão dentro do oceano, cria água/fundo de Terrain em blocos de 400 studs, costões, enseadas, equipamentos de praia e marcadores. O módulo é chamado após a reserva da região e antes do preenchimento rural. A região inteira permanece reservada para impedir árvores/plantação no mar. O bloqueio antigo de fim da LK-102 é removido; a ponte não é construída.

`CoastService` inicializa após ZoneService, economia e inventário. Reutiliza NPCKit para 15 NPCs parados, limitando custo de física e evitando navegação constante. As vendas validam vida, distância, estado do personagem, saldo, espaço e duplicidade. Lanches são Tools temporárias adotadas pelo InventoryService existente; o consumo só funciona equipado e uma vez. Nenhuma mudança no esquema persistente de carros ou dinheiro.

## Testar e gerar

Requer Python com `zstandard` e `lz4`, Luau 0.698 e as fixtures existentes em `../banco-marco10-28`. Caminhos Luau podem ser fornecidos por variáveis de ambiente.

```sh
LUAU=/caminho/luau python tests/run.py
LUAU=/caminho/luau python tests/run.py --dealer
LUAU=/caminho/luau python tests/run.py --coast
LUAU=/caminho/luau python tests/run.py --bank
LUAU=/caminho/luau python tests/run.py --vehicles
LUAU_COMPILE=/caminho/luau-compile python tools/build.py LittleLife_Metropole_Concessionaria.rbxl LittleLife_Litoral_Concessionaria.rbxl
```

O build exige o hash correto, altera seis fontes existentes e acrescenta `CoastBuilder` e `CoastService`. Todas as 12.246 instâncias de entrada permanecem no arquivo, inclusive o template completo da concessionária. As alterações físicas são executadas pelos construtores durante Play.

A validação independente do binário pode usar `../metropole-v3/tools/placekit` com `--verify`. Para recriar a planta esquemática, execute `tools/overview.py` com Matplotlib.

395 verificações, 104 scripts compilados; testes de serviços e geometria com mocks, sem renderização/physics engine do Studio. Veja o guia da entrega para as limitações e passos de teste real.
