import json
import os
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = os.getenv('BIND_HOST', '127.0.0.1')
PORT = int(os.getenv('PORT', '8765'))
TOKEN = os.getenv('MINER_TOKEN', '')
MODEL = os.getenv('OLLAMA_MODEL', 'qwen3:4b')
OLLAMA_URL = os.getenv('OLLAMA_URL', 'http://127.0.0.1:11434/api/generate')

SCHEMA = {
    'type': 'object',
    'properties': {
        'task': {'type': 'string', 'enum': ['tunnel', 'unsupported']},
        'length': {'type': 'integer', 'minimum': 0, 'maximum': 64},
    },
    'required': ['task', 'length'],
    'additionalProperties': False,
}

class Handler(BaseHTTPRequestHandler):
    def reply(self, status, body):
        data = json.dumps(body, ensure_ascii=True).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        if self.path != '/plan':
            return self.reply(404, {'error': 'Rota inexistente'})
        if not TOKEN or self.headers.get('X-Miner-Token') != TOKEN:
            return self.reply(401, {'error': 'Token invalido'})
        try:
            size = int(self.headers.get('Content-Length', '0'))
            if not 0 < size <= 4096:
                return self.reply(400, {'error': 'Tamanho de pedido invalido'})
            req = json.loads(self.rfile.read(size))
            prompt = req.get('prompt')
            if not isinstance(prompt, str) or not 0 < len(prompt.strip()) <= 500:
                return self.reply(400, {'error': 'Escreva um pedido de ate 500 caracteres'})
            payload = {
                'model': MODEL,
                'stream': False,
                'think': False,
                'keep_alive': '15m',
                'format': SCHEMA,
                'prompt': ('Converta o pedido em uma tarefa para uma turtle de Minecraft. '
                           'Somente tarefa tunnel (tunel reto de 2 blocos de altura, comprimento em blocos) '
                           'ou unsupported. Para unsupported, length=0. '
                           'Nao invente um comprimento; se faltar, unsupported. Pedido: ' + prompt),
                'options': {'temperature': 0},
            }
            request = urllib.request.Request(
                OLLAMA_URL, json.dumps(payload).encode('utf-8'),
                {'Content-Type': 'application/json'}, method='POST')
            with urllib.request.urlopen(request, timeout=120) as response:
                outer = json.load(response)
            plan = json.loads(outer['response'])
            if (not isinstance(plan, dict) or set(plan) != {'task', 'length'}
                    or type(plan['length']) is not int or plan['task'] not in ('tunnel', 'unsupported')
                    or (plan['task'] == 'tunnel' and not 1 <= plan['length'] <= 64)
                    or (plan['task'] == 'unsupported' and plan['length'] != 0)):
                return self.reply(422, {'error': 'Plano invalido recebido do Ollama'})
            return self.reply(200, plan)
        except (ValueError, KeyError, TypeError, urllib.error.URLError, TimeoutError) as exc:
            return self.reply(502, {'error': 'Falha ao consultar Ollama: ' + str(exc)[:180]})

if __name__ == '__main__':
    if not TOKEN:
        raise SystemExit('Defina MINER_TOKEN antes de iniciar o servidor')
    print(f'Servidor em http://{HOST}:{PORT} | modelo {MODEL}')
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
