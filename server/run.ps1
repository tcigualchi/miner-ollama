$env:OLLAMA_MODEL="qwen3:4b"
$env:FLEET_TOKEN="TROQUE-POR-UM-TOKEN-FORTE"
$env:WEB_PASSWORD="TROQUE-POR-UMA-SENHA-FORTE"
python -m uvicorn app:app --host 0.0.0.0 --port 8000
