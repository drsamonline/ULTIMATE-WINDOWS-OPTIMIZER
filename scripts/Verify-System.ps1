<#
    Verify-System.ps1
    Checks the CURRENT system state against what a chosen profile is
    supposed to have applied, and reports Applied / Not Applied / Unknown
    per tweak - it does not assume success.

    Usage:
      .\Verify-System.ps1 -ProfileName Gaming
      .\Verify-System.ps1                       -> prompts for a profile name
#>
param(
    [string]$ProfileName
)

. (Join-Path $PSScriptRoot 'Common-Functions.ps1')

if (-not $ProfileName -or -not $Global:ProfileDefinitions.ContainsKey($ProfileName)) {
    Write-Host "Available profiles: $($Global:ProfileDefinitions.Keys -join ', ')" -ForegroundColor Cyan
    $ProfileName = Read-Host "Enter the profile name to verify"
}

if (-not $Global:ProfileDefinitions.ContainsKey($ProfileName)) {
    Write-Host "Unknown profile '$ProfileName'." -ForegroundColor Red
    exit 1
}

$logFile = New-LogFile -Name "Verify_$ProfileName"
$tweaks = $Global:ProfileDefinitions[$ProfileName]

Write-Host ""
Write-Host "=== Verifying profile: $ProfileName ===" -ForegroundColor Cyan

$results = @()
foreach ($tweak in $tweaks) {
    if ($Global:TweakVerificationMap.ContainsKey($tweak)) {
        $spec = $Global:TweakVerificationMap[$tweak]
        try {
            $current = (Get-ItemProperty -Path $spec.Path -Name $spec.Name -ErrorAction Stop).$($spec.Name)
            $status = if ($current -eq $spec.ExpectedValue) { 'Applied' } else { "Not Applied (current: $current, expected: $($spec.ExpectedValue))" }
        } catch {
            $status = 'Not Applied (registry value not found)'
        }
        $results += [pscustomobject]@{ Tweak = $tweak; Status = $status }
    }
    elseif ($Global:TweakServiceMap.ContainsKey($tweak)) {
        $spec = $Global:TweakServiceMap[$tweak]
        try {
            $svc = Get-CimInstance -ClassName Win32_Service -Filter "Name='$($spec.ServiceName)'" -ErrorAction Stop
            $status = if ($svc.StartMode -eq $spec.ExpectedStartMode) { 'Applied' } else { "Not Applied (current: $($svc.StartMode), expected: $($spec.ExpectedStartMode))" }
        } catch {
            $status = 'Unknown (service not found)'
        }
        $results += [pscustomobject]@{ Tweak = $tweak; Status = $status }
    }
    elseif ($Global:TweakMultiServiceMap.ContainsKey($tweak)) {
        # Multi-service tweak (e.g. DisableXboxServices): all listed services must
        # match the expected start mode for the tweak to count as 'Applied'.
        $spec = $Global:TweakMultiServiceMap[$tweak]
        $notMatching = @()
        $notFound = @()
        foreach ($svcName in $spec.ServiceNames) {
            try {
                $svc = Get-CimInstance -ClassName Win32_Service -Filter "Name='$svcName'" -ErrorAction Stop
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
    elseif ($Global:TweakPowerPlanMap.ContainsKey($tweak)) {
        # Power-plan tweak: parse the active scheme GUID and compare against
        # the well-known alias GUIDs (SCHEME_MIN = High Performance, SCHEME_BALANCED = Balanced).
        $expectedAlias = $Global:TweakPowerPlanMap[$tweak]
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
