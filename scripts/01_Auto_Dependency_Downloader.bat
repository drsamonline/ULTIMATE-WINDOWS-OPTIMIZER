@echo off
setlocal
cd /d "%~dp0\.."
if not exist "Dependencies" mkdir "Dependencies"

echo =========================================================
echo   OPTIONAL DIAGNOSTIC TOOLS
echo =========================================================
echo.
echo This toolkit does NOT require these tools to function. They are
echo optional third-party utilities you can use to independently verify
echo your hardware and any changes this toolkit makes:
echo.
echo   - HWiNFO64  (sensors / hardware info)   https://www.hwinfo.com/download/
echo   - GPU-Z     (GPU info)                  https://www.techpowerup.com/download/techpowerup-gpu-z/
echo.
echo Direct download links change with every release, so rather than fetch
echo a version-pinned URL that may go stale, this script opens the official
echo download pages in your browser. Please verify any downloaded installer
echo yourself (e.g. VirusTotal) before running it.
echo.
set /p proceed="Open both download pages now? (Y/N): "
if /i not "%proceed%"=="Y" goto END

start "" "https://www.hwinfo.com/download/"
start "" "https://www.techpowerup.com/download/techpowerup-gpu-z/"

echo.
echo Opened both pages in your default browser.

:END
endlocal
pause
