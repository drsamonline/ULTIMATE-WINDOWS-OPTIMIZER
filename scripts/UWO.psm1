#Requires -Version 5.1
<#
    UWO.psm1
    ---------------------
    Shared engine for Ultimate Windows Optimizer, packaged as a PowerShell
    module. Every Optimize-*.ps1 profile script, and the utility scripts,
    import this module (Common-Functions.ps1 remains as a thin backward
    compatibility shim). It provides:

      - Admin / environment checks
      - Logging
      - Registry value backup + safe-set + restore  (real rollback, not cosmetic)
      - Windows service backup + safe-set + restore
      - Backup-file retention/pruning
      - A system snapshot function used by Performance-Monitor / Compare-Results
      - A tweak catalog + generic profile runner, so every optimization
        profile is a genuinely different, explicit list of tweaks rather
        than a copy-pasted script with a different label.
      - The tweak/profile catalog itself, exposed through accessor functions
        so profile and utility scripts share a single source of truth.

    Nothing in this file requires internet access. Nothing in this file
    is destructive without first writing a JSON backup record that
    Undo-All-Changes.ps1 can read to restore the exact previous state.

    v6.2.0 notes:
      - The log/backup/snapshot directories are now created lazily, the first
        time something is actually written, instead of at import time. A
        read-only utility (or a -WhatIf preview) no longer touches the disk.
      - Services, power plans and hibernation are now idempotent and
        de-duplicated on undo, exactly like registry values (see
        Set-ServiceStateSafe, the PowerPlan* tweaks and
        Select-BackupRecordsToRestore).
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# $env:UWO_LOG_ROOT lets tests (and advanced users) redirect logs/backups/
# snapshots away from the real %USERPROFILE%\OptimizationLogs tree.
$Script:UserProfileDir = if ($env:UWO_LOG_ROOT) { $env:UWO_LOG_ROOT }
                         elseif ($env:USERPROFILE) { Join-Path $env:USERPROFILE 'OptimizationLogs' }
                         else { Join-Path $HOME 'OptimizationLogs' }

$Script:RootLogDir     = $Script:UserProfileDir
$Script:BackupDir      = Join-Path $Script:RootLogDir 'Backups'
$Script:SnapshotDir    = Join-Path $Script:RootLogDir 'Snapshots'
$Script:BackupArchiveDir = Join-Path $Script:BackupDir 'restored'

# Directories are created on first write, not at import time (see
# Ensure-Directory), so importing the module has no filesystem side effects.

function Get-UwoLogDirectory      { return $Script:RootLogDir }
function Get-UwoBackupDirectory   { return $Script:BackupDir }
function Get-UwoBackupArchiveDirectory { return $Script:BackupArchiveDir }
function Get-UwoSnapshotDirectory { return $Script:SnapshotDir }

# ---------------------------------------------------------------------------
# Environment checks
# ---------------------------------------------------------------------------

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Admin {
    if (-not (Test-IsAdmin)) {
        Write-Host "[ERROR] This script must be run from an elevated (Administrator) PowerShell session." -ForegroundColor Red
        Write-Host "Right-click the launcher .bat file and choose 'Run as administrator', or run PowerShell as Administrator." -ForegroundColor Yellow
        exit 1
    }
}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

function Ensure-Directory {
    # Creates a directory only when it is about to be written to, so simply
    # importing the module (or running a read-only utility) leaves no trace.
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) { New-Item -Path $Path -ItemType Directory -Force | Out-Null }
}

function New-LogFile {
    param([Parameter(Mandatory)][string]$Name)
    Ensure-Directory -Path $Script:RootLogDir
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $path = Join-Path $Script:RootLogDir "$Name`_$timestamp.log"
    New-Item -Path $path -ItemType File -Force | Out-Null
    return $path
}

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][string]$LogFile,
        [ValidateSet('INFO','WARN','ERROR','OK')][string]$Level = 'INFO'
    )
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Add-Content -Path $LogFile -Value $line
    switch ($Level) {
        'OK'    { Write-Host $Message -ForegroundColor Green }
        'WARN'  { Write-Host $Message -ForegroundColor Yellow }
        'ERROR' { Write-Host $Message -ForegroundColor Red }
        default { Write-Host $Message }
    }
}

# ---------------------------------------------------------------------------
# Backup file handling (JSON, one file per script run)
# ---------------------------------------------------------------------------

function New-BackupFile {
    param([Parameter(Mandatory)][string]$Name)
    Ensure-Directory -Path $Script:BackupDir
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $path = Join-Path $Script:BackupDir "$Name`_$timestamp.json"
    # Write a literal '[]' so the file is a valid empty JSON array.
    # (Piping @() to ConvertTo-Json produces no output on PowerShell 5.1,
    #  which left the file empty and broke every downstream reader.)
    Set-Content -Path $path -Value '[]' -Encoding UTF8
    return $path
}

