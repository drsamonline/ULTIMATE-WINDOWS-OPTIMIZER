@{
    RootModule        = 'UWO.psm1'
    ModuleVersion     = '6.1.0'
    GUID              = 'c0f6f2b1-3f0c-4a4a-9f2c-6f2a1a0d5f21'
    Author            = 'Dr. Sohil Momin (Coding For Fun / @DrSamOnline)'
    Description       = 'Shared engine for Ultimate Windows Optimizer: logging, registry/service safe-set with JSON backups, backup retention, verification maps and the profile/tweak catalog.'
    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        'Test-IsAdmin'
        'Assert-Admin'
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
        'Get-SystemSnapshot'
        'Save-SystemSnapshot'
        'Invoke-Tweak'
        'Invoke-OptimizationProfile'
        'Get-TweakVerificationMap'
        'Get-TweakMultiRegistryMap'
        'Get-TweakServiceMap'
        'Get-TweakMultiServiceMap'
        'Get-TweakPowerPlanMap'
        'Get-ProfileDefinition'
        'Get-ProfileName'
        'Get-ProfileTweak'
        'Get-UwoLogDirectory'
        'Get-UwoBackupDirectory'
        'Get-UwoBackupArchiveDirectory'
        'Get-UwoSnapshotDirectory'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags       = @('Windows','Optimization','Registry','Services','Backup')
            LicenseUri = 'https://github.com/drsamonline/ULTIMATE-WINDOWS-OPTIMIZER/blob/main/LICENSE'
            ProjectUri = 'https://github.com/drsamonline/ULTIMATE-WINDOWS-OPTIMIZER'
        }
    }
}
