function Get-OpenMeteoWeatherDescription {
    param([AllowNull()]$WeatherCode)

    try {
        if ($null -eq $WeatherCode) { return '' }
        $c = [int]$WeatherCode
        switch ($c) {
            0 { 'Clear sky' }
            1 { 'Mainly clear' }
            2 { 'Partly cloudy' }
            3 { 'Overcast' }
            45 { 'Fog' }
            48 { 'Depositing rime fog' }
            51 { 'Light drizzle' }
            53 { 'Moderate drizzle' }
            55 { 'Dense drizzle' }
            56 { 'Light freezing drizzle' }
            57 { 'Dense freezing drizzle' }
            61 { 'Slight rain' }
            63 { 'Moderate rain' }
            65 { 'Heavy rain' }
            66 { 'Light freezing rain' }
            67 { 'Heavy freezing rain' }
            71 { 'Slight snow fall' }
            73 { 'Moderate snow fall' }
            75 { 'Heavy snow fall' }
            77 { 'Snow grains' }
            80 { 'Slight rain showers' }
            81 { 'Moderate rain showers' }
            82 { 'Violent rain showers' }
            85 { 'Slight snow showers' }
            86 { 'Heavy snow showers' }
            95 { 'Thunderstorm' }
            96 { 'Thunderstorm with hail' }
            99 { 'Thunderstorm with hail' }
            default { "Weather code $c" }
        }
    }
    catch {
        ''
    }
}

function Get-WeatherGlyph {
    param(
        [string]$Condition,
        [string]$WeatherCode
    )

    # Prefer numeric weather codes if present (Open-Meteo uses WMO codes).
    try {
        $wc = (SafeStr $WeatherCode '').Trim()
        if ($wc -match '^\d+$') {
            $c = [int]$wc
            if ($c -in 95,96,99) { return '⛈' }
            if ($c -in 71,73,75,77,85,86) { return '❄' }
            if ($c -in 51,53,55,56,57,61,63,65,66,67,80,81,82) { return '🌧' }
            if ($c -in 45,48) { return '🌫' }
            if ($c -in 1,2,3) { return '☁' }
            if ($c -eq 0) { return '☀' }
        }
    }
    catch {
        # fall through
    }

    $cnd = (SafeStr $Condition '').ToLowerInvariant()
    if ($cnd -match 'thunder|storm') { return '⛈' }
    if ($cnd -match 'snow|sleet|blizzard|ice|freezing') { return '❄' }
    if ($cnd -match 'rain|drizzle|shower') { return '🌧' }
    if ($cnd -match 'fog|mist|haze') { return '🌫' }
    if ($cnd -match 'overcast|cloud') { return '☁' }
    return '☀'
}

function Get-OpenMeteoGeocode {
    param(
        [Parameter(Mandatory)]
        [string]$City,

        [string]$Language = 'en',

        [int]$TimeoutSec = 15
    )

    $cityClean = (SafeStr $City '').Trim()
    if ([string]::IsNullOrWhiteSpace($cityClean)) {
        throw 'City is empty.'
    }

    $nameEnc = [System.Uri]::EscapeDataString($cityClean)
    $lang = (SafeStr $Language 'en').Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($lang) -or $lang -eq '--') { $lang = 'en' }
    $langEnc = [System.Uri]::EscapeDataString($lang)
    $uri = "https://geocoding-api.open-meteo.com/v1/search?name=$nameEnc&count=1&language=$langEnc&format=json"
    $geo = Invoke-JsonGet -Uri $uri -TimeoutSec $TimeoutSec
    if (-not $geo -or -not $geo.results -or $geo.results.Count -lt 1) {
        throw "City not found: $cityClean"
    }
    $geo.results[0]
}

