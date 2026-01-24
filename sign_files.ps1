# Five Star Chicken POS - PowerShell File Signing Script
Write-Host "==========================================" -ForegroundColor Green
Write-Host "  Five Star Chicken POS - File Signing" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""

# Set variables
$CertPath = "clinthoskote.pfx"
$ExePath = "build\windows\x64\runner\Release\five_star_chicken_enterprise.exe"
$MsixPath = "build\windows\x64\runner\Release\five_star_chicken_enterprise.msix"
$TimestampUrl = "http://timestamp.digicert.com"

# Check if certificate exists
if (-not (Test-Path $CertPath)) {
    Write-Host "ERROR: Certificate file not found: $CertPath" -ForegroundColor Red
    Write-Host "Please ensure the certificate file is in the project root" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Check if signtool is available
try {
    $null = Get-Command signtool -ErrorAction Stop
    Write-Host "SignTool found successfully" -ForegroundColor Green
} catch {
    Write-Host "ERROR: SignTool not found in PATH!" -ForegroundColor Red
    Write-Host "Please install Windows SDK or Visual Studio with Windows development tools" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "SignTool is typically located at:" -ForegroundColor Yellow
    Write-Host "  C:\Program Files (x86)\Windows Kits\10\bin\x64\signtool.exe" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "You can add it to PATH or run this script from Developer Command Prompt" -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "Certificate: $CertPath" -ForegroundColor Cyan
Write-Host ""

# Prompt for certificate password
$CertPassword = Read-Host "Enter certificate password (press Enter if no password)" -AsSecureString
$CertPasswordPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($CertPassword))

Write-Host ""
Write-Host "Step 1: Signing EXE file..." -ForegroundColor Yellow

if (Test-Path $ExePath) {
    Write-Host "Signing: $ExePath" -ForegroundColor Cyan
    
    $signArgs = @(
        "sign"
        "/f", $CertPath
        "/p", $CertPasswordPlain
        "/t", $TimestampUrl
        "/fd", "SHA256"
        "/v"
        $ExePath
    )
    
    $result = & signtool @signArgs
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "EXE signed successfully!" -ForegroundColor Green
    } else {
        Write-Host "ERROR: EXE signing failed!" -ForegroundColor Red
        Write-Host "SignTool output: $result" -ForegroundColor Red
        Read-Host "Press Enter to continue"
    }
} else {
    Write-Host "WARNING: EXE file not found at $ExePath" -ForegroundColor Yellow
    Write-Host "Please build the project first using build_release.bat" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Step 2: Signing MSIX file..." -ForegroundColor Yellow

if (Test-Path $MsixPath) {
    Write-Host "Signing: $MsixPath" -ForegroundColor Cyan
    
    $signArgs = @(
        "sign"
        "/f", $CertPath
        "/p", $CertPasswordPlain
        "/t", $TimestampUrl
        "/fd", "SHA256"
        "/v"
        $MsixPath
    )
    
    $result = & signtool @signArgs
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "MSIX signed successfully!" -ForegroundColor Green
    } else {
        Write-Host "ERROR: MSIX signing failed!" -ForegroundColor Red
        Write-Host "SignTool output: $result" -ForegroundColor Red
        Read-Host "Press Enter to continue"
    }
} else {
    Write-Host "WARNING: MSIX file not found at $MsixPath" -ForegroundColor Yellow
    Write-Host "Please build the MSIX package first using build_msix.bat" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Step 3: Verifying signatures..." -ForegroundColor Yellow
Write-Host ""

Write-Host "Verifying EXE signature..." -ForegroundColor Cyan
if (Test-Path $ExePath) {
    $verifyResult = & signtool verify /pa $ExePath
    if ($LASTEXITCODE -eq 0) {
        Write-Host "EXE signature verified successfully!" -ForegroundColor Green
    } else {
        Write-Host "EXE signature verification failed!" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Verifying MSIX signature..." -ForegroundColor Cyan
if (Test-Path $MsixPath) {
    $verifyResult = & signtool verify /pa $MsixPath
    if ($LASTEXITCODE -eq 0) {
        Write-Host "MSIX signature verified successfully!" -ForegroundColor Green
    } else {
        Write-Host "MSIX signature verification failed!" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host "  FILE SIGNING COMPLETE!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Signed files:" -ForegroundColor Cyan
if (Test-Path $ExePath) { Write-Host "  - $ExePath" -ForegroundColor White }
if (Test-Path $MsixPath) { Write-Host "  - $MsixPath" -ForegroundColor White }
Write-Host ""
Write-Host "Your files are now digitally signed and ready for distribution!" -ForegroundColor Green
Write-Host ""

# Clear the password from memory
$CertPasswordPlain = $null
[System.GC]::Collect()

Read-Host "Press Enter to exit"