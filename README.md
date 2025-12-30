# Weather App - Windows 98 Style 🌤️

A nostalgic PowerShell-based weather application with a classic Windows 98 interface. Built as an ad-free alternative to the Windows 11 weather app.

![Windows 98 Style](https://img.shields.io/badge/style-Windows%2098-blue)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue)
![No Ads](https://img.shields.io/badge/ads-none-green)

## 🎯 Features

- **Ad-Free**: No advertisements, no tracking, no bloat
- **Classic UI**: Authentic Windows 98 interface styling
- **Fast & Lightweight**: Simple PowerShell script with minimal dependencies
- **Current Weather**: Real-time weather conditions for any city
- **3-Day Forecast**: Quick glance at upcoming weather
- **Powered by wttr.in**: Reliable weather data API

## 📋 Requirements

- Windows PowerShell 5.1 or higher (comes with Windows 10/11)
- Internet connection
- Windows operating system

## 🚀 Installation

1. Clone this repository or download the `WeatherApp.ps1` file:
```powershell
git clone https://github.com/hossemarino/weather_app_win98.git
cd weather_app_win98
```

2. (Optional) Unblock the script if downloaded from the internet:
```powershell
Unblock-File -Path .\WeatherApp.ps1
```

## 💻 Usage

### Running the App

Simply run the PowerShell script:

```powershell
.\WeatherApp.ps1
```

Or right-click on `WeatherApp.ps1` and select "Run with PowerShell"

### Using the App

1. Enter a city name in the text box (e.g., "London", "New York", "Tokyo")
2. Click "Get Weather" or press Enter
3. View the current weather conditions and 3-day forecast

### Examples of City Names

- `London`
- `New York`
- `Tokyo`
- `Paris`
- `Sydney`
- `Berlin`
- `Mumbai`

You can also use more specific locations like:
- `London,UK`
- `Paris,France`
- `New York,NY`

## 🎨 Windows 98 Styling

The application features authentic Windows 98 design elements:

- Classic gray color scheme (RGB: 192, 192, 192)
- MS Sans Serif and Courier New fonts
- Standard Windows 98 button and border styles
- Traditional status bar
- GroupBox controls for organization

## 🌐 API Information

This application uses the [wttr.in](https://wttr.in) service for weather data:
- Free and open weather API
- No API key required
- Returns weather data in JSON format
- Includes current conditions and forecasts

## 🔒 Execution Policy

If you encounter an execution policy error, you can run:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

Or run the script with bypass:

```powershell
powershell -ExecutionPolicy Bypass -File .\WeatherApp.ps1
```

## 🐛 Troubleshooting

**Script won't run**: Check your PowerShell execution policy (see above)

**No weather data**: Verify your internet connection and that the city name is correct

**API errors**: The wttr.in service might be temporarily unavailable, try again later

## 📝 License

This project is open source. Feel free to use and modify as needed.

## 🙏 Credits

- Weather data provided by [wttr.in](https://wttr.in)
- Inspired by the classic Windows 98 aesthetic
- Created as an ad-free alternative to modern weather apps

## 🤝 Contributing

Contributions are welcome! Feel free to submit issues or pull requests.

---

**Note**: This is a fan project and is not affiliated with Microsoft or Windows. Windows 98 is a trademark of Microsoft Corporation.
