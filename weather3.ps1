Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

& {

try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
}
catch {
    # Ignore if not supported
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Prefer classic Win98-like widgets (including scrollbars) by disabling Visual Styles.
# Note: True per-control Win98 scrollbars aren't reliably themeable on Win11; this is the closest native WinForms option.
try {
    [System.Windows.Forms.Application]::VisualStyleState = [System.Windows.Forms.VisualStyles.VisualStyleState]::NoneEnabled
}
catch {
    # no-op
}
try {
    [System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)
}
catch {
    # no-op
}

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

function Get-WttrJson {
    param(
        [Parameter(Mandatory)]
        [string]$City,

        [int]$TimeoutSec = 15
    )

    $cityClean = (SafeStr $City '').Trim()
    if ([string]::IsNullOrWhiteSpace($cityClean)) {
        throw 'City is empty.'
    }

    $cityEncoded = [System.Uri]::EscapeDataString($cityClean)
    $uri = 'https://wttr.in/{0}?format=j1' -f $cityEncoded

    $headers = @{
        'User-Agent' = 'curl/8.0.0'
        'Accept'     = 'application/json'
    }

    if ($PSVersionTable.PSVersion.Major -lt 6) {
        $resp = Invoke-WebRequest -Method Get -Uri $uri -Headers $headers -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop
    }
    else {
        $resp = Invoke-WebRequest -Method Get -Uri $uri -Headers $headers -TimeoutSec $TimeoutSec -ErrorAction Stop
    }

    $jsonText = [string]$resp.Content
    $trim = $jsonText.TrimStart()
    if (-not ($trim.StartsWith('{') -or $trim.StartsWith('['))) {
        $short = $trim
        if ($short.Length -gt 200) { $short = $short.Substring(0, 200) + '…' }
        throw "wttr.in returned non-JSON. First chars: $short"
    }

    $jsonText | ConvertFrom-Json -ErrorAction Stop
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

function Get-WeatherGlyph {
    param(
        [string]$Condition,
        [string]$WeatherCode
    )
    $c = (SafeStr $Condition '').ToLowerInvariant()
    if ($c -match 'thunder|storm') { return '⛈' }
    if ($c -match 'snow|sleet|blizzard|ice|freezing') { return '❄' }
    if ($c -match 'rain|drizzle|shower') { return '🌧' }
    if ($c -match 'fog|mist|haze') { return '🌫' }
    if ($c -match 'overcast|cloud') { return '☁' }
    return '☀'
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

$script:AppBase = Get-AppBaseDirectory
$script:SoundSuccessPath = [System.IO.Path]::Combine($script:AppBase, 'ding.wav')
$script:SoundErrorPath = [System.IO.Path]::Combine($script:AppBase, 'chord.wav')
$script:StartupSoundPlayed = $false
$script:CitiesIniPath = Join-Path $script:AppBase 'Cities.ini'

function Get-CitiesFromIni {
    param(
        [string]$Path = $script:CitiesIniPath
    )

    $results = New-Object System.Collections.Generic.List[string]
    if (-not (Test-Path -LiteralPath $Path)) {
        return @()
    }

    try {
        $lines = Get-Content -LiteralPath $Path -ErrorAction Stop
    }
    catch {
        return @()
    }

    $inCities = $false
    foreach ($lineRaw in $lines) {
        $line = [string]$lineRaw
        if ($null -eq $line) { continue }
        $trim = $line.Trim()
        if ($trim.Length -eq 0) { continue }
        if ($trim.StartsWith(';') -or $trim.StartsWith('#')) { continue }

        if ($trim -match '^\[(.+)\]$') {
            $section = $Matches[1].Trim()
            $inCities = ($section -ieq 'Cities')
            continue
        }

        if ($inCities) {
            # Prefer City=<name> (repeatable)
            if ($trim -match '^City\s*=\s*(.+)$') {
                $name = $Matches[1].Trim()
                if ($name.Length -gt 0) { $results.Add($name) }
            }
            else {
                # Fallback: allow plain city names as lines
                $results.Add($trim)
            }
        }
        else {
            # Back-compat: if no [Cities] section exists, treat lines as city names
            $results.Add($trim)
        }
    }

    # Unique + sorted (case-insensitive)
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $unique = New-Object System.Collections.Generic.List[string]
    foreach ($c in $results) {
        $city = ([string]$c).Trim()
        if ($city.Length -eq 0) { continue }
        if ($seen.Add($city)) { $unique.Add($city) }
    }

    $unique.ToArray() | Sort-Object
}

function Set-CitiesIni {
    param(
        [Parameter(Mandatory)]
        [string[]]$Cities,

        [string]$Path = $script:CitiesIniPath
    )

    $citiesSorted = @($Cities | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } | Sort-Object)
    $content = New-Object System.Collections.Generic.List[string]
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

function Update-CityList {
    param(
        [Parameter(Mandatory)]
        [string]$City
    )

    $cityTrim = ([string]$City).Trim()
    if ([string]::IsNullOrWhiteSpace($cityTrim)) { return }

    $existing = @(Get-CitiesFromIni)
    $all = @($existing + $cityTrim)

    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $unique = New-Object System.Collections.Generic.List[string]
    foreach ($c in $all) {
        $v = ([string]$c).Trim()
        if ($v.Length -eq 0) { continue }
        if ($seen.Add($v)) { $unique.Add($v) }
    }

    $sorted = @($unique.ToArray() | Sort-Object)
    Set-CitiesIni -Cities $sorted

    try {
        $cmbCity.BeginUpdate()
        $cmbCity.Items.Clear()
        if ($sorted.Count -gt 0) {
            [void]$cmbCity.Items.AddRange($sorted)
        }
        $idx = -1
        try { $idx = $cmbCity.FindStringExact($cityTrim) } catch { $idx = -1 }
        if ($idx -ge 0) {
            $cmbCity.SelectedIndex = $idx
        }
        else {
            # Keep allowing free-typed cities even if not in the list
            $cmbCity.Text = $cityTrim
        }
    }
    finally {
        try { $cmbCity.EndUpdate() } catch {}
    }
}

function Get-SelectedCity {
    # ComboBox.Text can be affected by AutoComplete; prefer SelectedItem when a list entry is chosen.
    try {
        if ($cmbCity.SelectedIndex -ge 0 -and $null -ne $cmbCity.SelectedItem) {
            return ([string]$cmbCity.SelectedItem).Trim()
        }
    }
    catch {
        # fall through
    }
    return ([string]$cmbCity.Text).Trim()
}

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

# --- Win98-ish theme (system colors keep the classic look) ---
$win98Gray = [System.Drawing.SystemColors]::Control
$win98Light = [System.Drawing.SystemColors]::ControlLight
$font = New-Object System.Drawing.Font('Microsoft Sans Serif', 8.25)
$mono = New-Object System.Drawing.Font('Consolas', 9)

# --- Form ---
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Windows 98 Weather'
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.Size = New-Object System.Drawing.Size(860, 620)
$form.BackColor = $win98Gray
$form.Font = $font
try {
    $ico = Join-Path $script:AppBase 'weather.ico'
    if (Test-Path -LiteralPath $ico) {
        $form.Icon = New-Object System.Drawing.Icon($ico)
    }
    else {
        $form.Icon = [System.Drawing.SystemIcons]::Application
    }
}
catch {
    try { $form.Icon = [System.Drawing.SystemIcons]::Application } catch {}
}

# --- Menu (Help / About) ---
$menu = New-Object System.Windows.Forms.MenuStrip
$menu.Dock = 'Top'
$menu.BackColor = $win98Gray
$menu.RenderMode = 'System'

$miHelpRoot = New-Object System.Windows.Forms.ToolStripMenuItem
$miHelpRoot.Text = '&Help'

$miHelp = New-Object System.Windows.Forms.ToolStripMenuItem
$miHelp.Text = '&Help'

$miAbout = New-Object System.Windows.Forms.ToolStripMenuItem
$miAbout.Text = '&About'

$miFileRoot = New-Object System.Windows.Forms.ToolStripMenuItem
$miFileRoot.Text = '&File'

$miQuit = New-Object System.Windows.Forms.ToolStripMenuItem
$miQuit.Text = '&Quit'

[void]$miHelpRoot.DropDownItems.Add($miHelp)
[void]$miHelpRoot.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$miHelpRoot.DropDownItems.Add($miAbout)

[void]$miFileRoot.DropDownItems.Add($miQuit)

[void]$menu.Items.Add($miFileRoot)
[void]$menu.Items.Add($miHelpRoot)
$form.MainMenuStrip = $menu

# --- Top bar ---
$topPanel = New-Object System.Windows.Forms.Panel
$topPanel.Dock = 'Top'
$topPanel.Height = 40
$topPanel.BackColor = $win98Gray
$topPanel.BorderStyle = 'Fixed3D'

$lblCity = New-Object System.Windows.Forms.Label
$lblCity.Text = 'City:'
$lblCity.AutoSize = $true
$lblCity.Location = New-Object System.Drawing.Point(12, 12)
$topPanel.Controls.Add($lblCity)

$cmbCity = New-Object System.Windows.Forms.ComboBox
$cmbCity.DropDownStyle = 'DropDown'
$cmbCity.Location = New-Object System.Drawing.Point(48, 9)
$cmbCity.Width = 240
$iniCities = @(Get-CitiesFromIni)
if ($iniCities.Count -gt 0) {
    [void]$cmbCity.Items.AddRange($iniCities)
    $cmbCity.SelectedIndex = 0
}
$cmbCity.AutoCompleteMode = 'Suggest'
$cmbCity.AutoCompleteSource = 'ListItems'
$topPanel.Controls.Add($cmbCity)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = 'Refresh'
$btnRefresh.Location = New-Object System.Drawing.Point(300, 8)
$btnRefresh.Size = New-Object System.Drawing.Size(90, 25)
$btnRefresh.BackColor = $win98Light
$btnRefresh.FlatStyle = 'System'
$topPanel.Controls.Add($btnRefresh)

# --- Tabs ---
$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = 'Fill'
$tabs.Appearance = 'Normal'
$tabs.SizeMode = 'Normal'
$tabs.HotTrack = $false

$tabCurrent = New-Object System.Windows.Forms.TabPage
$tabCurrent.Text = 'Current'
$tabCurrent.BackColor = $win98Gray
$tabs.TabPages.Add($tabCurrent)

$tabForecast = New-Object System.Windows.Forms.TabPage
$tabForecast.Text = 'Forecast'
$tabForecast.BackColor = $win98Gray
$tabs.TabPages.Add($tabForecast)

$tabRaw = New-Object System.Windows.Forms.TabPage
$tabRaw.Text = 'Raw JSON'
$tabRaw.BackColor = $win98Gray
$tabs.TabPages.Add($tabRaw)

# --- Status bar ---
$status = New-Object System.Windows.Forms.StatusStrip
$statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLabel.Text = 'Ready.'
[void]$status.Items.Add($statusLabel)

# IMPORTANT: Docking order matters. Add Fill first, then Bottom, then Top rows.
# For Win98-style layout, menu sits directly under the title bar.
$form.Controls.Add($tabs)
$form.Controls.Add($status)
$form.Controls.Add($topPanel)
$form.Controls.Add($menu)

# --- Current tab layout ---
$currentSplit = New-Object System.Windows.Forms.SplitContainer
$currentSplit.Dock = 'Fill'
$currentSplit.Orientation = 'Horizontal'
$currentSplit.SplitterDistance = 240
$currentSplit.BorderStyle = 'Fixed3D'
$tabCurrent.Controls.Add($currentSplit)

$grpCurrent = New-Object System.Windows.Forms.GroupBox
$grpCurrent.Text = 'Current Condition'
$grpCurrent.Dock = 'Fill'
$grpCurrent.BackColor = $win98Gray
$currentSplit.Panel1.Controls.Add($grpCurrent)

$tblCur = New-Object System.Windows.Forms.TableLayoutPanel
$tblCur.Dock = 'Fill'
$tblCur.ColumnCount = 4
$tblCur.RowCount = 7
$tblCur.Padding = '6,12,6,6'
$tblCur.AutoSize = $false
$tblCur.BackColor = $win98Gray
$tblCur.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 120)))
$tblCur.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
$tblCur.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 120)))
$tblCur.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
$grpCurrent.Controls.Add($tblCur)

