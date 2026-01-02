# weather_app_win98
Windows 98 Styled Weather program based on curl wttr.in/&lt;city_name>

## Build an EXE (local)

This repo does not commit the generated `.exe`. Build it locally when you need it.

### Prereqs

- Windows
- PowerShell (Windows PowerShell 5.1 or PowerShell 7+)
- Internet access (first run installs the `ps2exe` module from PSGallery)

### Build

From the repo folder:

- `powershell -NoProfile -ExecutionPolicy Bypass -File .\build-exe.ps1`

Optional (show a console window):

- `powershell -NoProfile -ExecutionPolicy Bypass -File .\build-exe.ps1 -Console`

Output:

- `Windows98Weather.exe`

Notes:

- If your machine prompts about installing from PSGallery, re-run in an elevated PowerShell or set PSGallery to trusted.
- `.exe` files are ignored by git (see `.gitignore`).
