# PowerShell script to create a single-file installer
Write-Host "Creating Single-File Installer for Five Star Chicken POS v1.0.6" -ForegroundColor Green

$AppName = "FiveStarChickenPOS_v1.0.6_SingleFile"
$SourceDir = "build\windows\x64\runner\Release"
$OutputFile = "$AppName.exe"

# Check if 7-Zip is available (for creating self-extracting archive)
$SevenZip = "C:\Program Files\7-Zip\7z.exe"
if (Test-Path $SevenZip) {
    Write-Host "Creating self-extracting installer..." -ForegroundColor Yellow
    
    # Create a self-extracting archive
    & $SevenZip a -sfx7z.sfx "$OutputFile" "$SourceDir\*" -mx9
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "SUCCESS: Single-file installer created: $OutputFile" -ForegroundColor Green
        Write-Host "File size: $((Get-Item $OutputFile).Length / 1MB) MB" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Users can now:" -ForegroundColor Yellow
        Write-Host "1. Download the single .exe file" -ForegroundColor White
        Write-Host "2. Run it directly - no zip extraction needed" -ForegroundColor White
        Write-Host "3. App will extract and run automatically" -ForegroundColor White
    } else {
        Write-Host "ERROR: Failed to create installer" -ForegroundColor Red
    }
} else {
    Write-Host "7-Zip not found. Creating portable ZIP instead..." -ForegroundColor Yellow
    
    # Create a ZIP file as fallback
    Compress-Archive -Path "$SourceDir\*" -DestinationPath "$AppName.zip" -Force
    Write-Host "Created: $AppName.zip" -ForegroundColor Green
}

Write-Host ""
Write-Host "Current files:" -ForegroundColor Cyan
Get-ChildItem "FiveStarChickenPOS_v1.0.6*" | Format-Table Name, Length, LastWriteTime