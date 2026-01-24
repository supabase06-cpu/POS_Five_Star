# Create Single-Click Installer for Five Star Chicken POS
Write-Host "Creating Single-Click Installer..." -ForegroundColor Green

$AppName = "FiveStarChickenPOS_v1.0.6_Installer.exe"
$SourcePath = "build\windows\x64\runner\Release"

# Create installer script
$InstallerScript = @'
@echo off
title Five Star Chicken POS v1.0.6 Installer
echo Installing Five Star Chicken POS v1.0.6...
echo Please wait...

set "INSTALL_DIR=%LOCALAPPDATA%\FiveStarChickenPOS"
if exist "%INSTALL_DIR%" rmdir /s /q "%INSTALL_DIR%"
mkdir "%INSTALL_DIR%"

echo Extracting files...
powershell -WindowStyle Hidden -Command "& {$data = [System.IO.File]::ReadAllBytes('%~f0'); $start = [System.Text.Encoding]::ASCII.GetString($data) -split 'DATA_START' | Select-Object -Last 1 -Skip 0; $zipStart = $data.Length - [System.Text.Encoding]::ASCII.GetByteCount($start); $zipData = $data[$zipStart..($data.Length-1)]; [System.IO.File]::WriteAllBytes('temp.zip', $zipData); Expand-Archive -Path 'temp.zip' -DestinationPath '%INSTALL_DIR%' -Force; Remove-Item 'temp.zip'}"

echo Creating shortcuts...
powershell -WindowStyle Hidden -Command "$WshShell = New-Object -comObject WScript.Shell; $Shortcut = $WshShell.CreateShortcut('%USERPROFILE%\Desktop\Five Star Chicken POS.lnk'); $Shortcut.TargetPath = '%INSTALL_DIR%\five_star_chicken_enterprise.exe'; $Shortcut.Save()"

echo Installation complete!
echo Starting Five Star Chicken POS...
start "" "%INSTALL_DIR%\five_star_chicken_enterprise.exe"
exit

DATA_START
'@

# Save installer script
$InstallerScript | Out-File -FilePath "temp_installer.bat" -Encoding ASCII

# Create ZIP of release files
Write-Host "Compressing application files..." -ForegroundColor Yellow
Compress-Archive -Path "$SourcePath\*" -DestinationPath "temp_app.zip" -Force

# Combine installer script and ZIP data
Write-Host "Creating single installer file..." -ForegroundColor Yellow
$installerBytes = [System.IO.File]::ReadAllBytes("temp_installer.bat")
$zipBytes = [System.IO.File]::ReadAllBytes("temp_app.zip")
$combinedBytes = $installerBytes + $zipBytes
[System.IO.File]::WriteAllBytes($AppName, $combinedBytes)

# Cleanup
Remove-Item "temp_installer.bat" -Force
Remove-Item "temp_app.zip" -Force

Write-Host ""
Write-Host "SUCCESS!" -ForegroundColor Green
Write-Host "Created: $AppName" -ForegroundColor Cyan
Write-Host "Size: $([math]::Round((Get-Item $AppName).Length / 1MB, 2)) MB" -ForegroundColor Cyan
Write-Host ""
Write-Host "Users can now:" -ForegroundColor Yellow
Write-Host "1. Download this ONE file" -ForegroundColor White
Write-Host "2. Double-click to install" -ForegroundColor White
Write-Host "3. App installs and runs automatically" -ForegroundColor White
Write-Host ""