param(
    # Kept for backwards-compat; build.ps1 always builds from weather3.ps1
    [string]$InputFile = (Join-Path $PSScriptRoot 'weather3.ps1'),

    # Match build.ps1 defaults
    [string]$OutDir = (Join-Path $PSScriptRoot 'dist'),
    [string]$ExeName = 'Windows98Weather.exe',

    # Kept for backwards-compat: -Console means show a console window
    [switch]$Console,

    # Common flags people expect
    [switch]$Clean,
    [switch]$SkipModuleInstall,

    # Preserve the newer behavior (single EXE, no src\ in dist)
    [switch]$BundleModules = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Warning 'build-exe.ps1 is deprecated. Use build.ps1 instead (same output, more features).'

$root = $PSScriptRoot
if (-not $root) {
    try { $root = Split-Path -Parent $MyInvocation.MyCommand.Path } catch { $root = (Get-Location).Path }
}

$build = Join-Path $root 'build.ps1'
if (-not (Test-Path -LiteralPath $build)) {
    throw "Missing build script: $build"
}

if (-not (Test-Path -LiteralPath $InputFile)) {
    throw "Input file not found: $InputFile"
}

$argsToForward = @{
    OutDir            = $OutDir
    ExeName           = $ExeName
    Clean             = $Clean
    SkipModuleInstall = $SkipModuleInstall
    BundleModules     = $BundleModules
}

if ($Console) {
    # build.ps1 uses -NoConsole (default true). If caller requested -Console, flip it.
    $argsToForward.NoConsole = $false
}

& $build @argsToForward
