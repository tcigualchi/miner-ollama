# CC Fleet AI

Sistema de frota para CC:Tweaked com:

- GPS
- navegação de turtles
- comunicação Rednet
- PC central
- Pocket Computer
- servidor web
- Ollama (`qwen3:4b`) para interpretar pedidos
- geração determinística de blueprint
- construção automática por camadas

## Arquitetura

Web -> FastAPI/Ollama -> fila -> PC Central -> Rednet -> Turtle -> GPS

A turtle busca o blueprint completo no servidor por HTTP usando o `plan_id`.

## 1. GPS

Use os quatro hosts GPS que você já configurou. Cada computador deve executar:

```lua
shell.run("gps", "host", X, Y, Z)
```

com as coordenadas reais daquele computador.

## 2. Servidor Windows

Abra PowerShell na pasta `server`:

```powershell
python -m pip install -r requirements.txt
ollama pull qwen3:4b
```

Edite `run.ps1` e troque:

- `FLEET_TOKEN`
- `WEB_PASSWORD`

Depois:

```powershell
.\run.ps1
```

Teste:

```text
http://127.0.0.1:8000/health
```

Se for usar ngrok:

```powershell
ngrok http 8000
```

Copie a URL HTTPS do ngrok.

## 3. PC central

Copie os arquivos da pasta `central` para o Advanced Computer:

- `/config.lua`
- `/controller.lua`
- `/startup.lua`

Edite `config.lua`:

- `server_url` = URL pública do servidor
- `fleet_token` = exatamente o mesmo token do servidor

Execute:

```text
reboot
```

Anote o ID mostrado pelo computador.

## 4. Turtle

Copie para a turtle:

- `/config.lua`
- `/worker.lua`
- `/startup.lua`
- `/lib/net.lua`
- `/lib/nav.lua`
- `/lib/inventory.lua`
- `/lib/builder.lua`

Edite `config.lua`:

- `controller_id` = ID do PC central
- `server_url` = mesma URL
- `fleet_token` = mesmo token
- `turtle_name` = nome único

Depois:

```text
reboot
```

## 5. Pocket Computer

Copie:

- `/config.lua`
- `/remote.lua`
- `/startup.lua`

Configure `controller_id`, equipe um modem wireless e reinicie.

## 6. Construindo pelo navegador

Abra a URL do servidor no navegador.

Informe:

- senha do painel
- ID do PC central
- ID da turtle
- X, Y, Z do canto de origem
- descrição da casa

Exemplo:

```text
Casa medieval 13x11, dois andares, paredes de spruce, bastante vidro,
porta na frente e telhado.
```

O servidor:

1. envia o texto ao Ollama;
2. recebe parâmetros estruturados;
3. limita materiais e dimensões;
4. gera o blueprint;
5. salva o plano;
6. coloca um comando na fila;
7. o PC central recebe;
8. envia o `plan_id` à turtle;
9. a turtle baixa o blueprint e constrói.

## Materiais

A turtle precisa possuir os blocos físicos.

Se acabar um material no meio da construção, ela entra em:

```text
WAITING_MATERIAL
```

e verifica o inventário a cada 2 segundos. Coloque o material e ela continua.

O painel mostra a quantidade total prevista antes da construção.

## Área de construção

A versão atual assume que o espaço onde a turtle viajará está livre.

Ela NÃO quebra obstáculos durante a construção. Isso é proposital para evitar destruir a própria casa.

A coordenada de origem é o canto do piso da construção.

## Segurança

Não exponha o servidor com os valores padrão.

Troque:

- `FLEET_TOKEN`
- `WEB_PASSWORD`

O Rednet não oferece autenticação forte por si só. Em um servidor multiplayer não confiável,
adicione autenticação/assinatura das mensagens antes de aceitar comandos de outros computadores.

## Comandos do PC central

```text
list
ping <turtle_id>
goto <turtle_id> <x> <y> <z>
build <turtle_id> <plan_id>
```

## Limitação atual

A construção automática já funciona, mas esta primeira versão produz casas paramétricas
retangulares. Ela entende estilo, tamanho, andares, materiais básicos, janelas, porta e telhado.

A evolução natural é adicionar módulos determinísticos para:

- quartos e divisórias
- escadas
- varanda
- garagem
- torres
- castelos
- casas em L
- decoração
- iluminação
- mobília
- múltiplas turtles dividindo setores
- estação automática de reabastecimento
