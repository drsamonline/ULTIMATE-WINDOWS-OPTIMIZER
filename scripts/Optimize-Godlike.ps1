<#
    Optimize-Godlike.ps1
    The most aggressive profile: everything in Extreme, plus disabling
    Windows Search indexing and Xbox services entirely. This trades away
    real functionality (Start menu / File Explorer search will become slow
    or unreliable) for maximum resource availability. Because the tradeoff
    is significant and not reversible-by-reboot, this script requires the
    operator to type CONFIRM before it makes any changes.

    Desktop enthusiast machines only. Do not use on laptops or on any
    machine where fast file search matters to you.
#>
. (Join-Path $PSScriptRoot 'Common-Functions.ps1')

Assert-Admin

Write-Host "=======================================================" -ForegroundColor Yellow
Write-Host " GODLIKE PROFILE - MAXIMUM AGGRESSION" -ForegroundColor Yellow
Write-Host "=======================================================" -ForegroundColor Yellow
Write-Host "This will disable Windows Search indexing (slower file/Start" -ForegroundColor Yellow
Write-Host "menu search), Xbox services, hibernation, and (hardware permitting)" -ForegroundColor Yellow
Write-Host "Superfetch and kernel memory paging. All changes are reversible" -ForegroundColor Yellow
Write-Host "with Undo-All-Changes.ps1, but review the tradeoffs above first." -ForegroundColor Yellow
Write-Host ""
$confirmation = Read-Host "Type CONFIRM to proceed"
if ($confirmation -ne 'CONFIRM') {
    Write-Host "Aborted - no changes were made." -ForegroundColor Cyan
    exit 0
}

$tweaks = @(
    'DisableTelemetry'
    'EnableHAGS'
    'GamingPriorityBoost'
    'DisableNetworkThrottling'
    'DisableGameDVR'
    'PowerPlanHighPerformance'
    'VisualEffectsBestPerformance'
    'DisableHibernation'
    'DisableSearchIndexingService'
    'DisableXboxServices'
)
$guards = @('Windows Search indexing disabled: file/Start-menu search will be noticeably slower.')

try {
    $totalRamGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 0)
} catch { $totalRamGB = 0 }

if ($totalRamGB -ge 16) {
    $tweaks += 'DisablePagingExecutive'
    $guards += "RAM detected: ${totalRamGB}GB - DisablePagingExecutive will be applied."
} else {
    $guards += "RAM detected: ${totalRamGB}GB - DisablePagingExecutive skipped (recommended only for 16GB+ systems)."
}

try {
    $sysDriveLetter = $env:SystemDrive.TrimEnd(':')
    $partition = Get-Partition -DriveLetter $sysDriveLetter -ErrorAction Stop
    $physicalDisk = Get-PhysicalDisk -ErrorAction Stop | Where-Object { $_.DeviceId -eq $partition.DiskNumber }
    $isSSD = $physicalDisk.MediaType -eq 'SSD'
} catch { $isSSD = $false }

if ($isSSD) {
    $tweaks += 'DisableSysMain'
    $guards += 'System drive detected as SSD - Superfetch/SysMain will be disabled.'
} else {
    $guards += 'System drive not confirmed as SSD - Superfetch/SysMain left enabled (it helps on HDDs).'
}

Invoke-OptimizationProfile -ProfileName 'Godlike' -Tweaks $tweaks -Guards $guards
