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
    # Note: True per-control Win98 scrollbars aren''t reliably themeable on Win11; this is the closest native WinForms option.
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

    # --- Module imports (split from original monolithic script) ---
    $script:AppBase = $null
    try {
        if ($PSScriptRoot) { $script:AppBase = $PSScriptRoot }
    }
    catch {
        $script:AppBase = $null
    }
    if (-not $script:AppBase) {
        try { $script:AppBase = Split-Path -Parent $MyInvocation.MyCommand.Path } catch { $script:AppBase = (Get-Location).Path }
    }

    . (Join-Path $script:AppBase 'src\Core.ps1')
    . (Join-Path $script:AppBase 'src\Settings.ps1')
    . (Join-Path $script:AppBase 'src\OpenMeteo.ps1')
    . (Join-Path $script:AppBase 'src\Sounds.ps1')
    . (Join-Path $script:AppBase 'src\UiLayout.ps1')
    . (Join-Path $script:AppBase 'src\UiUpdate.ps1')
    . (Join-Path $script:AppBase 'src\UiActions.ps1')

    # --- Globals / paths ---
    $script:SoundSuccessPath = [System.IO.Path]::Combine($script:AppBase, 'ding.wav')
    $script:SoundErrorPath = [System.IO.Path]::Combine($script:AppBase, 'chord.wav')
    $script:StartupSoundPlayed = $false

    $script:SettingsIniPath = Join-Path $script:AppBase 'Settings.ini'
    $script:LegacyCitiesIniPath = Join-Path $script:AppBase 'Cities.ini'
    $script:UnitSystem = 'Metric' # Metric | Imperial
    $script:LastCity = ''
    $script:Language = 'en'
    $script:StartupCities = @()
    Initialize-AppSettings

    Initialize-WeatherUi -AppBase $script:AppBase -StartupCities $script:StartupCities -LastCity $script:LastCity -UnitSystem $script:UnitSystem | Out-Null
    Register-WeatherUiHandlers
    $form.ShowDialog() | Out-Null

} | Out-Null
