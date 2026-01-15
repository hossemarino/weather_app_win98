Set-StrictMode -Version Latest

function Update-WeatherUiFromData {
    param(
        [Parameter(Mandatory)]
        $Data
    )

    $script:LastData = $Data
    $txtRaw.Text = Format-PrettyJson $Data

    $cc = $null
    if ($Data.current_condition -and $Data.current_condition.Count -gt 0) { $cc = $Data.current_condition[0] }

    $u = $null
    try { $u = $Data._units } catch { $u = $null }
    if ($null -eq $u) { $u = Get-UnitConfig -UnitSystem $script:UnitSystem }

    if ($null -ne $cc) {
        $tempC = SafeStr $cc.temp_C
        $feels = SafeStr $cc.FeelsLikeC
        $desc = SafeStr (Get-ValueFromArray $cc.weatherDesc '')
        $glyph = Get-WeatherGlyph -Condition $desc -WeatherCode (SafeStr $cc.weatherCode '')

        $lblGlyph.Text = $glyph
        $lblBigTemp.Text = "$tempC$($u.tempSuffix)"
        $lblTemp.Text = "$tempC$($u.tempSuffix)"
        $lblFeels.Text = "$feels$($u.tempSuffix)"
        $lblCond.Text = $desc
        $lblHumidity.Text = "$(SafeStr $cc.humidity)%"
        $lblPressure.Text = "$(SafeStr $cc.pressure) hPa"
        $lblWind.Text = "$(SafeStr $cc.windspeedKmph) $($u.windSuffix) $(SafeStr $cc.winddir16Point)"
        $lblVisibility.Text = "$(SafeStr $cc.visibility) $($u.visibilitySuffix)"
        $lblPrecip.Text = "$(SafeStr $cc.precipMM) $($u.precipSuffix)"
        $lblCloud.Text = "$(SafeStr $cc.cloudcover)%"
        $lblUv.Text = SafeStr $cc.uvIndex
        $lblObs.Text = SafeStr $cc.observation_time
        $lblLocal.Text = SafeStr $cc.localObsDateTime

        if ($lblDewPoint) { $lblDewPoint.Text = "$(SafeStr $cc.dewPointC)$($u.tempSuffix)" }
        if ($lblWindGust) { $lblWindGust.Text = "$(SafeStr $cc.windgustKmph) $($u.windSuffix)" }
        if ($lblRain) { $lblRain.Text = "$(SafeStr $cc.rainMM) $($u.precipSuffix)" }
        if ($lblShowers) { $lblShowers.Text = "$(SafeStr $cc.showersMM) $($u.precipSuffix)" }
        if ($lblSnowDepth) { $lblSnowDepth.Text = "$(SafeStr $cc.snowDepth) $($u.snowSuffix)" }
        if ($lblIsDay) { $lblIsDay.Text = SafeStr $cc.isDay }
        if ($lblSurfacePressure) { $lblSurfacePressure.Text = "$(SafeStr $cc.surfacePressure) hPa" }
        if ($lblCloudLayers) {
            $lo = SafeStr $cc.cloudLow
            $mi = SafeStr $cc.cloudMid
            $hi = SafeStr $cc.cloudHigh
            if ($lo -eq '--' -or $mi -eq '--' -or $hi -eq '--') {
                $lblCloudLayers.Text = '--'
            }
            else {
                $lblCloudLayers.Text = "$lo/$mi/$hi%"
            }
        }
    }
    else {
        $lblBigTemp.Text = '--'
    }

    $na = $null
    if ($Data.nearest_area -and $Data.nearest_area.Count -gt 0) { $na = $Data.nearest_area[0] }
    if ($null -ne $na) {
        $lblArea.Text = SafeStr (Get-ValueFromArray $na.areaName)
        $lblRegion.Text = SafeStr (Get-ValueFromArray $na.region)
        $lblCountry.Text = SafeStr (Get-ValueFromArray $na.country)
        $lat = SafeStr $na.latitude
        $lon = SafeStr $na.longitude
        $lblLatLon.Text = "$lat, $lon"
        $lblPopulation.Text = SafeStr $na.population
        if ($lblTimezone) { $lblTimezone.Text = SafeStr $na.timezone }
        if ($lblElevation) {
            $e = SafeStr $na.elevation
            if ($e -ne '--') {
                if ($u.unitSystem -eq 'Imperial') {
                    try {
                        $ft = [Math]::Round(([double]$e) * 3.28084, 0)
                        $lblElevation.Text = "$ft $($u.elevationSuffix)"
                    }
                    catch {
                        $lblElevation.Text = "$e m"
                    }
                }
                else {
                    $lblElevation.Text = "$e $($u.elevationSuffix)"
                }
            }
            else { $lblElevation.Text = '--' }
        }
    }

    $rq = $null
    if ($Data.request -and $Data.request.Count -gt 0) { $rq = $Data.request[0] }
    if ($null -ne $rq) {
        $lblRequest.Text = "$(SafeStr $rq.type): $(SafeStr $rq.query)"
    }

    # Forecast days
    $lstDays.Items.Clear()
    $script:DayMap = @{}
    if ($Data.weather) {
        foreach ($day in $Data.weather) {
            $date = SafeStr $day.date
            if ($date -ne '--') {
                [void]$lstDays.Items.Add($date)
                $script:DayMap[$date] = $day
            }
        }
    }

    if ($lstDays.Items.Count -gt 0) {
        $lstDays.SelectedIndex = 0
    }
}

