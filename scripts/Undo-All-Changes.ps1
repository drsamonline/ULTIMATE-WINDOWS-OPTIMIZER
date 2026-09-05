<#
    Undo-All-Changes.ps1
    Reads every backup JSON file written by any Optimize-*.ps1 or
    Advanced-Modules.ps1 run and restores each tracked value to its
    original state - registry values, services, hibernation, and power plan.
    This is a genuine full rollback, not a single-service restart.

    By default it processes ALL backup files it finds (oldest first) and
    then archives them so re-running doesn't reapply the same restores
    endlessly. Use -WhatIf to preview without changing anything.

    Registry records are de-duplicated across all backup files by Path\Name,
    keeping the OLDEST record for each value: a later run that recorded an
    already-tweaked value as "original" must never override the true
    pre-toolkit baseline.
#>
param(
    [switch]$WhatIf
)

Import-Module (Join-Path $PSScriptRoot 'UWO.psd1') -Force

Assert-Admin
$logFile = New-LogFile -Name 'UndoAllChanges'

$backupDir = Get-UwoBackupDirectory
$backupFiles = @(Get-ChildItem -Path $backupDir -Filter '*.json' -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime)

if ($backupFiles.Count -eq 0) {
    Write-Host "No backup files found in $backupDir - nothing to undo." -ForegroundColor Yellow
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

$archiveDir = Get-UwoBackupArchiveDirectory
if (-not (Test-Path $archiveDir)) { New-Item -Path $archiveDir -ItemType Directory -Force | Out-Null }

$restoredCount = 0
$failedCount = 0

# --- Pass 1: parse every backup file (oldest first) ------------------------
$allRecords = @()
$parsedFiles = @()
foreach ($file in $backupFiles) {
    Write-Log -Message "Reading backup file: $($file.Name)" -LogFile $logFile -Level INFO
    try {
        $raw = Get-Content -Path $file.FullName -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) {
            Write-Log -Message "Backup file '$($file.Name)' is empty - skipped" -LogFile $logFile -Level WARN
            $parsedFiles += $file
            continue
        }
        $records = @(ConvertFrom-Json -InputObject $raw)
        # Filter out any spurious $null entries that could exist in older
        # backup files written before the Add-BackupRecord null-coercion fix.
        $allRecords += @($records | Where-Object { $null -ne $_ })
        $parsedFiles += $file
    } catch {
        Write-Log -Message "Backup file '$($file.Name)' could not be parsed: $($_.Exception.Message) - skipped" -LogFile $logFile -Level ERROR
        $failedCount++
        $parsedFiles += $file
    }
}

# --- Pass 2: keep the earliest record per registry value -------------------
$recordsToRestore = @(Select-BackupRecordsToRestore -Records $allRecords)
$skipped = $allRecords.Count - $recordsToRestore.Count
if ($skipped -gt 0) {
    Write-Log -Message "Ignoring $skipped duplicate registry record(s) from later runs - the oldest recorded original value wins." -LogFile $logFile -Level INFO
}

# --- Pass 3: restore -------------------------------------------------------
foreach ($record in $recordsToRestore) {
    if ($WhatIf) {
        $target = @(
            (Get-RecordProperty -Record $record -Name 'Path')
            (Get-RecordProperty -Record $record -Name 'Name')
            (Get-RecordProperty -Record $record -Name 'ServiceName')
        ) -join ''
        Write-Host "[WhatIf] Would restore: $(Get-RecordProperty -Record $record -Name 'Type') $target"
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
                # Records written since v6.1 store the clean GUID directly;
                # older ones store the raw, locale-dependent
                # 'powercfg /getactivescheme' output, which is parsed here.
                $guid = Get-PowerSchemeGuid -SchemeOutput ([string](Get-RecordProperty -Record $record -Name 'OriginalGuid'))
                if (-not $guid) {
                    $guid = Get-PowerSchemeGuid -SchemeOutput ([string](Get-RecordProperty -Record $record -Name 'OriginalSchemeRaw'))
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
                    Write-Log -Message "Power plan original GUID could not be determined from the backup record - restore manually via Control Panel > Power Options" -LogFile $logFile -Level WARN
                }
            }
            default {
                Write-Log -Message "Unknown backup record type '$($record.Type)' - skipped" -LogFile $logFile -Level WARN
            }
        }
    } catch {
        Write-Log -Message "Failed to restore a $($record.Type) record: $($_.Exception.Message)" -LogFile $logFile -Level ERROR
        $failedCount++
    }
}

if (-not $WhatIf) {
    foreach ($file in $parsedFiles) {
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
