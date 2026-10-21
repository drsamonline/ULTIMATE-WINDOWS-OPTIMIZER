<#
    Verify-System.ps1
    Checks the CURRENT system state against what a chosen profile is
    supposed to have applied, and reports Applied / Not Applied / Unknown
    per tweak - it does not assume success.

    Registry values are compared with Test-RegistryValueMatch (the same
    normalising comparison the write path uses), so a value written as
    0xffffffff and read back as -1 is correctly reported as Applied.

    Usage:
      .\Verify-System.ps1 -ProfileName Gaming
      .\Verify-System.ps1                       -> prompts for a profile name
#>
param(
    [string]$ProfileName
)

Import-Module (Join-Path $PSScriptRoot 'UWO.psd1') -Force

$profileDefinitions   = Get-ProfileDefinition
$verificationMap      = Get-TweakVerificationMap
$multiRegistryMap     = Get-TweakMultiRegistryMap
$serviceMap           = Get-TweakServiceMap
$multiServiceMap      = Get-TweakMultiServiceMap
$powerPlanMap         = Get-TweakPowerPlanMap

if (-not $ProfileName -or -not $profileDefinitions.ContainsKey($ProfileName)) {
    Write-Host "Available profiles: $((Get-ProfileName) -join ', ')" -ForegroundColor Cyan
    $ProfileName = Read-Host "Enter the profile name to verify"
}

if (-not $profileDefinitions.ContainsKey($ProfileName)) {
    Write-Host "Unknown profile '$ProfileName'." -ForegroundColor Red
    exit 1
}

$logFile = New-LogFile -Name "Verify_$ProfileName"
$tweaks = Get-ProfileTweak -ProfileName $ProfileName

Write-Host ""
Write-Host "=== Verifying profile: $ProfileName ===" -ForegroundColor Cyan

