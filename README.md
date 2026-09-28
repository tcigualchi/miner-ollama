# CC Fleet AI v2

Versao ampliada com:

- site estilo pixel art
- painel de frota em tempo quase real
- status de todas as turtles
- comandos de construcao com IA
- goto
- dig line
- quarry
- Pocket Computer atualizado
- UTF-8 em todo o site para evitar caracteres quebrados

## O que mudou em relacao a v1

### Dashboard web

O servidor agora recebe status do PC central e mostra:

- estado atual de cada turtle
- posicao X/Y/Z
- combustivel
- extras (destino, plan_id, progresso, etc.)
- fila de comandos pendentes
- eventos recentes

### Novos comandos

- `goto`
- `build`
- `dig_line`
- `quarry`
- `reboot`

## Observacao importante sobre quarry

Nesta versao, o comando `quarry` limpa a area em serpentina no plano atual e abre altura configuravel.
Ele e intencionalmente conservador para nao destruir sua propria base por acidente.
Se quiser, a proxima iteracao pode virar uma quarry 3D completa por camadas com retorno automatico ao bau.

## Instalação rápida

### Servidor

Na pasta `server`:

```powershell
python -m pip install -r requirements.txt
ollama pull qwen3:4b
```

Edite `run.ps1` e troque:

- `FLEET_TOKEN`
- `WEB_PASSWORD`

Rode:

```powershell
.un.ps1
```

Se for usar ngrok:

```powershell
ngrok http 8000
```

### PC central

Copie:

- `central/config.lua`
- `central/controller.lua`
- `central/startup.lua`

Edite `config.lua` com:

- URL do ngrok
- mesmo token do servidor

### Turtle

Copie tudo da pasta `turtle/` mantendo a pasta `lib/`.

Edite `turtle/config.lua`:

- `controller_id` = ID do PC central
- `server_url` = URL do ngrok
- `fleet_token` = mesmo token
- `turtle_name` = nome unico

### Pocket

Copie `pocket/` e configure o ID do central.

## Exemplos de uso no site

### Construção com IA

```text
Casa medieval 13x11, dois andares, paredes de spruce, janelas grandes e telhado.
```

### Goto

- Controller ID: 8
- Turtle ID: 0
- X/Y/Z desejados

### Dig line

- comprimento: 20
- altura: 2

### Quarry

- largura: 8
- profundidade: 12
- altura: 3

## Comandos do central

```text
list
ping <id>
goto <id> <x> <y> <z>
dig <id> <len> [altura]
quarry <id> <w> <d> [altura]
build <id> <plan_id>
reboot <id>
```