function Remove-OldBackupFile {
    <#
        Prunes accumulated backup JSON files. A file is pruned only when it is
        BOTH older than -MaxAgeDays AND outside the newest -KeepCount files in
        its directory, so a conservative default never removes recent history.

        Un-restored (pending) backups in the Backups root are left alone unless
        -IncludePending is specified: they are the only way to undo changes that
        have not been undone yet. Backups already processed by
        Undo-All-Changes.ps1 (moved to the 'restored' subfolder) are pruned by
        default. Everything pruned is logged.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)][string]$LogFile,
        [ValidateRange(0, 10000)][int]$KeepCount = 20,
        [ValidateRange(1, 36500)][int]$MaxAgeDays = 30,
        [switch]$IncludePending
    )

    $cutoff = (Get-Date).AddDays(-$MaxAgeDays)
    $targets = @(
        [pscustomobject]@{ Directory = $Script:BackupArchiveDir; Label = 'restored (already undone)' }
    )
    if ($IncludePending) {
        $targets += [pscustomobject]@{ Directory = $Script:BackupDir; Label = 'pending (not yet undone)' }
    }

    $prunedCount = 0
    foreach ($target in $targets) {
        if (-not (Test-Path $target.Directory)) { continue }
        $files = @(Get-ChildItem -Path $target.Directory -Filter '*.json' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending)
        if ($files.Count -le $KeepCount) {
            Write-Log -Message "Retention: $($files.Count) $($target.Label) backup file(s) - within the keep-last-$KeepCount limit, nothing pruned." -LogFile $LogFile -Level INFO
            continue
        }
        $candidates = @($files | Select-Object -Skip $KeepCount | Where-Object { $_.LastWriteTime -lt $cutoff })
        foreach ($file in $candidates) {
            if ($PSCmdlet.ShouldProcess($file.FullName, 'Remove backup file')) {
                Remove-Item -Path $file.FullName -Force
                Write-Log -Message "Retention: pruned $($target.Label) backup '$($file.Name)' (last written $($file.LastWriteTime))" -LogFile $LogFile -Level OK
            } else {
                Write-Log -Message "Retention: would prune $($target.Label) backup '$($file.Name)' (last written $($file.LastWriteTime))" -LogFile $LogFile -Level INFO
            }
            $prunedCount++
        }
        $keptOld = @($files | Select-Object -Skip $KeepCount | Where-Object { $_.LastWriteTime -ge $cutoff }).Count
        if ($keptOld -gt 0) {
            Write-Log -Message "Retention: kept $keptOld $($target.Label) backup file(s) newer than $MaxAgeDays day(s)." -LogFile $LogFile -Level INFO
        }
    }

    if (-not $IncludePending) {
        Write-Log -Message 'Retention: pending (not yet undone) backups were left untouched - re-run with -IncludePending to prune those too.' -LogFile $LogFile -Level INFO
    }
    return $prunedCount
}

function Get-RecordProperty {
    # Backup records are read back as PSCustomObjects and older files may not
    # contain newer fields, so every read goes through this helper (referencing
    # a missing property directly is an error under Set-StrictMode).
    param(
        [Parameter(Mandatory)]$Record,
        [Parameter(Mandatory)][string]$Name,
        $Default = $null
    )
    if ($null -eq $Record) { return $Default }
    if ($Record -is [hashtable]) {
        if ($Record.ContainsKey($Name)) { return $Record[$Name] }
        return $Default
    }
    $prop = $Record.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $Default }
    return $prop.Value
}

function Add-BackupRecord {
    param(
        [Parameter(Mandatory)][string]$BackupFile,
        [Parameter(Mandatory)][hashtable]$Record
    )
    # Read defensively - an empty or corrupted file should never crash the run.
    $records = $null
    try {
        $raw = Get-Content -Path $BackupFile -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) {
            $records = @()
        } else {
            $records = @(ConvertFrom-Json -InputObject $raw)
            # ConvertFrom-Json returns $null for an empty literal 'null' or
            # for an empty file coerced through the pipeline. Normalize.
            if ($null -eq $records) { $records = @() }
            # Filter out any spurious $null entries from older backup files
            # that were created before this fix.
            $records = @($records | Where-Object { $null -ne $_ })
        }
    } catch {
        Write-Warning "Backup file '$BackupFile' was unreadable ($($_.Exception.Message)); starting a fresh record list."
        $records = @()
    }
    $records += [pscustomobject]$Record
    $records | ConvertTo-Json -Depth 5 | Set-Content -Path $BackupFile -Encoding UTF8
}

# ---------------------------------------------------------------------------
# Registry: safe set (backs up the previous value first) + restore
# ---------------------------------------------------------------------------

function ConvertTo-ComparableRegistryValue {
    # Normalizes a registry value so a stored value and a desired value can be
    # compared regardless of how PowerShell surfaces them (a DWord written as
    # 0xffffffff reads back as -1, MultiString/Binary read back as arrays).
    param($Value, [Parameter(Mandatory)][string]$Type)
    if ($null -eq $Value) { return $null }
    switch ($Type) {
        'DWord'  { try { return [uint32](([int64]$Value) -band 0xFFFFFFFFL) } catch { return $null } }
        'QWord'  { try { return [int64]$Value } catch { return $null } }
        'Binary' { return (@($Value) | ForEach-Object { [string][int]$_ }) -join ',' }
        'MultiString' { return (@($Value) | ForEach-Object { [string]$_ }) -join "`0" }
        default  { return [string]$Value }
    }
}

function Test-RegistryValueMatch {
    param($CurrentValue, $DesiredValue, [Parameter(Mandatory)][string]$Type)
    $current = ConvertTo-ComparableRegistryValue -Value $CurrentValue -Type $Type
    $desired = ConvertTo-ComparableRegistryValue -Value $DesiredValue -Type $Type
    if ($null -eq $current -or $null -eq $desired) { return $false }
    return ($current -eq $desired)
}

function Test-RegistryKeyEmpty {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) { return $false }
    $key = Get-Item -Path $Path
    return ($key.SubKeyCount -eq 0 -and $key.ValueCount -eq 0)
}