function New-LabelPairRow {
    param(
        [int]$Row,
        [string]$LeftKey,
        [ref]$LeftValue,
        [string]$RightKey,
        [ref]$RightValue
    )

    $k1 = New-Object System.Windows.Forms.Label
    $k1.Text = $LeftKey
    $k1.AutoSize = $true
    $v1 = New-Object System.Windows.Forms.Label
    $v1.Text = '--'
    $v1.AutoSize = $true

    $k2 = New-Object System.Windows.Forms.Label
    $k2.Text = $RightKey
    $k2.AutoSize = $true
    $v2 = New-Object System.Windows.Forms.Label
    $v2.Text = '--'
    $v2.AutoSize = $true

    $tblCur.Controls.Add($k1, 0, $Row)
    $tblCur.Controls.Add($v1, 1, $Row)
    $tblCur.Controls.Add($k2, 2, $Row)
    $tblCur.Controls.Add($v2, 3, $Row)

    $LeftValue.Value = $v1
    $RightValue.Value = $v2
}

$lblTemp = $null
$lblFeels = $null
$lblCond = $null
$lblObs = $null
$lblHumidity = $null
$lblPressure = $null
$lblWind = $null
$lblVisibility = $null
$lblPrecip = $null
$lblCloud = $null
$lblUv = $null
$lblLocal = $null
$lblGlyph = New-Object System.Windows.Forms.Label
$lblGlyph.Text = '☀'
$lblGlyph.Font = New-Object System.Drawing.Font('Segoe UI Emoji', 28)
$lblGlyph.AutoSize = $true
$lblGlyph.Location = New-Object System.Drawing.Point(14, 28)
$grpCurrent.Controls.Add($lblGlyph)

