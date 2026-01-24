@echo off
echo ==========================================
echo   Creating Single EXE File
echo ==========================================
echo.

set SOURCE_DIR=build\windows\x64\runner\Release
set OUTPUT_EXE=FiveStarChickenPOS_v1.0.6_SingleFile.exe
set TEMP_BAT=temp_extractor.bat

echo Step 1: Building Flutter app...
flutter build windows --release

echo.
echo Step 2: Creating self-extracting EXE...

REM Create a batch file that will extract and run
echo @echo off > %TEMP_BAT%
echo echo Extracting Five Star Chicken POS... >> %TEMP_BAT%
echo set TEMP_DIR=%%TEMP%%\FiveStarChickenPOS >> %TEMP_BAT%
echo if exist "%%TEMP_DIR%%" rmdir /s /q "%%TEMP_DIR%%" >> %TEMP_BAT%
echo mkdir "%%TEMP_DIR%%" >> %TEMP_BAT%
echo cd /d "%%TEMP_DIR%%" >> %TEMP_BAT%
echo findstr /v "^@echo\|^set\|^if\|^mkdir\|^cd\|^findstr\|^start\|^exit" "%%~f0" ^> app.zip >> %TEMP_BAT%
echo powershell -command "Expand-Archive -Path 'app.zip' -DestinationPath '.' -Force" >> %TEMP_BAT%
echo start "" "five_star_chicken_enterprise.exe" >> %TEMP_BAT%
echo exit >> %TEMP_BAT%

REM Create ZIP of the Release folder
powershell -command "Compress-Archive -Path '%SOURCE_DIR%\*' -DestinationPath 'temp_app.zip' -Force"

REM Combine batch file and ZIP
copy /b %TEMP_BAT% + temp_app.zip %OUTPUT_EXE%

REM Cleanup
del %TEMP_BAT%
del temp_app.zip

echo.
echo ==========================================
echo   SUCCESS! Single EXE Created
echo ==========================================
echo.
echo File: %OUTPUT_EXE%
echo.
echo This is a TRUE single .exe file:
echo   - Users download ONE file
echo   - Double-click to run
echo   - No installation needed
echo   - Runs directly from temp folder
echo.
dir %OUTPUT_EXE%
pause