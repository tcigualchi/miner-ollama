$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) { throw 'Python nao encontrado no PATH.' }
& $python.Source -c 'import fastapi, uvicorn; import sys; sys.exit(0)'
if ($LASTEXITCODE -ne 0) { throw 'Instale as dependencias com: python -m pip install -r requirements.txt' }

$ngrok = $env:NGROK_PATH
if (-not $ngrok) { $ngrok = (Get-Command ngrok -ErrorAction SilentlyContinue).Source }
if (-not $ngrok) { throw 'ngrok nao encontrado no PATH. Configure NGROK_PATH ou adicione ngrok.exe ao PATH.' }

$tokenPath = Join-Path $PSScriptRoot 'data\grabcraft-token.txt'
if (-not (Test-Path -LiteralPath $tokenPath)) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $tokenPath) -Force | Out-Null
    $bytes = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    $rng.Dispose()
    [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+','-').Replace('/','_') |
        Set-Content -LiteralPath $tokenPath -NoNewline -Encoding ascii
}
$env:GRABCRAFT_TOKEN = (Get-Content -LiteralPath $tokenPath -Raw).Trim()

$service = $null
$tunnel = $null
try {
    $service = Start-Process -FilePath $python.Source -ArgumentList @('-m','uvicorn','grabcraft_service:app','--host','0.0.0.0','--port','8010') -WorkingDirectory $PSScriptRoot -PassThru -NoNewWindow
    $ready = $false
    for ($i=0; $i -lt 30; $i++) {
        if ($service.HasExited) { throw 'O servico GrabCraft encerrou durante a inicializacao.' }
        try { if ((Invoke-RestMethod 'http://127.0.0.1:8010/health' -TimeoutSec 1).ok) { $ready=$true; break } } catch { Start-Sleep -Milliseconds 500 }
    }
    if (-not $ready) { throw 'O servico nao respondeu em http://127.0.0.1:8010/health.' }
    $tunnel = Start-Process -FilePath $ngrok -ArgumentList @('http','8010') -WorkingDirectory $PSScriptRoot -PassThru -WindowStyle Hidden
    $publicUrl = $null
    for ($i=0; $i -lt 30; $i++) {
        if ($tunnel.HasExited) { throw 'ngrok encerrou. Verifique a autenticacao do ngrok.' }
        try {
            $tunnels = Invoke-RestMethod 'http://127.0.0.1:4040/api/tunnels' -TimeoutSec 1
            $publicUrl = ($tunnels.tunnels | Where-Object { $_.public_url -like 'https://*' } | Select-Object -First 1).public_url
            if ($publicUrl) { break }
        } catch { }
        Start-Sleep -Milliseconds 500
    }
    if (-not $publicUrl) { throw 'ngrok nao informou URL HTTPS.' }
    Write-Host 'Inspetor GrabCraft ativo (sem painel web).'
    Write-Host "Instale em cada Turtle: wget run $publicUrl/install.lua $publicUrl $env:GRABCRAFT_TOKEN"
    Write-Host 'Depois: grabcraft <link-direto-da-pagina-de-blueprint>'
    Write-Host 'O link deve ser uma pÃ¡gina individual do GrabCraft, nÃ£o a listagem geral.'
    Write-Host 'Pressione Ctrl+C para encerrar.'
    while (-not $service.HasExited -and -not $tunnel.HasExited) { Start-Sleep -Seconds 1 }
    if ($service.HasExited) { throw 'O serviÃ§o GrabCraft foi encerrado.' }
    throw 'O tÃºnel ngrok foi encerrado.'
} finally {
    if ($tunnel -and -not $tunnel.HasExited) { Stop-Process -Id $tunnel.Id -Force }
    if ($service -and -not $service.HasExited) { Stop-Process -Id $service.Id -Force }
}

