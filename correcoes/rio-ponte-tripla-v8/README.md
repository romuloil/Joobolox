# Rio ampliado e ponte tripla — V8

Continuação da V7 aprovada. A largura da água foi multiplicada por **2 em todo o curso**, conservando o traçado, o comprimento de aproximadamente 793 m e a ligação com o mar. Na travessia, passa de 36 para 72 studs: aproximadamente **20,16 m**.

A ponte utiliza **três módulos de 120 studs** no mesmo estilo estaiado vermelho aprovado. O tabuleiro contínuo tem 360 studs (100,8 m), com duas faixas e passeios. Mantém altura, cores, mastros e cabos do desenho anterior; inclui apoios entre módulos, rampas reposicionadas, iluminação distribuída e recanto deslocado para o novo encontro leste. As rampas permanecem abaixo de 5%. Placas e postes acompanham a largura variável do acesso.

## Escopo e reprodução

Somente `RiverLayout` e `RiverBuilder` foram alterados. As 12.353 instâncias existentes e as 158 outras fontes permanecem preservadas. Os testes usam as fontes da V6, sobrepostas pelas da V7 e por estas duas fontes V8.

Requer Python 3, `zstandard`, `lz4` e Luau 0.698. Defina `LUAU` e `LUAU_COMPILE` para os executáveis locais. Os simuladores existentes ficam em `../banco-marco10-28/tests`.

```bash
mkdir -p delivery
python tests/run.py > delivery/river.log
python tests/run.py regression.luau > delivery/regression.log
python tools/build.py ../../entregas/Rio_Ponte_V7/LittleLife_Rio_Ponte_V7.rbxl delivery/LittleLife_Rio_Ampliado_Ponte_Tripla_V8.rbxl
```

O construtor exige o hash da entrega V7. Os testes cobrem a duplicação exata da largura ao longo do traçado, três módulos independentes com pista contínua, passagem sob a ponte, margens, circulação, GPS e preservação das comunidades e do distrito. Os 160 scripts foram compilados e o arquivo foi aberto por um decodificador independente. A física, o visual, a natação e o desempenho ainda precisam de Playtest no Roblox Studio; as imagens são prévias técnicas.

## Crédito

Estilo adaptado de “Bridge Road Lowpoly”, de **00amza**, [Sketchfab](https://sketchfab.com/3d-models/bridge-road-lowpoly-a91e8f0d30f140e6b7ccbdf3044cd7c5), [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). A referência original está em `../rio-ponte-v7/referencias/bridge_road_lowpoly.glb`. A V8 repete a adaptação da V7 em três módulos e ajusta apoios, iluminação e acessos. A ponte usa peças nativas, sem depender da publicação de um MeshPart remoto.