function Update-WeatherUiForDay {
    param(
        [Parameter(Mandatory)]
        [string]$Date
    )

    if (-not $script:DayMap.ContainsKey($Date)) {
        $lblFDate.Text = '--'
        $lblFMin.Text = '--'
        $lblFMax.Text = '--'
        $lblFAvg.Text = '--'
        $lblFSun.Text = '--'
        $lblFUV.Text = '--'
        $lblFPrecip.Text = '--'
        $lblFSnow.Text = '--'
        $lblFSunrise.Text = '--'
        $lblFSunset.Text = '--'
        $lblFDaylight.Text = '--'
        $gridHourly.DataSource = $null
        return
    }

    $day = $script:DayMap[$Date]
    $astro = $null
    if ($day.astronomy -and $day.astronomy.Count -gt 0) { $astro = $day.astronomy[0] }

    # Current tab sunrise/sunset should reflect selected day too
    if ($null -ne $astro) {
        $lblSunrise.Text = SafeStr $astro.sunrise
        $lblSunset.Text = SafeStr $astro.sunset
    }

    $lblFDate.Text = $Date
    $u = $null
    try { $u = $script:LastData._units } catch { $u = $null }
    if ($null -eq $u) { $u = Get-UnitConfig -UnitSystem $script:UnitSystem }

    $lblFMin.Text = "$(SafeStr $day.mintempC)$($u.tempSuffix)"
    $lblFMax.Text = "$(SafeStr $day.maxtempC)$($u.tempSuffix)"
    $lblFAvg.Text = "$(SafeStr $day.avgtempC)$($u.tempSuffix)"
    $lblFSun.Text = "$(SafeStr $day.sunHour) h"
    $lblFUV.Text = SafeStr $day.uvIndex
    if ($day.PSObject.Properties.Name -contains 'precipSumMm') {
        $lblFPrecip.Text = "$(SafeStr $day.precipSumMm) $($u.precipSuffix)"
    }
    else {
        $lblFPrecip.Text = '--'
    }

    $lblFSnow.Text = "$(SafeStr $day.totalSnow_cm) $($u.snowSuffix)"
    $lblFDaylight.Text = "$(SafeStr $day.sunHour) h"
    if ($null -ne $astro) {
        $lblFSunrise.Text = SafeStr $astro.sunrise
        $lblFSunset.Text = SafeStr $astro.sunset
    }
    else {
        $lblFSunrise.Text = '--'
        $lblFSunset.Text = '--'
    }

    $rows = New-Object System.Collections.Generic.List[object]
    if ($day.hourly) {
        foreach ($h in $day.hourly) {
            $time = SafeStr $h.time
            if ($time -match '^\d+$') {
                $time = $time.PadLeft(4, '0')
                $time = $time.Insert(2, ':')
            }
            $desc = SafeStr (Get-ValueFromArray $h.weatherDesc '')
            $rows.Add([pscustomobject]@{
                Time = $time
                TempC = SafeStr $h.tempC
                FeelsLikeC = SafeStr $h.FeelsLikeC
                Condition = $desc.Trim()
                WindKmph = SafeStr $h.windspeedKmph
                WindDir = SafeStr $h.winddir16Point
                HumidityPct = SafeStr $h.humidity
                PrecipMM = SafeStr $h.precipMM
                Pressure = SafeStr $h.pressure
                VisibilityKm = SafeStr $h.visibility
                UV = SafeStr $h.uvIndex
                ChanceRain = SafeStr $h.chanceofrain
                ChanceSnow = SafeStr $h.chanceofsnow
            })
        }
    }
    $gridHourly.DataSource = $rows

    try {
        if ($gridHourly.Columns['TempC']) { $gridHourly.Columns['TempC'].HeaderText = "Temp ($($u.tempSuffix))" }
        if ($gridHourly.Columns['FeelsLikeC']) { $gridHourly.Columns['FeelsLikeC'].HeaderText = "Feels ($($u.tempSuffix))" }
        if ($gridHourly.Columns['HumidityPct']) { $gridHourly.Columns['HumidityPct'].HeaderText = 'Humidity (%)' }
        if ($gridHourly.Columns['PrecipMM']) { $gridHourly.Columns['PrecipMM'].HeaderText = "Precip ($($u.precipSuffix))" }
        if ($gridHourly.Columns['VisibilityKm']) { $gridHourly.Columns['VisibilityKm'].HeaderText = "Vis ($($u.visibilitySuffix))" }
        if ($gridHourly.Columns['WindKmph']) { $gridHourly.Columns['WindKmph'].HeaderText = "Wind ($($u.windSuffix))" }
        if ($gridHourly.Columns['ChanceRain']) { $gridHourly.Columns['ChanceRain'].HeaderText = 'Chance Rain (%)' }
        if ($gridHourly.Columns['ChanceSnow']) { $gridHourly.Columns['ChanceSnow'].HeaderText = "Snow ($($u.snowSuffix))" }
        if ($gridHourly.Columns['Time']) { $gridHourly.Columns['Time'].Frozen = $true }
        if ($gridHourly.Columns['TempC']) { $gridHourly.Columns['TempC'].Frozen = $true }
    }
    catch {
        # no-op
    }
}
