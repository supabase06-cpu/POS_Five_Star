@echo off
echo Checking version information...
echo.

echo Current pubspec.yaml version:
findstr "version:" pubspec.yaml

echo.
echo Current MSIX version:
findstr "msix_version:" pubspec.yaml

echo.
echo Checking built EXE properties...
powershell "Get-ItemProperty 'build\windows\x64\runner\Release\five_star_chicken_enterprise.exe' | Select-Object VersionInfo"

echo.
echo Files ready for distribution:
dir FiveStarChickenPOS_v1.0.4_PrinterFixed_Signed.*

pause