function Set-RegistryValueSafe {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [ValidateSet('DWord','String','QWord','Binary','MultiString','ExpandString')][string]$Type = 'DWord',
        [Parameter(Mandatory)][string]$LogFile,
        [Parameter(Mandatory)][string]$BackupFile
    )
    $keyCreated = $false
    try {
        $existed = $false
        $originalValue = $null
        if (Test-Path $Path) {
            $prop = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
            if ($null -ne $prop -and ($prop.PSObject.Properties.Name -contains $Name)) {
                $existed = $true
                $originalValue = $prop.$Name
            }
        }

        # Idempotency: if the value is already what we would write, change
        # nothing and record nothing. Otherwise a second run of the same
        # profile would store the already-tweaked value as the "original".
        if ($existed -and (Test-RegistryValueMatch -CurrentValue $originalValue -DesiredValue $Value -Type $Type)) {
            Write-Log -Message "$Path\$Name is already set to $Value - skipped (no backup record written)" -LogFile $LogFile -Level INFO
            return $true
        }

        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
            $keyCreated = $true
        }

        # The backup record is written only after the value has actually been
        # set, so a failed write cannot leave a phantom record behind for
        # Undo-All-Changes.ps1 to "restore".
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
        Add-BackupRecord -BackupFile $BackupFile -Record @{
            Type          = 'Registry'
            Path          = $Path
            Name          = $Name
            Existed       = $existed
            OriginalValue = $originalValue
            ValueType     = $Type
            KeyCreated    = $keyCreated
        }

        Write-Log -Message "Set $Path\$Name = $Value" -LogFile $LogFile -Level INFO
        return $true
    } catch {
        Write-Log -Message "FAILED to set $Path\$Name : $($_.Exception.Message)" -LogFile $LogFile -Level ERROR
        if ($keyCreated) {
            try {
                if (Test-RegistryKeyEmpty -Path $Path) {
                    Remove-Item -Path $Path -Force
                    Write-Log -Message "Removed registry key $Path that was created for the failed write" -LogFile $LogFile -Level INFO
                }
            } catch {
                Write-Log -Message "Could not remove registry key $Path after a failed write: $($_.Exception.Message)" -LogFile $LogFile -Level WARN
            }
        }
        return $false
    }
}

function Restore-RegistryBackupRecord {
    param(
        [Parameter(Mandatory)]$Record,
        [Parameter(Mandatory)][string]$LogFile
    )
    try {
        if ($Record.Existed) {
            New-ItemProperty -Path $Record.Path -Name $Record.Name -Value $Record.OriginalValue -PropertyType $Record.ValueType -Force | Out-Null
            Write-Log -Message "Restored $($Record.Path)\$($Record.Name) to original value ($($Record.OriginalValue))" -LogFile $LogFile -Level OK
        } else {
            if (Test-Path $Record.Path) {
                Remove-ItemProperty -Path $Record.Path -Name $Record.Name -ErrorAction SilentlyContinue
                Write-Log -Message "Removed $($Record.Path)\$($Record.Name) (did not exist before optimization)" -LogFile $LogFile -Level OK

                # The key itself was created by this toolkit: remove it too,
                # but only if nothing else was added to it in the meantime.
                if ((Get-RecordProperty -Record $Record -Name 'KeyCreated' -Default $false) -and (Test-RegistryKeyEmpty -Path $Record.Path)) {
                    Remove-Item -Path $Record.Path -Force
                    Write-Log -Message "Removed registry key $($Record.Path) (created by this toolkit and now empty)" -LogFile $LogFile -Level OK
                }
            }
        }
    } catch {
        Write-Log -Message "FAILED to restore $($Record.Path)\$($Record.Name) : $($_.Exception.Message)" -LogFile $LogFile -Level ERROR
    }
}

# ---------------------------------------------------------------------------
# Services: safe set (backs up previous StartupType) + restore
# ---------------------------------------------------------------------------

function ConvertTo-CimFilterLiteral {
    # Escapes a value for use inside a single-quoted WQL string literal.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    # In a -replace replacement string a backslash is literal (only '$' is
    # special), so '\\' produces the doubled backslash WQL expects.
    return ($Value -replace '\\', '\\' -replace "'", "\'")
}

function Get-ServiceStartMode {
    # Returns the Win32_Service-style start mode ('Auto'/'Manual'/'Disabled'/
    # 'Boot'/'System') for a ServiceController, preferring the object we
    # already have over a second, string-interpolated CIM query.
    param([Parameter(Mandatory)]$Service)
    $startType = Get-RecordProperty -Record $Service -Name 'StartType'
    if ($startType) {
        switch ([string]$startType) {
            'Automatic'  { return 'Auto' }
            'Boot'       { return 'Boot' }
            'System'     { return 'System' }
            'Manual'     { return 'Manual' }
            'Disabled'   { return 'Disabled' }
            default      { return [string]$startType }
        }
    }
    # PowerShell versions without ServiceController.StartType: fall back to CIM
    # with a safely escaped filter.
    $filter = "Name='{0}'" -f (ConvertTo-CimFilterLiteral -Value $Service.Name)
    $wmiSvc = Get-CimInstance -ClassName Win32_Service -Filter $filter
    return $wmiSvc.StartMode
}

function Set-ServiceStateSafe {
    param(
        [Parameter(Mandatory)][string]$ServiceName,
        [ValidateSet('Automatic','Manual','Disabled')][string]$StartupType,
        [switch]$StopNow,
        [Parameter(Mandatory)][string]$LogFile,
        [Parameter(Mandatory)][string]$BackupFile
    )
    try {
        $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if (-not $svc) {
            Write-Log -Message "Service '$ServiceName' not found on this system - skipped" -LogFile $LogFile -Level WARN
            return $false
        }

        $currentStartMode = Get-ServiceStartMode -Service $svc   # Auto / Manual / Disabled / Boot / System
        $targetStartMode  = switch ($StartupType) {
            'Automatic' { 'Auto' }
            'Manual'    { 'Manual' }
            'Disabled'  { 'Disabled' }
        }

        # Idempotency, matching Set-RegistryValueSafe: if the service is already
        # in the desired start mode, change nothing and record nothing, so a
        # second run of the same profile cannot store the already-tweaked mode
        # as the "original" (which would corrupt undo).
        if ($currentStartMode -eq $targetStartMode) {
            Write-Log -Message "Service '$ServiceName' is already set to $targetStartMode - skipped (no backup record written)" -LogFile $LogFile -Level INFO
            return $true
        }

        $originalStatus = $svc.Status

        Set-Service -Name $ServiceName -StartupType $StartupType
        if ($StopNow -and $svc.Status -eq 'Running') {
            Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        }

        # The backup record is written only after the change actually
        # succeeded, the same guarantee the registry path gives.
        Add-BackupRecord -BackupFile $BackupFile -Record @{
            Type               = 'Service'
            ServiceName        = $ServiceName
            OriginalStartMode  = $currentStartMode
            OriginalStatus     = $originalStatus.ToString()
        }

        Write-Log -Message "Service '$ServiceName' set to $StartupType (was $currentStartMode)" -LogFile $LogFile -Level INFO
        return $true
    } catch {
        Write-Log -Message "FAILED to change service '$ServiceName' : $($_.Exception.Message)" -LogFile $LogFile -Level ERROR
        return $false
    }
}

