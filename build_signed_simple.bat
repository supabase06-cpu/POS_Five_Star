@echo off
echo ==========================================
echo   Five Star Chicken POS - Signed Build
echo ==========================================
echo.

:: Set variables
set CERT_PATH=clinthoskote.pfx
set APP_NAME=FiveStarChickenPOS
set VERSION=1.0.3.0
set OUTPUT_DIR=build\signed_packages
set EXE_PATH=build\windows\x64\runner\Release\five_star_chicken_enterprise.exe

:: Check if certificate exists
if not exist %CERT_PATH% (
    echo ERROR: Certificate file not found: %CERT_PATH%
    pause
    exit /b 1
)

:: Check Flutter
flutter --version
if errorlevel 1 (
    echo ERROR: Flutter not found!
    pause
    exit /b 1
)

:: Set SignTool path
set SIGNTOOL="C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe"
if not exist %SIGNTOOL% (
    set SIGNTOOL="C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\signtool.exe"
)

echo Using SignTool: %SIGNTOOL%
echo.

echo Step 1: Cleaning previous build...
flutter clean

echo.
echo Step 2: Getting dependencies...
flutter pub get

echo.
echo Step 3: Building Windows release...
flutter build windows --release

echo.
echo Step 4: Creating output directory...
if not exist %OUTPUT_DIR% mkdir %OUTPUT_DIR%

echo.
echo Step 5: Signing EXE file...
if exist %EXE_PATH% (
    echo Signing: %EXE_PATH%
    %SIGNTOOL% sign /f %CERT_PATH% /p "" /t http://timestamp.digicert.com /fd SHA256 %EXE_PATH%
    if errorlevel 1 (
        echo WARNING: EXE signing failed
    ) else (
        echo EXE signed successfully!
    )
) else (
    echo WARNING: EXE file not found
)

echo.
echo Step 6: Creating MSIX package...
flutter pub run msix:create

echo.
echo Step 7: Signing MSIX file...
if exist build\windows\x64\runner\Release\five_star_chicken_enterprise.msix (
    echo Signing MSIX...
    %SIGNTOOL% sign /f %CERT_PATH% /p "" /t http://timestamp.digicert.com /fd SHA256 build\windows\x64\runner\Release\five_star_chicken_enterprise.msix
    if errorlevel 1 (
        echo WARNING: MSIX signing failed
    ) else (
        echo MSIX signed successfully!
    )
    
    :: Copy to output directory
    copy build\windows\x64\runner\Release\five_star_chicken_enterprise.msix %OUTPUT_DIR%\%APP_NAME%_v%VERSION%_Signed.msix
) else (
    echo WARNING: MSIX file not found
)

echo.
echo ==========================================
echo   BUILD COMPLETE!
echo ==========================================
echo.
echo Files location:
echo   EXE: %EXE_PATH%
echo   MSIX: %OUTPUT_DIR%\%APP_NAME%_v%VERSION%_Signed.msix
echo.

if exist %OUTPUT_DIR% explorer %OUTPUT_DIR%
pause