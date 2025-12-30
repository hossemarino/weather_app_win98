# Windows 98 Styled Weather App
# A PowerShell GUI application for weather information without advertisements

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Create the main form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Weather App - Windows 98 Style"
$form.Size = New-Object System.Drawing.Size(600, 500)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.MaximizeBox = $false

# Windows 98 color scheme
$win98Gray = [System.Drawing.Color]::FromArgb(192, 192, 192)
$win98DarkGray = [System.Drawing.Color]::FromArgb(128, 128, 128)
$win98Blue = [System.Drawing.Color]::FromArgb(0, 0, 128)
$win98LightGray = [System.Drawing.Color]::FromArgb(212, 208, 200)

$form.BackColor = $win98LightGray

# Title Label
$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Location = New-Object System.Drawing.Point(10, 10)
$titleLabel.Size = New-Object System.Drawing.Size(560, 30)
$titleLabel.Text = "Weather Information Service"
$titleLabel.Font = New-Object System.Drawing.Font("MS Sans Serif", 12, [System.Drawing.FontStyle]::Bold)
$titleLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$form.Controls.Add($titleLabel)

# City input group
$cityGroupBox = New-Object System.Windows.Forms.GroupBox
$cityGroupBox.Location = New-Object System.Drawing.Point(10, 50)
$cityGroupBox.Size = New-Object System.Drawing.Size(560, 60)
$cityGroupBox.Text = "Location"
$cityGroupBox.Font = New-Object System.Drawing.Font("MS Sans Serif", 8)
$form.Controls.Add($cityGroupBox)

# City Label
$cityLabel = New-Object System.Windows.Forms.Label
$cityLabel.Location = New-Object System.Drawing.Point(10, 25)
$cityLabel.Size = New-Object System.Drawing.Size(80, 20)
$cityLabel.Text = "City Name:"
$cityLabel.Font = New-Object System.Drawing.Font("MS Sans Serif", 8)
$cityGroupBox.Controls.Add($cityLabel)

# City TextBox
$cityTextBox = New-Object System.Windows.Forms.TextBox
$cityTextBox.Location = New-Object System.Drawing.Point(100, 23)
$cityTextBox.Size = New-Object System.Drawing.Size(250, 20)
$cityTextBox.Font = New-Object System.Drawing.Font("MS Sans Serif", 8)
$cityGroupBox.Controls.Add($cityTextBox)

# Get Weather Button
$getWeatherButton = New-Object System.Windows.Forms.Button
$getWeatherButton.Location = New-Object System.Drawing.Point(360, 21)
$getWeatherButton.Size = New-Object System.Drawing.Size(180, 24)
$getWeatherButton.Text = "Get Weather"
$getWeatherButton.Font = New-Object System.Drawing.Font("MS Sans Serif", 8)
$getWeatherButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Standard
$cityGroupBox.Controls.Add($getWeatherButton)

# Weather Display GroupBox
$weatherGroupBox = New-Object System.Windows.Forms.GroupBox
$weatherGroupBox.Location = New-Object System.Drawing.Point(10, 120)
$weatherGroupBox.Size = New-Object System.Drawing.Size(560, 300)
$weatherGroupBox.Text = "Weather Information"
$weatherGroupBox.Font = New-Object System.Drawing.Font("MS Sans Serif", 8)
$form.Controls.Add($weatherGroupBox)

# Weather TextBox (multiline for display)
$weatherTextBox = New-Object System.Windows.Forms.TextBox
$weatherTextBox.Location = New-Object System.Drawing.Point(10, 20)
$weatherTextBox.Size = New-Object System.Drawing.Size(540, 270)
$weatherTextBox.Multiline = $true
$weatherTextBox.ScrollBars = "Vertical"
$weatherTextBox.Font = New-Object System.Drawing.Font("Courier New", 8)
$weatherTextBox.BackColor = [System.Drawing.Color]::White
$weatherTextBox.ReadOnly = $true
$weatherGroupBox.Controls.Add($weatherTextBox)

# Status Bar
$statusBar = New-Object System.Windows.Forms.StatusBar
$statusBar.Text = "Ready"
$statusBar.Font = New-Object System.Drawing.Font("MS Sans Serif", 8)
$form.Controls.Add($statusBar)