function Get-OpenMeteoForecast {
    param(
        [Parameter(Mandatory)]
        [double]$Latitude,
        [Parameter(Mandatory)]
        [double]$Longitude,
        [Parameter(Mandatory)]
        [string]$Timezone,

        [ValidateSet('celsius', 'fahrenheit')]
        [string]$TemperatureUnit = 'celsius',

        [ValidateSet('kmh', 'mph', 'ms', 'kn')]
        [string]$WindSpeedUnit = 'kmh',

        [ValidateSet('mm', 'inch')]
        [string]$PrecipitationUnit = 'mm',

        [int]$ForecastDays = 16,
        [int]$TimeoutSec = 15
    )

    $tz = (SafeStr $Timezone 'auto')
    $lat = $Latitude.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    $lon = $Longitude.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    $days = [Math]::Max(1, [Math]::Min(16, [int]$ForecastDays))

    $current = @(
        'temperature_2m',
        'relative_humidity_2m',
        'dew_point_2m',
        'apparent_temperature',
        'precipitation',
        'rain',
        'showers',
        'cloud_cover',
        'cloud_cover_low',
        'cloud_cover_mid',
        'cloud_cover_high',
        'pressure_msl',
        'surface_pressure',
        'wind_speed_10m',
        'wind_direction_10m',
        'wind_gusts_10m',
        'visibility',
        'uv_index',
        'snow_depth',
        'is_day',
        'weather_code'
    ) -join ','

    $hourly = @(
        'temperature_2m',
        'apparent_temperature',
        'relative_humidity_2m',
        'precipitation',
        'precipitation_probability',
        'snowfall',
        'pressure_msl',
        'visibility',
        'uv_index',
        'wind_speed_10m',
        'wind_direction_10m',
        'weather_code'
    ) -join ','

    $daily = @(
        'temperature_2m_max',
        'temperature_2m_min',
        'uv_index_max',
        'precipitation_sum',
        'snowfall_sum',
        'sunrise',
        'sunset',
        'daylight_duration'
    ) -join ','

    $tzEnc = [System.Uri]::EscapeDataString($tz)
    $tu = [System.Uri]::EscapeDataString($TemperatureUnit)
    $wu = [System.Uri]::EscapeDataString($WindSpeedUnit)
    $pu = [System.Uri]::EscapeDataString($PrecipitationUnit)
    $uri = "https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&timezone=$tzEnc&forecast_days=$days&temperature_unit=$tu&wind_speed_unit=$wu&precipitation_unit=$pu&current=$current&hourly=$hourly&daily=$daily"
    Invoke-JsonGet -Uri $uri -TimeoutSec $TimeoutSec
}

