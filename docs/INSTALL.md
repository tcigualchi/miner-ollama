# Instalação e operação

## Servidor

Na primeira execução, o run.ps1 cria e guarda credenciais fortes em `server/data/secrets.json`, inicia a API e abre o ngrok. Ele mostra os valores de acesso no terminal. Também é possível definir variáveis antes de iniciar:

    $env:WEB_PASSWORD = "uma-senha-longa"
    $env:FLEET_ENROLLMENT_TOKEN = "um-token-de-cadastro-longo"
    $env:PLAYER_BEACON_TOKEN = "um-token-diferente-para-o-pocket"
    .\server\run.ps1

O run.ps1 inicia Uvicorn e ngrok e imprime a URL pública. A opção HTTP deve estar ativada na configuração do CC:Tweaked. Para usar um endereço local, permita o IP local na configuração do mod.

## Turtle

O bootstrap pede URL HTTPS e token de cadastro uma única vez. Ele gera um token individual, grava /fleet/config.lua, baixa o agente e cria o startup.

    wget run https://URL/bootstrap/install.lua https://URL TOKEN "Construtora 01"

Depois do cadastro, configure opcionalmente a base em /fleet/config.lua:

    base = { x = 529, y = 72, z = 351 }

Uma Turtle precisa de modem wireless para GPS. O primeiro movimento com GPS calibra a orientação; deixe um bloco livre à frente quando for possível. Turtles de mineração precisam de uma ferramenta capaz de quebrar blocos.

## Pocket Beacon

O Pocket Computer deve estar com o jogador e em alcance da rede GPS:

    wget run https://URL/bootstrap/beacon.lua https://URL TOKEN_DO_BEACON "João"

O beacon envia nome, X, Y, Z e dimensão configurada (o quarto argumento opcional, por exemplo `minecraft:the_nether`). Venha até mim navega ao último local recebido e exige que o beacon esteja ativo e atualizado nos últimos 12 segundos.

## Compatibilidade com o controlador antigo

O servidor ainda aceita `POST /api/status` autenticado por `X-Fleet-Token` para parar os 422 da versão que usa um computador central. Esse registro é apenas de monitoramento. Para receber tarefas, instale o agente atual diretamente na Turtle pelo bootstrap; o painel identifica registros antigos e não os oferece como trabalhadores.

## Operação segura

Comece com Vá para X Y Z em uma área livre. Depois teste uma parede pequena e mineração curta. O algoritmo de navegação tenta cavar e atacar obstáculos quando a tarefa permite; não o use perto de construções que você queira preservar.
