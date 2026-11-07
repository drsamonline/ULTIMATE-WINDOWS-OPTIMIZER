@echo off
setlocal enabledelayedexpansion
title Ultimate Windows Optimizer v6.2.1
cd /d "%~dp0"

:: --- Admin check -----------------------------------------------------------
:: `net session` is the traditional elevation test, but it ALSO requires the
:: "Server" (LanmanServer) service to be running. On many Windows 10/11
:: installs that service is Manual or Disabled, so `net session` fails even in
:: an elevated window - which made this launcher wrongly report "not admin".
:: `fltmc` needs elevation but not the Server service, so it is tried first,
:: then `net session`, then an authoritative PowerShell principal check.
:: (Flat `goto` structure on purpose: no multi-line parenthesised blocks, so a
:: `)` inside the PowerShell command or the install path cannot break parsing.)
set "UWO_IS_ADMIN="
if defined UWO_SKIP_ADMIN_CHECK set "UWO_IS_ADMIN=1"
if defined UWO_IS_ADMIN goto :ADMIN_OK

fltmc >nul 2>&1
if not errorlevel 1 set "UWO_IS_ADMIN=1"
if defined UWO_IS_ADMIN goto :ADMIN_OK

net session >nul 2>&1
if not errorlevel 1 set "UWO_IS_ADMIN=1"
if defined UWO_IS_ADMIN goto :ADMIN_OK

powershell -NoProfile -Command "if (-not (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 1 }" >nul 2>&1
if not errorlevel 1 set "UWO_IS_ADMIN=1"
if defined UWO_IS_ADMIN goto :ADMIN_OK

:: Not elevated - offer to relaunch elevated once (guarded so it cannot loop).
if defined UWO_ELEVATION_ATTEMPTED goto :NOT_ADMIN
set "UWO_ELEVATION_ATTEMPTED=1"
echo.
echo This launcher needs Administrator privileges - requesting elevation...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs" >nul 2>&1
if not errorlevel 1 exit /b 0

:NOT_ADMIN
echo.
echo [ERROR] This launcher must be run as Administrator.
echo Right-click this file and choose "Run as administrator".
echo.
echo If you are ALREADY running as Administrator, the check may be blocked by
echo the "Server" (LanmanServer) service being stopped or disabled. Start it:
echo     sc config LanmanServer start= auto
echo     net start LanmanServer
echo ...or set UWO_SKIP_ADMIN_CHECK=1 in this window and run the launcher again.
echo.
pause
exit /b 1

:ADMIN_OK

:MENU
cls
echo =========================================================
echo   ULTIMATE WINDOWS OPTIMIZER v6.2.1
echo   github.com/DrSamOnline
echo =========================================================
echo.
echo   OPTIMIZATION PROFILES (each applies a genuinely different,
echo   documented set of tweaks - see README.md for details)
echo.
echo   [1] Daily Home       - balanced, everyday use
echo   [2] Gaming           - GPU scheduling, priority boost (desktop)
echo   [3] Office           - productivity, background-app trimming
echo   [4] Laptop           - battery-aware (safe for laptops)
echo   [5] Extreme          - aggressive, hardware-gated (desktop)
echo   [6] Godlike          - maximum aggression, requires confirmation
echo   [7] Server           - headless/background-service machines
echo   [8] Streaming        - gaming + capture/streaming software
echo.
echo   UTILITIES
echo   [9]  Compatibility Check       [C] Cleanup System (real space freed)
echo   [H]  Hardware Detection        [V] Verify a Profile Was Applied
echo   [M]  Performance Snapshot      [R] Compare Two Snapshots
echo   [A]  Advanced Modules (8 real toggles)
echo   [S]  Create System Restore Point / Open System Restore
echo   [U]  UNDO ALL TRACKED CHANGES
echo   [P]  Prune Old Backup Files (keeps last 20 / 30 days)
echo   [D]  Download Optional Diagnostic Tools (HWiNFO64, GPU-Z)
echo.
echo   [Q] Quit
echo.
set "choice="
set /p choice="Select an option: "
if not defined choice goto MENU

if /i "%choice%"=="1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "Optimize-Daily-Home.ps1"
    goto PAUSE_MENU
)
if /i "%choice%"=="2" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "Optimize-Gaming.ps1"
    goto PAUSE_MENU
)
if /i "%choice%"=="3" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "Optimize-Office.ps1"
    goto PAUSE_MENU
)
if /i "%choice%"=="4" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "Optimize-Laptop.ps1"
    goto PAUSE_MENU
)
if /i "%choice%"=="5" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "Optimize-Extreme.ps1"
    goto PAUSE_MENU
)
if /i "%choice%"=="6" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "Optimize-Godlike.ps1"
    goto PAUSE_MENU
)
if /i "%choice%"=="7" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "Optimize-Server.ps1"
    goto PAUSE_MENU
)
if /i "%choice%"=="8" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "Optimize-Streaming.ps1"
    goto PAUSE_MENU
)
if /i "%choice%"=="9" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "Compatibility-Check.ps1"
    goto PAUSE_MENU
)
if /i "%choice%"=="C" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "Cleanup-System.ps1"
    goto PAUSE_MENU
)
if /i "%choice%"=="H" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "Hardware-Detection.ps1"
    goto PAUSE_MENU
)
if /i "%choice%"=="V" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "Verify-System.ps1"
    goto PAUSE_MENU
)
if /i "%choice%"=="M" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "Performance-Monitor.ps1"
    goto PAUSE_MENU
)
if /i "%choice%"=="R" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "Compare-Results.ps1"
    goto PAUSE_MENU
)
if /i "%choice%"=="A" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "Advanced-Modules.ps1"
    goto PAUSE_MENU
)
if /i "%choice%"=="S" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "System-Rollback.ps1"
    goto PAUSE_MENU
)
if /i "%choice%"=="U" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "Undo-All-Changes.ps1"
    goto PAUSE_MENU
)
if /i "%choice%"=="P" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "Cleanup-Backups.ps1"
    goto PAUSE_MENU
)
if /i "%choice%"=="D" (
    call "01_Auto_Dependency_Downloader.bat"
    goto PAUSE_MENU
)
if /i "%choice%"=="Q" goto END

echo Invalid choice.
timeout /t 2 >nul
goto MENU

:PAUSE_MENU
echo.
pause
goto MENU

:END
endlocal
exit /b 0
