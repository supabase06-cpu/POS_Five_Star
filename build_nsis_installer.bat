@echo off
echo ==========================================
echo   Creating Single EXE Installer
echo ==========================================
echo.

REM Check if NSIS is installed
set NSIS_PATH=C:\Program Files (x86)\NSIS\makensis.exe
if not exist "%NSIS_PATH%" (
    echo ERROR: NSIS not found!
    echo.
    echo Please install NSIS from: https://nsis.sourceforge.io/Download
    echo After installation, run this script again.
    pause
    exit /b 1
)

echo Step 1: Building Flutter app...
flutter build windows --release

echo.
echo Step 2: Creating NSIS installer...
"%NSIS_PATH%" installer.nsi

if errorlevel 1 (
    echo ERROR: Failed to create installer
    pause
    exit /b 1
)

echo.
echo ==========================================
echo   SUCCESS! Single EXE Installer Created
echo ==========================================
echo.
echo Your installer: FiveStarChickenPOS_v1.0.6_Setup.exe
echo.
echo This is a TRUE single EXE file that:
echo   - Users download ONE .exe file
echo   - Double-click to install
echo   - No ZIP extraction needed
echo   - Creates Start Menu shortcuts
echo   - Proper Windows installer behavior
echo.
dir FiveStarChickenPOS_v1.0.6_Setup.exe
pause