Set-StrictMode -Version Latest

function Get-StartupSoundCandidatePaths {
    $candidates = @(
        (Join-Path $script:AppBase 'Windows_98.wav'),
        (Join-Path $script:AppBase 'Windows98.wav'),
        (Join-Path $script:AppBase 'Windows 98.wav'),
        (Join-Path $script:AppBase 'Windows 98 Startup.wav'),
        (Join-Path $script:AppBase 'Windows98 Startup.wav'),
        (Join-Path $script:AppBase 'windows98-startup.wav')
    )

    # Also pick up any *.wav in app folder matching “windows*98*startup*”
    try {
        $extra = Get-ChildItem -LiteralPath $script:AppBase -File -Filter '*.wav' -ErrorAction Stop |
            Where-Object { $_.Name -match 'windows\s*98.*startup' } |
            Sort-Object -Property Name |
            Select-Object -ExpandProperty FullName
        $candidates += $extra
    }
    catch {
        # no-op
    }

    # Unique, preserve order
    $seen = @{}
    foreach ($p in $candidates) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        if (-not $seen.ContainsKey($p)) {
            $seen[$p] = $true
            $p
        }
    }
}

function Get-WindowsStartupSoundPath {
    # Try the configured Windows sound scheme first (if any).
    $regPaths = @(
        'HKEY_CURRENT_USER\AppEvents\Schemes\Apps\.Default\SystemStart\.Current',
        'HKEY_CURRENT_USER\AppEvents\Schemes\Apps\.Default\WindowsLogon\.Current',
        'HKEY_USERS\.DEFAULT\AppEvents\Schemes\Apps\.Default\SystemStart\.Current',
        'HKEY_USERS\.DEFAULT\AppEvents\Schemes\Apps\.Default\WindowsLogon\.Current'
    )

    foreach ($rp in $regPaths) {
        try {
            $v = [Microsoft.Win32.Registry]::GetValue($rp, '', $null)
            if ($v -and ($v -is [string])) {
                $path = $v.Trim('"')
                if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path)) {
                    return $path
                }
            }
        }
        catch {
            # no-op
        }
    }

    # Common fallback (may or may not exist depending on Windows version/settings)
    try {
        $media = Join-Path $env:WINDIR 'Media'
        $common = @(
            (Join-Path $media 'Windows Startup.wav'),
            (Join-Path $media 'Windows Logon.wav')
        )
        foreach ($p in $common) {
            if (Test-Path -LiteralPath $p) { return $p }
        }
    }
    catch {
        # no-op
    }

    return $null
}

function Invoke-StartupSound {
    try {
        foreach ($p in (Get-StartupSoundCandidatePaths)) {
            if (Test-Path -LiteralPath $p) {
                (New-Object System.Media.SoundPlayer($p)).Play()
                return
            }
        }

        $sys = Get-WindowsStartupSoundPath
        if ($sys -and (Test-Path -LiteralPath $sys)) {
            (New-Object System.Media.SoundPlayer($sys)).Play()
        }
    }
    catch {
        # no-op
    }
}

function Invoke-SoundFileOrFallback {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateSet('Success', 'Error')]
        [string]$Kind
    )

    try {
        if ([System.IO.File]::Exists($Path)) {
            $player = New-Object System.Media.SoundPlayer($Path)
            $player.Play()
            return
        }
    }
    catch {
        # fall through
    }

    try {
        if ($Kind -eq 'Success') {
            [System.Media.SystemSounds]::Asterisk.Play()
        }
        else {
            [System.Media.SystemSounds]::Exclamation.Play()
        }
    }
    catch {
        # no-op
    }
}

function Invoke-SuccessSound {
    Invoke-SoundFileOrFallback -Path $script:SoundSuccessPath -Kind Success
}

function Invoke-ErrorSound {
    Invoke-SoundFileOrFallback -Path $script:SoundErrorPath -Kind Error
}
