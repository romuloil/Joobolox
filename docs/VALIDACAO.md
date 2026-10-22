# Validação — Marco 5.4

Ferramentas oficiais Luau 0.698, revisão `ff 6d 381e 57bcd 1799d 850d 7fabe 543c 0f 0980a 5d`.

- 57/57 scripts compilados.
- 153 verificações de regras: prisão 42, polícia 34, profissões 39, táxi 19, atividades 19.
- 564 verificações de serviços reais com objetos simulados: prisão 134, roupa de
  custódia 103, atividades 42, polícia 101, uniformes profissionais 107, veículos 36, táxi 41.
- 85 verificações de moradores com consultas ao mapa gerado sob simulação.
- 89.392 verificações geométricas, com 1.642 peças cívicas e 237 árvores. Conferem celas fechadas, caminhos de personagem, apoio real sob
  os pés, escadas, pisos superiores, portas, vagas, lotes, terreno e árvores.
- O gerador relê o XML e compara o conteúdo de todos os scripts com os fontes.

A roupa de custódia é testada em R 6/R 15, incluindo roupas que carregam depois, novas
propriedades do avatar, restauração, troca de personagem e falha de construção.
Os testes de atividades exercitam distância, cura limitada, intervalos, exercício
interrompido, furto com duração e posição, paredes e atributos falsos, gavetas, portas,
entrada em área restrita e limpeza de objetos. A criação do prompt após assumir
realmente o cargo policial tem regressão específica.

A polícia é testada em captura autorizada, espera de 10 s, cancelamento, recaptura
interna, multa e afastamento por abuso, dano apenas em procurados, vítima morta,
pagamento único e ausência de recompensa em simulações. Veículos testam retirada
por emprego/local, motorista, perda do cargo, lentidão temporária e expulsão.

## Limites

Não houve execução do Roblox Studio. Os testes não simulam o motor físico,
renderização, avatares reais, rede, animações online ou DataStore. O gerador aleatório
simulado é diferente do Roblox. Os envelopes geométricos não substituem caminhar e
dirigir no motor real. Confira também roupas em camadas, prompts, barreiras,
escadas, colisões, física do passageiro, celular e desempenho.

## Reproduzir

```sh
python tools/validate_luau.py --luau-dir /workspace/tooling/luau-0.698/source
python tools/build_rbxlx.py src dist/LittleLife_Marco 5_4.rbxlx
```

Ajuste o caminho das ferramentas em outra máquina; veja `tools/VALIDACAO.md`.
Para jogar no Studio, basta o `.rbxlx` entregue. Roteiro: `TESTE_NO_STUDIO.md`.
