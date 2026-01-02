param(
    [string]$InputFile = (Join-Path $PSScriptRoot 'weather3.ps1'),
    [string]$OutDir = (Join-Path $PSScriptRoot 'dist'),
    [string]$ExeName = 'Windows98Weather.exe',
    [switch]$Console
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Initialize-Tls12 {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    }
    catch {
        # no-op
    }
}

function Install-Ps2ExeIfNeeded {
    Initialize-Tls12

    # Make installs non-interactive on fresh machines
    try { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null } catch {}
    try { Set-PSRepository -Name PSGallery -InstallationPolicy Trusted } catch {}

    if (-not (Get-Module -ListAvailable -Name ps2exe)) {
        Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber
    }

    Import-Module ps2exe -Force
}

if (-not (Test-Path -LiteralPath $InputFile)) {
    throw "Input file not found: $InputFile"
}

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$exePath = Join-Path $OutDir $ExeName

Install-Ps2ExeIfNeeded

$invokeParams = @{
    InputFile  = $InputFile
    OutputFile = $exePath
}

# Default to GUI app behavior (no console) unless explicitly requested.
if (-not $Console) {
    $invokeParams.NoConsole = $true
}

Invoke-ps2exe @invokeParams

if (-not (Test-Path -LiteralPath $exePath)) {
    throw "EXE was not created: $exePath"
}

Write-Host "Built: $exePath"
