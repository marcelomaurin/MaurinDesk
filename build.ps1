param([string]$Lazarus = 'C:\lazarus\lazbuild.exe')
$ErrorActionPreference = 'Stop'
Push-Location -LiteralPath $PSScriptRoot
try {
    & $Lazarus --build-all desktop/MaurinDesk.lpi
    if ($LASTEXITCODE -ne 0) { throw 'Falha na compilação. Se MaurinDesk.exe estiver aberto, feche-o e tente novamente.' }
    $binary = Get-Item -LiteralPath 'bin/MaurinDesk.exe'
    $versionMatch = [regex]::Match((Get-Content -LiteralPath 'desktop/uDeskUpdate.pas' -Raw), "DESK_VERSION\s*=\s*'([0-9.]+)'")
    if (-not $versionMatch.Success) { throw 'Versão do aplicativo não encontrada.' }
    $version = $versionMatch.Groups[1].Value
    if ($binary.VersionInfo.FileVersion -notlike "$version.*") { throw 'A versão do executável difere de DESK_VERSION.' }
    $hash = (Get-FileHash -LiteralPath $binary.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $manifest = [ordered]@{
        version = $version; platform = 'windows-x64'; filename = 'MaurinDesk.exe'
        bytes = $binary.Length; sha256 = $hash; lazarus = '4.6'; fpc = '3.2.2'
        build_date = (Get-Date -Format 'yyyy-MM-dd'); stage = 'bidirectional-file-manager'
    }
    $manifest | ConvertTo-Json | Set-Content -LiteralPath 'bin/manifest.json' -Encoding utf8
    $update = [ordered]@{
        version = $version; platform = 'windows-x64'; filename = 'MaurinDesk.exe'
        download_url = 'https://raw.githubusercontent.com/marcelomaurin/MaurinDesk/fila/bin/MaurinDesk.exe'
        bytes = $binary.Length; sha256 = $hash; build_date = $manifest.build_date
        minimum_api_schema = '0.9'
        release_notes = 'Transferir arquivos acessivel na barra responsiva do visualizador e na sessao ativa, com envio e recebimento para a pasta escolhida.'
    }
    $update | ConvertTo-Json | Set-Content -LiteralPath 'update.json' -Encoding utf8
    Write-Output "Gerado bin/MaurinDesk.exe v$version e metadados de atualização."
} finally { Pop-Location }
