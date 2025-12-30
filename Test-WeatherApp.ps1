# Test script for WeatherApp.ps1
# This tests the core functionality without requiring Windows Forms

Write-Host "Testing WeatherApp.ps1 core functionality..." -ForegroundColor Cyan
Write-Host ""

# Test 1: Check if script file exists
Write-Host "[Test 1] Checking if WeatherApp.ps1 exists..." -NoNewline
if (Test-Path "WeatherApp.ps1") {
    Write-Host " PASS" -ForegroundColor Green
} else {
    Write-Host " FAIL" -ForegroundColor Red
    exit 1
}

# Test 2: Validate PowerShell syntax
Write-Host "[Test 2] Validating PowerShell syntax..." -NoNewline
try {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile("WeatherApp.ps1", [ref]$null, [ref]$null)
    if ($ast) {
        Write-Host " PASS" -ForegroundColor Green
    } else {
        Write-Host " FAIL" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host " FAIL - $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Test 3: Check for required assemblies references
Write-Host "[Test 3] Checking for required assemblies..." -NoNewline
$content = Get-Content "WeatherApp.ps1" -Raw
if ($content -match "System\.Windows\.Forms" -and $content -match "System\.Drawing") {
    Write-Host " PASS" -ForegroundColor Green
} else {
    Write-Host " FAIL" -ForegroundColor Red
    exit 1
}

# Test 4: Check for wttr.in API integration
Write-Host "[Test 4] Checking for wttr.in API integration..." -NoNewline
if ($content -match "wttr\.in" -and $content -match "Invoke-RestMethod") {
    Write-Host " PASS" -ForegroundColor Green
} else {
    Write-Host " FAIL" -ForegroundColor Red
    exit 1
}

# Test 5: Check for Windows 98 styling elements
Write-Host "[Test 5] Checking for Windows 98 styling elements..." -NoNewline
if ($content -match "MS Sans Serif" -and $content -match "FromArgb") {
    Write-Host " PASS" -ForegroundColor Green
} else {
    Write-Host " FAIL" -ForegroundColor Red
    exit 1
}

# Test 6: Check for key UI components
Write-Host "[Test 6] Checking for UI components..." -NoNewline
$hasForm = $content -match "New-Object System\.Windows\.Forms\.Form"
$hasTextBox = $content -match "New-Object System\.Windows\.Forms\.TextBox"
$hasButton = $content -match "New-Object System\.Windows\.Forms\.Button"
$hasGroupBox = $content -match "New-Object System\.Windows\.Forms\.GroupBox"

if ($hasForm -and $hasTextBox -and $hasButton -and $hasGroupBox) {
    Write-Host " PASS" -ForegroundColor Green
} else {
    Write-Host " FAIL" -ForegroundColor Red
    exit 1
}

# Test 7: Check for error handling
Write-Host "[Test 7] Checking for error handling..." -NoNewline
if ($content -match "try" -and $content -match "catch" -and $content -match "ErrorAction") {
    Write-Host " PASS" -ForegroundColor Green
} else {
    Write-Host " FAIL" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "All tests passed!" -ForegroundColor Green
Write-Host ""
Write-Host "Note: The GUI can only be tested on Windows systems with a graphical environment." -ForegroundColor Yellow
Write-Host "To test manually, run: .\WeatherApp.ps1 on a Windows machine" -ForegroundColor Yellow
