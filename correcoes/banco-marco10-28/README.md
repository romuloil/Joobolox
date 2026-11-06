# Correção do banco — base Marco 10.28

Correção limitada ao banco do `modeloprochat.rbxl` enviado pelo usuário. Os três fontes em `src/` correspondem aos ModuleScripts ativos:

- `ServerScriptService/Services/BankBuilder`
- `ServerScriptService/Services/BankService`
- `StarterPlayer/StarterPlayerScripts/Controllers/BankController`

Os arquivos `.rbxl`, `.zip`, o guia e o relatório de preservação estão em `entregas/Banco_Marco10_28/` no repositório.

## Testes

Pré-requisitos: Python 3.10+, Luau 0.698 (executáveis `luau` e `luau-compile`). Para o leitor binário: `pip install -r requirements.txt`.

```sh
LUAU=/caminho/luau python tests/run.py
```

A suíte executa os fontes reais de BankBuilder, BankService, BankController e HeistEvents em Luau. Ela usa um relógio controlado e substitutos dos serviços Roblox. O construtor usa metadados de posição/tamanho extraídos do cofre enviado e também testa sua alternativa feita de peças. O minigame compartilhado e o carregamento de avatares são substituídos; a simulação não executa física, renderização nem replicação reais.

`original/` contém os três módulos anteriores e os dois módulos de referência necessários aos testes. Não são versões para instalar no jogo. `BANK_ORIGINAL=1` executa a suíte contra os módulos originais e reproduz a falha inicial de ativação do crachá no servidor.

## Gerar um arquivo de jogo

Use o arquivo original enviado pelo usuário (SHA-256 `d5471f6223a2472f45ea000d37d6a7b1b165911b83d1ec0644b6a742da7bb18e`):

```sh
LUAU_COMPILE=/caminho/luau-compile python tools/build_delivery.py modeloprochat.rbxl LittleLife_Banco_Corrigido.rbxl
```

O leitor substitui somente as três propriedades `Source` selecionadas. Mantém os outros blocos binários byte a byte, verifica todas as referências e hierarquia e compila todos os scripts do arquivo resultante. O relatório JSON registra hashes, módulos alterados e limites da validação.

O leitor suporta o formato binário e a compressão Zstandard presentes neste upload. Não é um conversor universal de arquivos Roblox.
