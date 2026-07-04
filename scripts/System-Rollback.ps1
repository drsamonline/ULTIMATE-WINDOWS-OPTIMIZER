<#
    System-Rollback.ps1
    Creates a real Windows System Restore point before you run an
    optimization profile, and can list/launch restore UI. This is a
    different, complementary safety net to Undo-All-Changes.ps1: System
    Restore covers the whole system state (including things this toolkit
    doesn't track), while Undo-All-Changes.ps1 surgically reverts only
    what this toolkit itself changed.

    Usage:
      .\System-Rollback.ps1 -Create              -> creates a restore point
      .\System-Rollback.ps1 -ListAndLaunch        -> lists restore points and opens System Restore UI
#>
param(
    [switch]$Create,
    [switch]$ListAndLaunch
)

. (Join-Path $PSScriptRoot 'Common-Functions.ps1')
Assert-Admin
$logFile = New-LogFile -Name 'SystemRollback'

if (-not $Create -and -not $ListAndLaunch) {
    Write-Host "Choose an action:" -ForegroundColor Cyan
    Write-Host "  [1] Create a restore point now"
    Write-Host "  [2] List existing restore points and open System Restore"
    $choice = Read-Host "Enter 1 or 2"
    if ($choice -eq '1') { $Create = $true } else { $ListAndLaunch = $true }
}

if ($Create) {
    try {
        Enable-ComputerRestore -Drive $env:SystemDrive -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "UltimateWindowsOptimizer_$(Get-Date -Format 'yyyyMMdd_HHmmss')" -RestorePointType 'MODIFY_SETTINGS'
        Write-Log -Message "System Restore point created successfully" -LogFile $logFile -Level OK
        Write-Host "Restore point created." -ForegroundColor Green
    } catch {
        Write-Log -Message "Failed to create restore point: $($_.Exception.Message)" -LogFile $logFile -Level ERROR
        Write-Host "Could not create a restore point: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "System Restore may be disabled on this drive, or your Windows edition/policy blocks it." -ForegroundColor Yellow
    }
}

if ($ListAndLaunch) {
    try {
        $points = Get-ComputerRestorePoint -ErrorAction Stop
        if ($points) {
            Write-Host "Existing restore points:" -ForegroundColor Cyan
            $points | Select-Object SequenceNumber, Description, CreationTime | Format-Table -AutoSize
        } else {
            Write-Host "No restore points found." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Could not enumerate restore points: $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Host "Opening System Restore..." -ForegroundColor Cyan
    Start-Process -FilePath 'rstrui.exe'
}
