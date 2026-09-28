# Minerador com IA + painel pixel art

Mining Turtle (CC: Tweaked) + Ollama local + servidor Python. O modelo converte texto em um plano limitado; a turtle valida o plano e pede confirmacao antes de qualquer movimento.

## O que faz

- Abre tunel horizontal de 2 blocos de altura para **frente, direita, esquerda ou tras** (direcoes relativas a orientacao atual).
- Busca um **bloco especifico** por ate 64 blocos, inspecionando frente, acima e abaixo do corredor. Exemplo: `procure minerio de diamante por 12 blocos a esquerda`. O nome precisa ser um ID de bloco Minecraft, como `minecraft:diamond_ore`.
- Volta ao ponto de partida quando o caminho permite; mantem a nova orientacao. Detecta liquidos, inventario cheio e combustivel insuficiente.
- Exibe painel pixel art em `http://127.0.0.1:8766`: slots, itens coletados nesta sessao, combustivel, progresso, direcao e posicao relativa.

**Na busca especifica, a turtle nao quebra outros blocos para chegar ao alvo.** Se pedra ou outro bloco bloquear a frente, ela para e volta. Para abrir caminho atraves de pedra, use primeiro o modo tunel. O modo de busca nao procura cavernas ou veios fora da linha percorrida. A orientacao inicial e chamada de norte, sem GPS; reiniciar o programa redefine a posicao relativa.

## Iniciar no Windows (PowerShell)

Deixe `server.py` e `dashboard.html` na **mesma pasta**.

```powershell
ollama pull qwen3:4b
$env:MINER_TOKEN = 'ESCOLHA-UM-TOKEN-LONGO-E-NOVO'
$env:OLLAMA_MODEL = 'qwen3:4b'
python server.py
```

Em outro terminal:

```powershell
ngrok http 8765
```

Abra o painel **somente no computador com o Python** em `http://127.0.0.1:8766`. O ngrok publica apenas a API na porta 8765; a porta 8766 fica restrita a localhost. O Ollama tambem permanece local. Se o ngrok reiniciar, atualize sua URL na turtle. Como um token curto anterior foi exposto, escolha um novo token e nao publique seu valor no GitHub.

## Na Mining Turtle

Coloque `miner.lua` na turtle. Edite `SERVER` para a URL HTTPS exata mostrada pelo ngrok e `TOKEN` para o valor de `MINER_TOKEN`. O endereco nao deve terminar em `/plan`. Abasteca a turtle e rode `miner`.

Exemplos de pedidos:

```text
abra um tunel de 5 blocos a direita
abra um tunel de 3 blocos para tras
procure minecraft:diamond_ore por 12 blocos a esquerda
```

Confirme com `sim`. Digite `sair` para encerrar. O timeout HTTP do CC: Tweaked e de no maximo 60 segundos. Se o Ollama levar mais que isso, a consulta falha; aqueça o modelo localmente antes de tentar novamente. Se usar Ctrl+T durante a escavacao, a turtle pode parar longe do ponto inicial.

## Limites

Nao aceita instrucoes livres de Lua, escavacao vertical ou deposito automatico em baus. Os itens coletados sao calculados pela diferenca positiva no inventario entre etapas: movimentacao manual e reinicios podem afetar a contagem. O painel depende de o programa `miner` estar aberto; a API guarda apenas o ultimo estado em memoria, sem persistencia apos reiniciar o Python.
