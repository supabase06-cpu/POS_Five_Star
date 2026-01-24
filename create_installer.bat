@echo off
echo ==========================================
echo   Creating Self-Extracting Installer
echo ==========================================
echo.

:: Set paths
set "RELEASE_DIR=build\windows\x64\runner\Release"
set "OUTPUT_DIR=build\installer"
set "APP_NAME=FiveStarChickenPOS"

:: Create output directory
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

:: Check if 7-Zip is installed
if exist "C:\Program Files\7-Zip\7z.exe" (
    set "SEVENZIP=C:\Program Files\7-Zip\7z.exe"
) else if exist "C:\Program Files (x86)\7-Zip\7z.exe" (
    set "SEVENZIP=C:\Program Files (x86)\7-Zip\7z.exe"
) else (
    echo ERROR: 7-Zip not found!
    echo Please install 7-Zip from https://www.7-zip.org/download.html
    pause
    exit /b 1
)

echo Found 7-Zip at: %SEVENZIP%
echo.

:: Create config file for self-extracting archive
echo ;!@Install@!UTF-8! > "%OUTPUT_DIR%\config.txt"
echo Title="Five Star Chicken POS" >> "%OUTPUT_DIR%\config.txt"
echo BeginPrompt="Install Five Star Chicken POS?" >> "%OUTPUT_DIR%\config.txt"
echo RunProgram="five_star_chicken_enterprise.exe" >> "%OUTPUT_DIR%\config.txt"
echo ;!@InstallEnd@! >> "%OUTPUT_DIR%\config.txt"

echo Step 1: Creating 7z archive...
"%SEVENZIP%" a -t7z "%OUTPUT_DIR%\app.7z" ".\%RELEASE_DIR%\*" -mx=9

echo.
echo Step 2: Creating self-extracting EXE...
copy /b "C:\Program Files\7-Zip\7z.sfx" + "%OUTPUT_DIR%\config.txt" + "%OUTPUT_DIR%\app.7z" "%OUTPUT_DIR%\%APP_NAME%_Setup.exe"

echo.
echo Cleaning up...
del "%OUTPUT_DIR%\app.7z"
del "%OUTPUT_DIR%\config.txt"

echo.
echo ==========================================
echo   DONE!
echo ==========================================
echo.
echo Your installer is ready:
echo   %OUTPUT_DIR%\%APP_NAME%_Setup.exe
echo.
echo This single EXE will:
echo   1. Ask user to install
echo   2. Extract all files
echo   3. Run the app automatically
echo.
explorer "%OUTPUT_DIR%"
pause