$lblBigTemp = New-Object System.Windows.Forms.Label
$lblBigTemp.Text = '--°C'
$lblBigTemp.Font = New-Object System.Drawing.Font('Microsoft Sans Serif', 20, [System.Drawing.FontStyle]::Bold)
$lblBigTemp.AutoSize = $true
$lblBigTemp.Location = New-Object System.Drawing.Point(58, 34)
$grpCurrent.Controls.Add($lblBigTemp)

New-LabelPairRow -Row 0 -LeftKey 'Temp'      -LeftValue ([ref]$lblTemp)      -RightKey 'Feels Like' -RightValue ([ref]$lblFeels)
New-LabelPairRow -Row 1 -LeftKey 'Condition' -LeftValue ([ref]$lblCond)      -RightKey 'Cloud'      -RightValue ([ref]$lblCloud)
New-LabelPairRow -Row 2 -LeftKey 'Humidity'  -LeftValue ([ref]$lblHumidity)  -RightKey 'Pressure'   -RightValue ([ref]$lblPressure)
New-LabelPairRow -Row 3 -LeftKey 'Wind'      -LeftValue ([ref]$lblWind)      -RightKey 'Visibility' -RightValue ([ref]$lblVisibility)
New-LabelPairRow -Row 4 -LeftKey 'Precip'    -LeftValue ([ref]$lblPrecip)    -RightKey 'UV Index'   -RightValue ([ref]$lblUv)
New-LabelPairRow -Row 5 -LeftKey 'Observed'  -LeftValue ([ref]$lblObs)       -RightKey 'Local Time' -RightValue ([ref]$lblLocal)