function Get-PowerSchemeGuid {
    # Extracts the scheme GUID from 'powercfg /getactivescheme' output. Doing
    # this at CAPTURE time keeps undo independent of the machine's locale.
    param([AllowNull()][AllowEmptyString()][string]$SchemeOutput)
    if ([string]::IsNullOrWhiteSpace($SchemeOutput)) { return $null }
    $match = [regex]::Match($SchemeOutput, '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})')
    if ($match.Success) { return $match.Groups[1].Value }
    return $null
}

# Well-known power-scheme alias GUIDs (locale-independent identifiers for the
# standard Windows plans), used for idempotency checks.
$Script:PowerSchemeGuids = @{
    'SCHEME_BALANCED' = '381b4222-f694-41f0-9685-ff5bb260df2e'
    'SCHEME_MIN'      = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'   # High Performance
    'SCHEME_MAX'      = 'a1841308-3541-4fab-bc81-f71556f20b4a'   # Power Saver
}

function Get-ActivePowerSchemeGuid {
    # Returns the GUID of the active power scheme, or $null if it cannot be read.
    try {
        $raw = (powercfg.exe /getactivescheme) -join ''
        return Get-PowerSchemeGuid -SchemeOutput $raw
    } catch {
        return $null
    }
}

function Select-BackupRecordsToRestore {
    <#
        Takes every backup record across all backup files in OLDEST-FIRST order
        and removes duplicate records for the same logical target, keeping the
        earliest one. Without this, a second run of the same profile - which
        would have recorded the already-tweaked state as "original" - could
        override the true pre-toolkit baseline during undo.

        De-duplication keys (earliest record per key wins):
          Registry    -> Path\Name
          Service     -> ServiceName
          PowerPlan   -> a single constant key (there is only one active plan)
          Hibernation -> a single constant key (there is only one hibernation state)
        Any other record type is never de-duplicated.
    #>
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Records)

    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $kept = @()
    foreach ($record in $Records) {
        if ($null -eq $record) { continue }
        $type = Get-RecordProperty -Record $record -Name 'Type'
        $key = $null
        switch ($type) {
            'Registry'    { $key = 'R|{0}\{1}' -f (Get-RecordProperty -Record $record -Name 'Path'), (Get-RecordProperty -Record $record -Name 'Name') }
            'Service'     { $key = 'S|{0}' -f (Get-RecordProperty -Record $record -Name 'ServiceName') }
            'PowerPlan'   { $key = 'P|active' }
            'Hibernation' { $key = 'H|state' }
        }
        if ($key -and -not $seen.Add($key)) { continue }
        $kept += $record
    }
    return $kept
}

function Invoke-NativeCommand {
    # Wrapper that runs a native exe and throws on a non-zero exit code.
    # PowerShell's `&` operator does NOT throw on native-command failures -
    # without this, tweaks like DisableHibernation / PowerPlan* would silently
    # record a backup even when the underlying powercfg call failed.
    param(
        [Parameter(Mandatory)][string]$ExePath,
        [string[]]$Arguments = @()
    )
    & $ExePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$ExePath exited with code $LASTEXITCODE"
    }
}

function Restore-ServiceBackupRecord {
    param(
        [Parameter(Mandatory)]$Record,
        [Parameter(Mandatory)][string]$LogFile
    )
    try {
        # Win32_Service StartMode can be: Boot, System, Auto, Manual, Disabled.
        # Set-Service -StartupType only accepts Automatic/Manual/Disabled/Automatic (Delayed Start).
        # For Boot/System services (kernel drivers, etc.), Set-Service cannot restore the original
        # start mode, so we log a clear warning and skip rather than silently downgrading to Manual.
        $startupTypeMap = @{ 'Auto' = 'Automatic'; 'Manual' = 'Manual'; 'Disabled' = 'Disabled' }
        $mapped = $startupTypeMap[$Record.OriginalStartMode]
        if (-not $mapped) {
            Write-Log -Message "Service '$($Record.ServiceName)' original start mode was '$($Record.OriginalStartMode)' (Boot/System) - cannot be restored via Set-Service. Skipping startup-type restore; please verify manually." -LogFile $LogFile -Level WARN
            return
        }
        Set-Service -Name $Record.ServiceName -StartupType $mapped -ErrorAction SilentlyContinue
        if ($Record.OriginalStatus -eq 'Running') {
            Start-Service -Name $Record.ServiceName -ErrorAction SilentlyContinue
        }
        Write-Log -Message "Restored service '$($Record.ServiceName)' to $mapped (was $($Record.OriginalStatus))" -LogFile $LogFile -Level OK
    } catch {
        Write-Log -Message "FAILED to restore service '$($Record.ServiceName)' : $($_.Exception.Message)" -LogFile $LogFile -Level ERROR
    }
}

# ---------------------------------------------------------------------------
# System snapshot (used by Performance-Monitor.ps1 and Compare-Results.ps1)
# ---------------------------------------------------------------------------

function Get-SystemSnapshot {
    param([string]$Label = 'Snapshot')

    $os      = Get-CimInstance -ClassName Win32_OperatingSystem
    $cpu     = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1
    $disk    = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"
    $uptime  = (Get-Date) - $os.LastBootUpTime

    # A short CPU sample (non-blocking, ~1 second)
    $cpuCounter = Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 1
    $cpuLoad = $cpuCounter.CounterSamples[0].CookedValue

    $totalRamMB = [math]::Round($os.TotalVisibleMemorySize / 1KB, 0)
    $freeRamMB  = [math]::Round($os.FreePhysicalMemory / 1KB, 0)
    $usedRamMB  = $totalRamMB - $freeRamMB

    $topProcesses = Get-Process | Sort-Object CPU -Descending | Select-Object -First 5 -Property Name,
        @{N='CPU_s';E={[math]::Round($_.CPU,1)}},
        @{N='WorkingSetMB';E={[math]::Round($_.WorkingSet64/1MB,1)}}

    [pscustomobject]@{
        Label            = $Label
        Timestamp        = Get-Date -Format 'o'
        OSBuild          = $os.BuildNumber
        CPUName          = $cpu.Name
        CPULoadPercent   = [math]::Round($cpuLoad, 1)
        TotalRamMB       = $totalRamMB
        UsedRamMB        = $usedRamMB
        FreeRamMB        = $freeRamMB
        SystemDriveFreeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
        SystemDriveSizeGB = [math]::Round($disk.Size / 1GB, 2)
        UptimeHours      = [math]::Round($uptime.TotalHours, 2)
        TopProcesses     = $topProcesses
    }
}

