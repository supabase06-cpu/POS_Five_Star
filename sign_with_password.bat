@echo off
echo ==========================================
echo   Five Star Chicken POS - Code Signing
echo ==========================================
echo.

set SIGNTOOL="C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe"
set CERT_PATH=clinthoskote.pfx
set EXE_PATH=build\windows\x64\runner\Release\five_star_chicken_enterprise.exe

echo Certificate: %CERT_PATH%
echo EXE File: %EXE_PATH%
echo.

:: Prompt for password
set /p CERT_PASSWORD="Enter certificate password: "

echo.
echo Signing EXE file...
%SIGNTOOL% sign /f %CERT_PATH% /p "%CERT_PASSWORD%" /t http://timestamp.digicert.com /fd SHA256 "%EXE_PATH%"

if errorlevel 1 (
    echo ERROR: EXE signing failed!
    pause
    exit /b 1
) else (
    echo EXE signed successfully!
)

echo.
echo Verifying EXE signature...
%SIGNTOOL% verify /pa "%EXE_PATH%"

echo.
echo Now building and signing MSIX...
flutter pub run msix:create

echo.
echo Signing MSIX file...
if exist "build\windows\x64\runner\Release\five_star_chicken_enterprise.msix" (
    %SIGNTOOL% sign /f %CERT_PATH% /p "%CERT_PASSWORD%" /t http://timestamp.digicert.com /fd SHA256 "build\windows\x64\runner\Release\five_star_chicken_enterprise.msix"
    
    if errorlevel 1 (
        echo ERROR: MSIX signing failed!
    ) else (
        echo MSIX signed successfully!
        echo.
        echo Verifying MSIX signature...
        %SIGNTOOL% verify /pa "build\windows\x64\runner\Release\five_star_chicken_enterprise.msix"
    )
) else (
    echo ERROR: MSIX file not found!
)

echo.
echo ==========================================
echo   SIGNING COMPLETE!
echo ==========================================
echo.
echo Your signed files are ready:
echo   EXE: %EXE_PATH%
echo   MSIX: build\windows\x64\runner\Release\five_star_chicken_enterprise.msix
echo.

explorer "build\windows\x64\runner\Release"
pause