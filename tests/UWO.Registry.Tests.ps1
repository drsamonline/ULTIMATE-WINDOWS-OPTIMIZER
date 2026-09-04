#Requires -Version 5.1
<#
    Registry backup/set/restore tests. These touch the registry, but ONLY under
    HKCU:\Software\UWO-Test, which is created and deleted by the tests.
    Skipped automatically on non-Windows hosts.
#>

BeforeDiscovery {
    $script:IsWindowsHost = ($null -eq $IsWindows) -or $IsWindows
}

BeforeAll {
    $env:UWO_LOG_ROOT = Join-Path ([System.IO.Path]::GetTempPath()) ("uwo-registry-tests-" + [guid]::NewGuid().ToString('N'))
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts/UWO.psd1') -Force

    $script:TestRoot = 'HKCU:\Software\UWO-Test'

    function New-TestContext {
        # A fresh log + backup file and a clean test key for each test.
        if (Test-Path $script:TestRoot) { Remove-Item $script:TestRoot -Recurse -Force }
        New-Item -Path $script:TestRoot -Force | Out-Null
        return [pscustomobject]@{
            LogFile    = New-LogFile -Name 'PesterRegistry'
            BackupFile = New-BackupFile -Name 'PesterRegistry'
        }
    }

    function Get-BackupRecord {
        param([string]$BackupFile)
        return @(ConvertFrom-Json -InputObject (Get-Content -Path $BackupFile -Raw) | Where-Object { $null -ne $_ })
    }
}

AfterAll {
    if ($script:TestRoot -and (Test-Path $script:TestRoot)) { Remove-Item $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue }
    Remove-Module UWO -Force -ErrorAction SilentlyContinue
    if (Test-Path $env:UWO_LOG_ROOT) { Remove-Item $env:UWO_LOG_ROOT -Recurse -Force -ErrorAction SilentlyContinue }
    Remove-Item Env:\UWO_LOG_ROOT -ErrorAction SilentlyContinue
}

Describe 'New-BackupFile / Add-BackupRecord' -Skip:(-not $script:IsWindowsHost) {
    It 'creates a valid, empty JSON array' {
        $ctx = New-TestContext
        (Get-Content -Path $ctx.BackupFile -Raw).Trim() | Should -Be '[]'
        @(ConvertFrom-Json -InputObject (Get-Content -Path $ctx.BackupFile -Raw)).Count | Should -Be 0
    }

    It 'appends records without losing earlier ones' {
        $ctx = New-TestContext
        Add-BackupRecord -BackupFile $ctx.BackupFile -Record @{ Type = 'Registry'; Path = 'HKCU:\A'; Name = 'One' }
        Add-BackupRecord -BackupFile $ctx.BackupFile -Record @{ Type = 'Registry'; Path = 'HKCU:\A'; Name = 'Two' }
        $records = Get-BackupRecord -BackupFile $ctx.BackupFile
        $records.Count | Should -Be 2
        @($records.Name) | Should -Be @('One','Two')
    }
}

Describe 'Set-RegistryValueSafe' -Skip:(-not $script:IsWindowsHost) {
    It 'writes the value and records the previous one' {
        $ctx = New-TestContext
        New-ItemProperty -Path $script:TestRoot -Name 'Existing' -Value 1 -PropertyType DWord -Force | Out-Null

        Set-RegistryValueSafe -Path $script:TestRoot -Name 'Existing' -Value 5 -Type DWord -LogFile $ctx.LogFile -BackupFile $ctx.BackupFile |
            Should -BeTrue

        (Get-ItemProperty -Path $script:TestRoot -Name 'Existing').Existing | Should -Be 5
        $records = Get-BackupRecord -BackupFile $ctx.BackupFile
        $records.Count | Should -Be 1
        $records[0].Existed | Should -BeTrue
        $records[0].OriginalValue | Should -Be 1
        $records[0].KeyCreated | Should -BeFalse
    }

    It 'does not write a backup record when the write fails' {
        $ctx = New-TestContext
        Mock -CommandName New-ItemProperty -ModuleName UWO -MockWith { throw 'simulated registry failure' }

        Set-RegistryValueSafe -Path $script:TestRoot -Name 'Nope' -Value 1 -Type DWord -LogFile $ctx.LogFile -BackupFile $ctx.BackupFile |
            Should -BeFalse

        (Get-BackupRecord -BackupFile $ctx.BackupFile).Count | Should -Be 0
    }

    It 'removes a key it created when the write fails' {
        $ctx = New-TestContext
        $newKey = Join-Path $script:TestRoot 'CreatedThenFailed'
        Mock -CommandName New-ItemProperty -ModuleName UWO -MockWith { throw 'simulated registry failure' }

        Set-RegistryValueSafe -Path $newKey -Name 'Nope' -Value 1 -Type DWord -LogFile $ctx.LogFile -BackupFile $ctx.BackupFile |
            Should -BeFalse

        Test-Path $newKey | Should -BeFalse
        (Get-BackupRecord -BackupFile $ctx.BackupFile).Count | Should -Be 0
    }

    It 'records KeyCreated when it had to create the key' {
        $ctx = New-TestContext
        $newKey = Join-Path $script:TestRoot 'Created'

        Set-RegistryValueSafe -Path $newKey -Name 'Value' -Value 1 -Type DWord -LogFile $ctx.LogFile -BackupFile $ctx.BackupFile |
            Should -BeTrue

        $records = Get-BackupRecord -BackupFile $ctx.BackupFile
        $records[0].KeyCreated | Should -BeTrue
        $records[0].Existed | Should -BeFalse
    }

    It 'is idempotent: a second identical set writes no backup record' {
        $ctx = New-TestContext
        Set-RegistryValueSafe -Path $script:TestRoot -Name 'Idem' -Value 7 -Type DWord -LogFile $ctx.LogFile -BackupFile $ctx.BackupFile | Should -BeTrue
        Set-RegistryValueSafe -Path $script:TestRoot -Name 'Idem' -Value 7 -Type DWord -LogFile $ctx.LogFile -BackupFile $ctx.BackupFile | Should -BeTrue

        $records = Get-BackupRecord -BackupFile $ctx.BackupFile
        $records.Count | Should -Be 1
        $records[0].Existed | Should -BeFalse
    }

    It 'does not record the already-tweaked value as the original on a re-run' {
        $ctx = New-TestContext
        New-ItemProperty -Path $script:TestRoot -Name 'Baseline' -Value 2 -PropertyType DWord -Force | Out-Null
        Set-RegistryValueSafe -Path $script:TestRoot -Name 'Baseline' -Value 38 -Type DWord -LogFile $ctx.LogFile -BackupFile $ctx.BackupFile | Should -BeTrue
        Set-RegistryValueSafe -Path $script:TestRoot -Name 'Baseline' -Value 38 -Type DWord -LogFile $ctx.LogFile -BackupFile $ctx.BackupFile | Should -BeTrue

        $records = Get-BackupRecord -BackupFile $ctx.BackupFile
        $records.Count | Should -Be 1
        $records[0].OriginalValue | Should -Be 2
    }
}

