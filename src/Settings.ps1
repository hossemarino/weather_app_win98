function Get-UnitConfig {
    param(
        [ValidateSet('Metric', 'Imperial')]
        [string]$UnitSystem = 'Metric'
    )

    if ($UnitSystem -eq 'Imperial') {
        return [pscustomobject]@{
            unitSystem = 'Imperial'
            temperature_unit = 'fahrenheit'
            wind_speed_unit = 'mph'
            precipitation_unit = 'inch'
            tempSuffix = '°F'
            windSuffix = 'mph'
            precipSuffix = 'in'
            visibilitySuffix = 'mi'
            snowSuffix = 'in'
            elevationSuffix = 'ft'
        }
    }

    return [pscustomobject]@{
        unitSystem = 'Metric'
        temperature_unit = 'celsius'
        wind_speed_unit = 'kmh'
        precipitation_unit = 'mm'
        tempSuffix = '°C'
        windSuffix = 'km/h'
        precipSuffix = 'mm'
        visibilitySuffix = 'km'
        snowSuffix = 'cm'
        elevationSuffix = 'm'
    }
}

function Get-SettingsFromIni {
    param(
        [string]$Path = $script:SettingsIniPath
    )

    $result = [pscustomobject]@{
        UnitSystem = 'Metric'
        LastCity   = ''
        Language   = 'en'
        Cities     = @()
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        return $result
    }

    try {
        $lines = Get-Content -LiteralPath $Path -ErrorAction Stop
    }
    catch {
        return $result
    }

    $section = ''
    $cities = New-Object System.Collections.Generic.List[string]

    foreach ($lineRaw in $lines) {
        $line = [string]$lineRaw
        if ($null -eq $line) { continue }
        $trim = $line.Trim()
        if ($trim.Length -eq 0) { continue }
        if ($trim.StartsWith(';') -or $trim.StartsWith('#')) { continue }

        if ($trim -match '^\[(.+)\]$') {
            $section = $Matches[1].Trim()
            continue
        }

        if ($section -ieq 'Settings') {
            if ($trim -match '^([^=]+)=(.*)$') {
                $k = $Matches[1].Trim()
                $v = $Matches[2].Trim()
                if ($k -ieq 'UnitSystem') {
                    if ($v -ieq 'Imperial') { $result.UnitSystem = 'Imperial' } else { $result.UnitSystem = 'Metric' }
                }
                elseif ($k -ieq 'LastCity') {
                    $result.LastCity = $v
                }
                elseif ($k -ieq 'Language') {
                    $lang = ([string]$v).Trim().ToLowerInvariant()
                    if (-not [string]::IsNullOrWhiteSpace($lang)) { $result.Language = $lang }
                }
            }
            continue
        }

        if ($section -ieq 'Cities') {
            if ($trim -match '^City\s*=\s*(.+)$') {
                $name = $Matches[1].Trim()
                if ($name.Length -gt 0) { $cities.Add($name) }
            }
            else {
                $cities.Add($trim)
            }
        }
    }

    # Unique + sorted (case-insensitive)
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $unique = New-Object System.Collections.Generic.List[string]
    foreach ($c in $cities) {
        $city = ([string]$c).Trim()
        if ($city.Length -eq 0) { continue }
        if ($seen.Add($city)) { $unique.Add($city) }
    }
    $result.Cities = @($unique.ToArray() | Sort-Object)

    return $result
}

function Save-SettingsIni {
    param(
        [ValidateSet('Metric', 'Imperial')]
        [string]$UnitSystem,

        [string]$LastCity,

        [string]$Language = 'en',

        [string[]]$Cities,

        [string]$Path = $script:SettingsIniPath
    )

    $citiesSorted = @($Cities | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } | Sort-Object)
    $lastCityValue = ''
    try {
        if ($null -ne $LastCity) { $lastCityValue = [string]$LastCity }
    }
    catch {
        $lastCityValue = ''
    }
    $content = New-Object System.Collections.Generic.List[string]
    $content.Add('[Settings]')
    $content.Add('UnitSystem=' + $UnitSystem)
    $content.Add('LastCity=' + $lastCityValue)
    $langValue = 'en'
    try {
        if ($null -ne $Language) {
            $langValue = ([string]$Language).Trim().ToLowerInvariant()
        }
    }
    catch { $langValue = 'en' }
    if ([string]::IsNullOrWhiteSpace($langValue) -or $langValue -eq '--') { $langValue = 'en' }
    $content.Add('Language=' + $langValue)
    $content.Add('')
    $content.Add('[Cities]')
    foreach ($c in $citiesSorted) {
        $content.Add('City=' + $c)
    }

    try {
        $dir = Split-Path -Path $Path -Parent
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }
    catch {
        # no-op
    }

    Set-Content -LiteralPath $Path -Value $content -Encoding UTF8
}

function Initialize-AppSettings {
    # If Settings.ini is missing but legacy Cities.ini exists, create Settings.ini.
    try {
        if (-not (Test-Path -LiteralPath $script:SettingsIniPath) -and (Test-Path -LiteralPath $script:LegacyCitiesIniPath)) {
            $legacyCities = @()
            try {
                # Reuse Settings parser by treating legacy file as just [Cities]
                $legacyCities = @((Get-SettingsFromIni -Path $script:LegacyCitiesIniPath).Cities)
            }
            catch {
                $legacyCities = @()
            }

            $first = ''
            if ($legacyCities.Count -gt 0) { $first = [string]$legacyCities[0] }
            Save-SettingsIni -UnitSystem 'Metric' -LastCity $first -Language 'en' -Cities $legacyCities
        }
    }
    catch {
        # no-op
    }

    $s = Get-SettingsFromIni
    $script:UnitSystem = $s.UnitSystem
    $script:LastCity = $s.LastCity
    $script:Language = $s.Language
    $script:StartupCities = @($s.Cities)
}

function Update-Personalizations {
    param(
        [string]$City
    )

    $cityTrim = ([string]$City).Trim()
    if (-not [string]::IsNullOrWhiteSpace($cityTrim)) {
        $script:LastCity = $cityTrim
    }

    $existing = @($script:StartupCities)
    if (-not [string]::IsNullOrWhiteSpace($cityTrim)) {
        $existing += $cityTrim
    }

    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $unique = New-Object System.Collections.Generic.List[string]
    foreach ($c in $existing) {
        $v = ([string]$c).Trim()
        if ($v.Length -eq 0) { continue }
        if ($seen.Add($v)) { $unique.Add($v) }
    }

    $sorted = @($unique.ToArray() | Sort-Object)
    $script:StartupCities = $sorted

    try {
        Save-SettingsIni -UnitSystem $script:UnitSystem -LastCity $script:LastCity -Language $script:Language -Cities $sorted
    }
    catch {
        # no-op
    }

    # Update the combo box list if it exists
    if ($null -ne (Get-Variable -Name cmbCity -Scope Script -ErrorAction SilentlyContinue)) {
        try {
            $cmbCity.BeginUpdate()
            $cmbCity.Items.Clear()
            if ($sorted.Count -gt 0) {
                [void]$cmbCity.Items.AddRange($sorted)
            }
            if (-not [string]::IsNullOrWhiteSpace($cityTrim)) {
                $cmbCity.Text = $cityTrim
            }
        }
        finally {
            try { $cmbCity.EndUpdate() } catch {}
        }
    }
}