# Function to fetch weather data
function Get-WeatherData {
    param (
        [string]$city
    )
    
    if ([string]::IsNullOrWhiteSpace($city)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Please enter a city name.",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return
    }
    
    $statusBar.Text = "Fetching weather data..."
    $weatherTextBox.Text = "Loading weather information..."
    
    try {
        # Encode the city name for URL
        $encodedCity = [System.Uri]::EscapeDataString($city)
        
        # Fetch weather data from wttr.in
        # Using the plain text format for better parsing
        $url = "https://wttr.in/${encodedCity}?format=j1"
        
        $response = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop
        
        # Validate response structure
        if (-not $response.current_condition -or -not $response.nearest_area -or -not $response.weather) {
            throw "Invalid response from weather service"
        }
        
        # Parse and format the weather data with safe array access
        $weatherDesc = if ($response.current_condition.weatherDesc -and $response.current_condition.weatherDesc.Count -gt 0) {
            $response.current_condition.weatherDesc[0].value
        } else { "Unknown" }
        
        $tempC = $response.current_condition.temp_C
        $tempF = $response.current_condition.temp_F
        $feelsLikeC = $response.current_condition.FeelsLikeC
        $feelsLikeF = $response.current_condition.FeelsLikeF
        $humidity = $response.current_condition.humidity
        $windSpeed = $response.current_condition.windspeedKmph
        $windDir = $response.current_condition.winddir16Point
        $pressure = $response.current_condition.pressure
        $visibility = $response.current_condition.visibility
        $uvIndex = $response.current_condition.uvIndex
        
        $locationName = if ($response.nearest_area.areaName -and $response.nearest_area.areaName.Count -gt 0) {
            $response.nearest_area.areaName[0].value
        } else { $city }
        
        $country = if ($response.nearest_area.country -and $response.nearest_area.country.Count -gt 0) {
            $response.nearest_area.country[0].value
        } else { "" }
        
        # Format the output in a Windows 98 style
        $output = @"
╔════════════════════════════════════════════════════════════════╗
║              WEATHER INFORMATION - $locationName, $country
╚════════════════════════════════════════════════════════════════╝

Current Conditions:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Condition:      $weatherDesc
  Temperature:    $tempC°C ($tempF°F)
  Feels Like:     $feelsLikeC°C ($feelsLikeF°F)
  
  Wind:          $windSpeed km/h $windDir
  Humidity:      $humidity%
  Pressure:      $pressure mb
  Visibility:    $visibility km
  UV Index:      $uvIndex

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

3-Day Forecast:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

"@
        
        # Add forecast data
        $forecastDays = [Math]::Min(3, $response.weather.Count)
        for ($i = 0; $i -lt $forecastDays; $i++) {
            $forecast = $response.weather[$i]
            $date = $forecast.date
            $maxTemp = $forecast.maxtempC
            $minTemp = $forecast.mintempC
            
            # Use first available hourly forecast (index 0) instead of hard-coded index 4
            $desc = if ($forecast.hourly -and $forecast.hourly.Count -gt 0 -and 
                       $forecast.hourly[0].weatherDesc -and $forecast.hourly[0].weatherDesc.Count -gt 0) {
                $forecast.hourly[0].weatherDesc[0].value
            } else { "No description available" }
            
            $output += "`n  $date"
            $output += "`n    High: $maxTemp°C  Low: $minTemp°C"
            $output += "`n    $desc`n"
        }
        
        $weatherTextBox.Text = $output
        $statusBar.Text = "Weather data retrieved successfully - $(Get-Date -Format 'HH:mm:ss')"
        
    } catch {
        $errorMessage = "Failed to retrieve weather data: $($_.Exception.Message)"
        $weatherTextBox.Text = $errorMessage
        $statusBar.Text = "Error occurred"
        
        [System.Windows.Forms.MessageBox]::Show(
            "Unable to fetch weather data. Please check the city name and your internet connection.",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    }
}

# Button click event
$getWeatherButton.Add_Click({
    Get-WeatherData -city $cityTextBox.Text
})

# Enter key press event for city textbox
$cityTextBox.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        Get-WeatherData -city $cityTextBox.Text
        $e.SuppressKeyPress = $true
    }
})

# Show initial message
$weatherTextBox.Text = @"
╔════════════════════════════════════════════════════════════════╗
║         Welcome to Windows 98 Weather App!                    ║
╚════════════════════════════════════════════════════════════════╝

Features:
  • No advertisements
  • Fast and lightweight
  • Classic Windows 98 interface
  • Powered by wttr.in

Instructions:
  1. Enter a city name in the text box above
  2. Click "Get Weather" or press Enter
  3. View current weather and 3-day forecast

Examples of city names:
  • London
  • New York
  • Tokyo
  • Paris
  • Sydney

"@

# Show the form
$form.ShowDialog() | Out-Null