$grpMeta = New-Object System.Windows.Forms.GroupBox
$grpMeta.Text = 'Location + Astronomy (Selected Day)'
$grpMeta.Dock = 'Fill'
$grpMeta.BackColor = $win98Gray
$currentSplit.Panel2.Controls.Add($grpMeta)

$tblMeta = New-Object System.Windows.Forms.TableLayoutPanel
$tblMeta.Dock = 'Fill'
$tblMeta.ColumnCount = 4
$tblMeta.RowCount = 6
$tblMeta.Padding = '6,12,6,6'
$tblMeta.BackColor = $win98Gray
$tblMeta.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 120)))
$tblMeta.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
$tblMeta.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 120)))
$tblMeta.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
$grpMeta.Controls.Add($tblMeta)

function New-MetaRow {
    param(
        [int]$Row,
        [string]$LeftKey,
        [ref]$LeftValue,
        [string]$RightKey,
        [ref]$RightValue
    )

    $k1 = New-Object System.Windows.Forms.Label
    $k1.Text = $LeftKey
    $k1.AutoSize = $true
    $v1 = New-Object System.Windows.Forms.Label
    $v1.Text = '--'
    $v1.AutoSize = $true

    $k2 = New-Object System.Windows.Forms.Label
    $k2.Text = $RightKey
    $k2.AutoSize = $true
    $v2 = New-Object System.Windows.Forms.Label
    $v2.Text = '--'
    $v2.AutoSize = $true

    $tblMeta.Controls.Add($k1, 0, $Row)
    $tblMeta.Controls.Add($v1, 1, $Row)
    $tblMeta.Controls.Add($k2, 2, $Row)
    $tblMeta.Controls.Add($v2, 3, $Row)

    $LeftValue.Value = $v1
    $RightValue.Value = $v2
}

