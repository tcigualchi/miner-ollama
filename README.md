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

A Turtle usa o GPS atual como origem: X cresce para leste, Z para sul e Y para cima. Ela calibra a direção com um movimento curto e reversível, verifica os itens antes de iniciar, mantém uma reserva de combustível, não escava blocos e para se encontrar obstáculos. Se interromper uma construção, salva a origem e o cursor para retomá-la depois.

O reabastecimento automático vem ativado: mantenha carvão ou carvão vegetal em qualquer slot da Turtle. Ela identifica esses combustíveis pela API do CC:Tweaked, consome apenas esses itens e pausa para reposição se o nível cair abaixo da reserva. Uma mochila colocada como item no inventário continua sendo apenas um item: a Turtle não consegue ler o conteúdo guardado dentro dela. O inventário padrão da Turtle tem 16 slots fixos.

Para atualizar o comando da Turtle, execute novamente o mesmo comando `wget run .../install.lua ...`; ele substitui o programa local.

## Abastecimento automatico por baus comuns

O computador central seleciona os itens; a Turtle nao precisa de modem cabeado. Monte uma rede cabeada do CC:Tweaked ligando um modem cabeado no Advanced Computer aos modems cabeados dos baus de materiais e do bau de entrega. Deixe tambem um modem wireless no Advanced Computer para receber pedidos rednet. O bau de entrega deve ficar diretamente abaixo da Turtle quando ela estiver na estacao; funis podem alimentar os baus de materiais.

No Advanced Computer, use `peripheral.getNames()` para localizar o nome do bau de entrega. Baixe e inicie o despachante com `wget run https://SEU-NGROK/chest-supply.lua`. Na primeira execucao, informe uma chave compartilhada com pelo menos 8 caracteres e o nome do bau de entrega. Anote o ID exibido por `id` e use a mesma chave ao instalar a Turtle. O despachante procura o ID exato `minecraft:...` nos inventarios da rede cabeada e transfere ate 64 itens para o bau de entrega.

Instale/reinstale o agente enquanto a Turtle estiver sobre o bau de entrega; informe o ID do Advanced Computer, a mesma chave e confirme a estacao manual. O GPS grava a posicao da estacao. Ao faltar um bloco, a Turtle volta, pede o material, recolhe do bau inferior com `suckDown()` e retorna a obra. Deixe espaco no inventario da Turtle; ele continua limitado a 16 slots. A rede cabeada precisa ligar os baus ao computador, mas nao precisa chegar a Turtle. O ME Bridge e opcional e nao e necessario neste fluxo.

## Limites do construtor

A construção usa as coordenadas voxel do modelo 3D do GrabCraft (não uma interpretação por IA das imagens). A primeira versão limita cada dimensão a 128 blocos e o projeto a 12.000 voxels. Não é preciso carregar todos os materiais de uma vez: quando faltar o próximo bloco, a Turtle pausa naquele ponto e verifica o inventário a cada dois segundos; ao inserir o bloco, ela continua automaticamente. Mantenha um slot livre e retire itens que não fazem parte da construção se o inventário estiver cheio. A Turtle ainda precisa ter combustível suficiente para o trajeto planejado.

Nomes antigos do GrabCraft são normalizados para os itens atuais da lista 1.21.1: `Hardened Clay`/`hardened_clay` vira `minecraft:terracotta`, e nomes como `White Stained Clay`/`white_stained_clay` viram `minecraft:white_terracotta` (a mesma regra cobre todas as cores). `Block of Quartz` também é normalizado para `minecraft:quartz_block`. A Turtle salva a origem GPS e o próximo bloco por blueprint; após uma nova instalação, ela retoma desse cursor. A origem pode ser informada explicitamente como argumentos adicionais do comando. A localização usa leituras GPS confirmadas e espera o sinal retornar se houver uma falha temporária.

Rótulos legados também são convertidos para variantes atuais: `Wooden Trapdoor`, `Wood Trapdoor` e `Trapdoor` viram `minecraft:oak_trapdoor`.

O modelo do site descreve nomes, posições e algumas direções, mas pode não expor todos os estados internos do Minecraft. Estados como metade/orientação de slabs podem diferir; a Turtle reporta essa aproximação antes de construir. Blocos configurados como indisponíveis em sobrevivência são ignorados no inventário e na construção; atualmente isso inclui `Grass`/`Grass Block`, barreira, bedrock, spawner, blocos de comando/estrutura, portal e outros blocos sem item normal. O terminal mostra a contagem e os nomes ignorados. A Turtle não limpa terreno e não substitui blocos: área ocupada interrompe a execução. Coloque-a junto a uma área plana e livre, com espaço acima para calibrar e construir. Teste primeiro um blueprint pequeno em local descartável.

Páginas que não têm um JSON de modelo 3D no GrabCraft não são aceitas para construção automática. A listagem geral `/minecraft/buildings` não é um blueprint; use a página individual da construção.

## Serviço e segurança

`server/run.ps1` inicia somente o inspetor sem interface. O inspetor aceita links HTTPS de GrabCraft, limita o tamanho do modelo e protege a consulta com token. O token é gravado em `server/data/grabcraft-token.txt`, ignorado pelo Git. Para revogá-lo, pare o serviço, apague esse arquivo e inicie novamente; reinstale então as Turtles com o token novo.

O painel e o sistema de frota anteriores foram preservados como legado em `server/run-fleet-legacy.ps1`, mas não fazem parte deste fluxo.
