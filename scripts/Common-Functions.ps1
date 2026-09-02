#Requires -Version 5.1
<#
    Common-Functions.ps1
    ---------------------
    Shared engine for Ultimate Windows Optimizer v6.0.
    Every Optimize-*.ps1 profile script, and the utility scripts, dot-source
    this file. It provides:

      - Admin / environment checks
      - Logging
      - Registry value backup + safe-set + restore  (real rollback, not cosmetic)
      - Windows service backup + safe-set + restore
      - A system snapshot function used by Performance-Monitor / Compare-Results
      - A tweak catalog + generic profile runner, so every optimization
        profile is a genuinely different, explicit list of tweaks rather
        than a copy-pasted script with a different label.

    Nothing in this file requires internet access. Nothing in this file
    is destructive without first writing a JSON backup record that
    Undo-All-Changes.ps1 can read to restore the exact previous state.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Script:RootLogDir     = Join-Path $env:USERPROFILE 'OptimizationLogs'
$Script:BackupDir      = Join-Path $Script:RootLogDir 'Backups'
$Script:SnapshotDir    = Join-Path $Script:RootLogDir 'Snapshots'

foreach ($dir in @($Script:RootLogDir, $Script:BackupDir, $Script:SnapshotDir)) {
    if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
}

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

function New-LogFile {
    param([Parameter(Mandatory)][string]$Name)
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
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $path = Join-Path $Script:BackupDir "$Name`_$timestamp.json"
    # Write a literal '[]' so the file is a valid empty JSON array.
    # (Piping @() to ConvertTo-Json produces no output on PowerShell 5.1,
    #  which left the file empty and broke every downstream reader.)
    Set-Content -Path $path -Value '[]' -Encoding UTF8
    return $path
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

function Set-RegistryValueSafe {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [ValidateSet('DWord','String','QWord','Binary','MultiString','ExpandString')][string]$Type = 'DWord',
        [Parameter(Mandatory)][string]$LogFile,
        [Parameter(Mandatory)][string]$BackupFile
    )
    try {
        $existed = $false
        $originalValue = $null
        if (Test-Path $Path) {
            $prop = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
            if ($null -ne $prop -and ($prop.PSObject.Properties.Name -contains $Name)) {
                $existed = $true
                $originalValue = $prop.$Name
            }
        } else {
            New-Item -Path $Path -Force | Out-Null
        }

        Add-BackupRecord -BackupFile $BackupFile -Record @{
            Type          = 'Registry'
            Path          = $Path
            Name          = $Name
            Existed       = $existed
            OriginalValue = $originalValue
            ValueType     = $Type
        }

        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
        Write-Log -Message "Set $Path\$Name = $Value" -LogFile $LogFile -Level INFO
        return $true
    } catch {
        Write-Log -Message "FAILED to set $Path\$Name : $($_.Exception.Message)" -LogFile $LogFile -Level ERROR
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
            }
        }
    } catch {
        Write-Log -Message "FAILED to restore $($Record.Path)\$($Record.Name) : $($_.Exception.Message)" -LogFile $LogFile -Level ERROR
    }
}

# ---------------------------------------------------------------------------
# Services: safe set (backs up previous StartupType) + restore
# ---------------------------------------------------------------------------

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
        $wmiSvc = Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'"
        $originalStartMode = $wmiSvc.StartMode   # Auto / Manual / Disabled
        $originalStatus    = $svc.Status

        Add-BackupRecord -BackupFile $BackupFile -Record @{
            Type               = 'Service'
            ServiceName        = $ServiceName
            OriginalStartMode  = $originalStartMode
            OriginalStatus     = $originalStatus.ToString()
        }

        Set-Service -Name $ServiceName -StartupType $StartupType
        if ($StopNow -and $svc.Status -eq 'Running') {
            Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        }
        Write-Log -Message "Service '$ServiceName' set to $StartupType" -LogFile $LogFile -Level INFO
        return $true
    } catch {
        Write-Log -Message "FAILED to change service '$ServiceName' : $($_.Exception.Message)" -LogFile $LogFile -Level ERROR
        return $false
    }
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