$lblArea = $null
$lblRegion = $null
$lblCountry = $null
$lblLatLon = $null
$lblPopulation = $null
$lblRequest = $null
$lblSunrise = $null
$lblSunset = $null
$lblMoon = $null
$lblMoonRiseSet = $null

New-MetaRow -Row 0 -LeftKey 'Area'       -LeftValue ([ref]$lblArea)       -RightKey 'Region'     -RightValue ([ref]$lblRegion)
New-MetaRow -Row 1 -LeftKey 'Country'    -LeftValue ([ref]$lblCountry)    -RightKey 'Lat/Lon'    -RightValue ([ref]$lblLatLon)
New-MetaRow -Row 2 -LeftKey 'Population' -LeftValue ([ref]$lblPopulation) -RightKey 'Request'    -RightValue ([ref]$lblRequest)
New-MetaRow -Row 3 -LeftKey 'Sunrise'    -LeftValue ([ref]$lblSunrise)    -RightKey 'Sunset'     -RightValue ([ref]$lblSunset)
New-MetaRow -Row 4 -LeftKey 'Moon'       -LeftValue ([ref]$lblMoon)       -RightKey 'Moon R/S'   -RightValue ([ref]$lblMoonRiseSet)

# --- Forecast tab layout ---
$forecastSplit = New-Object System.Windows.Forms.SplitContainer
$forecastSplit.Dock = 'Fill'
$forecastSplit.Orientation = 'Vertical'
$forecastSplit.SplitterDistance = 200
$forecastSplit.BorderStyle = 'Fixed3D'
$tabForecast.Controls.Add($forecastSplit)

$grpDays = New-Object System.Windows.Forms.GroupBox
$grpDays.Text = 'Days'
$grpDays.Dock = 'Fill'
$grpDays.BackColor = $win98Gray
$forecastSplit.Panel1.Controls.Add($grpDays)

$lstDays = New-Object System.Windows.Forms.ListBox
$lstDays.Dock = 'Fill'
$lstDays.BorderStyle = 'Fixed3D'
$grpDays.Controls.Add($lstDays)

$forecastRightSplit = New-Object System.Windows.Forms.SplitContainer
$forecastRightSplit.Dock = 'Fill'
$forecastRightSplit.Orientation = 'Horizontal'
$forecastRightSplit.SplitterDistance = 160
$forecastRightSplit.BorderStyle = 'Fixed3D'
$forecastSplit.Panel2.Controls.Add($forecastRightSplit)

# Keep Forecast split proportions consistent
$script:ForecastDaysWidthPercent = 0.13
$script:ForecastHourlyHeightPercent = 0.55