function Save-SystemSnapshot {
    param([Parameter(Mandatory)][string]$Label)
    Ensure-Directory -Path $Script:SnapshotDir
    $snapshot = Get-SystemSnapshot -Label $Label
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $safeLabel = ($Label -replace '[^a-zA-Z0-9_-]', '_')
    $path = Join-Path $Script:SnapshotDir "$safeLabel`_$timestamp.json"
    $snapshot | ConvertTo-Json -Depth 5 | Set-Content -Path $path
    return $path
}

# ---------------------------------------------------------------------------
# Tweak catalog
# Each tweak is a real, independent, documented change. Profiles reference
# tweaks by key. This is what makes each optimization profile genuinely
# different from the others (unlike v5.1, where every profile secretly
# ran the same four tweaks under a different label).
# ---------------------------------------------------------------------------

# USB selective suspend lives inside the ACTIVE power scheme, under the USB
# settings subgroup. These GUIDs are the documented Windows identifiers.
$Script:UsbSubgroupGuid        = '2a737441-1930-4402-8d77-b2bebba308a3'
$Script:UsbSuspendSettingGuid  = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'

function Get-UsbSelectiveSuspendKey {
    # Builds the registry path of the USB selective-suspend setting for a given
    # power-scheme GUID, so both the tweak and its verification share one source.
    param([Parameter(Mandatory)][string]$SchemeGuid)
    return "HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\$SchemeGuid\$($Script:UsbSubgroupGuid)\$($Script:UsbSuspendSettingGuid)"
}