Describe 'Restore-RegistryBackupRecord' -Skip:(-not $script:IsWindowsHost) {
    It 'restores the original value' {
        $ctx = New-TestContext
        New-ItemProperty -Path $script:TestRoot -Name 'Restore' -Value 3 -PropertyType DWord -Force | Out-Null
        Set-RegistryValueSafe -Path $script:TestRoot -Name 'Restore' -Value 9 -Type DWord -LogFile $ctx.LogFile -BackupFile $ctx.BackupFile | Out-Null

        foreach ($record in Get-BackupRecord -BackupFile $ctx.BackupFile) {
            Restore-RegistryBackupRecord -Record $record -LogFile $ctx.LogFile
        }

        (Get-ItemProperty -Path $script:TestRoot -Name 'Restore').Restore | Should -Be 3
    }

    It 'removes a value that did not exist before, and the key the toolkit created' {
        $ctx = New-TestContext
        $newKey = Join-Path $script:TestRoot 'ToRemove'
        Set-RegistryValueSafe -Path $newKey -Name 'Value' -Value 1 -Type DWord -LogFile $ctx.LogFile -BackupFile $ctx.BackupFile | Out-Null

        foreach ($record in Get-BackupRecord -BackupFile $ctx.BackupFile) {
            Restore-RegistryBackupRecord -Record $record -LogFile $ctx.LogFile
        }

        Test-Path $newKey | Should -BeFalse
    }

    It 'keeps a created key that is no longer empty' {
        $ctx = New-TestContext
        $newKey = Join-Path $script:TestRoot 'StillUsed'
        Set-RegistryValueSafe -Path $newKey -Name 'Value' -Value 1 -Type DWord -LogFile $ctx.LogFile -BackupFile $ctx.BackupFile | Out-Null
        New-ItemProperty -Path $newKey -Name 'SomeoneElse' -Value 1 -PropertyType DWord -Force | Out-Null

        foreach ($record in Get-BackupRecord -BackupFile $ctx.BackupFile) {
            Restore-RegistryBackupRecord -Record $record -LogFile $ctx.LogFile
        }

        Test-Path $newKey | Should -BeTrue
        (Get-ItemProperty -Path $newKey).PSObject.Properties.Name | Should -Not -Contain 'Value'
    }

    It 'leaves an existing key alone for records written before KeyCreated existed' {
        $ctx = New-TestContext
        $legacyRecord = [pscustomobject]@{
            Type = 'Registry'; Path = $script:TestRoot; Name = 'Legacy'; Existed = $false; ValueType = 'DWord'
        }
        New-ItemProperty -Path $script:TestRoot -Name 'Legacy' -Value 1 -PropertyType DWord -Force | Out-Null

        Restore-RegistryBackupRecord -Record $legacyRecord -LogFile $ctx.LogFile

        Test-Path $script:TestRoot | Should -BeTrue
        (Get-ItemProperty -Path $script:TestRoot).PSObject.Properties.Name | Should -Not -Contain 'Legacy'
    }
}
