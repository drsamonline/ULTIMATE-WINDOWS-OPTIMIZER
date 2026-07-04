<#
    Advanced-Modules.ps1
    Runs 8 real, independent, backed-up tweaks and reports an ACTUAL count
    of how many succeeded/failed - not a hard-coded "8 modules executed".
#>
. (Join-Path $PSScriptRoot 'Common-Functions.ps1')

Assert-Admin
$logFile = New-LogFile -Name 'AdvancedModules'
$backupFile = New-BackupFile -Name 'AdvancedModules'

$modules = @(
    @{ Name = 'Disable Telemetry (DiagTrack)';        Key = 'DisableTelemetry' }
    @{ Name = 'Disable Start Menu suggestions/ads';    Key = 'DisableStartMenuSuggestions' }
    @{ Name = 'Disable background UWP apps';           Key = 'DisableBackgroundApps' }
    @{ Name = 'Disable Xbox services';                 Key = 'DisableXboxServices' }
    @{ Name = 'Disable Game DVR background recording'; Key = 'DisableGameDVR' }
    @{ Name = 'Set visual effects to Best Performance'; Key = 'VisualEffectsBestPerformance' }
    @{ Name = 'Remove network throttling for multimedia'; Key = 'DisableNetworkThrottling' }
    @{ Name = 'Disable startup animation delay';        Key = 'DisableStartupDelay' }
)

Write-Host ""
Write-Host "=== Advanced Modules ===" -ForegroundColor Cyan
$succeeded = 0
$failed = 0

foreach ($m in $modules) {
    Write-Host "Running: $($m.Name)..." -NoNewline
    try {
        Invoke-Tweak -Key $m.Key -LogFile $logFile -BackupFile $backupFile
        Write-Host " OK" -ForegroundColor Green
        $succeeded++
    } catch {
        Write-Host " FAILED: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log -Message "$($m.Name) failed: $($_.Exception.Message)" -LogFile $logFile -Level ERROR
        $failed++
    }
}

Write-Log -Message "Advanced Modules complete: $succeeded succeeded, $failed failed (out of $($modules.Count))" -LogFile $logFile -Level OK
Write-Host ""
Write-Host "$succeeded of $($modules.Count) module(s) applied successfully." -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Yellow' })
if ($failed -gt 0) { Write-Host "$failed module(s) failed - see log: $logFile" -ForegroundColor Red }
Write-Host "Backup file: $backupFile" -ForegroundColor Cyan
