<#
    Cleanup-System.ps1
    Cleans user/Windows temp folders and the Recycle Bin, and reports the
    ACTUAL disk space freed (measured before/after), not a canned "5-15GB" claim.
#>
. (Join-Path $PSScriptRoot 'Common-Functions.ps1')

Assert-Admin
$logFile = New-LogFile -Name 'Cleanup'

function Get-FreeSpaceGB {
    (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'").FreeSpace / 1GB
}

$before = Get-FreeSpaceGB
Write-Log -Message "Free space before cleanup: $([math]::Round($before,2)) GB" -LogFile $logFile -Level INFO

$targets = @(
    "$env:TEMP\*"
    "$env:WINDIR\Temp\*"
    "$env:WINDIR\SoftwareDistribution\Download\*"
    "$env:LOCALAPPDATA\Microsoft\Windows\INetCache\*"
)

foreach ($target in $targets) {
    try {
        Remove-Item -Path $target -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log -Message "Cleared: $target" -LogFile $logFile -Level INFO
    } catch {
        Write-Log -Message "Could not fully clear $target : $($_.Exception.Message)" -LogFile $logFile -Level WARN
    }
}

try {
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    Write-Log -Message "Recycle Bin emptied" -LogFile $logFile -Level INFO
} catch {
    Write-Log -Message "Recycle Bin could not be emptied: $($_.Exception.Message)" -LogFile $logFile -Level WARN
}

Start-Sleep -Seconds 1
$after = Get-FreeSpaceGB
$freedGB = [math]::Round($after - $before, 2)

Write-Log -Message "Free space after cleanup: $([math]::Round($after,2)) GB" -LogFile $logFile -Level INFO
Write-Log -Message "Space freed: $freedGB GB (measured, not estimated)" -LogFile $logFile -Level OK

Write-Host ""
Write-Host "=== Cleanup Complete ===" -ForegroundColor Green
Write-Host "Free space before: $([math]::Round($before,2)) GB"
Write-Host "Free space after:  $([math]::Round($after,2)) GB"
Write-Host "Space freed:       $freedGB GB" -ForegroundColor Cyan
Write-Host "(Actual results depend entirely on how much temp/cache data existed on this machine.)" -ForegroundColor DarkGray
