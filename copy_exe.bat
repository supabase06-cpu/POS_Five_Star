@echo off
echo ==========================================
echo   Copying and Renaming EXE File
echo ==========================================
echo.

set "SOURCE_EXE=build\windows\x64\runner\Release\five_star_chicken_enterprise.exe"
set "TARGET_EXE=FiveStarChickenPOS_v1.0.6_Signed.exe"

if exist "%SOURCE_EXE%" (
    echo Copying %SOURCE_EXE% to %TARGET_EXE%...
    copy "%SOURCE_EXE%" "%TARGET_EXE%"
    if errorlevel 0 (
        echo SUCCESS: File copied successfully!
        echo New file: %TARGET_EXE%
    ) else (
        echo ERROR: Failed to copy file
    )
) else (
    echo ERROR: Source file not found: %SOURCE_EXE%
    echo Please build the app first using: flutter build windows --release
)

echo.
pause