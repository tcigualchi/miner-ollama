# Arquitetura do CC Fleet OS

    Painel web <--> sessão HTTP e WebSocket <--> API FastAPI + SQLite
                                                     ^          |
                                                     | HTTPS    | tarefas e eventos
                                                     |          v
                                                Pocket Beacon  Agente Turtle
                                                   | GPS          | gps.locate e turtle API

## Coordenação

O backend guarda agentes, tarefas, checkpoints, logs e posições em SQLite. Um heartbeat com intervalo curto marca a Turtle online; depois de 20 segundos sem heartbeat ela passa a OFFLINE.

Uma tarefa em grupo cria subtarefas exclusivas. A mineração e a limpeza são divididas em faixas por Turtle. Construção de casas ainda é uma tarefa individual e o servidor a rejeita quando várias Turtles são selecionadas para evitar que construam no mesmo espaço. O servidor só atribui tarefas a agentes online, livres e com o agente novo instalado.

## Segurança

O token de cadastro só cria ou gira a credencial de um agente. Depois do cadastro, cada Turtle usa seu agent_id e token próprios no cabeçalho X-Agent-Token. O painel usa um cookie HttpOnly de sessão de oito horas após validar WEB_PASSWORD; a senha não está no JavaScript nem é armazenada pelo aplicativo.

Use HTTPS na URL pública. Nunca compartilhe o token de cadastro ou o token do Pocket Beacon.

## Recuperação

O agente grava o ID da tarefa e checkpoint em /fleet/state.json por troca atômica. No reinício, ele recupera a tarefa RUNNING atribuída a ele; tarefas de construção usam coordenadas absolutas e áreas mineradas podem ser refeitas desde o início. Nem toda tarefa retoma exatamente do último bloco. Falhas recuperáveis de combustível, inventário cheio, GPS, beacon e bloqueio deixam a tarefa BLOCKED e tentam novamente após 30 segundos; outros erros são marcados FAILED.

## Atualização

O bootstrap instala todos os módulos em /fleet, configura startup e inicia o agente. O agente consulta o manifesto autenticado ao iniciar e a cada 15 minutos enquanto estiver ocioso. Para publicar uma versão nova, altere app.version e reinicie o servidor; tarefas em andamento terminam antes da atualização automática.

## Migração da versão central antiga

O endpoint `/api/status` aceita heartbeats do controlador antigo com `X-Fleet-Token` para evitar respostas 422 enquanto ele é migrado. Esses computadores aparecem como monitoramento legado e não recebem tarefas novas. Instale o agente atual na Turtle para habilitar a fila autenticada de tarefas.

## IA futura

parse_task é a fronteira de interpretação. A interpretação atual é determinística e reconhece somente formatos simples; não há integração de IA nem detecção de veios de minério ainda. Uma integração Ollama pode ser adicionada acima dela, mas deve produzir somente o mesmo schema validado de tipos permitidos: goto, follow_player, mine_area, clear_area, build_wall, build_house, build_bridge e return_base. O agente não carrega Lua recebido pela rede.
