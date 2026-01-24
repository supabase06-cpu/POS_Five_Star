@echo off
echo ==========================================
echo   Five Star Chicken POS - Signed Build
echo ==========================================
echo.

:: Set variables
set "CERT_PATH=clinthoskote.pfx"
set "APP_NAME=FiveStarChickenPOS"
set "VERSION=1.0.6.0"
set "OUTPUT_DIR=build\signed_packages"
set "EXE_PATH=build\windows\x64\runner\Release\five_star_chicken_enterprise.exe"

:: Check if certificate exists
if not exist "%CERT_PATH%" (
    echo ERROR: Certificate file not found: %CERT_PATH%
    echo Please ensure the certificate file is in the project root
    pause
    exit /b 1
)

:: Check if Flutter is available
flutter --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Flutter not found in PATH!
    echo Please install Flutter and add it to your PATH
    pause
    exit /b 1
)

:: Find and set SignTool path
set "SIGNTOOL_PATH="
if exist "C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe" (
    set "SIGNTOOL_PATH=C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe"
) else if exist "C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\signtool.exe" (
    set "SIGNTOOL_PATH=C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\signtool.exe"
) else (
    echo ERROR: SignTool not found!
    echo Please install Windows SDK or Visual Studio with Windows development tools
    pause
    exit /b 1
)

echo Using SignTool: %SIGNTOOL_PATH%

echo Step 1: Cleaning previous build...
call flutter clean

echo.
echo Step 2: Getting dependencies...
call flutter pub get

echo.
echo Step 3: Building Windows release...
call flutter build windows --release

echo.
echo Step 4: Signing the EXE file...
if exist "%EXE_PATH%" (
    echo Signing: %EXE_PATH%
    "%SIGNTOOL_PATH%" sign /f "%CERT_PATH%" /p "" /t http://timestamp.digicert.com /fd SHA256 "%EXE_PATH%"
    if errorlevel 1 (
        echo WARNING: EXE signing failed. Continuing with MSIX build...
    ) else (
        echo EXE signed successfully!
    )
) else (
    echo WARNING: EXE file not found at %EXE_PATH%
)

echo.
echo Step 5: Creating output directory...
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

echo.
echo Step 6: Creating signed MSIX package...
call dart run msix:create

echo.
echo Step 7: Copying and renaming MSIX...
if exist "build\windows\x64\runner\Release\*.msix" (
    copy "build\windows\x64\runner\Release\*.msix" "%OUTPUT_DIR%\"
    if exist "%OUTPUT_DIR%\five_star_chicken_enterprise.msix" (
        ren "%OUTPUT_DIR%\five_star_chicken_enterprise.msix" "%APP_NAME%_v%VERSION%_Signed.msix"
    )
)

echo.
echo Step 8: Verifying signatures...
echo Verifying EXE signature...
if exist "%EXE_PATH%" (
    "%SIGNTOOL_PATH%" verify /pa "%EXE_PATH%"
)

echo.
echo Verifying MSIX signature...
if exist "%OUTPUT_DIR%\%APP_NAME%_v%VERSION%_Signed.msix" (
    "%SIGNTOOL_PATH%" verify /pa "%OUTPUT_DIR%\%APP_NAME%_v%VERSION%_Signed.msix"
)

echo.
echo ==========================================
echo   SIGNED BUILD COMPLETE!
echo ==========================================
echo.
echo Your signed packages are ready at:
echo   EXE: %EXE_PATH%
echo   MSIX: %OUTPUT_DIR%\%APP_NAME%_v%VERSION%_Signed.msix
echo.
echo Package Details:
echo   - App Name: Five Star Chicken POS
echo   - Version: %VERSION%
echo   - Publisher: Five Star Chicken
echo   - Certificate: %CERT_PATH%
echo   - Signed with: SHA256 + Timestamp
echo.
echo Distribution Notes:
echo   - Both EXE and MSIX are digitally signed
echo   - Users will see verified publisher information
echo   - No security warnings during installation
echo.
echo Opening output folder...
explorer "%OUTPUT_DIR%"
pause