function Set-ForecastLayout {
    try {
        # Days list width: ~10-15% of the full window (use 13%)
        if ($forecastSplit.Width -gt 0) {
            $daysWidth = [int][Math]::Round($forecastSplit.Width * $script:ForecastDaysWidthPercent)
            if ($daysWidth -lt 120) { $daysWidth = 120 }
            if ($daysWidth -gt ($forecastSplit.Width - 260)) { $daysWidth = [Math]::Max(120, $forecastSplit.Width - 260) }
            $forecastSplit.SplitterDistance = $daysWidth
            $forecastSplit.Panel1MinSize = 110
            $forecastSplit.Panel2MinSize = 240
        }

        # Hourly pane height: ~55% of right-side height (bottom pane)
        if ($forecastRightSplit.Height -gt 0) {
            $topHeight = [int][Math]::Round($forecastRightSplit.Height * (1.0 - $script:ForecastHourlyHeightPercent))
            if ($topHeight -lt 120) { $topHeight = 120 }
            if ($topHeight -gt ($forecastRightSplit.Height - 160)) { $topHeight = [Math]::Max(120, $forecastRightSplit.Height - 160) }
            $forecastRightSplit.SplitterDistance = $topHeight
            $forecastRightSplit.Panel1MinSize = 120
            $forecastRightSplit.Panel2MinSize = 140
        }
    }
    catch {
        # no-op
    }
}

$grpDay = New-Object System.Windows.Forms.GroupBox
$grpDay.Text = 'Selected Day'
$grpDay.Dock = 'Fill'
$grpDay.BackColor = $win98Gray
$forecastRightSplit.Panel1.Controls.Add($grpDay)

$tblDay = New-Object System.Windows.Forms.TableLayoutPanel
$tblDay.Dock = 'Fill'
$tblDay.ColumnCount = 4
$tblDay.RowCount = 6
$tblDay.Padding = '6,12,6,6'
$tblDay.BackColor = $win98Gray
$tblDay.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 120)))
$tblDay.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
$tblDay.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 120)))
$tblDay.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
$grpDay.Controls.Add($tblDay)

function New-ForecastRow {
    param(
        [int]$Row,
        [string]$LeftKey,
        [ref]$LeftValue,
        [string]$RightKey,
        [ref]$RightValue
    )

    $k1 = New-Object System.Windows.Forms.Label
    $k1.Text = $LeftKey
    $k1.AutoSize = $true
    $v1 = New-Object System.Windows.Forms.Label
    $v1.Text = '--'
    $v1.AutoSize = $true

    $k2 = New-Object System.Windows.Forms.Label
    $k2.Text = $RightKey
    $k2.AutoSize = $true
    $v2 = New-Object System.Windows.Forms.Label
    $v2.Text = '--'
    $v2.AutoSize = $true

    $tblDay.Controls.Add($k1, 0, $Row)
    $tblDay.Controls.Add($v1, 1, $Row)
    $tblDay.Controls.Add($k2, 2, $Row)
    $tblDay.Controls.Add($v2, 3, $Row)

    $LeftValue.Value = $v1
    $RightValue.Value = $v2
}

$lblFDate = $null
$lblFMin = $null
$lblFMax = $null
$lblFAvg = $null
$lblFSun = $null
$lblFUV = $null
$lblFSnow = $null
$lblFSunrise = $null
$lblFSunset = $null
$lblFMoon = $null
$lblFMoonRS = $null
$lblFDummy = $null

New-ForecastRow -Row 0 -LeftKey 'Date'       -LeftValue ([ref]$lblFDate)    -RightKey 'Avg Temp'  -RightValue ([ref]$lblFAvg)
New-ForecastRow -Row 1 -LeftKey 'Min Temp'   -LeftValue ([ref]$lblFMin)     -RightKey 'Max Temp'  -RightValue ([ref]$lblFMax)
New-ForecastRow -Row 2 -LeftKey 'Sun Hours'  -LeftValue ([ref]$lblFSun)     -RightKey 'UV Index'  -RightValue ([ref]$lblFUV)
New-ForecastRow -Row 3 -LeftKey 'Total Snow' -LeftValue ([ref]$lblFSnow)    -RightKey 'Sunrise'   -RightValue ([ref]$lblFSunrise)
New-ForecastRow -Row 4 -LeftKey 'Sunset'     -LeftValue ([ref]$lblFSunset)  -RightKey 'Moon'      -RightValue ([ref]$lblFMoon)
New-ForecastRow -Row 5 -LeftKey 'Moon R/S'   -LeftValue ([ref]$lblFMoonRS)  -RightKey ''          -RightValue ([ref]$lblFDummy)
$lblFDummy.Text = ''

