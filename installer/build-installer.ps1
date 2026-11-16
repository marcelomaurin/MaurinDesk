param(
    [string]$Iscc = 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    [string]$OpenSslBin = 'C:\Program Files\OpenSSL-Win64\bin'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $root
try {
    if (-not (Test-Path -LiteralPath $Iscc)) {
        throw "Inno Setup (ISCC.exe) não encontrado em: $Iscc"
    }
    $exe = Join-Path $root 'bin\MaurinDesk.exe'
    if (-not (Test-Path -LiteralPath $exe)) {
        throw "Executável não encontrado em: $exe. Execute ./build.ps1 antes."
    }
    foreach ($dll in @('libssl-3-x64.dll', 'libcrypto-3-x64.dll')) {
        $target = Join-Path $root "bin\$dll"
        if (-not (Test-Path -LiteralPath $target)) {
            $src = Join-Path $OpenSslBin $dll
            if (-not (Test-Path -LiteralPath $src)) {
                throw "Biblioteca OpenSSL ausente: $src"
            }
            Copy-Item -LiteralPath $src -Destination $target -Force
        }
    }
    $versionMatch = [regex]::Match((Get-Content -LiteralPath 'desktop\uDeskUpdate.pas' -Raw), "DESK_VERSION\s*=\s*'([0-9.]+)'")
    if (-not $versionMatch.Success) { throw 'DESK_VERSION não encontrado em desktop/uDeskUpdate.pas.' }
    $version = $versionMatch.Groups[1].Value

    & $Iscc "/DAppVersion=$version" (Join-Path $PSScriptRoot 'MaurinDesk.iss')
    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao compilar o instalador com ISCC.exe (código $LASTEXITCODE)."
    }
    $setup = Get-Item -LiteralPath (Join-Path $root 'bin\MaurinDesk-Setup.exe')
    Write-Output "Instalador gerado: $($setup.FullName) ($($setup.Length) bytes, v$version)"
} finally {
    Pop-Location
}