$results = @()
foreach ($tweak in $tweaks) {
    if ($verificationMap.ContainsKey($tweak)) {
        $spec = $verificationMap[$tweak]
        $type = Get-RecordProperty -Record $spec -Name 'Type' -Default 'DWord'
        try {
            $current = (Get-ItemProperty -Path $spec.Path -Name $spec.Name -ErrorAction Stop).$($spec.Name)
            $status = if (Test-RegistryValueMatch -CurrentValue $current -DesiredValue $spec.ExpectedValue -Type $type) {
                'Applied'
            } else {
                "Not Applied (current: $current, expected: $($spec.ExpectedValue))"
            }
        } catch {
            $status = 'Not Applied (registry value not found)'
        }
        $results += [pscustomobject]@{ Tweak = $tweak; Status = $status }
    }
    elseif ($multiRegistryMap.ContainsKey($tweak)) {
        # Multi-value registry tweak (e.g. DisableStartMenuSuggestions): every
        # listed value must match for the tweak to count as 'Applied'.
        $spec = $multiRegistryMap[$tweak]
        $problems = @()
        foreach ($valueSpec in $spec.Values) {
            $type = Get-RecordProperty -Record $valueSpec -Name 'Type' -Default 'DWord'
            try {
                $current = (Get-ItemProperty -Path $valueSpec.Path -Name $valueSpec.Name -ErrorAction Stop).$($valueSpec.Name)
                if (-not (Test-RegistryValueMatch -CurrentValue $current -DesiredValue $valueSpec.ExpectedValue -Type $type)) {
                    $problems += "$($valueSpec.Name)=$current (expected $($valueSpec.ExpectedValue))"
                }
            } catch {
                $problems += "$($valueSpec.Name)=<not found>"
            }
        }
        $status = if ($problems.Count -eq 0) { 'Applied' } else { "Not Applied ($($problems -join '; '))" }
        $results += [pscustomobject]@{ Tweak = $tweak; Status = $status }
    }
    elseif ($serviceMap.ContainsKey($tweak)) {
        $spec = $serviceMap[$tweak]
        try {
            $svc = Get-CimInstance -ClassName Win32_Service -Filter ("Name='{0}'" -f (ConvertTo-CimFilterLiteral -Value $spec.ServiceName)) -ErrorAction Stop
            $status = if ($svc.StartMode -eq $spec.ExpectedStartMode) { 'Applied' } else { "Not Applied (current: $($svc.StartMode), expected: $($spec.ExpectedStartMode))" }
        } catch {
            $status = 'Unknown (service not found)'
        }
        $results += [pscustomobject]@{ Tweak = $tweak; Status = $status }
    }
    elseif ($multiServiceMap.ContainsKey($tweak)) {
        # Multi-service tweak (e.g. DisableXboxServices): all listed services must
        # match the expected start mode for the tweak to count as 'Applied'.
        $spec = $multiServiceMap[$tweak]
        $notMatching = @()
        $notFound = @()
        foreach ($svcName in $spec.ServiceNames) {
            try {
                $svc = Get-CimInstance -ClassName Win32_Service -Filter ("Name='{0}'" -f (ConvertTo-CimFilterLiteral -Value $svcName)) -ErrorAction Stop
                if ($svc.StartMode -ne $spec.ExpectedStartMode) {
                    $notMatching += "$svcName=$($svc.StartMode)"
                }
            } catch {
                $notFound += $svcName
            }
        }
        if ($notFound.Count -gt 0) {
            $status = "Not Applied (services not found: $($notFound -join ', '))"
        } elseif ($notMatching.Count -gt 0) {
            $status = "Not Applied (mismatched: $($notMatching -join ', '); expected: $($spec.ExpectedStartMode))"
        } else {
            $status = 'Applied'
        }
        $results += [pscustomobject]@{ Tweak = $tweak; Status = $status }
    }
    elseif ($powerPlanMap.ContainsKey($tweak)) {
        # Power-plan tweak: parse the active scheme GUID and compare against
        # the well-known alias GUIDs (SCHEME_MIN = High Performance, SCHEME_BALANCED = Balanced).
        $expectedAlias = $powerPlanMap[$tweak]
        try {
            $active = (powercfg.exe /getactivescheme) -join ''
            $isActive = $false
            switch ($expectedAlias) {
                'SCHEME_MIN'      { $isActive = $active -match 'High Performance' -or $active -match '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' }
                'SCHEME_BALANCED'  { $isActive = $active -match 'Balanced' -or $active -match '381b4222-f694-41f0-9685-ff5bb260df2e' }
            }
            $status = if ($isActive) { 'Applied' } else { "Not Applied (current active scheme: $active)" }
        } catch {
            $status = 'Unknown (powercfg /getactivescheme failed)'
        }
        $results += [pscustomobject]@{ Tweak = $tweak; Status = $status }
    }
    elseif ($tweak -eq 'DisableHibernation') {
        # Hibernation is 'applied' (i.e. disabled) when powercfg reports it as off.
        try {
            $hbnOut = (powercfg.exe /a) -join ''
            $isOff = $hbnOut -match 'Hibernation has been disabled' -or ($hbnOut -split '`n' | Where-Object { $_ -match 'Hibernation' -and $_ -match 'Unavailable' }).Count -gt 0
            $status = if ($isOff) { 'Applied' } else { 'Not Applied (hibernation still enabled)' }
        } catch {
            $status = 'Unknown (powercfg /a failed)'
        }
        $results += [pscustomobject]@{ Tweak = $tweak; Status = $status }
    }
    elseif ($tweak -eq 'EnableUSBSelectiveSuspend') {
        # USB selective suspend is stored per active power scheme; both the AC
        # and DC value must be 1 for the tweak to count as applied.
        try {
            $schemeGuid = Get-ActivePowerSchemeGuid
            if (-not $schemeGuid) {
                $status = 'Unknown (active power scheme could not be determined)'
            } else {
                $usbKey = Get-UsbSelectiveSuspendKey -SchemeGuid $schemeGuid
                $ac = (Get-ItemProperty -Path $usbKey -Name 'ACSettingIndex' -ErrorAction Stop).ACSettingIndex
                $dc = (Get-ItemProperty -Path $usbKey -Name 'DCSettingIndex' -ErrorAction Stop).DCSettingIndex
                $status = if ($ac -eq 1 -and $dc -eq 1) { 'Applied' } else { "Not Applied (AC=$ac, DC=$dc; expected 1/1)" }
            }
        } catch {
            $status = 'Not Applied (USB selective-suspend values not found)'
        }
        $results += [pscustomobject]@{ Tweak = $tweak; Status = $status }
    }
    else {
        $results += [pscustomobject]@{ Tweak = $tweak; Status = 'Unknown (not automatically verifiable - check manually via Settings/powercfg)' }
    }
}

$results | Format-Table -AutoSize | Out-String | ForEach-Object { Write-Host $_ }

foreach ($r in $results) {
    $level = if ($r.Status -eq 'Applied') { 'OK' } elseif ($r.Status -like 'Not Applied*') { 'WARN' } else { 'INFO' }
    Write-Log -Message "$($r.Tweak): $($r.Status)" -LogFile $logFile -Level $level
}

$appliedCount = ($results | Where-Object { $_.Status -eq 'Applied' }).Count
Write-Host ""
Write-Host "$appliedCount of $($results.Count) automatically-verifiable tweaks confirmed applied." -ForegroundColor Cyan
