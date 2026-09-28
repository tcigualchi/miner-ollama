$ErrorActionPreference = 'Stop'

Set-Location -LiteralPath $PSScriptRoot

# =========================
# CONFIGURACAO
# =========================

$env:OLLAMA_MODEL = 'qwen3:4b'
$env:FLEET_TOKEN = '123'
$env:WEB_PASSWORD = '123'

# =========================
# PYTHON
# =========================

$python = Get-Command python -ErrorAction SilentlyContinue

if (-not $python) {
    throw 'Python nao encontrado. Instale Python e adicione ao PATH.'
}

# =========================
# NGROK
# =========================

$ngrok = $env:NGROK_PATH

if (-not $ngrok) {
    $ngrokCommand = Get-Command ngrok -ErrorAction SilentlyContinue

    if ($ngrokCommand) {
        $ngrok = $ngrokCommand.Source
    }
}

if (-not $ngrok) {
    $savedPath = @(
        [Environment]::GetEnvironmentVariable('Path', 'User'),
        [Environment]::GetEnvironmentVariable('Path', 'Machine')
    ) -join ';'

    foreach ($directory in ($savedPath -split ';')) {
        if (-not $directory) {
            continue
        }

        $candidate = Join-Path $directory 'ngrok.exe'

        if (Test-Path -LiteralPath $candidate) {
            $ngrok = $candidate
            break
        }
    }
}

if (-not $ngrok -or -not (Test-Path -LiteralPath $ngrok)) {
    throw 'ngrok nao encontrado. Instale o ngrok e adicione ao PATH, ou defina NGROK_PATH com o caminho do ngrok.exe.'
}

# =========================
# INICIALIZACAO
# =========================

$server = $null
$tunnel = $null

try {

    Write-Host ''
    Write-Host '====================================='
    Write-Host '        CC FLEET AI - START'
    Write-Host '====================================='
    Write-Host ''
    Write-Host "Modelo Ollama: $env:OLLAMA_MODEL"
    Write-Host "Fleet token configurado: SIM"
    Write-Host "Senha web configurada: SIM"
    Write-Host ''

    # =========================
    # FASTAPI / UVICORN
    # =========================

    $server = Start-Process `
        -FilePath $python.Source `
        -ArgumentList @(
            '-m',
            'uvicorn',
            'app:app',
            '--host',
            '0.0.0.0',
            '--port',
            '8000'
        ) `
        -WorkingDirectory $PSScriptRoot `
        -PassThru `
        -NoNewWindow

    Write-Host 'Iniciando servidor FastAPI...'

    $ready = $false

    for ($i = 0; $i -lt 30; $i++) {

        if ($server.HasExited) {
            throw 'O servidor encerrou durante a inicializacao. Confira as dependencias com: python -m pip install -r requirements.txt'
        }

        try {
            $health = Invoke-RestMethod `
                -Uri 'http://127.0.0.1:8000/health' `
                -TimeoutSec 1

            if ($health.ok) {
                $ready = $true
                break
            }
        }
        catch {
            Start-Sleep -Milliseconds 500
        }
    }

    if (-not $ready) {
        throw 'O servidor nao respondeu em http://127.0.0.1:8000/health.'
    }

    Write-Host 'Servidor FastAPI: OK'

    # =========================
    # NGROK
    # =========================

    Write-Host 'Iniciando ngrok...'

    $tunnel = Start-Process `
        -FilePath $ngrok `
        -ArgumentList @(
            'http',
            '8000'
        ) `
        -WorkingDirectory $PSScriptRoot `
        -PassThru `
        -WindowStyle Hidden

    $publicUrl = $null

    for ($i = 0; $i -lt 30; $i++) {

        if ($tunnel.HasExited) {
            throw 'O ngrok encerrou durante a inicializacao. Verifique sua autenticacao com: ngrok config add-authtoken SEU_TOKEN'
        }

        try {
            $tunnels = Invoke-RestMethod `
                -Uri 'http://127.0.0.1:4040/api/tunnels' `
                -TimeoutSec 1

            $publicUrl = (
                $tunnels.tunnels |
                Where-Object {
                    $_.public_url -like 'https://*'
                } |
                Select-Object -First 1
            ).public_url

            if ($publicUrl) {
                break
            }
        }
        catch {
        }

        Start-Sleep -Milliseconds 500
    }

    if (-not $publicUrl) {
        throw 'O ngrok nao disponibilizou uma URL HTTPS. Verifique a configuracao do ngrok.'
    }

    # =========================
    # RESULTADO
    # =========================

    Write-Host ''
    Write-Host '====================================='
    Write-Host '        CC FLEET AI ONLINE'
    Write-Host '====================================='
    Write-Host ''

    Write-Host 'Painel local:'
    Write-Host 'http://127.0.0.1:8000'
    Write-Host ''

    Write-Host 'Painel publico:'
    Write-Host $publicUrl
    Write-Host ''

    Write-Host 'Use esta URL em:'
    Write-Host 'central/config.lua'
    Write-Host 'turtle/config.lua'
    Write-Host ''

    Write-Host 'FLEET_TOKEN: 123'
    Write-Host 'WEB_PASSWORD: 123'
    Write-Host ''

    Write-Host 'Pressione Ctrl+C para encerrar.'
    Write-Host ''

    # Mantem servidor e ngrok rodando.
    while (
        -not $server.HasExited -and
        -not $tunnel.HasExited
    ) {
        Start-Sleep -Seconds 1
    }

    if ($server.HasExited) {
        throw 'O servidor foi encerrado.'
    }

    throw 'O tunel ngrok foi encerrado.'
}
finally {

    Write-Host ''
    Write-Host 'Encerrando CC Fleet AI...'

    if (
        $tunnel -and
        -not $tunnel.HasExited
    ) {
        Stop-Process `
            -Id $tunnel.Id `
            -Force
    }

    if (
        $server -and
        -not $server.HasExited
    ) {
        Stop-Process `
            -Id $server.Id `
            -Force
    }

    Write-Host 'Finalizado.'
}