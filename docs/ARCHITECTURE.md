# Arquitetura do construtor GrabCraft

1. A Turtle executa `grabcraft <url>` e consulta o serviço headless via ngrok.
2. `server/grabcraft_service.py` valida o host, extrai o ID do modelo 3D e busca o JSON voxel oficial usado pelo visualizador do GrabCraft.
3. A API devolve o resumo de dimensões/materiais e serve uma camada por requisição para limitar memória na Turtle.
4. A Turtle faz preflight de GPS, inventário e combustível. Se o plano é viável, constrói deterministicamente por camadas usando coordenadas GPS, sem comandos Lua arbitrários.
5. A execução interrompe em obstáculo, falta de item ou divergência GPS. O mesmo link pode continuar um plano parcial desde que os blocos já colocados correspondam ao modelo.

A versão atual não é um parser de imagens: depende de páginas com modelo 3D voxelizado em JSON. Ela não minera/limpa a área e não substitui blocos ocupados. Estados especiais podem ser aproximados quando o GrabCraft não fornece metadados suficientes para reproduzi-los com as APIs normais de Turtle.