function Convert-OpenMeteoToAppData {
    param(
        [Parameter(Mandatory)]
        $Geo,
        [Parameter(Mandatory)]
        $Forecast,
        [Parameter(Mandatory)]
        [string]$Query,

        [ValidateSet('Metric', 'Imperial')]
        [string]$UnitSystem = 'Metric'
    )

    $units = Get-UnitConfig -UnitSystem $UnitSystem

    $name = SafeStr $Geo.name
    $admin1 = SafeStr $Geo.admin1
    $country = SafeStr $Geo.country
    $lat = SafeStr $Geo.latitude
    $lon = SafeStr $Geo.longitude
    $tz = SafeStr $Forecast.timezone

    $current = $Forecast.current
    $ccTime = SafeStr $current.time
    $tempC = SafeStr $current.temperature_2m
    $feelsC = SafeStr $current.apparent_temperature
    $humidity = SafeStr $current.relative_humidity_2m
    $pressure = SafeStr $current.pressure_msl
    $surfacePressure = SafeStr $current.surface_pressure
    $wind = SafeStr $current.wind_speed_10m
    $windDeg = SafeStr $current.wind_direction_10m
    $windDir = Convert-WindDegreesTo16Point $windDeg
    $windGust = SafeStr $current.wind_gusts_10m

    $dewPoint = SafeStr $current.dew_point_2m
    $rainAmt = SafeStr $current.rain
    $showersAmt = SafeStr $current.showers

    $cloudLow = SafeStr $current.cloud_cover_low
    $cloudMid = SafeStr $current.cloud_cover_mid
    $cloudHigh = SafeStr $current.cloud_cover_high

    $isDayText = '--'
    try {
        $id = SafeStr $current.is_day
        if ($id -match '^\d+$') {
            if ([int]$id -eq 1) { $isDayText = 'Day' } else { $isDayText = 'Night' }
        }
    }
    catch { $isDayText = '--' }

    $snowDepthVal = '--'
    try {
        if ($null -ne $current.snow_depth) {
            $m = [double]$current.snow_depth
            if ($UnitSystem -eq 'Imperial') {
                $snowDepthVal = [Math]::Round($m * 39.3701, 1).ToString([System.Globalization.CultureInfo]::InvariantCulture)
            }
            else {
                $snowDepthVal = [Math]::Round($m * 100.0, 1).ToString([System.Globalization.CultureInfo]::InvariantCulture)
            }
        }
    }
    catch { $snowDepthVal = '--' }

    $visibilityVal = '--'
    try {
        if ($null -ne $current.visibility) {
            $km = ([double]$current.visibility) / 1000.0
            if ($UnitSystem -eq 'Imperial') {
                $mi = $km * 0.621371
                $visibilityVal = [Math]::Round($mi, 1).ToString([System.Globalization.CultureInfo]::InvariantCulture)
            }
            else {
                $visibilityVal = [Math]::Round($km, 1).ToString([System.Globalization.CultureInfo]::InvariantCulture)
            }
        }
    }
    catch { $visibilityVal = '--' }

    $precipMm = SafeStr $current.precipitation
    $cloud = SafeStr $current.cloud_cover
    $uv = SafeStr $current.uv_index
    $wmo = SafeStr $current.weather_code
    $desc = SafeStr (Get-OpenMeteoWeatherDescription $wmo)

    $obs = '--'
    $local = '--'
    try {
        if ($ccTime -and $ccTime -ne '--') {
            $dt = [DateTime]::Parse($ccTime, [System.Globalization.CultureInfo]::InvariantCulture)
            $obs = $dt.ToString('HH:mm')
            $local = $dt.ToString('yyyy-MM-dd HH:mm')
        }
    }
    catch {
        $obs = SafeStr $ccTime
        $local = SafeStr $ccTime
    }

    # Build a wttr-like object so the UI can stay simple.
    $data = [pscustomobject]@{
        request = @(
            [pscustomobject]@{
                type  = 'City'
                query = $Query
            }
        )
        nearest_area = @(
            [pscustomobject]@{
                areaName   = @([pscustomobject]@{ value = $name })
                region     = @([pscustomobject]@{ value = $admin1 })
                country    = @([pscustomobject]@{ value = $country })
                latitude   = $lat
                longitude  = $lon
                population = SafeStr $Geo.population
                timezone   = $tz
                elevation  = SafeStr $Forecast.elevation
            }
        )
        current_condition = @(
            [pscustomobject]@{
                temp_C           = $tempC
                FeelsLikeC       = $feelsC
                dewPointC        = $dewPoint
                weatherCode      = $wmo
                weatherDesc      = @([pscustomobject]@{ value = $desc })
                humidity         = $humidity
                pressure         = $pressure
                surfacePressure  = $surfacePressure
                windspeedKmph    = $wind
                windgustKmph     = $windGust
                winddir16Point   = $windDir
                visibility       = $visibilityVal
                precipMM         = $precipMm
                rainMM           = $rainAmt
                showersMM        = $showersAmt
                cloudcover       = $cloud
                cloudLow         = $cloudLow
                cloudMid         = $cloudMid
                cloudHigh        = $cloudHigh
                uvIndex          = $uv
                snowDepth        = $snowDepthVal
                isDay            = $isDayText
                observation_time = $obs
                localObsDateTime = $local
            }
        )
        weather = @()
        _provider = [pscustomobject]@{
            name = 'open-meteo'
            timezone = $tz
        }
        _units = $units
    }

    # Daily (Selected Day panel)
    $daily = $Forecast.daily
    $dailyTimes = @($daily.time)

    # Hourly (grid)
    $hourly = $Forecast.hourly
    $hourlyTimes = @($hourly.time)

    # Index hourly entries by date string
    $hourByDate = @{}
    for ($i = 0; $i -lt $hourlyTimes.Count; $i++) {
        $t = [string]$hourlyTimes[$i]
        if ([string]::IsNullOrWhiteSpace($t)) { continue }
        $dateKey = $t
        if ($dateKey.Length -ge 10) { $dateKey = $dateKey.Substring(0, 10) }
        if (-not $hourByDate.ContainsKey($dateKey)) {
            $hourByDate[$dateKey] = New-Object System.Collections.Generic.List[int]
        }
        $hourByDate[$dateKey].Add($i)
    }

    $days = New-Object System.Collections.Generic.List[object]
    for ($d = 0; $d -lt $dailyTimes.Count; $d++) {
        $date = SafeStr $dailyTimes[$d]
        if ($date -eq '--') { continue }

        $sunrise = SafeStr $daily.sunrise[$d]
        $sunset = SafeStr $daily.sunset[$d]

        $daylightHours = '--'
        try {
            $sec = $daily.daylight_duration[$d]
            if ($null -ne $sec) {
                $daylightHours = [Math]::Round(([double]$sec) / 3600.0, 1).ToString([System.Globalization.CultureInfo]::InvariantCulture)
            }
        }
        catch { $daylightHours = '--' }

        $snowSum = SafeStr $daily.snowfall_sum[$d]
        if ($UnitSystem -eq 'Imperial') {
            # Open-Meteo snowfall is in cm; convert to inches.
            try {
                if ($snowSum -ne '--') {
                    $snowSum = [Math]::Round(([double]$snowSum) / 2.54, 2).ToString([System.Globalization.CultureInfo]::InvariantCulture)
                }
            }
            catch { }
        }

        $dayObj = [pscustomobject]@{
            date = $date
            maxtempC = SafeStr $daily.temperature_2m_max[$d]
            mintempC = SafeStr $daily.temperature_2m_min[$d]
            avgtempC = '--'
            uvIndex  = SafeStr $daily.uv_index_max[$d]
            sunHour  = $daylightHours
            precipSumMm = SafeStr $daily.precipitation_sum[$d]
            totalSnow_cm = $snowSum
            astronomy = @(
                [pscustomobject]@{
                    sunrise = $sunrise
                    sunset = $sunset
                    moon_phase = '--'
                    moon_illumination = '--'
                    moonrise = '--'
                    moonset = '--'
                }
            )
            hourly = @()
        }

        # Compute avg temp from min/max if possible
        try {
            $min = [double]$daily.temperature_2m_min[$d]
            $max = [double]$daily.temperature_2m_max[$d]
            $dayObj.avgtempC = [Math]::Round(($min + $max) / 2.0, 1).ToString([System.Globalization.CultureInfo]::InvariantCulture)
        }
        catch {
            $dayObj.avgtempC = '--'
        }

        $rows = New-Object System.Collections.Generic.List[object]
        if ($hourByDate.ContainsKey($date)) {
            foreach ($ix in $hourByDate[$date]) {
                $ht = [string]$hourlyTimes[$ix]
                $hour = '--'
                try {
                    if ($ht -and $ht.Length -ge 13) { $hour = $ht.Substring(11, 2) }
                }
                catch { $hour = '--' }

                $timeField = $hour
                if ($timeField -match '^\d+$') {
                    $timeField = (([int]$timeField) * 100).ToString()
                }
                else {
                    $timeField = '--'
                }

                $hc = SafeStr $hourly.weather_code[$ix]
                $hdesc = SafeStr (Get-OpenMeteoWeatherDescription $hc)
                $hVis = '--'
                try {
                    if ($null -ne $hourly.visibility[$ix]) {
                        $km = ([double]$hourly.visibility[$ix]) / 1000.0
                        if ($UnitSystem -eq 'Imperial') {
                            $mi = $km * 0.621371
                            $hVis = [Math]::Round($mi, 1).ToString([System.Globalization.CultureInfo]::InvariantCulture)
                        }
                        else {
                            $hVis = [Math]::Round($km, 1).ToString([System.Globalization.CultureInfo]::InvariantCulture)
                        }
                    }
                }
                catch { $hVis = '--' }

                $snow = SafeStr $hourly.snowfall[$ix]
                if ($UnitSystem -eq 'Imperial') {
                    try {
                        if ($snow -ne '--') {
                            $snow = [Math]::Round(([double]$snow) / 2.54, 2).ToString([System.Globalization.CultureInfo]::InvariantCulture)
                        }
                    }
                    catch { }
                }

                $rows.Add([pscustomobject]@{
                    time = $timeField
                    tempC = SafeStr $hourly.temperature_2m[$ix]
                    FeelsLikeC = SafeStr $hourly.apparent_temperature[$ix]
                    weatherCode = $hc
                    weatherDesc = @([pscustomobject]@{ value = $hdesc })
                    windspeedKmph = SafeStr $hourly.wind_speed_10m[$ix]
                    winddir16Point = Convert-WindDegreesTo16Point $hourly.wind_direction_10m[$ix]
                    humidity = SafeStr $hourly.relative_humidity_2m[$ix]
                    precipMM = SafeStr $hourly.precipitation[$ix]
                    pressure = SafeStr $hourly.pressure_msl[$ix]
                    visibility = $hVis
                    uvIndex = SafeStr $hourly.uv_index[$ix]
                    chanceofrain = SafeStr $hourly.precipitation_probability[$ix]
                    chanceofsnow = $snow
                })
            }
        }

        $dayObj.hourly = $rows
        $days.Add($dayObj)
    }

    $data.weather = $days
    return $data
}

function Get-WeatherData {
    param(
        [Parameter(Mandatory)]
        [string]$City,

        [ValidateSet('Metric', 'Imperial')]
        [string]$UnitSystem = 'Metric',

        [int]$TimeoutSec = 15
    )

    $geo = Get-OpenMeteoGeocode -City $City -Language $script:Language -TimeoutSec $TimeoutSec

    $lat = [double]$geo.latitude
    $lon = [double]$geo.longitude
    $tz = SafeStr $geo.timezone 'auto'
    if ($tz -eq '--') { $tz = 'auto' }

    $u = Get-UnitConfig -UnitSystem $UnitSystem
    $forecast = Get-OpenMeteoForecast -Latitude $lat -Longitude $lon -Timezone $tz -TemperatureUnit $u.temperature_unit -WindSpeedUnit $u.wind_speed_unit -PrecipitationUnit $u.precipitation_unit -ForecastDays 16 -TimeoutSec $TimeoutSec
    Convert-OpenMeteoToAppData -Geo $geo -Forecast $forecast -Query $City -UnitSystem $UnitSystem
}
