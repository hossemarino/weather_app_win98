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