$grpHourly = New-Object System.Windows.Forms.GroupBox
$grpHourly.Text = 'Hourly'
$grpHourly.Dock = 'Fill'
$grpHourly.BackColor = $win98Gray
$forecastRightSplit.Panel2.Controls.Add($grpHourly)

$gridHourly = New-Object System.Windows.Forms.DataGridView
$gridHourly.Dock = 'Fill'
$gridHourly.BorderStyle = 'Fixed3D'
$gridHourly.BackgroundColor = $win98Gray
$gridHourly.ReadOnly = $true
$gridHourly.AllowUserToAddRows = $false
$gridHourly.AllowUserToDeleteRows = $false
$gridHourly.AllowUserToResizeRows = $false
$gridHourly.SelectionMode = 'FullRowSelect'
$gridHourly.MultiSelect = $false
$gridHourly.RowHeadersVisible = $false
$gridHourly.AutoSizeColumnsMode = 'DisplayedCells'
$gridHourly.ScrollBars = 'Both'
$grpHourly.Controls.Add($gridHourly)

# --- Raw tab ---
$txtRaw = New-Object System.Windows.Forms.TextBox
$txtRaw.Dock = 'Fill'
$txtRaw.Multiline = $true
$txtRaw.ReadOnly = $true
$txtRaw.ScrollBars = 'Both'
$txtRaw.WordWrap = $false
$txtRaw.Font = $mono
$tabRaw.Controls.Add($txtRaw)

$script:LastData = $null
$script:DayMap = @{}

function Update-WeatherUiFromData {
    param(
        [Parameter(Mandatory)]
        $Data
    )

    $script:LastData = $Data
    $txtRaw.Text = Format-PrettyJson $Data

    $cc = $null
    if ($Data.current_condition -and $Data.current_condition.Count -gt 0) { $cc = $Data.current_condition[0] }

    if ($null -ne $cc) {
        $tempC = SafeStr $cc.temp_C
        $feels = SafeStr $cc.FeelsLikeC
        $desc = SafeStr (Get-ValueFromArray $cc.weatherDesc '')
        $glyph = Get-WeatherGlyph -Condition $desc -WeatherCode (SafeStr $cc.weatherCode '')

        $lblGlyph.Text = $glyph
        $lblBigTemp.Text = "$tempC°C"
        $lblTemp.Text = "$tempC°C"
        $lblFeels.Text = "$feels°C"
        $lblCond.Text = $desc
        $lblHumidity.Text = "$(SafeStr $cc.humidity)%"
        $lblPressure.Text = "$(SafeStr $cc.pressure) hPa"
        $lblWind.Text = "$(SafeStr $cc.windspeedKmph) km/h $(SafeStr $cc.winddir16Point)"
        $lblVisibility.Text = "$(SafeStr $cc.visibility) km"
        $lblPrecip.Text = "$(SafeStr $cc.precipMM) mm"
        $lblCloud.Text = "$(SafeStr $cc.cloudcover)%"
        $lblUv.Text = SafeStr $cc.uvIndex
        $lblObs.Text = SafeStr $cc.observation_time
        $lblLocal.Text = SafeStr $cc.localObsDateTime
    }
    else {
        $lblBigTemp.Text = '--°C'
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
        $lblFSnow.Text = '--'
        $lblFSunrise.Text = '--'
        $lblFSunset.Text = '--'
        $lblFMoon.Text = '--'
        $lblFMoonRS.Text = '--'
        $gridHourly.DataSource = $null
        return
    }

    $day = $script:DayMap[$Date]
    $astro = $null
    if ($day.astronomy -and $day.astronomy.Count -gt 0) { $astro = $day.astronomy[0] }

    # Current tab astronomy should reflect selected day too
    if ($null -ne $astro) {
        $lblSunrise.Text = SafeStr $astro.sunrise
        $lblSunset.Text = SafeStr $astro.sunset
        $lblMoon.Text = "$(SafeStr $astro.moon_phase) ($(SafeStr $astro.moon_illumination)%)"
        $lblMoonRiseSet.Text = "$(SafeStr $astro.moonrise) / $(SafeStr $astro.moonset)"
    }

    $lblFDate.Text = $Date
    $lblFMin.Text = "$(SafeStr $day.mintempC)°C"
    $lblFMax.Text = "$(SafeStr $day.maxtempC)°C"
    $lblFAvg.Text = "$(SafeStr $day.avgtempC)°C"
    $lblFSun.Text = "$(SafeStr $day.sunHour) h"
    $lblFUV.Text = SafeStr $day.uvIndex
    $lblFSnow.Text = "$(SafeStr $day.totalSnow_cm) cm"
    if ($null -ne $astro) {
        $lblFSunrise.Text = SafeStr $astro.sunrise
        $lblFSunset.Text = SafeStr $astro.sunset
        $lblFMoon.Text = "$(SafeStr $astro.moon_phase) ($(SafeStr $astro.moon_illumination)%)"
        $lblFMoonRS.Text = "$(SafeStr $astro.moonrise) / $(SafeStr $astro.moonset)"
    }
    else {
        $lblFSunrise.Text = '--'
        $lblFSunset.Text = '--'
        $lblFMoon.Text = '--'
        $lblFMoonRS.Text = '--'
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
        if ($gridHourly.Columns['TempC']) { $gridHourly.Columns['TempC'].HeaderText = 'Temp (°C)' }
        if ($gridHourly.Columns['FeelsLikeC']) { $gridHourly.Columns['FeelsLikeC'].HeaderText = 'Feels (°C)' }
        if ($gridHourly.Columns['HumidityPct']) { $gridHourly.Columns['HumidityPct'].HeaderText = 'Humidity (%)' }
        if ($gridHourly.Columns['PrecipMM']) { $gridHourly.Columns['PrecipMM'].HeaderText = 'Precip (mm)' }
        if ($gridHourly.Columns['VisibilityKm']) { $gridHourly.Columns['VisibilityKm'].HeaderText = 'Vis (km)' }
        if ($gridHourly.Columns['WindKmph']) { $gridHourly.Columns['WindKmph'].HeaderText = 'Wind (km/h)' }
        if ($gridHourly.Columns['ChanceRain']) { $gridHourly.Columns['ChanceRain'].HeaderText = 'Chance Rain (%)' }
        if ($gridHourly.Columns['ChanceSnow']) { $gridHourly.Columns['ChanceSnow'].HeaderText = 'Chance Snow (%)' }
        if ($gridHourly.Columns['Time']) { $gridHourly.Columns['Time'].Frozen = $true }
        if ($gridHourly.Columns['TempC']) { $gridHourly.Columns['TempC'].Frozen = $true }
    }
    catch {
        # no-op
    }
}

