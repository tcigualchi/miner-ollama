param([switch]$LocalOnly)

$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot

$env:OLLAMA_MODEL = if ($env:OLLAMA_MODEL) { $env:OLLAMA_MODEL } else { 'qwen3:4b' }
$secretFile = Join-Path $PSScriptRoot 'data\secrets.json'
if (-not (Test-Path -LiteralPath $secretFile)) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $secretFile) -Force | Out-Null
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    function New-FleetSecret {
        $bytes = New-Object byte[] 32
        $rng.GetBytes($bytes)
        [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+','-').Replace('/','_')
    }
    $generated = @{
        web_password = if ($env:WEB_PASSWORD) { $env:WEB_PASSWORD } else { New-FleetSecret }
        enrollment_token = if ($env:FLEET_ENROLLMENT_TOKEN) { $env:FLEET_ENROLLMENT_TOKEN } elseif ($env:FLEET_TOKEN) { $env:FLEET_TOKEN } else { New-FleetSecret }
        player_beacon_token = if ($env:PLAYER_BEACON_TOKEN) { $env:PLAYER_BEACON_TOKEN } else { New-FleetSecret }
    }
    $generated | ConvertTo-Json | Set-Content -LiteralPath $secretFile -Encoding UTF8
}
$saved = Get-Content -LiteralPath $secretFile -Raw | ConvertFrom-Json
$env:WEB_PASSWORD = if ($env:WEB_PASSWORD) { $env:WEB_PASSWORD } else { $saved.web_password }
$env:FLEET_ENROLLMENT_TOKEN = if ($env:FLEET_ENROLLMENT_TOKEN) { $env:FLEET_ENROLLMENT_TOKEN } elseif ($env:FLEET_TOKEN) { $env:FLEET_TOKEN } else { $saved.enrollment_token }
$env:PLAYER_BEACON_TOKEN = if ($env:PLAYER_BEACON_TOKEN) { $env:PLAYER_BEACON_TOKEN } else { $saved.player_beacon_token }
$env:FLEET_TOKEN = $env:FLEET_ENROLLMENT_TOKEN

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) { throw 'Python nao encontrado. Instale Python e adicione ao PATH.' }
& $python.Source -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)'
if ($LASTEXITCODE -ne 0) { throw 'CC Fleet OS requer Python 3.10 ou superior.' }
$ngrok = $null
if (-not $LocalOnly) {
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
        throw 'ngrok nao encontrado. Use -LocalOnly para iniciar somente na rede local.'
    }
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

    if ($LocalOnly) {
        $addresses = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notlike '127.*' -and $_.AddressState -eq 'Preferred' } |
            Select-Object -ExpandProperty IPAddress -Unique)
        Write-Host 'Painel neste computador: http://127.0.0.1:8000'
        if ($addresses.Count) {
            Write-Host 'URL para Turtle/Pocket na mesma rede:'
            foreach ($address in $addresses) { Write-Host "  http://${address}:8000" }
        } else {
            Write-Host 'Nao consegui detectar o IP local. Consulte ipconfig e use http://IP-DO-PC:8000'
        }
        Write-Host "Senha do painel: $env:WEB_PASSWORD"
        Write-Host "Token de cadastro: $env:FLEET_ENROLLMENT_TOKEN"
        Write-Host "Token Pocket Beacon: $env:PLAYER_BEACON_TOKEN"
        Write-Host 'Modo local ativo. Pressione Ctrl+C para encerrar.'
        while (-not $server.HasExited) { Start-Sleep -Seconds 1 }
        throw 'O servidor foi encerrado.'
    }

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
    Write-Host "Senha do painel: $env:WEB_PASSWORD"
    Write-Host "Token de cadastro: $env:FLEET_ENROLLMENT_TOKEN"
    Write-Host "Token Pocket Beacon: $env:PLAYER_BEACON_TOKEN"
    Write-Host 'Use a URL publica em central/config.lua e turtle/config.lua. Pressione Ctrl+C para encerrar.'
    while (-not $server.HasExited -and -not $tunnel.HasExited) { Start-Sleep -Seconds 1 }
    if ($server.HasExited) { throw 'O servidor foi encerrado.' }
    throw 'O tunel ngrok foi encerrado.'
} finally {
    if ($tunnel -and -not $tunnel.HasExited) { Stop-Process -Id $tunnel.Id -Force }
    if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force }
}
