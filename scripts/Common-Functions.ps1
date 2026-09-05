#Requires -Version 5.1
<#
    Common-Functions.ps1
    ---------------------
    Backward-compatibility shim. The shared engine now lives in the UWO
    module (UWO.psd1 / UWO.psm1) in this same folder; every script in this
    toolkit imports that module directly.

    This file remains so that older or third-party scripts that dot-source
    Common-Functions.ps1 keep working: it imports the module and re-publishes
    the catalog under the legacy $Global: variable names.

    New code should use:
        Import-Module (Join-Path $PSScriptRoot 'UWO.psd1') -Force
    and read the catalog through Get-ProfileDefinition / Get-ProfileTweak /
    Get-Tweak*Map instead of the $Global: variables.
#>

Import-Module (Join-Path $PSScriptRoot 'UWO.psd1') -Force -Global

# Legacy names, kept in sync with the module's catalog.
$Global:ProfileDefinitions    = Get-ProfileDefinition
$Global:TweakVerificationMap  = Get-TweakVerificationMap
$Global:TweakMultiRegistryMap = Get-TweakMultiRegistryMap
$Global:TweakServiceMap       = Get-TweakServiceMap
$Global:TweakMultiServiceMap  = Get-TweakMultiServiceMap
$Global:TweakPowerPlanMap     = Get-TweakPowerPlanMap

# Legacy directory variables (previously $Script: scoped in this file).
$Script:RootLogDir  = Get-UwoLogDirectory
$Script:BackupDir   = Get-UwoBackupDirectory
$Script:SnapshotDir = Get-UwoSnapshotDirectory
