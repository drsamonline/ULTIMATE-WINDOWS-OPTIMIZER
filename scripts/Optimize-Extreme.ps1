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
Import-Module (Join-Path $PSScriptRoot 'UWO.psd1') -Force

Assert-Admin

# The tweak list comes from the module's profile catalog. The two
# hardware-gated tweaks are stripped out here and re-added below only when
# the RAM/SSD checks pass (they stay in the catalog so Verify-System.ps1 can
# still verify them).
$hardwareGated = @('DisablePagingExecutive','DisableSysMain')
$tweaks = @(Get-ProfileTweak -ProfileName 'Extreme' | Where-Object { $hardwareGated -notcontains $_ })
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
    # Use the supported cmdlet chain: Get-Partition | Get-Disk | Get-PhysicalDisk.
    # The previous approach compared $_.DeviceId (a string) with $partition.DiskNumber
    # (an integer), which silently failed on storage stacks that return non-numeric DeviceIds.
    $partition = Get-Partition -DriveLetter $sysDriveLetter -ErrorAction Stop
    $disk = $partition | Get-Disk -ErrorAction Stop
    $physicalDisk = $disk | Get-PhysicalDisk -ErrorAction Stop
    $isSSD = $physicalDisk.MediaType -eq 'SSD'
} catch { $isSSD = $false }

if ($isSSD) {
    $tweaks += 'DisableSysMain'
    $guards += 'System drive detected as SSD - Superfetch/SysMain will be disabled.'
} else {
    $guards += 'System drive not confirmed as SSD - Superfetch/SysMain left enabled (it helps on HDDs).'
}

Invoke-OptimizationProfile -ProfileName 'Extreme' -Tweaks $tweaks -Guards $guards
