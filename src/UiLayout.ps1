Set-StrictMode -Version Latest

function Add-LabelPairRow {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Forms.TableLayoutPanel]$Table,

        [Parameter(Mandatory)]
        [int]$Row,

        [string]$LeftKey = '',
        [Parameter(Mandatory)]
        [ref]$LeftValue,

        [string]$RightKey = '',
        [Parameter(Mandatory)]
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

    $Table.Controls.Add($k1, 0, $Row)
    $Table.Controls.Add($v1, 1, $Row)
    $Table.Controls.Add($k2, 2, $Row)
    $Table.Controls.Add($v2, 3, $Row)

    $LeftValue.Value = $v1
    $RightValue.Value = $v2
}

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

function Initialize-WeatherUi {
    param(
        [Parameter(Mandatory)]
        [string]$AppBase,

        [string[]]$StartupCities,
        [string]$LastCity,

        [ValidateSet('Metric', 'Imperial')]
        [string]$UnitSystem = 'Metric'
    )

    # --- Win98-ish theme (system colors keep the classic look) ---
    $win98Gray = [System.Drawing.SystemColors]::Control
    $win98Light = [System.Drawing.SystemColors]::ControlLight
    $font = New-Object System.Drawing.Font('Microsoft Sans Serif', 8.25)
    $mono = New-Object System.Drawing.Font('Consolas', 9)

    Set-Variable -Scope Script -Name win98Gray -Value $win98Gray
    Set-Variable -Scope Script -Name win98Light -Value $win98Light
    Set-Variable -Scope Script -Name font -Value $font
    Set-Variable -Scope Script -Name mono -Value $mono

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
        $ico = Join-Path $AppBase 'weather.ico'
        if (Test-Path -LiteralPath $ico) {
            $form.Icon = New-Object System.Drawing.Icon($ico)
        }
        else {
            $sysIcon = $null
            try {
                if ($script:IconDll) {
                    $ix = 0
                    try {
                        if ($null -ne $script:IconIndex) { $ix = [int]$script:IconIndex }
                    }
                    catch {
                        $ix = 0
                    }
                    $sysIcon = Get-IconFromLibrary -LibraryPath $script:IconDll -Index $ix
                }
            }
            catch {
                $sysIcon = $null
            }

            if ($sysIcon) {
                $form.Icon = $sysIcon
            }
            else {
                $form.Icon = [System.Drawing.SystemIcons]::Application
            }
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
    $iniCities = @($StartupCities)
    if ($iniCities.Count -gt 0) {
        [void]$cmbCity.Items.AddRange($iniCities)
        $cmbCity.SelectedIndex = 0
    }

    try {
        if (-not [string]::IsNullOrWhiteSpace($LastCity)) {
            $cmbCity.Text = $LastCity
        }
    }
    catch {
        # no-op
    }
    $cmbCity.AutoCompleteMode = 'SuggestAppend'
    $cmbCity.AutoCompleteSource = 'ListItems'
    $topPanel.Controls.Add($cmbCity)

    $btnRefresh = New-Object System.Windows.Forms.Button
    $btnRefresh.Text = 'Refresh'
    $btnRefresh.Location = New-Object System.Drawing.Point(300, 8)
    $btnRefresh.Size = New-Object System.Drawing.Size(90, 25)
    $btnRefresh.BackColor = $win98Light
    $btnRefresh.FlatStyle = 'System'
    $topPanel.Controls.Add($btnRefresh)

    $lblUnits = New-Object System.Windows.Forms.Label
    $lblUnits.Text = 'Units:'
    $lblUnits.AutoSize = $true
    $lblUnits.Location = New-Object System.Drawing.Point(402, 12)
    $topPanel.Controls.Add($lblUnits)

    $cmbUnits = New-Object System.Windows.Forms.ComboBox
    $cmbUnits.DropDownStyle = 'DropDownList'
    $cmbUnits.Location = New-Object System.Drawing.Point(448, 9)
    $cmbUnits.Width = 110
    [void]$cmbUnits.Items.Add('Metric')
    [void]$cmbUnits.Items.Add('Imperial')
    try {
        if ($UnitSystem -eq 'Imperial') { $cmbUnits.SelectedItem = 'Imperial' } else { $cmbUnits.SelectedItem = 'Metric' }
    }
    catch {
        $cmbUnits.SelectedIndex = 0
    }
    $topPanel.Controls.Add($cmbUnits)

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
    $tblCur.RowCount = 10
    $tblCur.Padding = '6,12,6,6'
    $tblCur.AutoSize = $false
    $tblCur.AutoScroll = $true
    $tblCur.BackColor = $win98Gray
    $tblCur.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 120)))
    $tblCur.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
    $tblCur.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 120)))
    $tblCur.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
    $grpCurrent.Controls.Add($tblCur)

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
    $lblDewPoint = $null
    $lblWindGust = $null
    $lblRain = $null
    $lblShowers = $null
    $lblSnowDepth = $null
    $lblIsDay = $null
    $lblSurfacePressure = $null
    $lblCloudLayers = $null

    $lblGlyph = New-Object System.Windows.Forms.Label
    $lblGlyph.Text = '☀'
    $lblGlyph.Font = New-Object System.Drawing.Font('Segoe UI Emoji', 28)
    $lblGlyph.AutoSize = $true
    $lblGlyph.Location = New-Object System.Drawing.Point(14, 28)
    $grpCurrent.Controls.Add($lblGlyph)

    $lblBigTemp = New-Object System.Windows.Forms.Label
    $lblBigTemp.Text = '--'
    $lblBigTemp.Font = New-Object System.Drawing.Font('Microsoft Sans Serif', 20, [System.Drawing.FontStyle]::Bold)
    $lblBigTemp.AutoSize = $true
    $lblBigTemp.Location = New-Object System.Drawing.Point(58, 34)
    $grpCurrent.Controls.Add($lblBigTemp)

    Add-LabelPairRow -Table $tblCur -Row 0 -LeftKey 'Temp'      -LeftValue ([ref]$lblTemp)      -RightKey 'Feels Like' -RightValue ([ref]$lblFeels)
    Add-LabelPairRow -Table $tblCur -Row 1 -LeftKey 'Condition' -LeftValue ([ref]$lblCond)      -RightKey 'Cloud'      -RightValue ([ref]$lblCloud)
    Add-LabelPairRow -Table $tblCur -Row 2 -LeftKey 'Humidity'  -LeftValue ([ref]$lblHumidity)  -RightKey 'Pressure'   -RightValue ([ref]$lblPressure)
    Add-LabelPairRow -Table $tblCur -Row 3 -LeftKey 'Wind'      -LeftValue ([ref]$lblWind)      -RightKey 'Visibility' -RightValue ([ref]$lblVisibility)
    Add-LabelPairRow -Table $tblCur -Row 4 -LeftKey 'Precip'    -LeftValue ([ref]$lblPrecip)    -RightKey 'UV Index'   -RightValue ([ref]$lblUv)
    Add-LabelPairRow -Table $tblCur -Row 5 -LeftKey 'Observed'  -LeftValue ([ref]$lblObs)       -RightKey 'Local Time' -RightValue ([ref]$lblLocal)
    Add-LabelPairRow -Table $tblCur -Row 6 -LeftKey 'Dew Point' -LeftValue ([ref]$lblDewPoint)  -RightKey 'Wind Gusts' -RightValue ([ref]$lblWindGust)
    Add-LabelPairRow -Table $tblCur -Row 7 -LeftKey 'Rain'      -LeftValue ([ref]$lblRain)      -RightKey 'Showers'    -RightValue ([ref]$lblShowers)
    Add-LabelPairRow -Table $tblCur -Row 8 -LeftKey 'SnowDepth' -LeftValue ([ref]$lblSnowDepth) -RightKey 'Day/Night'  -RightValue ([ref]$lblIsDay)
    Add-LabelPairRow -Table $tblCur -Row 9 -LeftKey 'Surface P' -LeftValue ([ref]$lblSurfacePressure) -RightKey 'Cloud L/M/H' -RightValue ([ref]$lblCloudLayers)

    $grpMeta = New-Object System.Windows.Forms.GroupBox
    $grpMeta.Text = 'Location + Sun (Selected Day)'
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

    $lblArea = $null
    $lblRegion = $null
    $lblCountry = $null
    $lblLatLon = $null
    $lblPopulation = $null
    $lblRequest = $null
    $lblSunrise = $null
    $lblSunset = $null
    $lblTimezone = $null
    $lblElevation = $null

    Add-LabelPairRow -Table $tblMeta -Row 0 -LeftKey 'Area'       -LeftValue ([ref]$lblArea)       -RightKey 'Region'     -RightValue ([ref]$lblRegion)
    Add-LabelPairRow -Table $tblMeta -Row 1 -LeftKey 'Country'    -LeftValue ([ref]$lblCountry)    -RightKey 'Lat/Lon'    -RightValue ([ref]$lblLatLon)
    Add-LabelPairRow -Table $tblMeta -Row 2 -LeftKey 'Population' -LeftValue ([ref]$lblPopulation) -RightKey 'Request'    -RightValue ([ref]$lblRequest)
    Add-LabelPairRow -Table $tblMeta -Row 3 -LeftKey 'Sunrise'    -LeftValue ([ref]$lblSunrise)    -RightKey 'Sunset'     -RightValue ([ref]$lblSunset)
    Add-LabelPairRow -Table $tblMeta -Row 4 -LeftKey 'Timezone'   -LeftValue ([ref]$lblTimezone)   -RightKey 'Elevation'  -RightValue ([ref]$lblElevation)

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

    $lblFDate = $null
    $lblFMin = $null
    $lblFMax = $null
    $lblFAvg = $null
    $lblFSun = $null
    $lblFUV = $null
    $lblFPrecip = $null
    $lblFSnow = $null
    $lblFDaylight = $null
    $lblFSunrise = $null
    $lblFSunset = $null
    $lblFDummy = $null

    Add-LabelPairRow -Table $tblDay -Row 0 -LeftKey 'Date'       -LeftValue ([ref]$lblFDate)    -RightKey 'Avg Temp'  -RightValue ([ref]$lblFAvg)
    Add-LabelPairRow -Table $tblDay -Row 1 -LeftKey 'Min Temp'   -LeftValue ([ref]$lblFMin)     -RightKey 'Max Temp'  -RightValue ([ref]$lblFMax)
    Add-LabelPairRow -Table $tblDay -Row 2 -LeftKey 'Sun Hours'  -LeftValue ([ref]$lblFSun)     -RightKey 'UV Index'  -RightValue ([ref]$lblFUV)
    Add-LabelPairRow -Table $tblDay -Row 3 -LeftKey 'Precip Sum' -LeftValue ([ref]$lblFPrecip)  -RightKey 'Sunrise'   -RightValue ([ref]$lblFSunrise)
    Add-LabelPairRow -Table $tblDay -Row 4 -LeftKey 'Snow Sum'   -LeftValue ([ref]$lblFSnow)    -RightKey 'Sunset'    -RightValue ([ref]$lblFSunset)
    Add-LabelPairRow -Table $tblDay -Row 5 -LeftKey 'Daylight'   -LeftValue ([ref]$lblFDaylight)-RightKey ''          -RightValue ([ref]$lblFDummy)
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

    # Script state used by update/actions
    $script:LastData = $null
    $script:DayMap = @{}

    # Export controls into script scope (so other modules can use them without huge param lists)
    Set-Variable -Scope Script -Name form -Value $form
    Set-Variable -Scope Script -Name menu -Value $menu
    Set-Variable -Scope Script -Name miHelpRoot -Value $miHelpRoot
    Set-Variable -Scope Script -Name miHelp -Value $miHelp
    Set-Variable -Scope Script -Name miAbout -Value $miAbout
    Set-Variable -Scope Script -Name miFileRoot -Value $miFileRoot
    Set-Variable -Scope Script -Name miQuit -Value $miQuit

    Set-Variable -Scope Script -Name topPanel -Value $topPanel
    Set-Variable -Scope Script -Name cmbCity -Value $cmbCity
    Set-Variable -Scope Script -Name btnRefresh -Value $btnRefresh
    Set-Variable -Scope Script -Name cmbUnits -Value $cmbUnits

    Set-Variable -Scope Script -Name tabs -Value $tabs
    Set-Variable -Scope Script -Name tabCurrent -Value $tabCurrent
    Set-Variable -Scope Script -Name tabForecast -Value $tabForecast
    Set-Variable -Scope Script -Name tabRaw -Value $tabRaw

    Set-Variable -Scope Script -Name status -Value $status
    Set-Variable -Scope Script -Name statusLabel -Value $statusLabel

    Set-Variable -Scope Script -Name currentSplit -Value $currentSplit
    Set-Variable -Scope Script -Name grpCurrent -Value $grpCurrent
    Set-Variable -Scope Script -Name tblCur -Value $tblCur

    Set-Variable -Scope Script -Name lblGlyph -Value $lblGlyph
    Set-Variable -Scope Script -Name lblBigTemp -Value $lblBigTemp

    Set-Variable -Scope Script -Name lblTemp -Value $lblTemp
    Set-Variable -Scope Script -Name lblFeels -Value $lblFeels
    Set-Variable -Scope Script -Name lblCond -Value $lblCond
    Set-Variable -Scope Script -Name lblObs -Value $lblObs
    Set-Variable -Scope Script -Name lblHumidity -Value $lblHumidity
    Set-Variable -Scope Script -Name lblPressure -Value $lblPressure
    Set-Variable -Scope Script -Name lblWind -Value $lblWind
    Set-Variable -Scope Script -Name lblVisibility -Value $lblVisibility
    Set-Variable -Scope Script -Name lblPrecip -Value $lblPrecip
    Set-Variable -Scope Script -Name lblCloud -Value $lblCloud
    Set-Variable -Scope Script -Name lblUv -Value $lblUv
    Set-Variable -Scope Script -Name lblLocal -Value $lblLocal
    Set-Variable -Scope Script -Name lblDewPoint -Value $lblDewPoint
    Set-Variable -Scope Script -Name lblWindGust -Value $lblWindGust
    Set-Variable -Scope Script -Name lblRain -Value $lblRain
    Set-Variable -Scope Script -Name lblShowers -Value $lblShowers
    Set-Variable -Scope Script -Name lblSnowDepth -Value $lblSnowDepth
    Set-Variable -Scope Script -Name lblIsDay -Value $lblIsDay
    Set-Variable -Scope Script -Name lblSurfacePressure -Value $lblSurfacePressure
    Set-Variable -Scope Script -Name lblCloudLayers -Value $lblCloudLayers

    Set-Variable -Scope Script -Name grpMeta -Value $grpMeta
    Set-Variable -Scope Script -Name tblMeta -Value $tblMeta
    Set-Variable -Scope Script -Name lblArea -Value $lblArea
    Set-Variable -Scope Script -Name lblRegion -Value $lblRegion
    Set-Variable -Scope Script -Name lblCountry -Value $lblCountry
    Set-Variable -Scope Script -Name lblLatLon -Value $lblLatLon
    Set-Variable -Scope Script -Name lblPopulation -Value $lblPopulation
    Set-Variable -Scope Script -Name lblRequest -Value $lblRequest
    Set-Variable -Scope Script -Name lblSunrise -Value $lblSunrise
    Set-Variable -Scope Script -Name lblSunset -Value $lblSunset
    Set-Variable -Scope Script -Name lblTimezone -Value $lblTimezone
    Set-Variable -Scope Script -Name lblElevation -Value $lblElevation

    Set-Variable -Scope Script -Name forecastSplit -Value $forecastSplit
    Set-Variable -Scope Script -Name forecastRightSplit -Value $forecastRightSplit
    Set-Variable -Scope Script -Name grpDays -Value $grpDays
    Set-Variable -Scope Script -Name lstDays -Value $lstDays
    Set-Variable -Scope Script -Name grpDay -Value $grpDay
    Set-Variable -Scope Script -Name tblDay -Value $tblDay

    Set-Variable -Scope Script -Name lblFDate -Value $lblFDate
    Set-Variable -Scope Script -Name lblFMin -Value $lblFMin
    Set-Variable -Scope Script -Name lblFMax -Value $lblFMax
    Set-Variable -Scope Script -Name lblFAvg -Value $lblFAvg
    Set-Variable -Scope Script -Name lblFSun -Value $lblFSun
    Set-Variable -Scope Script -Name lblFUV -Value $lblFUV
    Set-Variable -Scope Script -Name lblFPrecip -Value $lblFPrecip
    Set-Variable -Scope Script -Name lblFSnow -Value $lblFSnow
    Set-Variable -Scope Script -Name lblFDaylight -Value $lblFDaylight
    Set-Variable -Scope Script -Name lblFSunrise -Value $lblFSunrise
    Set-Variable -Scope Script -Name lblFSunset -Value $lblFSunset

    Set-Variable -Scope Script -Name grpHourly -Value $grpHourly
    Set-Variable -Scope Script -Name gridHourly -Value $gridHourly

    Set-Variable -Scope Script -Name txtRaw -Value $txtRaw

    return $form
}
