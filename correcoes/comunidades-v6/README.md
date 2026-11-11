# Comunidades e mirantes V6

Continuação da entrega V5, preservando o mapa enviado em `atual.rbxl`. Altera somente quatro fontes ativas: `FavelaBuilder`, `CityRoads`, `FinancialDistrictBuilder` e `MapController`. Os demais arquivos em `src` são o retrato das fontes da base, usado nos testes.

- Nebulosa: encosta curva que se estreita no alto, fachadas coloridas e mirante no lado sudeste.
- Lua Negra: becos compactos, patamares em pares, alvenaria mais escura e mirante no lado noroeste.
- Horizonte Solar: crista com ruas sinuosas, pedra clara, tons quentes e mirante no lado sudoeste.
- Vielas de 6,5 a 7,5 studs, escadas entre patamares, trilhas elevadas e mirantes direcionados para a cidade. Postes, fios, pipas, portas e estruturas de casas reaproveitados.
- Distrito ampliado com 83 lotes, mantendo os 75 anteriores. Ligação com vértice existente do Rodoanel; vias disponíveis ao mapa e ao GPS pelo CityRoads compartilhado.
- 90 moradias gratuitas de gangue e 18 opcionais compráveis. HomeService, HomeConfig, GangService e persistência permanecem idênticos à V5.

## Verificar

Python 3 e Luau 0.698. Defina `LUAU` e `LUAU_COMPILE` se necessário. Os simuladores são reutilizados de `../banco-marco10-28/tests`; o comparativo usa `../comunidades-v5/src/FinancialDistrictBuilder.lua`.

```bash
mkdir -p delivery
python tests/run.py > delivery/geometry.log
python tests/run.py housing.luau > delivery/housing.log
```

Geometria monta os construtores reais em simulação, verifica as 108 saídas das casas, 6.861 amostras de espaço para circulação, direção e desobstrução inicial dos mirantes, pontos de integração das vias e preservação dos lotes existentes. Moradia executa 20 casos do HomeService real, incluindo compra, saldo, distância, gangue, interior e restauração da propriedade. Interfaces de armazenamento, relógio e física não são o motor Roblox.

## Gerar o mapa

Instale `zstandard` e `lz4`. A base obrigatória é `LittleLife_Atual_Distrito_Comunidades.rbxl` da entrega V5; o SHA-256 é validado antes de qualquer alteração.

```bash
python tools/build.py ../../entregas/Distrito_Comunidades/LittleLife_Atual_Distrito_Comunidades.rbxl delivery/LittleLife_Comunidades_Mirantes_V6.rbxl
```

O processo altera as quatro fontes, preserva as instâncias e propriedades, compila todos os 158 scripts e registra o resultado dos testes. `tools/preview.py` gera apenas uma planta técnica das casas, usando matplotlib e numpy. Não representa uma captura do Studio.

A entrega também foi decodificada por `rbx_binary 3.0.1`/`rbx_dom_weak 4.2.0`, independentemente do editor de binário Python. Ainda é necessário testar aparência, desempenho, física, GPS em uso e DataStore real no Roblox Studio. As estruturas são geradas ao iniciar Play, como na base do jogo.
