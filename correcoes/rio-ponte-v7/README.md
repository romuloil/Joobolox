# Rio da Enseada e Ponte da Foz — V7

Base: entrega `LittleLife_Comunidades_Mirantes_V6.rbxl`, SHA-256 `1d749234f7a51f855f2d8e954442c7f4e4251c3e1d6a79cd86a1362b6b6c0b4f`.

O rio ocupa a faixa livre a leste da cidade e desemboca na Costa do Sol. Tem aproximadamente 2.831 studs de curso (793 m na escala de 0,28 m/stud), largura nominal de 36 studs na travessia (10,08 m), curvas suaves e foz progressivamente mais larga. Usa água de Terrain no mesmo nível do mar, com leito escavado, margens, pedras, vegetação e nascente.

A Ponte da Foz prolonga a via a partir do retorno leste da Avenida Beira-Mar. Tem duas faixas, passeios, guardas, sinalização, iluminação, rampas abaixo de 5%, retorno do outro lado e um recanto com banco para observar a foz. O desenho estaiado vermelho é uma adaptação em peças nativas do Roblox inspirada no GLB enviado. O GLB não foi publicado como MeshPart; o mapa não depende de um novo asset remoto para exibir a ponte.

## Escopo

Quatro fontes existentes alteradas:

- `MapBuilder`: recorte do chão, reserva e construção do rio após as dunas.
- `CityRoads`: nova via e retorno, compartilhados com o GPS.
- `ExpansionBuilder`: reserva da travessia sem gerar asfalto plano sobre o canal; placas respeitam a largura da transição.
- `MapController`: desenho do rio e marcadores da ponte e do recanto.

Dois módulos acrescentados:

- `ReplicatedStorage/Shared/RiverLayout`: traçado, larguras, alturas e funções geométricas comuns.
- `ServerScriptService/Services/RiverBuilder`: Terrain, ponte, acessos e ambientação.

As fontes inalteradas são reutilizadas de `../comunidades-v6/src` nos testes; `src` contém somente as seis fontes desta alteração. Banco, comunidades, distrito, litoral, concessionária e sistemas de moradia conservam seus scripts. Na faixa nova, a reserva evita plantações aleatórias e remove apenas decoração de restinga que invadiria o rio ou o acesso. Todas as ruas anteriores conservam as coordenadas, tipos e larguras.

## Testes e geração

Requer Python 3, `zstandard`, `lz4`, Luau 0.698 e os testes compartilhados em `../banco-marco10-28/tests`. Defina `LUAU` e `LUAU_COMPILE` para os executáveis locais. As bases de comparação ficam nas pastas `../comunidades-v5` e `../comunidades-v6`.

```bash
mkdir -p delivery
python tests/run.py > delivery/river.log
python tests/run.py regression.luau > delivery/regression.log
python tools/build.py ../../entregas/Comunidades_Mirantes_V6/LittleLife_Comunidades_Mirantes_V6.rbxl delivery/LittleLife_Rio_Ponte_V7.rbxl
```

O construtor exige o hash da V6, preserva as 12.351 instâncias originais e os blocos de propriedades, acrescenta somente os dois módulos e compila todos os 160 scripts. O arquivo também foi aberto por um decodificador independente `rbx_binary 3.0.1`/`rbx_dom_weak 4.2.0`.

Os testes executam os módulos reais com APIs simuladas: continuidade da água, terreno, altura das margens, integração com o construtor de ruas, circulação, GPS, preservação das vias e regressão de comunidades/distrito. Eles não executam a física, iluminação ou streaming do Roblox. Playtest no Studio ainda é necessário.

`tools/preview.py` gera plantas e uma perspectiva técnica a partir do log (requer numpy e matplotlib). As imagens não são capturas do jogo executando.

## Crédito do modelo de referência

“Bridge Road Lowpoly”, de **00amza**, [Sketchfab](https://sketchfab.com/3d-models/bridge-road-lowpoly-a91e8f0d30f140e6b7ccbdf3044cd7c5), [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). GLB fornecido pelo usuário, arquivado em `referencias/bridge_road_lowpoly.glb`. A adaptação muda escala, tabuleiro, mastros, cabos, acessos e materiais para a travessia do Little Life. A autoria e a licença também constam nos atributos do modelo no jogo.
