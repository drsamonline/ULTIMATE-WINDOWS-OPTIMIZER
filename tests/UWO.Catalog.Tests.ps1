#Requires -Version 5.1
<#
    Catalog / pure-logic tests. These do not touch the registry, services or
    powercfg, so they run on any platform PowerShell supports.
#>

BeforeAll {
    $env:UWO_LOG_ROOT = Join-Path ([System.IO.Path]::GetTempPath()) ("uwo-catalog-tests-" + [guid]::NewGuid().ToString('N'))
    $modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts/UWO.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module UWO -Force -ErrorAction SilentlyContinue
    if (Test-Path $env:UWO_LOG_ROOT) { Remove-Item $env:UWO_LOG_ROOT -Recurse -Force -ErrorAction SilentlyContinue }
    Remove-Item Env:\UWO_LOG_ROOT -ErrorAction SilentlyContinue
}

Describe 'Profile catalog' {
    It 'exposes every profile through Get-ProfileName' {
        (Get-ProfileName) | Should -Contain 'Gaming'
        (Get-ProfileName).Count | Should -Be (Get-ProfileDefinition).Keys.Count
    }

    It 'returns the same tweak list as the definitions map' {
        foreach ($name in Get-ProfileName) {
            (Get-ProfileTweak -ProfileName $name) | Should -Be @((Get-ProfileDefinition)[$name])
        }
    }

    It 'throws for an unknown profile' {
        { Get-ProfileTweak -ProfileName 'NoSuchProfile' } | Should -Throw '*Unknown profile*'
    }

    It 'keeps the hardware-gated tweaks in the Extreme and Godlike definitions' {
        foreach ($name in @('Extreme','Godlike')) {
            Get-ProfileTweak -ProfileName $name | Should -Contain 'DisablePagingExecutive'
            Get-ProfileTweak -ProfileName $name | Should -Contain 'DisableSysMain'
        }
    }

    It 'can verify every tweak referenced by a profile' {
        $verifiable = @((Get-TweakVerificationMap).Keys) +
                      @((Get-TweakMultiRegistryMap).Keys) +
                      @((Get-TweakServiceMap).Keys) +
                      @((Get-TweakMultiServiceMap).Keys) +
                      @((Get-TweakPowerPlanMap).Keys) +
                      @('DisableHibernation')
        foreach ($name in Get-ProfileName) {
            foreach ($tweak in Get-ProfileTweak -ProfileName $name) {
                $verifiable | Should -Contain $tweak -Because "profile '$name' lists '$tweak'"
            }
        }
    }

    It 'verifies DisableStartMenuSuggestions through both of the values it writes' {
        $spec = (Get-TweakMultiRegistryMap)['DisableStartMenuSuggestions']
        $spec.Values.Count | Should -Be 2
        @($spec.Values.Name) | Should -Contain 'SubscribedContent-338388Enabled'
        @($spec.Values.Name) | Should -Contain 'SystemPaneSuggestionsEnabled'
        foreach ($value in $spec.Values) { $value.ExpectedValue | Should -Be 0 }
        (Get-TweakVerificationMap).ContainsKey('DisableStartMenuSuggestions') | Should -BeFalse
    }
}

