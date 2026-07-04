<#
    Hardware-Detection.ps1
    Reports real hardware info via CIM (not the deprecated WMI cmdlets, and
    not hard-coded placeholder text).
#>
. (Join-Path $PSScriptRoot 'Common-Functions.ps1')

$logFile = New-LogFile -Name 'HardwareDetection'

$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$gpus = Get-CimInstance Win32_VideoController
$ram = Get-CimInstance Win32_ComputerSystem
$ramModules = Get-CimInstance Win32_PhysicalMemory
$disks = Get-CimInstance Win32_DiskDrive
$board = Get-CimInstance Win32_BaseBoard

Write-Host ""
Write-Host "=== Hardware Detection ===" -ForegroundColor Cyan

Write-Host "`nCPU:" -ForegroundColor Yellow
Write-Host "  $($cpu.Name)"
Write-Host "  Cores: $($cpu.NumberOfCores)  Logical processors: $($cpu.NumberOfLogicalProcessors)  Max clock: $($cpu.MaxClockSpeed) MHz"
Write-Log -Message "CPU: $($cpu.Name), $($cpu.NumberOfCores) cores / $($cpu.NumberOfLogicalProcessors) threads" -LogFile $logFile

Write-Host "`nGPU(s):" -ForegroundColor Yellow
foreach ($g in $gpus) {
    $vramGB = if ($g.AdapterRAM) { [math]::Round($g.AdapterRAM / 1GB, 2) } else { 0 }
    Write-Host "  $($g.Name)  (VRAM reported: ${vramGB}GB - Win32_VideoController under-reports on some modern GPUs)"
    Write-Log -Message "GPU: $($g.Name)" -LogFile $logFile
}

Write-Host "`nMemory:" -ForegroundColor Yellow
$totalRamGB = [math]::Round($ram.TotalPhysicalMemory / 1GB, 1)
Write-Host "  Total: ${totalRamGB}GB across $($ramModules.Count) module(s)"
foreach ($m in $ramModules) {
    $sizeGB = [math]::Round($m.Capacity / 1GB, 1)
    Write-Host "    - ${sizeGB}GB @ $($m.Speed)MHz ($($m.Manufacturer))"
}
Write-Log -Message "RAM: ${totalRamGB}GB total, $($ramModules.Count) module(s)" -LogFile $logFile

Write-Host "`nStorage:" -ForegroundColor Yellow
foreach ($d in $disks) {
    $sizeGB = [math]::Round($d.Size / 1GB, 1)
    Write-Host "  $($d.Model) - ${sizeGB}GB"
    Write-Log -Message "Disk: $($d.Model), ${sizeGB}GB" -LogFile $logFile
}

try {
    $physicalDisks = Get-PhysicalDisk -ErrorAction Stop
    Write-Host "`nMedia type (from Storage cmdlets):" -ForegroundColor Yellow
    foreach ($pd in $physicalDisks) {
        Write-Host "  $($pd.FriendlyName): $($pd.MediaType)"
        Write-Log -Message "PhysicalDisk: $($pd.FriendlyName) = $($pd.MediaType)" -LogFile $logFile
    }
} catch {
    Write-Host "`n(Storage cmdlets unavailable - SSD/HDD media type could not be determined)" -ForegroundColor DarkGray
}

Write-Host "`nMotherboard:" -ForegroundColor Yellow
Write-Host "  $($board.Manufacturer) $($board.Product)"
Write-Log -Message "Board: $($board.Manufacturer) $($board.Product)" -LogFile $logFile

Write-Host "`nFull details logged to: $logFile" -ForegroundColor Cyan
