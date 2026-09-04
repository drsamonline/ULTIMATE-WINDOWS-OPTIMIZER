#Requires -Version 5.1
<#
    Backup retention tests. Filesystem only - safe on any platform, and they
    only ever touch the throwaway directory pointed at by $env:UWO_LOG_ROOT.
#>

BeforeAll {
    $env:UWO_LOG_ROOT = Join-Path ([System.IO.Path]::GetTempPath()) ("uwo-retention-tests-" + [guid]::NewGuid().ToString('N'))
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts/UWO.psd1') -Force

    function New-BackupFileWithAge {
        param([string]$Directory, [string]$Name, [int]$AgeDays)
        if (-not (Test-Path $Directory)) { New-Item -Path $Directory -ItemType Directory -Force | Out-Null }
        $path = Join-Path $Directory $Name
        Set-Content -Path $path -Value '[]' -Encoding UTF8
        (Get-Item $path).LastWriteTime = (Get-Date).AddDays(-$AgeDays)
        return $path
    }

    function Reset-BackupDirectory {
        foreach ($dir in @((Get-UwoBackupArchiveDirectory), (Get-UwoBackupDirectory))) {
            if (Test-Path $dir) {
                Get-ChildItem -Path $dir -Filter '*.json' -File | Remove-Item -Force
            }
        }
    }
}

AfterAll {
    Remove-Module UWO -Force -ErrorAction SilentlyContinue
    if (Test-Path $env:UWO_LOG_ROOT) { Remove-Item $env:UWO_LOG_ROOT -Recurse -Force -ErrorAction SilentlyContinue }
    Remove-Item Env:\UWO_LOG_ROOT -ErrorAction SilentlyContinue
}

Describe 'Remove-OldBackupFile' {
    BeforeEach {
        Reset-BackupDirectory
        $script:LogFile = New-LogFile -Name 'PesterRetention'
        $script:Archive = Get-UwoBackupArchiveDirectory
        $script:Pending = Get-UwoBackupDirectory
    }

    It 'prunes nothing when there are fewer files than KeepCount' {
        1..3 | ForEach-Object { New-BackupFileWithAge -Directory $script:Archive -Name "old_$_.json" -AgeDays 400 | Out-Null }
        Remove-OldBackupFile -LogFile $script:LogFile -KeepCount 20 -MaxAgeDays 30 | Should -Be 0
        @(Get-ChildItem -Path $script:Archive -Filter '*.json').Count | Should -Be 3
    }

    It 'prunes only files that are both beyond KeepCount and older than MaxAgeDays' {
        1..3 | ForEach-Object { New-BackupFileWithAge -Directory $script:Archive -Name "recent_$_.json" -AgeDays $_ | Out-Null }
        1..4 | ForEach-Object { New-BackupFileWithAge -Directory $script:Archive -Name "ancient_$_.json" -AgeDays (100 + $_) | Out-Null }

        Remove-OldBackupFile -LogFile $script:LogFile -KeepCount 3 -MaxAgeDays 30 | Should -Be 4

        $remaining = @(Get-ChildItem -Path $script:Archive -Filter '*.json').Name
        $remaining.Count | Should -Be 3
        $remaining | ForEach-Object { $_ | Should -BeLike 'recent_*' }
    }

    It 'keeps old files that are still within KeepCount' {
        1..5 | ForEach-Object { New-BackupFileWithAge -Directory $script:Archive -Name "old_$_.json" -AgeDays (100 + $_) | Out-Null }
        Remove-OldBackupFile -LogFile $script:LogFile -KeepCount 5 -MaxAgeDays 30 | Should -Be 0
        @(Get-ChildItem -Path $script:Archive -Filter '*.json').Count | Should -Be 5
    }

    It 'never touches pending backups by default' {
        1..5 | ForEach-Object { New-BackupFileWithAge -Directory $script:Pending -Name "pending_$_.json" -AgeDays (100 + $_) | Out-Null }
        Remove-OldBackupFile -LogFile $script:LogFile -KeepCount 1 -MaxAgeDays 30 | Should -Be 0
        @(Get-ChildItem -Path $script:Pending -Filter '*.json').Count | Should -Be 5
    }

    It 'prunes pending backups only when -IncludePending is used' {
        1..5 | ForEach-Object { New-BackupFileWithAge -Directory $script:Pending -Name "pending_$_.json" -AgeDays (100 + $_) | Out-Null }
        Remove-OldBackupFile -LogFile $script:LogFile -KeepCount 2 -MaxAgeDays 30 -IncludePending | Should -Be 3
        @(Get-ChildItem -Path $script:Pending -Filter '*.json').Count | Should -Be 2
    }

    It 'deletes nothing when -WhatIf is used' {
        1..5 | ForEach-Object { New-BackupFileWithAge -Directory $script:Archive -Name "old_$_.json" -AgeDays (100 + $_) | Out-Null }
        Remove-OldBackupFile -LogFile $script:LogFile -KeepCount 1 -MaxAgeDays 30 -WhatIf | Should -Be 4
        @(Get-ChildItem -Path $script:Archive -Filter '*.json').Count | Should -Be 5
    }
}
