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
    else {
        # Tweaks like PowerPlanHighPerformance, DisableHibernation, PowerPlanBalanced, DisableStartMenuSuggestions
        # (multi-value) aren't single-value-checkable here; verified as "Unknown - check manually".
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
