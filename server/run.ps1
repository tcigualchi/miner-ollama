$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot

$env:OLLAMA_MODEL = if ($env:OLLAMA_MODEL) { $env:OLLAMA_MODEL } else { 'qwen3:4b' }
$env:FLEET_TOKEN = if ($env:FLEET_TOKEN) { $env:FLEET_TOKEN } else { 'TROQUE-POR-UM-TOKEN-FORTE' }
$env:WEB_PASSWORD = if ($env:WEB_PASSWORD) { $env:WEB_PASSWORD } else { 'TROQUE-POR-UMA-SENHA-FORTE' }

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) { throw 'Python nao encontrado. Instale Python e adicione ao PATH.' }
$ngrok = $env:NGROK_PATH
if (-not $ngrok) { $ngrok = (Get-Command ngrok -ErrorAction SilentlyContinue).Source }
if (-not $ngrok) {
    $savedPath = @(
        [Environment]::GetEnvironmentVariable('Path', 'User'),
        [Environment]::GetEnvironmentVariable('Path', 'Machine')
    ) -join ';'
    foreach ($directory in ($savedPath -split ';')) {
        if (-not $directory) { continue }
        $candidate = Join-Path $directory 'ngrok.exe'
        if (Test-Path -LiteralPath $candidate) { $ngrok = $candidate; break }
    }
}
if (-not $ngrok -or -not (Test-Path -LiteralPath $ngrok)) {
    throw 'ngrok nao encontrado. Instale o ngrok e adicione ao PATH, ou defina NGROK_PATH com o caminho do ngrok.exe.'
}

$server = $null
$tunnel = $null
try {
    $server = Start-Process -FilePath $python.Source -ArgumentList @('-m', 'uvicorn', 'app:app', '--host', '0.0.0.0', '--port', '8000') -WorkingDirectory $PSScriptRoot -PassThru -NoNewWindow
    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        if ($server.HasExited) { throw 'O servidor encerrou durante a inicializacao. Confira as dependencias com: python -m pip install -r requirements.txt' }
        try {
            $health = Invoke-RestMethod -Uri 'http://127.0.0.1:8000/health' -TimeoutSec 1
            if ($health.ok) { $ready = $true; break }
        } catch { Start-Sleep -Milliseconds 500 }
    }
    if (-not $ready) { throw 'O servidor nao respondeu em http://127.0.0.1:8000/health.' }

    $tunnel = Start-Process -FilePath $ngrok -ArgumentList @('http', '8000') -WorkingDirectory $PSScriptRoot -PassThru -WindowStyle Hidden
    $publicUrl = $null
    for ($i = 0; $i -lt 30; $i++) {
        if ($tunnel.HasExited) { throw 'O ngrok encerrou durante a inicializacao. Verifique sua autenticacao com: ngrok config add-authtoken SEU_TOKEN' }
        try {
            $tunnels = Invoke-RestMethod -Uri 'http://127.0.0.1:4040/api/tunnels' -TimeoutSec 1
            $publicUrl = ($tunnels.tunnels | Where-Object { $_.public_url -like 'https://*' } | Select-Object -First 1).public_url
            if ($publicUrl) { break }
        } catch { }
        Start-Sleep -Milliseconds 500
    }
    if (-not $publicUrl) { throw 'O ngrok nao disponibilizou uma URL HTTPS. Verifique a configuracao do ngrok.' }
    Write-Host "Painel local: http://127.0.0.1:8000"
    Write-Host "Painel publico: $publicUrl"
    Write-Host 'Use a URL publica em central/config.lua e turtle/config.lua. Pressione Ctrl+C para encerrar.'
    while (-not $server.HasExited -and -not $tunnel.HasExited) { Start-Sleep -Seconds 1 }
    if ($server.HasExited) { throw 'O servidor foi encerrado.' }
    throw 'O tunel ngrok foi encerrado.'
} finally {
    if ($tunnel -and -not $tunnel.HasExited) { Stop-Process -Id $tunnel.Id -Force }
    if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force }
}
