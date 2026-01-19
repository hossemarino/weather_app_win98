param(
    # Where to put the built exe + copied assets
    [string]$OutDir = (Join-Path $PSScriptRoot 'dist'),

    # Output exe name
    [string]$ExeName = 'Windows98Weather.exe',

    # Optional: .ico file to embed into the EXE (Explorer icon + pinned taskbar shortcut icon).
    # If provided, it is also copied into dist as weather.ico so the runtime window icon matches.
    [string]$IconFile = '',

    # Hide console window (recommended for WinForms)
    [switch]$NoConsole = $true,

    # Bundle src\*.ps1 modules into the EXE (recommended). When enabled, dist does NOT need src\.
    [switch]$BundleModules = $true,

    # If not bundling modules, copy src\ into dist\ so the EXE can dot-source at runtime.
    [switch]$IncludeSrcInDist = $false,

    # Delete OutDir before building
    [switch]$Clean,

    # Skip installing PS2EXE automatically
    [switch]$SkipModuleInstall,

    # If set, copy your local Settings.ini into dist (personal). By default dist gets Settings.ini from Settings.example.ini.
    [switch]$IncludeUserSettings
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

function New-IcoFromPng {
    param(
        [Parameter(Mandatory)]
        [byte[]]$PngBytes,
        [Parameter(Mandatory)]
        [string]$OutPath
    )

    if ($PngBytes.Length -lt 32) {
        throw 'PNG data too small.'
    }

    # PNG signature: 89 50 4E 47 0D 0A 1A 0A
    $sig = @(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
    for ($i = 0; $i -lt $sig.Count; $i++) {
        if ($PngBytes[$i] -ne $sig[$i]) {
            throw 'Input is not a PNG.'
        }
    }

    # IHDR starts at offset 12, data at 16: width/height are big-endian
    $w = ($PngBytes[16] -shl 24) -bor ($PngBytes[17] -shl 16) -bor ($PngBytes[18] -shl 8) -bor $PngBytes[19]
    $h = ($PngBytes[20] -shl 24) -bor ($PngBytes[21] -shl 16) -bor ($PngBytes[22] -shl 8) -bor $PngBytes[23]
    if ($w -lt 1 -or $h -lt 1) {
        throw "Invalid PNG dimensions: ${w}x${h}"
    }

    $entryWidth = if ($w -ge 256) { 0 } else { [byte]$w }
    $entryHeight = if ($h -ge 256) { 0 } else { [byte]$h }

    $header = New-Object byte[] 6
    # reserved 0
    $header[0] = 0; $header[1] = 0
    # type = 1 (icon)
    $header[2] = 1; $header[3] = 0
    # count = 1
    $header[4] = 1; $header[5] = 0

    $dir = New-Object byte[] 16
    $dir[0] = $entryWidth
    $dir[1] = $entryHeight
    $dir[2] = 0
    $dir[3] = 0
    # planes (LE)
    $dir[4] = 1; $dir[5] = 0
    # bitcount (LE) - 32bpp is typical
    $dir[6] = 32; $dir[7] = 0
    # bytes in resource (LE)
    $len = [int]$PngBytes.Length
    $dir[8] = [byte]($len -band 0xFF)
    $dir[9] = [byte](($len -shr 8) -band 0xFF)
    $dir[10] = [byte](($len -shr 16) -band 0xFF)
    $dir[11] = [byte](($len -shr 24) -band 0xFF)
    # offset (LE)
    $off = 6 + 16
    $dir[12] = [byte]($off -band 0xFF)
    $dir[13] = [byte](($off -shr 8) -band 0xFF)
    $dir[14] = [byte](($off -shr 16) -band 0xFF)
    $dir[15] = [byte](($off -shr 24) -band 0xFF)

    $ico = New-Object byte[] ($off + $len)
    [Array]::Copy($header, 0, $ico, 0, 6)
    [Array]::Copy($dir, 0, $ico, 6, 16)
    [Array]::Copy($PngBytes, 0, $ico, $off, $len)

    [System.IO.File]::WriteAllBytes($OutPath, $ico)
    return $OutPath
}

function Resolve-IconFileForBuild {
    param(
        [string]$CandidatePath,
        [Parameter(Mandatory)]
        [string]$OutDirectory
    )

    if ([string]::IsNullOrWhiteSpace($CandidatePath)) {
        return $null
    }

    if (-not (Test-Path -LiteralPath $CandidatePath)) {
        throw "Icon file not found: $CandidatePath"
    }

    $bytes = [System.IO.File]::ReadAllBytes($CandidatePath)
    if ($bytes.Length -ge 8 -and $bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50 -and $bytes[2] -eq 0x4E -and $bytes[3] -eq 0x47) {
        $outIco = Join-Path $OutDirectory '_icon_for_build.ico'
        Write-Host "NOTE: '$CandidatePath' is a PNG; wrapping into ICO for embedding..." -ForegroundColor Yellow
        return (New-IcoFromPng -PngBytes $bytes -OutPath $outIco)
    }

    # ICO signature is 00 00 01 00
    if ($bytes.Length -ge 4 -and $bytes[0] -eq 0 -and $bytes[1] -eq 0 -and $bytes[2] -eq 1 -and $bytes[3] -eq 0) {
        return $CandidatePath
    }

    throw "Unsupported icon format (expected .ico or PNG): $CandidatePath"
}

$iconPath = $null
if (-not [string]::IsNullOrWhiteSpace($IconFile)) {
    $cand = $IconFile
    if (-not [System.IO.Path]::IsPathRooted($cand)) {
        $cand = Join-Path $root $cand
    }
    $iconPath = Resolve-IconFileForBuild -CandidatePath $cand -OutDirectory $OutDir
}
else {
    $cand = Join-Path $root 'weather.ico'
    if (Test-Path -LiteralPath $cand) {
        $iconPath = Resolve-IconFileForBuild -CandidatePath $cand -OutDirectory $OutDir
    }
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
    'Weather98Help.html',
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

# Always ship the same validated icon as dist\weather.ico so the runtime window/taskbar icon matches the EXE icon.
try {
    if ($iconPath) {
        Copy-Item -LiteralPath $iconPath -Destination (Join-Path $OutDir 'weather.ico') -Force
    }
}
catch {
    # no-op
}

# Settings.ini is user-specific. For distributable builds, prefer Settings.example.ini.
try {
    $distSettings = Join-Path $OutDir 'Settings.ini'
    $example = Join-Path $root 'Settings.example.ini'
    $userSettings = Join-Path $root 'Settings.ini'

    if ($IncludeUserSettings -and (Test-Path -LiteralPath $userSettings)) {
        Copy-Item -LiteralPath $userSettings -Destination $distSettings -Force
    }
    elseif (Test-Path -LiteralPath $example) {
        Copy-Item -LiteralPath $example -Destination $distSettings -Force
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