function Invoke-Tweak {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$LogFile,
        [Parameter(Mandatory)][string]$BackupFile
    )

    switch ($Key) {

        'DisableHibernation' {
            # Removes hibernation (frees disk space equal to RAM size); NOT applied to laptop profile.
            # State-aware: if hibernation is already off, nothing is changed and nothing is recorded.
            try {
                $powerKey  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'
                $hiberProp = Get-ItemProperty -Path $powerKey -Name 'HibernateEnabled' -ErrorAction SilentlyContinue
                $wasEnabled = ($null -ne $hiberProp) -and ([int]$hiberProp.HibernateEnabled -eq 1)

                if (-not $wasEnabled) {
                    Write-Log -Message 'Hibernation is already disabled (or not enabled) - skipped (no backup record written)' -LogFile $LogFile -Level INFO
                    return $true
                }

                Invoke-NativeCommand -ExePath 'powercfg.exe' -Arguments '/hibernate','off'
                Write-Log -Message 'Hibernation disabled via powercfg (frees disk space equal to RAM size)' -LogFile $LogFile -Level OK
                Add-BackupRecord -BackupFile $BackupFile -Record @{ Type = 'Hibernation'; OriginalState = 'enabled' }
                return $true
            } catch {
                Write-Log -Message "FAILED to disable hibernation: $($_.Exception.Message)" -LogFile $LogFile -Level ERROR
                return $false
            }
        }

        'PowerPlanHighPerformance' {
            # Idempotent: if the active plan is already High Performance, nothing
            # is changed and nothing is recorded. The active GUID is captured
            # BEFORE switching so undo can restore the user's original plan.
            try {
                $originalScheme = (powercfg.exe /getactivescheme) -join ''
                $originalGuid   = Get-PowerSchemeGuid -SchemeOutput $originalScheme

                if ($originalGuid -and $originalGuid -eq $Script:PowerSchemeGuids['SCHEME_MIN']) {
                    Write-Log -Message 'Active power plan is already High Performance - skipped (no backup record written)' -LogFile $LogFile -Level INFO
                    return $true
                }

                Invoke-NativeCommand -ExePath 'powercfg.exe' -Arguments '/setactive','SCHEME_MIN'
                Write-Log -Message 'Power plan set to High Performance' -LogFile $LogFile -Level OK
                Add-BackupRecord -BackupFile $BackupFile -Record @{ Type = 'PowerPlan'; OriginalGuid = $originalGuid; OriginalSchemeRaw = $originalScheme }
                return $true
            } catch {
                Write-Log -Message "FAILED to set High Performance power plan: $($_.Exception.Message)" -LogFile $LogFile -Level ERROR
                return $false
            }
        }

        'PowerPlanBalanced' {
            # Symmetric with PowerPlanHighPerformance, including the idempotency check.
            try {
                $originalScheme = (powercfg.exe /getactivescheme) -join ''
                $originalGuid   = Get-PowerSchemeGuid -SchemeOutput $originalScheme

                if ($originalGuid -and $originalGuid -eq $Script:PowerSchemeGuids['SCHEME_BALANCED']) {
                    Write-Log -Message 'Active power plan is already Balanced - skipped (no backup record written)' -LogFile $LogFile -Level INFO
                    return $true
                }

                Invoke-NativeCommand -ExePath 'powercfg.exe' -Arguments '/setactive','SCHEME_BALANCED'
                Write-Log -Message 'Power plan set to Balanced' -LogFile $LogFile -Level OK
                Add-BackupRecord -BackupFile $BackupFile -Record @{ Type = 'PowerPlan'; OriginalGuid = $originalGuid; OriginalSchemeRaw = $originalScheme }
                return $true
            } catch {
                Write-Log -Message "FAILED to set Balanced power plan: $($_.Exception.Message)" -LogFile $LogFile -Level ERROR
                return $false
            }
        }

        'DisableXboxServices' {
            $ok = $true
            foreach ($svc in @('XblAuthManager','XblGameSave','XboxNetApiSvc','XboxGipSvc')) {
                $stepOk = Set-ServiceStateSafe -ServiceName $svc -StartupType Disabled -StopNow -LogFile $LogFile -BackupFile $BackupFile
                if (-not $stepOk) { $ok = $false }
            }
            return $ok
        }

        'DisableGameDVR' {
            return Set-RegistryValueSafe -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -Value 0 -Type DWord -LogFile $LogFile -BackupFile $BackupFile
        }

        'DisableTelemetry' {
            return Set-ServiceStateSafe -ServiceName 'DiagTrack' -StartupType Manual -StopNow -LogFile $LogFile -BackupFile $BackupFile
        }

        'EnableHAGS' {
            return Set-RegistryValueSafe -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' `
                -Name 'HwSchMode' -Value 2 -Type DWord -LogFile $LogFile -BackupFile $BackupFile
        }

        'DisableHAGS' {
            return Set-RegistryValueSafe -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' `
                -Name 'HwSchMode' -Value 1 -Type DWord -LogFile $LogFile -BackupFile $BackupFile
        }

        'GamingPriorityBoost' {
            return Set-RegistryValueSafe -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' `
                -Name 'Win32PrioritySeparation' -Value 38 -Type DWord -LogFile $LogFile -BackupFile $BackupFile
        }

        'BalancedPrioritySeparation' {
            return Set-RegistryValueSafe -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' `
                -Name 'Win32PrioritySeparation' -Value 2 -Type DWord -LogFile $LogFile -BackupFile $BackupFile
        }

        'ServerPrioritySeparation' {
            return Set-RegistryValueSafe -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' `
                -Name 'Win32PrioritySeparation' -Value 24 -Type DWord -LogFile $LogFile -BackupFile $BackupFile
        }

        'DisableNetworkThrottling' {
            return Set-RegistryValueSafe -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' `
                -Name 'NetworkThrottlingIndex' -Value 0xffffffff -Type DWord -LogFile $LogFile -BackupFile $BackupFile
        }

        'LowerSystemResponsivenessForMultimedia' {
            return Set-RegistryValueSafe -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' `
                -Name 'SystemResponsiveness' -Value 10 -Type DWord -LogFile $LogFile -BackupFile $BackupFile
        }

        'DisableStartupDelay' {
            return Set-RegistryValueSafe -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' `
                -Name 'StartupDelayInMSec' -Value 0 -Type DWord -LogFile $LogFile -BackupFile $BackupFile
        }

        'DisableStartMenuSuggestions' {
            $base = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
            $ok1 = Set-RegistryValueSafe -Path $base -Name 'SubscribedContent-338388Enabled' -Value 0 -Type DWord -LogFile $LogFile -BackupFile $BackupFile
            $ok2 = Set-RegistryValueSafe -Path $base -Name 'SystemPaneSuggestionsEnabled' -Value 0 -Type DWord -LogFile $LogFile -BackupFile $BackupFile
            return ($ok1 -and $ok2)
        }

        'DisableBackgroundApps' {
            return Set-RegistryValueSafe -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' `
                -Name 'GlobalUserDisabled' -Value 1 -Type DWord -LogFile $LogFile -BackupFile $BackupFile
        }

        'VisualEffectsBestPerformance' {
            return Set-RegistryValueSafe -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' `
                -Name 'VisualFXSetting' -Value 2 -Type DWord -LogFile $LogFile -BackupFile $BackupFile
        }

        'VisualEffectsBalanced' {
            # VisualFXSetting: 0 = Let Windows choose (the balanced default),
            # 1 = best appearance, 2 = best performance, 3 = custom. The
            # balanced option is 0 - the earlier version wrote 3, which is
            # actually "Custom" and did not correspond to a balanced preset.
            return Set-RegistryValueSafe -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' `
                -Name 'VisualFXSetting' -Value 0 -Type DWord -LogFile $LogFile -BackupFile $BackupFile
        }

        'DisableSysMain' {
            return Set-ServiceStateSafe -ServiceName 'SysMain' -StartupType Disabled -StopNow -LogFile $LogFile -BackupFile $BackupFile
        }

        'DisablePagingExecutive' {
            return Set-RegistryValueSafe -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' `
                -Name 'DisablePagingExecutive' -Value 1 -Type DWord -LogFile $LogFile -BackupFile $BackupFile
        }

        'EnableUSBSelectiveSuspend' {
            # USB selective suspend is a per-power-scheme setting, NOT the
            # CsEnabled (Connected/Modern Standby) flag an earlier version wrote
            # by mistake. It lives in the active scheme under the USB settings
            # subgroup; value 1 enables selective suspend for AC and DC.
            # Writing it through Set-RegistryValueSafe keeps it fully backed up
            # and reversible; the scheme is re-activated so it takes effect.
            $schemeGuid = Get-ActivePowerSchemeGuid
            if (-not $schemeGuid) {
                Write-Log -Message 'Could not determine the active power scheme - USB selective suspend skipped' -LogFile $LogFile -Level ERROR
                return $false
            }
            $usbKey = Get-UsbSelectiveSuspendKey -SchemeGuid $schemeGuid
            $okAc = Set-RegistryValueSafe -Path $usbKey -Name 'ACSettingIndex' -Value 1 -Type DWord -LogFile $LogFile -BackupFile $BackupFile
            $okDc = Set-RegistryValueSafe -Path $usbKey -Name 'DCSettingIndex' -Value 1 -Type DWord -LogFile $LogFile -BackupFile $BackupFile
            if ($okAc -and $okDc) {
                try {
                    Invoke-NativeCommand -ExePath 'powercfg.exe' -Arguments '/setactive',$schemeGuid
                } catch {
                    Write-Log -Message "USB selective suspend was written but re-activating the power scheme failed: $($_.Exception.Message)" -LogFile $LogFile -Level WARN
                }
            }
            return ($okAc -and $okDc)
        }

        'DisableSearchIndexingService' {
            return Set-ServiceStateSafe -ServiceName 'WSearch' -StartupType Disabled -StopNow -LogFile $LogFile -BackupFile $BackupFile
        }

        default {
            Write-Log -Message "Unknown tweak key '$Key' - skipped" -LogFile $LogFile -Level WARN
            return $false
        }
    }
}

