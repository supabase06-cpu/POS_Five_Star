@echo off
echo ==========================================
echo   Five Star Chicken POS - File Signing
echo ==========================================
echo.

:: Set variables
set "CERT_PATH=clinthoskote.pfx"
set "EXE_PATH=build\windows\x64\runner\Release\five_star_chicken_enterprise.exe"
set "MSIX_PATH=build\windows\x64\runner\Release\five_star_chicken_enterprise.msix"

:: Check if certificate exists
if not exist "%CERT_PATH%" (
    echo ERROR: Certificate file not found: %CERT_PATH%
    echo Please ensure the certificate file is in the project root
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

echo Certificate: %CERT_PATH%
echo.

:: Prompt for certificate password
set /p CERT_PASSWORD="Enter certificate password (press Enter if no password): "

echo.
echo Step 1: Signing EXE file...
if exist "%EXE_PATH%" (
    echo Signing: %EXE_PATH%
    "%SIGNTOOL_PATH%" sign /f "%CERT_PATH%" /p "%CERT_PASSWORD%" /t http://timestamp.digicert.com /fd SHA256 "%EXE_PATH%"
    if errorlevel 1 (
        echo ERROR: EXE signing failed!
        pause
        exit /b 1
    ) else (
        echo EXE signed successfully!
    )
) else (
    echo WARNING: EXE file not found at %EXE_PATH%
    echo Please build the project first using build_release.bat
)

echo.
echo Step 2: Signing MSIX file...
if exist "%MSIX_PATH%" (
    echo Signing: %MSIX_PATH%
    "%SIGNTOOL_PATH%" sign /f "%CERT_PATH%" /p "%CERT_PASSWORD%" /t http://timestamp.digicert.com /fd SHA256 "%MSIX_PATH%"
    if errorlevel 1 (
        echo ERROR: MSIX signing failed!
        pause
        exit /b 1
    ) else (
        echo MSIX signed successfully!
    )
) else (
    echo WARNING: MSIX file not found at %MSIX_PATH%
    echo Please build the MSIX package first using build_msix.bat
)

echo.
echo Step 3: Verifying signatures...
echo.
echo Verifying EXE signature...
if exist "%EXE_PATH%" (
    "%SIGNTOOL_PATH%" verify /pa "%EXE_PATH%"
    if errorlevel 1 (
        echo EXE signature verification failed!
    ) else (
        echo EXE signature verified successfully!
    )
)

echo.
echo Verifying MSIX signature...
if exist "%MSIX_PATH%" (
    "%SIGNTOOL_PATH%" verify /pa "%MSIX_PATH%"
    if errorlevel 1 (
        echo MSIX signature verification failed!
    ) else (
        echo MSIX signature verified successfully!
    )
)

echo.
echo ==========================================
echo   FILE SIGNING COMPLETE!
echo ==========================================
echo.
echo Signed files:
if exist "%EXE_PATH%" echo   - %EXE_PATH%
if exist "%MSIX_PATH%" echo   - %MSIX_PATH%
echo.
echo Your files are now digitally signed and ready for distribution!
echo.
pause