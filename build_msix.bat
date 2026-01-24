@echo off
echo ==========================================
echo   Five Star Chicken POS - Build MSIX
echo ==========================================
echo.

:: Check if Flutter is available
flutter --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Flutter not found in PATH!
    echo Please install Flutter and add it to your PATH
    pause
    exit /b 1
)

echo Step 1: Cleaning previous build...
call flutter clean

echo.
echo Step 2: Getting dependencies...
call flutter pub get

echo.
echo Step 3: Building Windows release...
call flutter build windows --release

echo.
echo Step 4: Creating MSIX package...
call dart run msix:create

echo.
echo ==========================================
echo   MSIX BUILD COMPLETE!
echo ==========================================
echo.
echo Your MSIX package is ready at:
echo   build\windows\x64\runner\Release\five_star_chicken_enterprise.msix
echo.
echo To distribute:
echo   1. Share the .msix file
echo   2. Users can install by double-clicking
echo   3. Or use: Add-AppxPackage -Path "filename.msix" in PowerShell
echo.
echo Opening build folder...
explorer build\windows\x64\runner\Release
pause