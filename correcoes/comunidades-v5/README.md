# Distrito e comunidades V5

Entrega derivada do atual.rbxl do usuário, SHA-256 f528f4be7606ff60af94e6470db6503f152cc07eaf95ffa85ba69e6410bff8c0.

Cinco fontes alteradas: CityRoads (ruas do distrito), MapBuilder (integração), FavelaBuilder (reforma visual e circulação), HomeConfig (casas opcionais), HomeService (compra restrita por gangue e conservação da propriedade). FinancialDistrictBuilder é um novo módulo isolado. Os demais arquivos em src documentam a versão ativa da base enviada e são usados pelos testes.

## Testes

Requer Luau 0.698. Defina LUAU e LUAU_COMPILE se os executáveis não estiverem nos caminhos do ambiente.

```bash
python tests/run.py
python tests/run.py housing.luau
```

Os simuladores são reutilizados de `../banco-marco10-28/tests`. Geometria testa as três comunidades, as 108 saídas das moradias, os contratos do GangService e a montagem real do distrito com os construtores existentes. Moradia executa HomeService, HomeConfig e FurnitureArt reais; relógio, economia e armazenamento usam interfaces simuladas.

## Gerar o arquivo

Python 3, zstandard e lz4 são necessários. Use exatamente o atual.rbxl original; o comando rejeita outra base.

```bash
python tools/build.py /caminho/atual.rbxl /caminho/LittleLife_Atual_Distrito_Comunidades.rbxl
```

O construtor preserva as instâncias e os blocos de propriedades existentes, altera só cinco fontes e acrescenta FinancialDistrictBuilder. Compila todos os scripts e compara as propriedades contra a base. Validações e limitações estão em `../../entregas/Distrito_Comunidades/`.