Describe 'Get-PowerSchemeGuid' {
    It 'extracts the GUID from English powercfg output' {
        Get-PowerSchemeGuid -SchemeOutput 'Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced)' |
            Should -Be '381b4222-f694-41f0-9685-ff5bb260df2e'
    }

    It 'extracts the GUID from localized powercfg output' {
        Get-PowerSchemeGuid -SchemeOutput 'GUID des Energieschemas: 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c  (Hochstleistung)' |
            Should -Be '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    }

    It 'returns a bare GUID unchanged' {
        Get-PowerSchemeGuid -SchemeOutput '381b4222-f694-41f0-9685-ff5bb260df2e' |
            Should -Be '381b4222-f694-41f0-9685-ff5bb260df2e'
    }

    It 'returns null when there is no GUID' {
        Get-PowerSchemeGuid -SchemeOutput 'no guid here' | Should -BeNullOrEmpty
        Get-PowerSchemeGuid -SchemeOutput '' | Should -BeNullOrEmpty
    }
}

Describe 'ConvertTo-CimFilterLiteral' {
    It 'escapes quotes and backslashes' {
        ConvertTo-CimFilterLiteral -Value "Ser'vice" | Should -Be "Ser\'vice"
        ConvertTo-CimFilterLiteral -Value 'a\b'      | Should -Be 'a\\b'
    }

    It 'leaves ordinary service names alone' {
        ConvertTo-CimFilterLiteral -Value 'DiagTrack' | Should -Be 'DiagTrack'
    }
}

Describe 'Select-BackupRecordsToRestore (oldest original wins)' {
    It 'keeps only the earliest registry record per Path\Name' {
        $records = @(
            [pscustomobject]@{ Type = 'Registry'; Path = 'HKCU:\A'; Name = 'V'; Existed = $true; OriginalValue = 1 }
            [pscustomobject]@{ Type = 'Service';  ServiceName = 'DiagTrack'; OriginalStartMode = 'Auto' }
            [pscustomobject]@{ Type = 'Registry'; Path = 'HKCU:\A'; Name = 'V'; Existed = $true; OriginalValue = 38 }
            [pscustomobject]@{ Type = 'Registry'; Path = 'HKCU:\B'; Name = 'V'; Existed = $false; OriginalValue = $null }
        )
        $kept = @(Select-BackupRecordsToRestore -Records $records)
        $kept.Count | Should -Be 3
        @($kept | Where-Object { $_.Type -eq 'Registry' -and $_.Path -eq 'HKCU:\A' }).OriginalValue | Should -Be 1
    }

    It 'matches Path\Name case-insensitively' {
        $records = @(
            [pscustomobject]@{ Type = 'Registry'; Path = 'HKCU:\A'; Name = 'Value'; OriginalValue = 1 }
            [pscustomobject]@{ Type = 'Registry'; Path = 'hkcu:\a'; Name = 'value'; OriginalValue = 2 }
        )
        @(Select-BackupRecordsToRestore -Records $records).Count | Should -Be 1
    }

    It 'never de-duplicates non-registry records' {
        $records = @(
            [pscustomobject]@{ Type = 'Service'; ServiceName = 'DiagTrack'; OriginalStartMode = 'Auto' }
            [pscustomobject]@{ Type = 'Service'; ServiceName = 'DiagTrack'; OriginalStartMode = 'Manual' }
            [pscustomobject]@{ Type = 'PowerPlan'; OriginalGuid = '381b4222-f694-41f0-9685-ff5bb260df2e' }
        )
        @(Select-BackupRecordsToRestore -Records $records).Count | Should -Be 3
    }

    It 'tolerates an empty record set' {
        @(Select-BackupRecordsToRestore -Records @()).Count | Should -Be 0
    }
}

Describe 'Get-RecordProperty' {
    It 'returns the default for a field older backup files do not have' {
        $record = [pscustomobject]@{ Type = 'Registry'; Path = 'HKCU:\A'; Name = 'V' }
        Get-RecordProperty -Record $record -Name 'KeyCreated' -Default $false | Should -BeFalse
    }

    It 'reads values from hashtables and objects alike' {
        Get-RecordProperty -Record @{ KeyCreated = $true } -Name 'KeyCreated' | Should -BeTrue
        Get-RecordProperty -Record ([pscustomobject]@{ KeyCreated = $true }) -Name 'KeyCreated' | Should -BeTrue
    }
}

Describe 'ConvertTo-ComparableRegistryValue / Test-RegistryValueMatch' {
    It 'treats a DWord written as 0xffffffff and read back as -1 as equal' {
        Test-RegistryValueMatch -CurrentValue -1 -DesiredValue 0xffffffff -Type DWord | Should -BeTrue
    }

    It 'compares plain DWords and strings' {
        Test-RegistryValueMatch -CurrentValue 2 -DesiredValue 2 -Type DWord | Should -BeTrue
        Test-RegistryValueMatch -CurrentValue 2 -DesiredValue 3 -Type DWord | Should -BeFalse
        Test-RegistryValueMatch -CurrentValue 'x' -DesiredValue 'x' -Type String | Should -BeTrue
    }

    It 'never matches a missing current value' {
        Test-RegistryValueMatch -CurrentValue $null -DesiredValue 0 -Type DWord | Should -BeFalse
    }
}
