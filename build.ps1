param(
    # Where to put the built exe + copied assets
    [string]$OutDir = (Join-Path $PSScriptRoot 'dist'),

    # Output exe name
    [string]$ExeName = 'Windows98Weather.exe',

    # Hide console window (recommended for WinForms)
    [switch]$NoConsole = $true,

    # Bundle src\*.ps1 modules into the EXE (recommended). When enabled, dist does NOT need src\.
    [switch]$BundleModules = $true,

    # If not bundling modules, copy src\ into dist\ so the EXE can dot-source at runtime.
    [switch]$IncludeSrcInDist = $false,

    # Delete OutDir before building
    [switch]$Clean,

    # Skip installing PS2EXE automatically
    [switch]$SkipModuleInstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
}
catch {
    # ignore
}

$root = $PSScriptRoot
if (-not $root) {
    try { $root = Split-Path -Parent $MyInvocation.MyCommand.Path } catch { $root = (Get-Location).Path }
}

$srcScript = Join-Path $root 'weather3.ps1'
if (-not (Test-Path -LiteralPath $srcScript)) {
    throw "Source script not found: $srcScript"
}

if ($Clean -and (Test-Path -LiteralPath $OutDir)) {
    Remove-Item -LiteralPath $OutDir -Recurse -Force
}
if (-not (Test-Path -LiteralPath $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}

# --- Ensure PS2EXE is available ---
$ps2exe = $null
try {
    $ps2exe = Get-Module -ListAvailable -Name PS2EXE | Select-Object -First 1
}
catch { $ps2exe = $null }

if (-not $ps2exe -and -not $SkipModuleInstall) {
    Write-Host 'PS2EXE not found; installing for CurrentUser...' -ForegroundColor Yellow
    try {
        # NuGet provider / PSGallery might prompt on first install.
        Install-Module -Name PS2EXE -Scope CurrentUser -Force -AllowClobber
    }
    catch {
        throw "Failed to install PS2EXE. Error: $($_.Exception.Message)"
    }
}

try {
    Import-Module PS2EXE -Force
}
catch {
    throw "Unable to import PS2EXE. Install it with: Install-Module PS2EXE -Scope CurrentUser"
}

$invoke = Get-Command -Name Invoke-PS2EXE -ErrorAction SilentlyContinue
if (-not $invoke) {
    $invoke = Get-Command -Name Invoke-ps2exe -ErrorAction SilentlyContinue
}
if (-not $invoke) {
    throw 'PS2EXE loaded, but Invoke-PS2EXE command not found.'
}

$outExe = Join-Path $OutDir $ExeName
$iconPath = Join-Path $root 'weather.ico'
if (-not (Test-Path -LiteralPath $iconPath)) {
    $iconPath = $null
}

function New-BundledBuildScript {
    param(
        [Parameter(Mandatory)]
        [string]$Root,
        [Parameter(Mandatory)]
        [string]$OutDirectory
    )

    $moduleFiles = @(
        'src\Core.ps1',
        'src\Settings.ps1',
        'src\OpenMeteo.ps1',
        'src\Sounds.ps1',
        'src\UiLayout.ps1',
        'src\UiUpdate.ps1',
        'src\UiActions.ps1'
    )

    foreach ($mf in $moduleFiles) {
        $p = Join-Path $Root $mf
        if (-not (Test-Path -LiteralPath $p)) {
            throw "Cannot bundle: missing module file: $p"
        }
    }

    $bundlePath = Join-Path $OutDirectory '_bundle_weather3.ps1'
    $sb = New-Object System.Text.StringBuilder

    [void]$sb.AppendLine('# Auto-generated build bundle. Do not edit.')
    [void]$sb.AppendLine('# This file is created by build.ps1 and compiled into the EXE.')
    [void]$sb.AppendLine('')

    foreach ($mf in $moduleFiles) {
        $p = Join-Path $Root $mf
        [void]$sb.AppendLine("# --- BEGIN $mf ---")
        [void]$sb.AppendLine((Get-Content -LiteralPath $p -Raw))
        [void]$sb.AppendLine("# --- END $mf ---")
        [void]$sb.AppendLine('')
    }

    $main = Get-Content -LiteralPath (Join-Path $Root 'weather3.ps1') -Raw
    # Remove dot-sourcing lines (modules are already inlined above)
    $main = $main -replace '(?m)^\s*\.\s*\(Join-Path\s+\$script:AppBase\s+''src\\Core\.ps1''\)\s*$', ''
    $main = $main -replace '(?m)^\s*\.\s*\(Join-Path\s+\$script:AppBase\s+''src\\Settings\.ps1''\)\s*$', ''
    $main = $main -replace '(?m)^\s*\.\s*\(Join-Path\s+\$script:AppBase\s+''src\\OpenMeteo\.ps1''\)\s*$', ''
    $main = $main -replace '(?m)^\s*\.\s*\(Join-Path\s+\$script:AppBase\s+''src\\Sounds\.ps1''\)\s*$', ''
    $main = $main -replace '(?m)^\s*\.\s*\(Join-Path\s+\$script:AppBase\s+''src\\UiLayout\.ps1''\)\s*$', ''
    $main = $main -replace '(?m)^\s*\.\s*\(Join-Path\s+\$script:AppBase\s+''src\\UiUpdate\.ps1''\)\s*$', ''
    $main = $main -replace '(?m)^\s*\.\s*\(Join-Path\s+\$script:AppBase\s+''src\\UiActions\.ps1''\)\s*$', ''

    [void]$sb.AppendLine('# --- BEGIN weather3.ps1 ---')
    [void]$sb.AppendLine($main)
    [void]$sb.AppendLine('# --- END weather3.ps1 ---')

    Set-Content -LiteralPath $bundlePath -Value $sb.ToString() -Encoding UTF8
    return $bundlePath
}

# --- Compile ---
$compileInput = $srcScript
if ($BundleModules) {
    Write-Host 'Bundling src\ modules into a single build script...' -ForegroundColor Cyan
    $compileInput = New-BundledBuildScript -Root $root -OutDirectory $OutDir
}

Write-Host "Compiling: $compileInput" -ForegroundColor Cyan
Write-Host "Output:    $outExe" -ForegroundColor Cyan

$params = @{
    inputFile  = $compileInput
    outputFile = $outExe
}

if ($NoConsole) {
    $params.noConsole = $true
}

if ($iconPath) {
    $params.iconFile = $iconPath
}

# NOTE: If BundleModules is disabled, the compiled EXE will still dot-source src\*.ps1 at runtime.
# In that case you must set -IncludeSrcInDist to copy src\ into dist\.
& $invoke @params | Out-Null

if (-not (Test-Path -LiteralPath $outExe)) {
    throw "Build failed: output exe not created: $outExe"
}

# --- Copy runtime files ---
Write-Host 'Copying runtime assets...' -ForegroundColor Cyan

if (-not $BundleModules) {
    if ($IncludeSrcInDist) {
        $srcDir = Join-Path $root 'src'
        if (Test-Path -LiteralPath $srcDir) {
            Copy-Item -LiteralPath $srcDir -Destination (Join-Path $OutDir 'src') -Recurse -Force
        }
    }
    else {
        Write-Host 'NOTE: src\ not copied. EXE will fail unless you bundle modules or include src\.' -ForegroundColor Yellow
    }
}

$assets = @(
    'ding.wav',
    'chord.wav',
    'Windows_98.wav',
    'Weather98Help.chm',
    'Settings.ini',
    'Settings.example.ini',
    'Cities.ini',
    'README.md',
    'weather.ico'
)

foreach ($name in $assets) {
    $p = Join-Path $root $name
    if (Test-Path -LiteralPath $p) {
        Copy-Item -LiteralPath $p -Destination (Join-Path $OutDir $name) -Force
    }
}

# If Settings.ini isn't present in the repo (it is user-specific / git-ignored),
# still ship a default Settings.ini in dist based on Settings.example.ini.
try {
    $distSettings = Join-Path $OutDir 'Settings.ini'
    if (-not (Test-Path -LiteralPath $distSettings)) {
        $example = Join-Path $root 'Settings.example.ini'
        if (Test-Path -LiteralPath $example) {
            Copy-Item -LiteralPath $example -Destination $distSettings -Force
        }
    }
}
catch {
    # no-op
}

# Remove the temporary bundled script from dist (the EXE already contains it)
try {
    $tmp = Join-Path $OutDir '_bundle_weather3.ps1'
    if (Test-Path -LiteralPath $tmp) {
        Remove-Item -LiteralPath $tmp -Force
    }
}
catch {
    # no-op
}

Write-Host 'Done.' -ForegroundColor Green
Write-Host "Run: $(Join-Path $OutDir $ExeName)" -ForegroundColor Green
