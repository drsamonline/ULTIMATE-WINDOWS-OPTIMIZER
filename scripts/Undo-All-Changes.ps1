<#
    Undo-All-Changes.ps1
    Reads every backup JSON file written by any Optimize-*.ps1 or
    Advanced-Modules.ps1 run and restores each tracked value to its
    original state - registry values, services, hibernation, and power plan.
    This is a genuine full rollback, not a single-service restart.

    By default it processes ALL backup files it finds (oldest first) and
    then archives them so re-running doesn't reapply the same restores
    endlessly. Use -WhatIf to preview without changing anything.
#>
param(
    [switch]$WhatIf
)

. (Join-Path $PSScriptRoot 'Common-Functions.ps1')

Assert-Admin
$logFile = New-LogFile -Name 'UndoAllChanges'

$backupFiles = Get-ChildItem -Path $Script:BackupDir -Filter '*.json' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime

if ($backupFiles.Count -eq 0) {
    Write-Host "No backup files found in $Script:BackupDir - nothing to undo." -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($backupFiles.Count) backup file(s):" -ForegroundColor Cyan
$backupFiles | ForEach-Object { Write-Host "  - $($_.Name)" }

if (-not $WhatIf) {
    $confirmation = Read-Host "`nRestore ALL tracked changes from these files? (Y/N)"
    if ($confirmation -notmatch '^[Yy]') {
        Write-Host "Aborted - no changes were made." -ForegroundColor Cyan
        exit 0
    }
}

$archiveDir = Join-Path $Script:BackupDir 'restored'
if (-not (Test-Path $archiveDir)) { New-Item -Path $archiveDir -ItemType Directory -Force | Out-Null }

$restoredCount = 0
$failedCount = 0

foreach ($file in $backupFiles) {
    Write-Log -Message "Processing backup file: $($file.Name)" -LogFile $logFile -Level INFO
    try {
        $raw = Get-Content -Path $file.FullName -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) {
            Write-Log -Message "Backup file '$($file.Name)' is empty - skipped" -LogFile $logFile -Level WARN
            if (-not $WhatIf) {
                Move-Item -Path $file.FullName -Destination (Join-Path $archiveDir $file.Name) -Force
            }
            continue
        }
        $records = @(ConvertFrom-Json -InputObject $raw)
        # Filter out any spurious $null entries that could exist in older
        # backup files written before the Add-BackupRecord null-coercion fix.
        $records = @($records | Where-Object { $null -ne $_ })
    } catch {
        Write-Log -Message "Backup file '$($file.Name)' could not be parsed: $($_.Exception.Message) - skipped" -LogFile $logFile -Level ERROR
        $failedCount++
        if (-not $WhatIf) {
            Move-Item -Path $file.FullName -Destination (Join-Path $archiveDir $file.Name) -Force
        }
        continue
    }

    foreach ($record in $records) {
        if ($WhatIf) {
            Write-Host "[WhatIf] Would restore: $($record.Type) $($record.Path)$($record.Name)$($record.ServiceName)"
            continue
        }
        try {
            switch ($record.Type) {
                'Registry' { Restore-RegistryBackupRecord -Record $record -LogFile $logFile; $restoredCount++ }
                'Service'  { Restore-ServiceBackupRecord -Record $record -LogFile $logFile; $restoredCount++ }
                'Hibernation' {
                    & powercfg.exe /hibernate on
                    Write-Log -Message "Hibernation re-enabled" -LogFile $logFile -Level OK
                    $restoredCount++
                }
                'PowerPlan' {
                    # Parse the GUID out of the recorded 'powercfg /getactivescheme'
                    # output (e.g. 'Power Scheme GUID: 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c  (High Performance)').
                    # If parsing fails, fall back to the original warning.
                    $guid = $null
                    if ($record.OriginalGuid) {
                        $match = [regex]::Match($record.OriginalGuid.ToString(), '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})')
                        if ($match.Success) { $guid = $match.Groups[1].Value }
                    }
                    if ($guid) {
                        try {
                            & powercfg.exe /setactive $guid
                            if ($LASTEXITCODE -eq 0) {
                                Write-Log -Message "Power plan restored to original GUID: $guid" -LogFile $logFile -Level OK
                                $restoredCount++
                            } else {
                                Write-Log -Message "powercfg /setactive $guid exited with code $LASTEXITCODE - restore manually via Control Panel > Power Options" -LogFile $logFile -Level WARN
                            }
                        } catch {
                            Write-Log -Message "Failed to restore power plan via powercfg: $($_.Exception.Message) - restore manually via Control Panel > Power Options" -LogFile $logFile -Level WARN
                        }
                    } else {
                        Write-Log -Message "Power plan original GUID could not be parsed from recorded value: '$($record.OriginalGuid)' - restore manually via Control Panel > Power Options" -LogFile $logFile -Level WARN
                    }
                }
                default {
                    Write-Log -Message "Unknown backup record type '$($record.Type)' - skipped" -LogFile $logFile -Level WARN
                }
            }
        } catch {
            Write-Log -Message "Failed to restore a record from $($file.Name): $($_.Exception.Message)" -LogFile $logFile -Level ERROR
            $failedCount++
        }
    }

    if (-not $WhatIf) {
        Move-Item -Path $file.FullName -Destination (Join-Path $archiveDir $file.Name) -Force
    }
}

Write-Host ""
if ($WhatIf) {
    Write-Host "Preview complete - no changes were made (ran with -WhatIf)." -ForegroundColor Cyan
} else {
    Write-Log -Message "Undo complete: $restoredCount record(s) restored, $failedCount failed" -LogFile $logFile -Level OK
    Write-Host "$restoredCount record(s) restored, $failedCount failed." -ForegroundColor $(if ($failedCount -eq 0) { 'Green' } else { 'Yellow' })
    Write-Host "Processed backup files were moved to: $archiveDir" -ForegroundColor Cyan
    Write-Host "A restart is recommended so all services/registry changes take full effect." -ForegroundColor Yellow
}
