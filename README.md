# CC Fleet AI v2

Painel para controlar turtles do CC:Tweaked com construção via Ollama, navegação, escavação linear e quarry. A frota, a fila e os eventos são atualizados automaticamente no navegador.

## Instalação

No computador que hospeda o servidor:

1. Instale as dependências com `python -m pip install -r server/requirements.txt`.
2. Instale o ngrok, autentique uma vez com `ngrok config add-authtoken SEU_TOKEN` e verifique que `ngrok` está no PATH. Se estiver em outro local, defina a variável `NGROK_PATH` com o caminho de `ngrok.exe`.
3. Configure `FLEET_TOKEN` e `WEB_PASSWORD` em `server/run.ps1` ou nas variáveis de ambiente. Use valores fortes diferentes dos exemplos.
4. Para construção com IA, instale Ollama e execute `ollama pull qwen3:4b`.
5. Execute `server/run.bat` com duplo clique, ou rode `powershell -File server/run.ps1` na raiz do projeto.

O inicializador abre o servidor e o túnel ngrok, aguarda os dois ficarem prontos e mostra as URLs local e pública. Ao interromper, encerra ambos. A URL do ngrok gratuito pode mudar entre execuções. Copie a URL mostrada para `server_url` em `central/config.lua` e `turtle/config.lua`; se quiser uma URL permanente, configure um domínio estático no ngrok.

## ComputerCraft

- Copie os arquivos de `central/` para o PC central e configure `central/config.lua` com a URL pública e o mesmo `FLEET_TOKEN`.
- Copie `turtle/` para a turtle, mantendo `lib/`, e configure `turtle/config.lua` com o ID da central, a URL pública e o token.
- Copie `pocket/` para o Pocket Computer, se quiser controle pelo jogo.
- É necessário um modem wireless; o GPS melhora a navegação e permite exibir coordenadas.

## Painel

Abra a URL exibida no terminal. Use a senha do painel e os IDs da central e da turtle para enviar comandos. O painel oferece construção com IA, navegação, escavação linear e quarry. A quarry limpa uma área no plano atual em serpentina com a altura configurada.

O status da turtle aceita inventário e detalhes vazios enviados pelo ComputerCraft, mesmo quando o JSON usa `[]` para tabelas Lua vazias. Para aplicar também a correção de envio e a mensagem de erro no terminal, atualize `central/controller.lua` no PC central.
