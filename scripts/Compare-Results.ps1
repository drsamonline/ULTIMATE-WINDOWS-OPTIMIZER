<#
    Compare-Results.ps1
    Diffs two REAL snapshots saved by Performance-Monitor.ps1. If fewer than
    two snapshots exist, it tells you to run Performance-Monitor.ps1 first -
    it does not fabricate numbers.
#>
. (Join-Path $PSScriptRoot 'Common-Functions.ps1')

$snapshotFiles = Get-ChildItem -Path $Script:SnapshotDir -Filter '*.json' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime

if ($snapshotFiles.Count -lt 2) {
    Write-Host "Only $($snapshotFiles.Count) snapshot(s) found." -ForegroundColor Yellow
    Write-Host "Run Performance-Monitor.ps1 once BEFORE optimizing (label it 'Baseline')" -ForegroundColor Yellow
    Write-Host "and once AFTER optimizing, then run this script again." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Available snapshots:" -ForegroundColor Cyan
for ($i = 0; $i -lt $snapshotFiles.Count; $i++) {
    $s = Get-Content $snapshotFiles[$i].FullName -Raw | ConvertFrom-Json
    Write-Host "  [$i] $($s.Label)  -  $($s.Timestamp)"
}

$beforeIndex = Read-Host "`nEnter the number of the BEFORE snapshot"
$afterIndex  = Read-Host "Enter the number of the AFTER snapshot"

try {
    $before = Get-Content $snapshotFiles[[int]$beforeIndex].FullName -Raw | ConvertFrom-Json
    $after  = Get-Content $snapshotFiles[[int]$afterIndex].FullName -Raw | ConvertFrom-Json
} catch {
    Write-Host "Invalid selection." -ForegroundColor Red
    exit 1
}

function Format-Delta {
    param($before, $after, $unit = '', $lowerIsBetter = $true)
    $delta = $after - $before
    $pct = if ($before -ne 0) { [math]::Round(($delta / $before) * 100, 1) } else { 0 }
    $improved = if ($lowerIsBetter) { $delta -le 0 } else { $delta -ge 0 }
    $color = if ($improved) { 'Green' } else { 'Red' }
    $sign = if ($delta -ge 0) { '+' } else { '' }
    return @{ Text = "$before$unit -> $after$unit  ($sign$delta$unit, $sign$pct%)"; Color = $color }
}

Write-Host ""
Write-Host "=== Comparison: '$($before.Label)' -> '$($after.Label)' ===" -ForegroundColor Cyan

$cpu = Format-Delta -before $before.CPULoadPercent -after $after.CPULoadPercent -unit '%'
Write-Host "CPU load:          $($cpu.Text)" -ForegroundColor $cpu.Color

$ram = Format-Delta -before $before.UsedRamMB -after $after.UsedRamMB -unit 'MB'
Write-Host "RAM used:          $($ram.Text)" -ForegroundColor $ram.Color

$disk = Format-Delta -before $before.SystemDriveFreeGB -after $after.SystemDriveFreeGB -unit 'GB' -lowerIsBetter $false
Write-Host "System drive free: $($disk.Text)" -ForegroundColor $disk.Color

Write-Host ""
Write-Host "Note: CPU load is a 1-second point sample, not a controlled benchmark." -ForegroundColor DarkGray
Write-Host "Take snapshots under similar conditions (same running apps, idle desktop) for a fair comparison." -ForegroundColor DarkGray
