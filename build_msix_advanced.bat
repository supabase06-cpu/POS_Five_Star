@echo off
echo ==========================================
echo   Five Star Chicken POS - Advanced MSIX
echo ==========================================
echo.

:: Set variables
set "APP_NAME=FiveStarChickenPOS"
set "VERSION=1.0.3.0"
set "OUTPUT_DIR=build\msix_packages"

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
echo Step 4: Creating output directory...
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

echo.
echo Step 5: Creating MSIX package...
call flutter pub run msix:create --output-path "%OUTPUT_DIR%"

echo.
echo Step 6: Copying MSIX to output directory...
if exist "build\windows\x64\runner\Release\*.msix" (
    copy "build\windows\x64\runner\Release\*.msix" "%OUTPUT_DIR%\"
    ren "%OUTPUT_DIR%\five_star_chicken_enterprise.msix" "%APP_NAME%_v%VERSION%.msix"
)

echo.
echo ==========================================
echo   ADVANCED MSIX BUILD COMPLETE!
echo ==========================================
echo.
echo Your MSIX package is ready at:
echo   %OUTPUT_DIR%\%APP_NAME%_v%VERSION%.msix
echo.
echo Package Details:
echo   - App Name: Five Star Chicken POS
echo   - Version: %VERSION%
echo   - Publisher: Five Star Chicken
echo   - Package ID: com.fivestarchicken.pos
echo.
echo Installation Instructions:
echo   1. Share the .msix file
echo   2. Users double-click to install
echo   3. Or use PowerShell: Add-AppxPackage -Path "filename.msix"
echo   4. App will appear in Start Menu
echo.
echo Opening output folder...
explorer "%OUTPUT_DIR%"
pause