function Invoke-Tweak {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$LogFile,
        [Parameter(Mandatory)][string]$BackupFile
    )

    switch ($Key) {

        'DisableHibernation' {
            # Removes hibernation (frees disk space equal to RAM size); NOT applied to laptop profile.
            # The backup record is only written if powercfg actually succeeds.
            try {
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
            # IMPORTANT: capture the active scheme GUID BEFORE switching -
            # otherwise we record the new High-Performance GUID, not the user's
            # original, which makes Undo-All-Changes.ps1 unable to restore it.
            try {
                $originalScheme = (powercfg.exe /getactivescheme) -join ''
                Invoke-NativeCommand -ExePath 'powercfg.exe' -Arguments '/setactive','SCHEME_MIN'
                Write-Log -Message 'Power plan set to High Performance' -LogFile $LogFile -Level OK
                Add-BackupRecord -BackupFile $BackupFile -Record @{ Type = 'PowerPlan'; OriginalGuid = $originalScheme }
                return $true
            } catch {
                Write-Log -Message "FAILED to set High Performance power plan: $($_.Exception.Message)" -LogFile $LogFile -Level ERROR
                return $false
            }
        }

        'PowerPlanBalanced' {
            # Symmetric backup handling with PowerPlanHighPerformance.
            try {
                $originalScheme = (powercfg.exe /getactivescheme) -join ''
                Invoke-NativeCommand -ExePath 'powercfg.exe' -Arguments '/setactive','SCHEME_BALANCED'
                Write-Log -Message 'Power plan set to Balanced' -LogFile $LogFile -Level OK
                Add-BackupRecord -BackupFile $BackupFile -Record @{ Type = 'PowerPlan'; OriginalGuid = $originalScheme }
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
            return Set-RegistryValueSafe -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' `
                -Name 'VisualFXSetting' -Value 3 -Type DWord -LogFile $LogFile -BackupFile $BackupFile
        }

        'DisableSysMain' {
            return Set-ServiceStateSafe -ServiceName 'SysMain' -StartupType Disabled -StopNow -LogFile $LogFile -BackupFile $BackupFile
        }

        'DisablePagingExecutive' {
            return Set-RegistryValueSafe -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' `
                -Name 'DisablePagingExecutive' -Value 1 -Type DWord -LogFile $LogFile -BackupFile $BackupFile
        }

        'EnableUSBSelectiveSuspend' {
            return Set-RegistryValueSafe -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' `
                -Name 'CsEnabled' -Value 1 -Type DWord -LogFile $LogFile -BackupFile $BackupFile
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
# Each registry entry: Path + Name + the value that means "tweak is applied".
# Each service entry: ServiceName + the ExpectedStartMode that means "applied".
# Power-plan & hibernation tweaks are checked separately in Verify-System.ps1
# via powercfg (not single-value-checkable here).
# ---------------------------------------------------------------------------
$Global:TweakVerificationMap = @{
    'EnableHAGS'                              = @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'; Name = 'HwSchMode'; ExpectedValue = 2 }
    'DisableHAGS'                              = @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'; Name = 'HwSchMode'; ExpectedValue = 1 }
    'GamingPriorityBoost'                     = @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl'; Name = 'Win32PrioritySeparation'; ExpectedValue = 38 }
    'BalancedPrioritySeparation'              = @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl'; Name = 'Win32PrioritySeparation'; ExpectedValue = 2 }
    'ServerPrioritySeparation'                = @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl'; Name = 'Win32PrioritySeparation'; ExpectedValue = 24 }
    'DisableNetworkThrottling'                = @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; Name = 'NetworkThrottlingIndex'; ExpectedValue = 0xffffffff }
    'LowerSystemResponsivenessForMultimedia'  = @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; Name = 'SystemResponsiveness'; ExpectedValue = 10 }
    'DisableStartupDelay'                     = @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize'; Name = 'StartupDelayInMSec'; ExpectedValue = 0 }
    'DisableStartMenuSuggestions'              = @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338388Enabled'; ExpectedValue = 0 }
    'DisableBackgroundApps'                   = @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications'; Name = 'GlobalUserDisabled'; ExpectedValue = 1 }
    'VisualEffectsBestPerformance'             = @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'; Name = 'VisualFXSetting'; ExpectedValue = 2 }
    'VisualEffectsBalanced'                   = @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'; Name = 'VisualFXSetting'; ExpectedValue = 3 }
    'DisablePagingExecutive'                  = @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'; Name = 'DisablePagingExecutive'; ExpectedValue = 1 }
    'EnableUSBSelectiveSuspend'               = @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Name = 'CsEnabled'; ExpectedValue = 1 }
    'DisableGameDVR'                          = @{ Path = 'HKCU:\System\GameConfigStore'; Name = 'GameDVR_Enabled'; ExpectedValue = 0 }
}

# Tweaks that map to a single service with a single expected StartMode.
$Global:TweakServiceMap = @{
    'DisableTelemetry'             = @{ ServiceName = 'DiagTrack'; ExpectedStartMode = 'Manual' }
    'DisableSysMain'                = @{ ServiceName = 'SysMain'; ExpectedStartMode = 'Disabled' }
    'DisableSearchIndexingService'  = @{ ServiceName = 'WSearch'; ExpectedStartMode = 'Disabled' }
}

# Tweaks that map to MULTIPLE services (all must be in the expected start mode
# for the tweak to count as 'Applied').
$Global:TweakMultiServiceMap = @{
    'DisableXboxServices' = @{
        ServiceNames = @('XblAuthManager','XblGameSave','XboxNetApiSvc','XboxGipSvc')
        ExpectedStartMode = 'Disabled'
    }
}

# Tweaks verified via powercfg (parsed at runtime in Verify-System.ps1).
$Global:TweakPowerPlanMap = @{
    'PowerPlanHighPerformance' = 'SCHEME_MIN'
    'PowerPlanBalanced'        = 'SCHEME_BALANCED'
}

$Global:ProfileDefinitions = @{
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
