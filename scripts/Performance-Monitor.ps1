<#
    Performance-Monitor.ps1
    Captures a real snapshot of current CPU load, RAM usage, disk free space,
    and top processes, and saves it as a labeled JSON file. Run this once
    BEFORE applying an optimization profile (label it "Baseline") and again
    AFTER (label it anything else, e.g. "AfterGaming"). Compare-Results.ps1
    then diffs two real snapshots - it does not print canned numbers.

    Usage:
      .\Performance-Monitor.ps1                  -> prompts for a label
      .\Performance-Monitor.ps1 -Label Baseline  -> non-interactive
#>
param(
    [string]$Label
)

. (Join-Path $PSScriptRoot 'Common-Functions.ps1')

if (-not $Label) {
    $Label = Read-Host "Enter a label for this snapshot (e.g. Baseline, AfterGaming)"
    if (-not $Label) { $Label = 'Snapshot' }
}

Write-Host "Capturing system snapshot (this takes about 1 second for CPU sampling)..." -ForegroundColor Cyan
$path = Save-SystemSnapshot -Label $Label
$snapshot = Get-Content -Path $path -Raw | ConvertFrom-Json

Write-Host ""
Write-Host "=== Snapshot: $Label ===" -ForegroundColor Green
Write-Host "Timestamp:        $($snapshot.Timestamp)"
Write-Host "CPU load:         $($snapshot.CPULoadPercent)%"
Write-Host "RAM used:         $($snapshot.UsedRamMB) MB of $($snapshot.TotalRamMB) MB"
Write-Host "System drive free:$($snapshot.SystemDriveFreeGB) GB of $($snapshot.SystemDriveSizeGB) GB"
Write-Host "Uptime:           $($snapshot.UptimeHours) hours"
Write-Host ""
Write-Host "Top processes by CPU time:" -ForegroundColor Yellow
$snapshot.TopProcesses | Format-Table -AutoSize | Out-String | ForEach-Object { Write-Host $_ }
Write-Host "Saved to: $path" -ForegroundColor Cyan