function Invoke-WeatherRefresh {
    $city = Get-SelectedCity
    if ([string]::IsNullOrWhiteSpace($city)) { return }
    $city = $city.Trim()

    try {
        $btnRefresh.Enabled = $false
        $statusLabel.Text = "Loading $city..."
        $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor

        $data = Get-WttrJson -City $city
        Update-WeatherUiFromData -Data $data
        $statusLabel.Text = "Updated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        try { Update-CityList -City $city } catch { }
        Invoke-SuccessSound
    }
    catch {
        $statusLabel.Text = "Error: $($_.Exception.Message)"
        Invoke-ErrorSound
    }
    finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
        $btnRefresh.Enabled = $true
    }
}

$btnRefresh.Add_Click({ Invoke-WeatherRefresh }) | Out-Null
$cmbCity.Add_SelectionChangeCommitted({ Invoke-WeatherRefresh }) | Out-Null
$cmbCity.Add_KeyDown({
    param($source, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        $e.SuppressKeyPress = $true
        Invoke-WeatherRefresh
    }
}) | Out-Null
$miAbout.Add_Click({
    $about = @(
        'Windows 98 Weather'
        ''
        'A tiny Win98-style weather dashboard powered by wttr.in.'
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
        '  Downloads fresh data from wttr.in (JSON).' 
        ''
        'Tabs:'
        '  Current  - current conditions + key details.'
        '  Forecast - pick a day on the left; hourly is below.'
        '  Raw JSON - shows the raw wttr.in response.'
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


$form.ShowDialog() | Out-Null

} | Out-Null