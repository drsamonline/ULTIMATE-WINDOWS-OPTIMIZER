<#
    Optimize-Extreme.ps1
    Aggressive desktop performance profile for high-end machines. Builds on
    the Gaming profile and adds hibernation removal, and two tweaks that are
    ONLY applied if the hardware actually supports them safely:

      - DisablePagingExecutive: only applied when total RAM >= 16GB, since on
        lower-memory machines it can reduce the memory available to
        applications and cause worse performance, not better.
      - DisableSysMain (Superfetch): only applied when the system drive is
        detected as an SSD, since Superfetch/Prefetch caching is genuinely
        useful on spinning HDDs.

    This is a desktop-only profile. Do not use on laptops (see Optimize-Laptop.ps1).
#>
. (Join-Path $PSScriptRoot 'Common-Functions.ps1')

Assert-Admin

$tweaks = @(
    'DisableTelemetry'
    'EnableHAGS'
    'GamingPriorityBoost'
    'DisableNetworkThrottling'
    'DisableGameDVR'
    'PowerPlanHighPerformance'
    'VisualEffectsBestPerformance'
    'DisableHibernation'
)
$guards = @('This profile removes hibernation (frees disk space equal to installed RAM, but disables Fast Startup and Sleep-to-hibernate).')

# --- Hardware-gated tweaks -------------------------------------------------
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

Invoke-OptimizationProfile -ProfileName 'Extreme' -Tweaks $tweaks -Guards $guards
