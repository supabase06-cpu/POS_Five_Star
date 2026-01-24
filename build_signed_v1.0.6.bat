@echo off
echo ==========================================
echo   Five Star Chicken POS v1.0.6 - Signed Build
echo ==========================================
echo.

REM Set variables
set CERT_PATH=clinthoskote.pfx
set CERT_PASSWORD=StrongPassword123!
set APP_NAME=FiveStarChickenPOS
set VERSION=1.0.6
set EXE_PATH=build\windows\x64\runner\Release\five_star_chicken_enterprise.exe
set MSIX_PATH=build\windows\x64\runner\Release\five_star_chicken_enterprise.msix
set SIGNTOOL_PATH=C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe

REM Check if certificate exists
if not exist %CERT_PATH% (
    echo ERROR: Certificate file not found: %CERT_PATH%
    pause
    exit /b 1
)

echo Step 1: Cleaning previous build...
flutter clean

echo.
echo Step 2: Getting dependencies...
flutter pub get

echo.
echo Step 3: Building release...
flutter build windows --release

echo.
echo Step 4: Signing the EXE file...
if exist %EXE_PATH% (
    echo Signing EXE...
    "%SIGNTOOL_PATH%" sign /f %CERT_PATH% /p %CERT_PASSWORD% /t http://timestamp.digicert.com /fd SHA256 %EXE_PATH%
    if errorlevel 1 (
        echo ERROR: EXE signing failed!
        pause
        exit /b 1
    ) else (
        echo EXE signed successfully!
    )
) else (
    echo ERROR: EXE file not found!
    pause
    exit /b 1
)

echo.
echo Step 5: Creating MSIX package...
dart run msix:create

echo.
echo Step 6: Signing the MSIX package...
if exist %MSIX_PATH% (
    echo Signing MSIX...
    "%SIGNTOOL_PATH%" sign /f %CERT_PATH% /p %CERT_PASSWORD% /t http://timestamp.digicert.com /fd SHA256 %MSIX_PATH%
    if errorlevel 1 (
        echo ERROR: MSIX signing failed!
        pause
        exit /b 1
    ) else (
        echo MSIX signed successfully!
    )
) else (
    echo ERROR: MSIX file not found!
    pause
    exit /b 1
)

echo.
echo Step 7: Creating final signed package...
copy %MSIX_PATH% %APP_NAME%_v%VERSION%_Signed.msix

echo.
echo Step 8: Verifying signatures...
echo Verifying EXE signature...
"%SIGNTOOL_PATH%" verify /pa %EXE_PATH%

echo.
echo Verifying MSIX signature...
"%SIGNTOOL_PATH%" verify /pa %APP_NAME%_v%VERSION%_Signed.msix

echo.
echo ==========================================
echo   SIGNED BUILD COMPLETE!
echo ==========================================
echo.
echo Your signed MSIX package is ready:
echo   %APP_NAME%_v%VERSION%_Signed.msix
echo.
pause