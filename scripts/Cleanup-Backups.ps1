<#
    Cleanup-Backups.ps1
    Prunes old backup JSON files in %USERPROFILE%\OptimizationLogs\Backups so
    they don't accumulate forever.

    Retention is deliberately conservative: a file is deleted only when it is
    BOTH outside the newest -KeepCount files AND older than -MaxAgeDays.
    Backups that have already been processed by Undo-All-Changes.ps1 (the
    'restored' subfolder) are pruned by default; backups that have NOT been
    undone yet are left alone unless you pass -IncludePending, because they
    are the only record of changes still applied to this machine.

    Usage:
      .\Cleanup-Backups.ps1                              -> keep last 20, delete restored backups older than 30 days
      .\Cleanup-Backups.ps1 -KeepCount 10 -MaxAgeDays 14
      .\Cleanup-Backups.ps1 -IncludePending              -> also prune not-yet-undone backups
      .\Cleanup-Backups.ps1 -WhatIf                      -> preview only
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateRange(0, 10000)][int]$KeepCount = 20,
    [ValidateRange(1, 36500)][int]$MaxAgeDays = 30,
    [switch]$IncludePending
)

Import-Module (Join-Path $PSScriptRoot 'UWO.psd1') -Force

$logFile = New-LogFile -Name 'BackupRetention'

Write-Host ""
Write-Host "=== Backup retention ===" -ForegroundColor Cyan
Write-Host "Backup folder: $(Get-UwoBackupDirectory)"
Write-Host "Keeping the newest $KeepCount file(s) and anything newer than $MaxAgeDays day(s)."
if ($IncludePending) {
    Write-Host "Pending (not yet undone) backups are INCLUDED in this prune." -ForegroundColor Yellow
} else {
    Write-Host "Pending (not yet undone) backups are left untouched."
}

$pruned = Remove-OldBackupFile -LogFile $logFile -KeepCount $KeepCount -MaxAgeDays $MaxAgeDays -IncludePending:$IncludePending

Write-Host ""
if ($WhatIfPreference) {
    Write-Host "$pruned backup file(s) would be pruned (ran with -WhatIf)." -ForegroundColor Cyan
} else {
    Write-Host "$pruned backup file(s) pruned." -ForegroundColor Green
}
Write-Host "Details logged to: $logFile" -ForegroundColor Cyan
