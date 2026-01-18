Set-StrictMode -Version Latest

function Invoke-WeatherRefresh {
    param(
        [AllowNull()]
        [string]$City
    )

    $city = [string]$City
    if ([string]::IsNullOrWhiteSpace($city)) {
        $city = [string]$cmbCity.Text
    }
    if ([string]::IsNullOrWhiteSpace($city)) { return }
    $city = $city.Trim()

    try {
        $btnRefresh.Enabled = $false
        $statusLabel.Text = "Loading $city..."
        $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor

        $data = Get-WeatherData -City $city -UnitSystem $script:UnitSystem
        Update-WeatherUiFromData -Data $data
        $statusLabel.Text = "Updated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        try { Update-Personalizations -City $city } catch { }
        Invoke-SuccessSound
    }
    catch {
        $statusLabel.Text = "Error: $($_.Exception.Message)"
        $isNetworkOrTimeout = $false
        try {
            $ex = $_.Exception

            # Typical timeout or offline cases show up as WebException in Windows PowerShell.
            if ($ex -is [System.Net.WebException]) {
                $isNetworkOrTimeout = $true
            }

            $msg = ''
            try { $msg = [string]$ex.Message } catch { $msg = '' }
            if ($msg) {
                if ($msg -match '(?i)timed out|timeout|name resolution|could not be resolved|connect|connection|unable to connect|internet') {
                    $isNetworkOrTimeout = $true
                }
            }
        }
        catch {
            $isNetworkOrTimeout = $true
        }

        if ($isNetworkOrTimeout) {
            Invoke-ErrorSound
        }
        else {
            try { [System.Media.SystemSounds]::Exclamation.Play() } catch { }
        }
    }
    finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
        $btnRefresh.Enabled = $true
    }
}

function Register-WeatherUiHandlers {
    $btnRefresh.Add_Click({ Invoke-WeatherRefresh }) | Out-Null

    $cmbCity.Add_SelectionChangeCommitted({
        $chosenCity = $null
        try {
            if ($null -ne $cmbCity.SelectedItem) {
                $chosenCity = [string]$cmbCity.SelectedItem
            }
        }
        catch {
            $chosenCity = $null
        }

        if ([string]::IsNullOrWhiteSpace($chosenCity)) {
            $chosenCity = [string]$cmbCity.Text
        }
        $chosenCity = ([string]$chosenCity).Trim()
        if (-not [string]::IsNullOrWhiteSpace($chosenCity)) {
            try { $cmbCity.Text = $chosenCity } catch { }
            try { Update-Personalizations -City $chosenCity } catch { }
            Invoke-WeatherRefresh -City $chosenCity
        }
    }) | Out-Null

    $cmbUnits.Add_SelectionChangeCommitted({
        try {
            $script:UnitSystem = [string]$cmbUnits.SelectedItem
            if ([string]::IsNullOrWhiteSpace($script:UnitSystem)) { $script:UnitSystem = 'Metric' }
        }
        catch {
            $script:UnitSystem = 'Metric'
        }
        try { Save-SettingsIni -UnitSystem $script:UnitSystem -LastCity $script:LastCity -Language $script:Language -Cities $script:StartupCities } catch { }
        Invoke-WeatherRefresh
    }) | Out-Null

    $cmbCity.Add_KeyDown({
        param($source, $e)
        if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
            $e.SuppressKeyPress = $true
            $typed = ([string]$cmbCity.Text).Trim()
            if (-not [string]::IsNullOrWhiteSpace($typed)) {
                try { Update-Personalizations -City $typed } catch { }
                Invoke-WeatherRefresh -City $typed
            }
        }
    }) | Out-Null

    $miAbout.Add_Click({
        $about = @(
            'Windows 98 Weather'
            ''
            'A tiny Win98-style weather dashboard powered by Open-Meteo.'
            ''
            'Built with:'
            '  - PowerShell'
            '  - Windows Forms (System.Windows.Forms)'
            ''
            'Made for a retro, readable UI: Current, Forecast, and Raw JSON tabs.'
            ''
            "App folder: $script:AppBase"
            "Sounds (optional): ding.wav, chord.wav"
        ) -join "`r`n"

        [System.Windows.Forms.MessageBox]::Show(
            $about,
            'About Windows 98 Weather',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }) | Out-Null

    $miHelp.Add_Click({
        try {
            $html1 = Join-Path $script:AppBase 'Weather98Help.html'
            $html2 = Join-Path $script:AppBase 'Windows98Weather.html'
            $html = $null
            if (Test-Path -LiteralPath $html1) {
                $html = $html1
            }
            elseif (Test-Path -LiteralPath $html2) {
                $html = $html2
            }

            if ($html) {
                Start-Process -FilePath $html | Out-Null
                return
            }

            $chm1 = Join-Path $script:AppBase 'Weather98Help.chm'
            $chm2 = Join-Path $script:AppBase 'Windows98Weather.chm'
            $chm = $null
            if (Test-Path -LiteralPath $chm1) {
                $chm = $chm1
            }
            elseif (Test-Path -LiteralPath $chm2) {
                $chm = $chm2
            }

            if ($chm) {
                Start-Process -FilePath $chm | Out-Null
                return
            }
        }
        catch {
            # fall through to built-in help
        }

        $helpText = @(
            'Windows 98 Weather - Help'
            ''
            'City:'
            '  Type a city name, or pick one from the list, then press Enter.'
            ''
            'Refresh:'
            '  Downloads fresh data from Open-Meteo (JSON).'
            ''
            'Units:'
            '  Switch between Metric and Imperial using the Units drop-down.'
            ''
            'Tabs:'
            '  Current  - current conditions + key details.'
            '  Forecast - pick a day on the left; hourly is below.'
            '  Raw JSON - shows the Open-Meteo-derived data.'
            ''
            'Sounds:'
            '  If ding.wav / chord.wav exist in the app folder, they play on success/error.'
            '  Otherwise Windows system sounds are used.'
        ) -join "`r`n"

        [System.Windows.Forms.MessageBox]::Show(
            $helpText,
            'Help',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }) | Out-Null

    $miQuit.Add_Click({
        try { $form.Close() } catch {}
    }) | Out-Null

    $lstDays.Add_SelectedIndexChanged({
        if ($null -ne $lstDays.SelectedItem) {
            Update-WeatherUiForDay -Date ([string]$lstDays.SelectedItem)
        }
    }) | Out-Null

    $form.Add_Shown({
        Set-ForecastLayout
        if (-not $script:StartupSoundPlayed) {
            $script:StartupSoundPlayed = $true
            Invoke-StartupSound
        }
        Invoke-WeatherRefresh
    }) | Out-Null

    $form.Add_Resize({ Set-ForecastLayout }) | Out-Null
}
