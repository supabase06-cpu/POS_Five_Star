@echo off
echo Cleaning local database...

set "DB_PATH=%LOCALAPPDATA%\FiveStarChickenPOS\five_star_pos.db"

if exist "%DB_PATH%" (
    echo Found database at: %DB_PATH%
    del "%DB_PATH%"
    echo Database deleted successfully!
) else (
    echo Database not found at: %DB_PATH%
)

echo.
echo Also checking for any temporary database files...
if exist "%LOCALAPPDATA%\FiveStarChickenPOS\five_star_pos.db-journal" (
    del "%LOCALAPPDATA%\FiveStarChickenPOS\five_star_pos.db-journal"
    echo Deleted journal file
)

if exist "%LOCALAPPDATA%\FiveStarChickenPOS\five_star_pos.db-wal" (
    del "%LOCALAPPDATA%\FiveStarChickenPOS\five_star_pos.db-wal"
    echo Deleted WAL file
)

if exist "%LOCALAPPDATA%\FiveStarChickenPOS\five_star_pos.db-shm" (
    del "%LOCALAPPDATA%\FiveStarChickenPOS\five_star_pos.db-shm"
    echo Deleted SHM file
)

echo.
echo Database cleanup complete. The app will create a fresh database on next run.
pause