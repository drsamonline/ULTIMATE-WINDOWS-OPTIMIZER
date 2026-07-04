<#
    Compatibility-Check.ps1
    Actually inspects the machine and reports PASS/WARN/FAIL per item,
    instead of printing a hard-coded "all checks passed" message.
#>
. (Join-Path $PSScriptRoot 'Common-Functions.ps1')

$logFile = New-LogFile -Name 'CompatibilityCheck'
$results = @()

function Test-Item {
    param([string]$Name, [scriptblock]$Check, [string]$PassDesc, [string]$FailDesc)
    try {
        $ok = & $Check
    } catch { $ok = $false }
    $status = if ($ok) { 'PASS' } else { 'FAIL' }
    $script:results += [pscustomobject]@{ Item = $Name; Status = $status; Detail = if ($ok) { $PassDesc } else { $FailDesc } }
}

$os = Get-CimInstance Win32_OperatingSystem
$ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
$freeSpaceGB = [math]::Round((Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'").FreeSpace / 1GB, 1)
$psVersion = $PSVersionTable.PSVersion

Test-Item -Name 'Administrator privileges' -Check { Test-IsAdmin } `
    -PassDesc 'Running elevated' -FailDesc 'Not elevated - re-run as Administrator'

Test-Item -Name 'Windows version' -Check { [int]$os.BuildNumber -ge 17763 } `
    -PassDesc "Build $($os.BuildNumber) ($($os.Caption))" -FailDesc "Build $($os.BuildNumber) is older than the minimum supported build (17763 / Windows 10 1809)"

Test-Item -Name 'PowerShell version' -Check { $psVersion.Major -ge 5 } `
    -PassDesc "PowerShell $psVersion" -FailDesc "PowerShell $psVersion detected - version 5.1+ required"

Test-Item -Name 'RAM' -Check { $ramGB -ge 4 } `
    -PassDesc "${ramGB}GB detected" -FailDesc "${ramGB}GB detected - 4GB minimum recommended"

Test-Item -Name 'Free disk space on system drive' -Check { $freeSpaceGB -ge 1 } `
    -PassDesc "${freeSpaceGB}GB free on $($env:SystemDrive)" -FailDesc "${freeSpaceGB}GB free - at least 1GB recommended for logs/restore points"

Test-Item -Name 'System Restore availability' -Check {
        (Get-CimInstance -Namespace root/default -ClassName SystemRestore -ErrorAction SilentlyContinue) -ne $null -or
        (Get-Command -Name Checkpoint-Computer -ErrorAction SilentlyContinue) -ne $null
    } -PassDesc 'Checkpoint-Computer cmdlet available' -FailDesc 'System Restore cmdlets unavailable on this SKU - create a manual backup instead'

Write-Host ""
Write-Host "=== Compatibility Check ===" -ForegroundColor Cyan
$results | Format-Table -AutoSize | Out-String | ForEach-Object { Write-Host $_ }

foreach ($r in $results) {
    Write-Log -Message "$($r.Item): $($r.Status) - $($r.Detail)" -LogFile $logFile -Level $(if ($r.Status -eq 'PASS') { 'OK' } else { 'ERROR' })
}

$failCount = ($results | Where-Object { $_.Status -eq 'FAIL' }).Count
if ($failCount -gt 0) {
    Write-Host "$failCount check(s) failed. Resolve these before running an optimization profile." -ForegroundColor Red
} else {
    Write-Host "All checks passed." -ForegroundColor Green
}
