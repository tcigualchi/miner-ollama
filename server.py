import json
import os
import threading
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = os.getenv("BIND_HOST", "127.0.0.1")
PORT = int(os.getenv("PORT", "8765"))
DASHBOARD_PORT = int(os.getenv("DASHBOARD_PORT", "8766"))
TOKEN = os.getenv("MINER_TOKEN", "")
MODEL = os.getenv("OLLAMA_MODEL", "qwen3:4b")
OLLAMA_URL = os.getenv("OLLAMA_URL", "http://127.0.0.1:11434/api/generate")
HERE = os.path.dirname(os.path.abspath(__file__))
STATE = {"online": False, "status": "Aguardando turtle", "inventory": [],
         "collected": {}, "position": {"x": 0, "y": 0, "z": 0},
         "heading": "norte", "fuel": 0, "progress": 0, "total": 0, "estimate": 0}
LOCK = threading.Lock()
SCHEMA = {
    "type": "object",
    "properties": {
        "task": {"type": "string", "enum": ["tunnel", "mine_target", "place", "area", "unsupported"]},
        "direction": {"type": "string", "enum": ["frente", "tras", "direita", "esquerda", "cima", "baixo"]},
        "length": {"type": "integer", "minimum": 0, "maximum": 4096},
        "block": {"type": "string"},
        "width": {"type": "integer", "minimum": 0, "maximum": 256},
        "height": {"type": "integer", "minimum": 0, "maximum": 256},
        "depth": {"type": "integer", "minimum": 0, "maximum": 64},
    },
    "required": ["task", "direction", "length", "block", "width", "height", "depth"],
    "additionalProperties": False,
}


