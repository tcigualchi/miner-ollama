# Construção de blueprints do GrabCraft via Turtle

O comando principal recebe uma página individual de blueprint, busca seu modelo 3D voxelizado, consulta a posição GPS da Turtle, confere materiais/combustível e constrói o modelo em camadas. Não há painel web nesta experiência; a resposta e o progresso aparecem no terminal da própria Turtle. O ngrok expõe apenas a API headless do PC central.

## PC central

1. Tenha Python 3.10+ e ngrok autenticado no PATH.
2. Instale as dependências uma vez: `python -m pip install -r server/requirements.txt`.
3. Execute `server/run.bat` ou `server/run.ps1` e mantenha essa janela aberta. O terminal imprime a URL do ngrok e um comando de instalação com token individual do inspetor.

## Turtle

Ative HTTP no CC:Tweaked e permita o host ngrok. Execute o comando de instalação impresso pelo PC uma vez:

    wget run https://SEU-NGROK/install.lua https://SEU-NGROK TOKEN

Para enviar uma construção, posicione a Turtle no canto mínimo da fundação, em espaço livre, e execute o link individual da página GrabCraft:

    grabcraft https://www.grabcraft.com/minecraft/troll-watchtower/military-buildings

A Turtle usa o GPS atual como origem: X cresce para leste, Z para sul e Y para cima. Ela calibra a direção com um movimento curto e reversível, verifica se os itens e o combustível bastam antes de iniciar, não escava blocos e para se encontrar obstáculos ou desvios no GPS. Se parar depois de iniciar, pode reexecutar o mesmo link para retomar blocos já colocados que coincidam com o plano.

Para atualizar o comando da Turtle, execute novamente o mesmo comando `wget run .../install.lua ...`; ele substitui o programa local.

## Limites do construtor

A construção usa as coordenadas voxel do modelo 3D do GrabCraft (não uma interpretação por IA das imagens). A primeira versão limita cada dimensão a 128 blocos e o projeto a 12.000 voxels. O inventário precisa conter todos os materiais ao mesmo tempo. Itens de blocos são associados a nomes conhecidos, e materiais ausentes ou ambíguos fazem a Turtle parar antes de se mover.

O modelo do site descreve nomes, posições e algumas direções, mas pode não expor todos os estados internos do Minecraft. Estados como metade/orientação de slabs podem diferir; a Turtle reporta essa aproximação antes de construir. Blocos configurados como indisponíveis em sobrevivência são ignorados no inventário e na construção; atualmente isso inclui `Grass`/`Grass Block`, barreira, bedrock, spawner, blocos de comando/estrutura, portal e outros blocos sem item normal. O terminal mostra a contagem e os nomes ignorados. A Turtle não limpa terreno e não substitui blocos: área ocupada interrompe a execução. Coloque-a junto a uma área plana e livre, com espaço acima para calibrar e construir. Teste primeiro um blueprint pequeno em local descartável.

Páginas que não têm um JSON de modelo 3D no GrabCraft não são aceitas para construção automática. A listagem geral `/minecraft/buildings` não é um blueprint; use a página individual da construção.

## Serviço e segurança

`server/run.ps1` inicia somente o inspetor sem interface. O inspetor aceita links HTTPS de GrabCraft, limita o tamanho do modelo e protege a consulta com token. O token é gravado em `server/data/grabcraft-token.txt`, ignorado pelo Git. Para revogá-lo, pare o serviço, apague esse arquivo e inicie novamente; reinstale então as Turtles com o token novo.

O painel e o sistema de frota anteriores foram preservados como legado em `server/run-fleet-legacy.ps1`, mas não fazem parte deste fluxo.