# ---------------------------------------------------------------------------
# Central verification maps used by Verify-System.ps1.
# Each registry entry: Path + Name + Type + the value that means "tweak is applied".
# Each service entry: ServiceName + the ExpectedStartMode that means "applied".
# Power-plan, hibernation and USB selective-suspend tweaks are checked
# separately in Verify-System.ps1 (they need powercfg / the active scheme GUID).
# These are module-scoped; consumers read them through the Get-Tweak*Map /
# Get-ProfileDefinition accessors below.
# ---------------------------------------------------------------------------
$Script:TweakVerificationMap = @{
    'EnableHAGS'                              = @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'; Name = 'HwSchMode'; Type = 'DWord'; ExpectedValue = 2 }
    'DisableHAGS'                              = @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'; Name = 'HwSchMode'; Type = 'DWord'; ExpectedValue = 1 }
    'GamingPriorityBoost'                     = @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl'; Name = 'Win32PrioritySeparation'; Type = 'DWord'; ExpectedValue = 38 }
    'BalancedPrioritySeparation'              = @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl'; Name = 'Win32PrioritySeparation'; Type = 'DWord'; ExpectedValue = 2 }
    'ServerPrioritySeparation'                = @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl'; Name = 'Win32PrioritySeparation'; Type = 'DWord'; ExpectedValue = 24 }
    'DisableNetworkThrottling'                = @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; Name = 'NetworkThrottlingIndex'; Type = 'DWord'; ExpectedValue = 0xffffffff }
    'LowerSystemResponsivenessForMultimedia'  = @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; Name = 'SystemResponsiveness'; Type = 'DWord'; ExpectedValue = 10 }
    'DisableStartupDelay'                     = @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize'; Name = 'StartupDelayInMSec'; Type = 'DWord'; ExpectedValue = 0 }
    'DisableBackgroundApps'                   = @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications'; Name = 'GlobalUserDisabled'; Type = 'DWord'; ExpectedValue = 1 }
    'VisualEffectsBestPerformance'             = @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'; Name = 'VisualFXSetting'; Type = 'DWord'; ExpectedValue = 2 }
    'VisualEffectsBalanced'                   = @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'; Name = 'VisualFXSetting'; Type = 'DWord'; ExpectedValue = 0 }
    'DisablePagingExecutive'                  = @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'; Name = 'DisablePagingExecutive'; Type = 'DWord'; ExpectedValue = 1 }
    'DisableGameDVR'                          = @{ Path = 'HKCU:\System\GameConfigStore'; Name = 'GameDVR_Enabled'; Type = 'DWord'; ExpectedValue = 0 }
}

# Tweaks that write MULTIPLE registry values (all of them must match for the
# tweak to count as 'Applied' - the single-value map cannot express that).
$Script:TweakMultiRegistryMap = @{
    'DisableStartMenuSuggestions' = @{
        Values = @(
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338388Enabled'; Type = 'DWord'; ExpectedValue = 0 }
            @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SystemPaneSuggestionsEnabled';    Type = 'DWord'; ExpectedValue = 0 }
        )
    }
}

# Tweaks that map to a single service with a single expected StartMode.
$Script:TweakServiceMap = @{
    'DisableTelemetry'             = @{ ServiceName = 'DiagTrack'; ExpectedStartMode = 'Manual' }
    'DisableSysMain'                = @{ ServiceName = 'SysMain'; ExpectedStartMode = 'Disabled' }
    'DisableSearchIndexingService'  = @{ ServiceName = 'WSearch'; ExpectedStartMode = 'Disabled' }
}

# Tweaks that map to MULTIPLE services (all must be in the expected start mode
# for the tweak to count as 'Applied').
$Script:TweakMultiServiceMap = @{
    'DisableXboxServices' = @{
        ServiceNames = @('XblAuthManager','XblGameSave','XboxNetApiSvc','XboxGipSvc')
        ExpectedStartMode = 'Disabled'
    }
}

# Tweaks verified via powercfg (parsed at runtime in Verify-System.ps1).
$Script:TweakPowerPlanMap = @{
    'PowerPlanHighPerformance' = 'SCHEME_MIN'
    'PowerPlanBalanced'        = 'SCHEME_BALANCED'
}

# Tweaks verified against the active power scheme / powercfg at runtime.
$Script:TweakRuntimeMap = @('DisableHibernation','EnableUSBSelectiveSuspend')

