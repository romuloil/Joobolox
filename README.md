# Little Life: Minha Cidade — Marco 5.2

Complexo prisional e funções policiais, continuando o Marco 5.1. A arquitetura usa
como referência a imagem enviada pelo usuário: blocos claros, faixas azuis,
telhados laranja, quatro torres e áreas separadas por acessos controlados.

## Downloads desta versão

- [Baixar o jogo para o Roblox Studio](entregas/Marco5_2/LittleLife_Marco5_2.rbxlx?raw=true)
- [Baixar o pacote com código e instruções](entregas/Marco5_2/LittleLife_Marco5_2_Pacote.zip?raw=true)

## Abrir e jogar

Baixe `LittleLife_Marco5_2.rbxlx`, abra no **Roblox Studio → Arquivo → Abrir do arquivo**
e pressione **F5 / Play**. O cenário é construído ao iniciar o jogo.

- **M:** mapa; **V:** carro; **B:** bicicleta; **E:** interações. Há botões no celular.
- A delegacia fica junto da Avenida das Palmeiras. A prisão fica além do anel externo,
  seguindo a mesma avenida para fora da cidade.
- Na delegacia ou na recepção pública da prisão, procure **Plantão policial** para
  entrar em serviço. Há três vagas por servidor, gratuitas nesta versão de testes.
- Retire o kit na armaria/arsenal. Use a mochila do Roblox para equipar as ferramentas;
  no PC também funcionam as teclas numéricas; no celular há um botão de uso.
- Lançador de água: mire e use. Algemas: aproxime-se do suspeito imobilizado. Lanterna:
  use para ligar/desligar. Rádio: consulte os informes da equipe.
- O centro de controle permite operar portões e portas e consultar as celas. Cada
  acesso também tem uma interação local para policiais em serviço.

## Prisão

Há **16 celas individuais**, com cama, sanitário, pia, iluminação, grades e porta
fechada. O preso permanece **15 segundos na cela lacrada**, depois recebe acesso
ao pátio. A pena total é **60 segundos**. Cumprir o prazo ou concluir a rota de
fuga libera o jogador. Resetar o personagem não reinicia os prazos.

O complexo inclui recepção/visitas, armaria, centro de controle, alojamentos,
refeitório, enfermaria, quadra, quatro torres acessíveis e passagem de manutenção.
O heliponto e o posto/conveniência são cenográficos: não incluem voo nem abastecimento.

## Funções policiais implementadas

- Entrada/saída de plantão, limite de três policiais, colete e distintivo originais.
- Retirada/reposição de lançador de água, algemas, lanterna e rádio.
- Imobilização e captura de suspeitos válidos, com alcance, linha de visão,
  equipamento, papel e tempo conferidos pelo servidor. A água não causa dano.
- Registro de informes por categorias, histórico da sessão e consulta pelo rádio.
- Ronda em quatro setores e treino individual com alvo móvel.
- Portões e portas controlados pela equipe; celas operadas pelo terminal, respeitando
  os 15 s iniciais. Fechar a porta não prolonga a pena de ninguém.
- Equipamentos e vaga devolvidos ao sair/resetar. Veículos não contornam a imobilização.

Na área de treino, um policial pode testar água e algemas sem outro jogador.
No Studio há ainda **Simular suspeito (Studio)** na recepção da prisão para testar
captura entre dois jogadores. A simulação de prisão na delegacia continua disponível.
Essas duas simulações de jogador não são habilitadas em servidores publicados.

Cidadãos não podem ser presos livremente. O sistema completo de banco/assaltos ainda
não foi implementado: `PoliceService.markSuspect` é uma API interna para futuros
serviços de crime. Esta versão não inventa crimes, recompensas ou multas, não desconta
saldo e não oferece salários policiais. Os informes usam categorias prontas.

## Código e validação

Os scripts ficam em `src/`, seguindo a hierarquia do Roblox. Para gerar o lugar:

```sh
python3 tools/build_rbxlx.py src dist/LittleLife_Marco5_2.rbxlx
```

O gerador precisa apenas de Python 3. No Windows, pode ser necessário usar `python`
no lugar de `python3`. A execução do jogo requer o Roblox Studio.

Consulte `docs/TESTE_NO_STUDIO.md` para o roteiro e `docs/VALIDACAO.md` para resultados
automatizados e limites. Não houve execução visual do Roblox Studio neste ambiente;
renderização, física, rede e desempenho real precisam de validação nele.
