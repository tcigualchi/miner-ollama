# CC Fleet OS

Sistema de coordenação de Turtles para CC:Tweaked. O painel recebe uma tarefa em linguagem natural, converte-a em um plano estruturado e a entrega a agentes Lua que executam apenas operações determinísticas permitidas.

## Início rápido

1. Instale Python 3.10+ e ngrok (autenticado) e as dependências: python -m pip install -r server/requirements.txt.
2. Inicie com server/run.bat. Ele inicia API e ngrok, cria segredos fortes em server/data/secrets.json na primeira execução e mostra URL, senha e tokens no terminal.
3. Opcionalmente, defina WEB_PASSWORD, FLEET_ENROLLMENT_TOKEN e PLAYER_BEACON_TOKEN antes de iniciar para substituir os segredos gerados.
4. Em cada Turtle, execute um único comando:

       wget run https://SEU-ENDERECO/bootstrap/install.lua https://SEU-ENDERECO SEU_TOKEN_DE_CADASTRO "Mineradora 01"

5. Abra a URL no navegador e entre com WEB_PASSWORD.

Consulte [instalação detalhada](docs/INSTALL.md) e [arquitetura](docs/ARCHITECTURE.md).

## Tarefas reconhecidas

- Venha até mim
- Mine uma área de 20x20
- Limpe uma área de 20x20
- Construa uma parede de pedra 30x10
- Construa uma casa 20x20
- Construa uma ponte 16
- Vá para 529 72 351
- Volte para a base

A interpretação resulta em um tipo de tarefa e parâmetros validados no servidor. Nenhum texto da IA ou do painel é executado como Lua.

## Limites conhecidos do CC:Tweaked base

GPS retorna somente X/Y/Z; dimensão e direção são mantidas pelo agente. A dimensão começa como minecraft:overworld e pode ser ajustada no arquivo /fleet/config.lua.

Uma Turtle comum não tem API para ler a posição de jogadores. Para Venha até mim, use o Pocket Beacon:

       wget run https://SEU-ENDERECO/bootstrap/beacon.lua https://SEU-ENDERECO TOKEN_DO_BEACON "João" minecraft:overworld

Carregue o Pocket Computer. Ele envia sua posição GPS ao servidor a cada três segundos. Não use comandos de servidor ou periféricos de mods extras como se fossem APIs nativas do CC:Tweaked.
