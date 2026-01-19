function Get-AppBaseDirectory {
    try {
        if ($PSScriptRoot) { return $PSScriptRoot }
    }
    catch {
        # no-op
    }
    try {
        return [System.AppDomain]::CurrentDomain.BaseDirectory
    }
    catch {
        return (Get-Location).Path
    }
}

function Invoke-JsonGet {
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [int]$TimeoutSec = 15
    )

    $headers = @{
        'User-Agent' = 'Windows98Weather/1.0 (+https://open-meteo.com)'
        'Accept'     = 'application/json'
    }

    if ($PSVersionTable.PSVersion.Major -lt 6) {
        $resp = Invoke-WebRequest -Method Get -Uri $Uri -Headers $headers -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop
    }
    else {
        $resp = Invoke-WebRequest -Method Get -Uri $Uri -Headers $headers -TimeoutSec $TimeoutSec -ErrorAction Stop
    }

    $jsonText = [string]$resp.Content
    $trim = $jsonText.TrimStart()
    if (-not ($trim.StartsWith('{') -or $trim.StartsWith('['))) {
        $short = $trim
        if ($short.Length -gt 200) { $short = $short.Substring(0, 200) + '…' }
        throw "API returned non-JSON. First chars: $short"
    }

    $jsonText | ConvertFrom-Json -ErrorAction Stop
}

function Convert-WindDegreesTo16Point {
    param([AllowNull()]$Degrees)
    try {
        if ($null -eq $Degrees) { return '--' }
        $d = [double]$Degrees
        # Normalize 0..360
        $d = ($d % 360 + 360) % 360
        $dirs = @('N','NNE','NE','ENE','E','ESE','SE','SSE','S','SSW','SW','WSW','W','WNW','NW','NNW')
        $ix = [int][Math]::Round($d / 22.5) % 16
        return $dirs[$ix]
    }
    catch {
        return '--'
    }
}

function Get-ValueFromArray {
    param(
        [AllowNull()]$ArrayWithValue,
        [string]$Default = ''
    )

    try {
        if ($null -eq $ArrayWithValue) { return $Default }
        if ($ArrayWithValue.Count -lt 1) { return $Default }
        $first = $ArrayWithValue[0]
        if ($null -eq $first) { return $Default }
        if ($null -ne $first.value) { return [string]$first.value }
        return [string]$first
    }
    catch {
        return $Default
    }
}

function SafeStr {
    param(
        [AllowNull()]$Value,
        [string]$Default = '--'
    )
    if ($null -eq $Value) { return $Default }
    $s = [string]$Value
    if ([string]::IsNullOrWhiteSpace($s)) { return $Default }
    $s
}

function Format-PrettyJson {
    param([AllowNull()]$Obj)
    try {
        if ($null -eq $Obj) { return '' }
        ($Obj | ConvertTo-Json -Depth 20)
    }
    catch {
        ''
    }
}

function Initialize-NativeIconInterop {
    try {
        if ('NativeIcon' -as [type]) { return }
    }
    catch {
        # no-op
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

    try {
        Add-Type -TypeDefinition $typeDef -Language CSharp -ErrorAction Stop | Out-Null
    }
    catch {
        # If the type already exists or Add-Type fails, just ignore.
    }
}

function Resolve-SystemLibraryPath {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $p = [Environment]::ExpandEnvironmentVariables(([string]$Path).Trim())
    if ([string]::IsNullOrWhiteSpace($p)) { return $null }
    if (Test-Path -LiteralPath $p) { return $p }

    # If user provided just a filename, try System32.
    try {
        $leaf = Split-Path -Path $p -Leaf
        if ($leaf -and $leaf -eq $p) {
            $sys32 = Join-Path $env:WINDIR 'System32'
            $cand = Join-Path $sys32 $leaf
            if (Test-Path -LiteralPath $cand) { return $cand }
        }
    }
    catch {
        # no-op
    }

    return $p
}

function Get-IconFromLibrary {
    param(
        [Parameter(Mandatory)]
        [string]$LibraryPath,

        [int]$Index = 0
    )

    try {
        Initialize-NativeIconInterop
        if (-not ('NativeIcon' -as [type])) { return $null }

        $resolved = Resolve-SystemLibraryPath -Path $LibraryPath
        if (-not $resolved) { return $null }
        if (-not (Test-Path -LiteralPath $resolved)) { return $null }

        $large = New-Object IntPtr[] 1
        $small = New-Object IntPtr[] 1
        $count = [NativeIcon]::ExtractIconEx($resolved, $Index, $large, $small, 1)
        if ($count -lt 1) { return $null }

        $h = [IntPtr]::Zero
        if ($large[0] -ne [IntPtr]::Zero) {
            $h = $large[0]
        }
        elseif ($small[0] -ne [IntPtr]::Zero) {
            $h = $small[0]
        }

        if ($h -eq [IntPtr]::Zero) { return $null }

        $icon = [System.Drawing.Icon]::FromHandle($h)
        $clone = $null
        try {
            $clone = [System.Drawing.Icon]$icon.Clone()
        }
        finally {
            try { [void][NativeIcon]::DestroyIcon($h) } catch {}
        }

        return $clone
    }
    catch {
        return $null
    }
}
