$env:OLLAMA_MODEL='qwen3:4b'
$env:FLEET_TOKEN='123'
$env:WEB_PASSWORD='123'
python -m uvicorn app:app --host 0.0.0.0 --port 8000