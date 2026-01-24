@echo off
echo ========================================
echo   Five Star Chicken POS - Build Release
echo ========================================
echo.

echo Step 1: Cleaning previous build...
call flutter clean

echo.
echo Step 2: Getting dependencies...
call flutter pub get

echo.
echo Step 3: Building Windows release...
call flutter build windows --release

echo.
echo ========================================
echo   BUILD COMPLETE!
echo ========================================
echo.
echo Your app is ready at:
echo   build\windows\x64\runner\Release\
echo.
echo To distribute:
echo   1. Zip the entire "Release" folder
echo   2. Share the zip file
echo   3. Users extract and run the .exe
echo.
echo Opening Release folder...
explorer build\windows\x64\runner\Release
pause
