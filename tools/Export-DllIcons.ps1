param(
    [Parameter(Mandatory)]
    [string]$DllPath,

    [string]$OutDir = '',

    [int]$MaxIcons = 200,

    [switch]$Png = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing | Out-Null

function Get-ThisScriptDirectory {
    try {
        if ($PSScriptRoot) { return $PSScriptRoot }
    }
    catch {}

    try {
        if ($PSCommandPath) { return (Split-Path -Parent $PSCommandPath) }
    }
    catch {}

    try {
        if ($MyInvocation -and $MyInvocation.MyCommand -and $MyInvocation.MyCommand.Path) {
            return (Split-Path -Parent $MyInvocation.MyCommand.Path)
        }
    }
    catch {}

    # Common dev case: running from repo root
    try {
        $cwd = (Get-Location).Path
        $cand = Join-Path $cwd 'tools'
        if (Test-Path -LiteralPath $cand) { return $cand }
        return $cwd
    }
    catch {
        return $null
    }
}

if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $base = Get-ThisScriptDirectory
    if (-not $base) { $base = (Get-Location).Path }
    $OutDir = Join-Path $base 'icons'
}

$typeDef = @'
using System;
using System.Runtime.InteropServices;

public static class NativeIcon
{
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern uint ExtractIconEx(
        string lpszFile,
        int nIconIndex,
        IntPtr[] phiconLarge,
        IntPtr[] phiconSmall,
        uint nIcons);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool DestroyIcon(IntPtr hIcon);
}
'@

try { if (-not ('NativeIcon' -as [type])) { Add-Type -TypeDefinition $typeDef -Language CSharp -ErrorAction Stop | Out-Null } } catch {}

$resolved = [Environment]::ExpandEnvironmentVariables(([string]$DllPath).Trim())
if (-not (Test-Path -LiteralPath $resolved)) {
    # If user passed only filename, try System32
    $leaf = Split-Path -Path $resolved -Leaf
    if ($leaf -and $leaf -eq $resolved) {
        $cand = Join-Path (Join-Path $env:WINDIR 'System32') $leaf
        if (Test-Path -LiteralPath $cand) { $resolved = $cand }
    }
}

if (-not (Test-Path -LiteralPath $resolved)) {
    throw "DLL not found: $resolved"
}

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

Write-Host "Exporting icons from: $resolved" -ForegroundColor Cyan
Write-Host "Output folder: $OutDir" -ForegroundColor Cyan

$found = 0
for ($i = 0; $i -lt $MaxIcons; $i++) {
    $large = New-Object IntPtr[] 1
    $small = New-Object IntPtr[] 1
    $count = [NativeIcon]::ExtractIconEx($resolved, $i, $large, $small, 1)
    if ($count -lt 1) { continue }

    $h = [IntPtr]::Zero
    if ($large[0] -ne [IntPtr]::Zero) { $h = $large[0] }
    elseif ($small[0] -ne [IntPtr]::Zero) { $h = $small[0] }
    if ($h -eq [IntPtr]::Zero) { continue }

    try {
        $icon = [System.Drawing.Icon]::FromHandle($h)
        $clone = [System.Drawing.Icon]$icon.Clone()

        $name = ('icon_{0:D3}' -f $i)
        if ($Png) {
            $bmp = $clone.ToBitmap()
            $out = Join-Path $OutDir ($name + '.png')
            $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
            $bmp.Dispose()
        }
        else {
            $out = Join-Path $OutDir ($name + '.ico')
            $fs = [System.IO.File]::Open($out, [System.IO.FileMode]::Create)
            try { $clone.Save($fs) } finally { $fs.Dispose() }
        }

        $found++
        if ($found % 25 -eq 0) {
            Write-Host ("Exported {0} icons so far..." -f $found) -ForegroundColor DarkGray
        }
    }
    catch {
        # ignore
    }
    finally {
        try { [void][NativeIcon]::DestroyIcon($h) } catch {}
    }
}

Write-Host ("Done. Exported {0} icons." -f $found) -ForegroundColor Green
Write-Host "Tip: set Settings.ini [Settings] IconDll=... and IconIndex=<number>" -ForegroundColor Green