class Handler(BaseHTTPRequestHandler):
    def reply(self, status, body):
        data = json.dumps(body, ensure_ascii=True).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path in ("/", "/dashboard", "/dashboard.html"):
            with open(os.path.join(HERE, "dashboard.html"), "rb") as file:
                data = file.read()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data)
        elif self.path == "/api/state":
            if not TOKEN or self.headers.get("X-Miner-Token") != TOKEN:
                return self.reply(401, {"error": "Token invalido"})
            with LOCK:
                return self.reply(200, STATE.copy())
        else:
            self.reply(404, {"error": "Rota inexistente"})

    def do_POST(self):
        if self.path not in ("/plan", "/telemetry"):
            return self.reply(404, {"error": "Rota inexistente"})
        if not TOKEN or self.headers.get("X-Miner-Token") != TOKEN:
            return self.reply(401, {"error": "Token invalido"})
        try:
            size = int(self.headers.get("Content-Length", "0"))
            if not 0 < size <= 8192:
                return self.reply(400, {"error": "Tamanho invalido"})
            req = json.loads(self.rfile.read(size))
            if not isinstance(req, dict):
                return self.reply(400, {"error": "JSON invalido"})
            if self.path == "/telemetry":
                if not isinstance(req.get("inventory"), list) or not isinstance(req.get("position"), dict):
                    return self.reply(400, {"error": "Telemetria invalida"})
                with LOCK:
                    STATE.update({k: req[k] for k in STATE if k in req})
                    STATE["online"] = True
                return self.reply(200, {"ok": True})
            prompt = req.get("prompt")
            if not isinstance(prompt, str) or not 0 < len(prompt.strip()) <= 500:
                return self.reply(400, {"error": "Escreva um pedido de ate 500 caracteres"})
            payload = {
                "model": MODEL, "stream": False, "think": False, "keep_alive": "15m",
                "format": SCHEMA, "options": {"temperature": 0},
                "prompt": (
                    "Converta o pedido em JSON para uma Mining Turtle. "
                    "tunnel abre tunel horizontal de 2 blocos de altura, ou escava poco vertical "
                    "de 1 bloco de largura para cima/baixo, por length passos (1 a 4096). "
                    "mine_target percorre ate length blocos e minera somente o bloco block indicado; "
                    "block deve ser id exato Minecraft, como minecraft:diamond_ore. "
                    "place coloca UM bloco do inventario adjacente, com length=1 e block="
                    "id Minecraft exato do item, por exemplo minecraft:cobblestone. "
                    "area cava um buraco retangular: primeiro contorno, depois interior em faixas. "
                    "width e largura para a direita, height e comprimento para frente, depth e "
                    "profundidade para baixo (se nao indicada, use 1). Para area use length=0, "
                    "direction=frente, block vazio. Dimensoes width/height 1..256, depth 1..64. "
                    "Para as outras tarefas use width=0, height=0, depth=0. "
                    "direction relativa a frente atual: frente, tras, direita, esquerda, cima, baixo. "
                    "Sem direcao, use frente. tunnel usa block vazio. "
                    "Sem comprimento para tunnel/mine_target use unsupported com length=0, "
                    "direction=frente, block vazio. "
                    "Exemplo: abra um tunel de 3 blocos a direita => "
                    '{"task":"tunnel","direction":"direita","length":3,"block":""}. '
                    "Exemplo: procure minerio de diamante por 12 blocos a esquerda => "
                    '{"task":"mine_target","direction":"esquerda","length":12,'
                    '"block":"minecraft:diamond_ore"}. '
                    "Exemplo: coloque pedra abaixo => "
                    '{"task":"place","direction":"baixo","length":1,"block":"minecraft:cobblestone"}. '
                    "Exemplo: cave um buraco 8x8 com 2 blocos de profundidade => "
                    '{"task":"area","direction":"frente","length":0,"block":"",'
                    '"width":8,"height":8,"depth":2}. '
                    "Pedido: " + prompt),
            }
            request = urllib.request.Request(
                OLLAMA_URL, json.dumps(payload).encode("utf-8"),
                {"Content-Type": "application/json"}, method="POST")
            with urllib.request.urlopen(request, timeout=55) as response:
                raw = json.load(response)["response"]
            plan = json.loads(raw)
            if not isinstance(plan, dict) or plan.get("task") not in ("tunnel", "mine_target", "place", "area", "unsupported"):
                return self.reply(422, {"error": "Plano invalido: " + str(raw)[:150]})
            if plan["task"] == "unsupported":
                return self.reply(200, {"task": "unsupported", "direction": "frente", "length": 0, "block": ""})
            if plan["task"] == "area":
                width, height, depth = plan.get("width"), plan.get("height"), plan.get("depth")
                if (type(width) is not int or type(height) is not int or type(depth) is not int
                        or not 1 <= width <= 256 or not 1 <= height <= 256 or not 1 <= depth <= 64):
                    return self.reply(422, {"error": "Dimensoes invalidas: " + str(raw)[:150]})
                return self.reply(200, {"task": "area", "width": width, "height": height, "depth": depth})
            direction, length, block = plan.get("direction"), plan.get("length"), plan.get("block")
            if direction not in ("frente", "tras", "direita", "esquerda", "cima", "baixo") or type(length) is not int or not 1 <= length <= 4096:
                return self.reply(422, {"error": "Direcao/comprimento invalidos: " + str(raw)[:150]})
            if plan["task"] in ("mine_target", "place"):
                if not isinstance(block, str) or not block.startswith("minecraft:") or not 1 <= len(block) <= 64:
                    return self.reply(422, {"error": "Bloco invalido: " + str(raw)[:150]})
                if plan["task"] == "place" and length != 1:
                    return self.reply(422, {"error": "Colocacao aceita um bloco por comando"})
            else:
                block = ""
            return self.reply(200, {"task": plan["task"], "direction": direction, "length": length, "block": block})
        except (ValueError, KeyError, TypeError, urllib.error.URLError, TimeoutError) as exc:
            return self.reply(502, {"error": "Falha ao consultar Ollama: " + str(exc)[:180]})


class Dashboard(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/api/state":
            with LOCK:
                data = json.dumps(STATE, ensure_ascii=True).encode("utf-8")
            content_type = "application/json; charset=utf-8"
        elif self.path in ("/", "/index.html"):
            with open(os.path.join(HERE, "dashboard.html"), "rb") as file:
                data = file.read()
            content_type = "text/html; charset=utf-8"
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)


if __name__ == "__main__":
    if not TOKEN:
        raise SystemExit("Defina MINER_TOKEN antes de iniciar o servidor")
    dashboard = ThreadingHTTPServer(("127.0.0.1", DASHBOARD_PORT), Dashboard)
    threading.Thread(target=dashboard.serve_forever, daemon=True).start()
    print(f"Turtle: http://{HOST}:{PORT} | Painel: http://127.0.0.1:{DASHBOARD_PORT} | {MODEL}")
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
