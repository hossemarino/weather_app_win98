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

To embed a custom Explorer/EXE icon (also used by pinned taskbar shortcuts), pass an .ico file:

- `powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -Clean -IconFile .\myicon.ico`

Tip (local-only): you can export an .ico from a system DLL to experiment with indices:

- `powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Export-DllIcons.ps1 -DllPath "%SystemRoot%\System32\netshell.dll" -MaxIcons 200 -Png:$false`

Output:

- `dist\Windows98Weather.exe`

## Documentation

- In the built folder, open `dist\Weather98Help.html`.
- In the app UI, use Help → Help.

Notes:

- `.exe` files and `dist\` are ignored by git (see `.gitignore`).
