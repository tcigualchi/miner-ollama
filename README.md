# CC: Tweaked + Ollama: minerador por texto

Primeira versao: a Mining Turtle escava um tunel reto de 2 blocos de altura por ate 64 blocos. Ela consulta o Ollama por meio de um servidor Python, pede confirmacao, verifica combustivel e inventario, para ao detectar agua/lava e tenta voltar ao inicio. O modelo apenas escolhe uma tarefa e um comprimento; ele nao executa codigo Lua.

## No computador com Ollama

1. Instale o Ollama, inicie o servico e baixe um modelo: `ollama pull qwen3:4b`.
2. Em um terminal Linux/macOS:
   ```sh
   export MINER_TOKEN='escolha-uma-senha-longa-aleatoria'
   export OLLAMA_MODEL='qwen3:4b'
   python3 server.py
   ```
   No PowerShell, use `$env:MINER_TOKEN='escolha-uma-senha-longa-aleatoria'` e `$env:OLLAMA_MODEL='qwen3:4b'`, depois `python server.py`.
3. Em outro terminal, publique somente o servidor Python: `ngrok http 8765`. Copie a URL HTTPS gerada.

O servidor Python se conecta ao Ollama localmente. Nao publique a porta 11434 do Ollama.

## Na Mining Turtle

1. Coloque `miner.lua` no computador da turtle (por exemplo, publique o arquivo em seu GitHub e use `wget run https://raw.githubusercontent.com/USUARIO/REPO/main/miner.lua` depois de configurar as duas primeiras linhas).
2. Edite `SERVER` com a URL HTTPS do ngrok e `TOKEN` com o mesmo valor de `MINER_TOKEN`.
3. Abasteca a turtle, deixe-a apontada para o local desejado e execute `miner`.
4. Digite `abra um tunel de 12 blocos` e confirme com `sim`.

O endereco gratuito do ngrok pode mudar entre inicializacoes. Atualize `SERVER` quando isso ocorrer. Para interromper manualmente, use Ctrl+T no computador da turtle; neste caso ela pode parar longe da origem. Durante o retorno, obstaculos colocados no caminho tambem podem impedi-la de voltar.

## Limites

Nao remove obstaculos no retorno e nao deposita itens em bau. Para escavacao extensa, exploracao de minerios, GPS, recarga e retomada apos reinicio, essas funcoes precisam de uma proxima etapa.