$Script:ProfileDefinitions = @{
    'Daily-Home' = @('DisableTelemetry','DisableStartupDelay','DisableStartMenuSuggestions','DisableBackgroundApps','VisualEffectsBalanced','PowerPlanBalanced')
    'Gaming'     = @('DisableTelemetry','EnableHAGS','GamingPriorityBoost','DisableNetworkThrottling','DisableGameDVR','PowerPlanHighPerformance','VisualEffectsBestPerformance')
    'Office'     = @('DisableTelemetry','DisableStartMenuSuggestions','DisableBackgroundApps','DisableXboxServices','VisualEffectsBalanced','PowerPlanBalanced','BalancedPrioritySeparation')
    'Laptop'     = @('DisableTelemetry','DisableStartMenuSuggestions','DisableBackgroundApps','DisableHAGS','EnableUSBSelectiveSuspend','VisualEffectsBalanced','PowerPlanBalanced')
    # Extreme/Godlike include the hardware-gated tweaks here in ProfileDefinitions so
    # Verify-System.ps1 can verify them. The .ps1 profile scripts ALSO append them at
    # runtime based on RAM/SSD detection - if the gating check fails at runtime, the
    # .ps1 script will skip them, and Verify-System.ps1 will (correctly) report them
    # as Not Applied because the runtime guard prevented them from being set.
    'Extreme'    = @('DisableTelemetry','EnableHAGS','GamingPriorityBoost','DisableNetworkThrottling','DisableGameDVR','PowerPlanHighPerformance','VisualEffectsBestPerformance','DisableHibernation','DisablePagingExecutive','DisableSysMain')
    'Godlike'    = @('DisableTelemetry','EnableHAGS','GamingPriorityBoost','DisableNetworkThrottling','DisableGameDVR','PowerPlanHighPerformance','VisualEffectsBestPerformance','DisableHibernation','DisableSearchIndexingService','DisableXboxServices','DisablePagingExecutive','DisableSysMain')
    'Server'     = @('DisableTelemetry','DisableSearchIndexingService','DisableXboxServices','DisableHibernation','PowerPlanHighPerformance','VisualEffectsBestPerformance','ServerPrioritySeparation')
    'Streaming'  = @('DisableTelemetry','EnableHAGS','GamingPriorityBoost','DisableNetworkThrottling','LowerSystemResponsivenessForMultimedia','PowerPlanHighPerformance','VisualEffectsBestPerformance')
}

# ---------------------------------------------------------------------------
# Catalog accessors - the single source of truth for profiles and verification
# ---------------------------------------------------------------------------

function Get-TweakVerificationMap  { return $Script:TweakVerificationMap }
function Get-TweakMultiRegistryMap { return $Script:TweakMultiRegistryMap }
function Get-TweakServiceMap       { return $Script:TweakServiceMap }
function Get-TweakMultiServiceMap  { return $Script:TweakMultiServiceMap }
function Get-TweakPowerPlanMap     { return $Script:TweakPowerPlanMap }
function Get-TweakRuntimeMap       { return $Script:TweakRuntimeMap }
function Get-ProfileDefinition     { return $Script:ProfileDefinitions }
function Get-ProfileName           { return @($Script:ProfileDefinitions.Keys | Sort-Object) }

function Get-ProfileTweak {
    # The tweak list for a profile. Profile scripts call this instead of
    # re-declaring their own array, so the two can never drift apart.
    param([Parameter(Mandatory)][string]$ProfileName)
    if (-not $Script:ProfileDefinitions.ContainsKey($ProfileName)) {
        throw "Unknown profile '$ProfileName'. Known profiles: $((Get-ProfileName) -join ', ')"
    }
    return @($Script:ProfileDefinitions[$ProfileName])
}

# ---------------------------------------------------------------------------
# Generic profile runner
# ---------------------------------------------------------------------------

function Invoke-OptimizationProfile {
    param(
        [Parameter(Mandatory)][string]$ProfileName,
        [Parameter(Mandatory)][string[]]$Tweaks,
        [string[]]$Guards = @()   # optional human-readable guard notes shown before running
    )

    Assert-Admin
    $logFile = New-LogFile -Name $ProfileName
    $backupFile = New-BackupFile -Name $ProfileName

    Write-Log -Message "=== $ProfileName profile started ===" -LogFile $logFile -Level INFO
    Write-Log -Message "Backup file: $backupFile" -LogFile $logFile -Level INFO

    if ($Guards.Count -gt 0) {
        foreach ($g in $Guards) { Write-Log -Message "NOTE: $g" -LogFile $logFile -Level WARN }
    }

    $applied = 0
    $failed  = 0
    foreach ($tweak in $Tweaks) {
        Write-Log -Message "Applying tweak: $tweak" -LogFile $logFile -Level INFO
        try {
            $tweakOk = Invoke-Tweak -Key $tweak -LogFile $logFile -BackupFile $backupFile
            if ($tweakOk) {
                $applied++
            } else {
                $failed++
            }
        } catch {
            Write-Log -Message "Tweak '$tweak' threw an error: $($_.Exception.Message)" -LogFile $logFile -Level ERROR
            $failed++
        }
    }

    Write-Log -Message "=== $ProfileName profile finished: $applied tweak(s) applied, $failed failed ===" -LogFile $logFile -Level OK
    Write-Host ""
    Write-Host "Log file:    $logFile" -ForegroundColor Cyan
    Write-Host "Backup file: $backupFile" -ForegroundColor Cyan
    Write-Host "Run Undo-All-Changes.ps1 at any time to revert every tracked change." -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
# Public surface
# ---------------------------------------------------------------------------

Export-ModuleMember -Function @(
    'Test-IsAdmin'
    'Assert-Admin'
    'Ensure-Directory'
    'New-LogFile'
    'Write-Log'
    'New-BackupFile'
    'Add-BackupRecord'
    'Get-RecordProperty'
    'Remove-OldBackupFile'
    'Select-BackupRecordsToRestore'
    'ConvertTo-ComparableRegistryValue'
    'Test-RegistryValueMatch'
    'Test-RegistryKeyEmpty'
    'Set-RegistryValueSafe'
    'Restore-RegistryBackupRecord'
    'ConvertTo-CimFilterLiteral'
    'Get-ServiceStartMode'
    'Set-ServiceStateSafe'
    'Restore-ServiceBackupRecord'
    'Invoke-NativeCommand'
    'Get-PowerSchemeGuid'
    'Get-ActivePowerSchemeGuid'
    'Get-UsbSelectiveSuspendKey'
    'Get-SystemSnapshot'
    'Save-SystemSnapshot'
    'Invoke-Tweak'
    'Invoke-OptimizationProfile'
    'Get-TweakVerificationMap'
    'Get-TweakMultiRegistryMap'
    'Get-TweakServiceMap'
    'Get-TweakMultiServiceMap'
    'Get-TweakPowerPlanMap'
    'Get-TweakRuntimeMap'
    'Get-ProfileDefinition'
    'Get-ProfileName'
    'Get-ProfileTweak'
    'Get-UwoLogDirectory'
    'Get-UwoBackupDirectory'
    'Get-UwoBackupArchiveDirectory'
    'Get-UwoSnapshotDirectory'
)
