# weather_app_win98
Windows 98 Styled Weather program using Open-Meteo (geocoding + forecast).

Includes a Metric/Imperial units selector (°C/°F, km/h/mph).

Personalizations are stored in Settings.ini:
- [Settings] UnitSystem, LastCity, Language
- [Cities] saved city list

Note: Settings.ini is user-specific and is ignored by git. Use Settings.example.ini as a template.

If you have an old Cities.ini, the app will auto-migrate it on first run.

## Build an EXE (local)

This repo does not commit the generated `.exe`. Build it locally when you need it.

### Prereqs

- Windows
- PowerShell (Windows PowerShell 5.1 or PowerShell 7+)
- Internet access (first run may install PS2EXE from PSGallery)

### Build

From the repo folder:

- `powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -Clean`

Output:

- `dist\Windows98Weather.exe`

Notes:

- `.exe` files and `dist\` are ignored by git (see `.gitignore`).
