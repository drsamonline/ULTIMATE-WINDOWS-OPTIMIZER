<#
    Permanent-Debloat.ps1
    ---------------------
    IRREVERSIBLE.

    This script performs debloat actions that CANNOT be undone by this toolkit:
    uninstalling consumer Appx packages, uninstalling the OneDrive client, and
    compacting the component store (DISM /ResetBase).

    There is no backup record and no rollback. Undo-All-Changes.ps1 does not
    touch any of it. Every action is appended to a separate, append-only ledger
    at %USERPROFILE%\OptimizationLogs\PermanentChanges.log so you can see what
    was done - but you cannot put it back from here.

    Typing I UNDERSTAND is required before anything changes.
#>
Import-Module (Join-Path $PSScriptRoot 'UWO.psd1') -Force

Assert-Admin

Write-Host "=========================================================" -ForegroundColor Red
Write-Host "  PERMANENT / IRREVERSIBLE DEBLOAT" -ForegroundColor Red
Write-Host "=========================================================" -ForegroundColor Red
Write-Host ""
Write-Host "  Everything in this script is a one-way door." -ForegroundColor Yellow
Write-Host "  No backup is written. Undo-All-Changes.ps1 cannot revert it." -ForegroundColor Yellow
Write-Host ""

$ops   = Get-IrreversibleOperation
$names = Get-IrreversibleName
$i = 1
foreach ($name in $names) {
    Write-Host ("  [{0}] {1}" -f $i, $ops[$name].Title) -ForegroundColor White
    Write-Host ("      {0}" -f $ops[$name].Warning) -ForegroundColor DarkYellow
    $i++
}
Write-Host "  [A] All of the above" -ForegroundColor White
Write-Host "  [Q] Quit" -ForegroundColor White
Write-Host ""

$choice = Read-Host "Choose"
if ($choice -match '^[Qq]$') {
    Write-Host "Aborted - nothing changed." -ForegroundColor Cyan
    exit 0
}

if ($choice -match '^[Aa]$') {
    $selected = $names
} elseif ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $names.Count) {
    $selected = @($names[[int]$choice - 1])
} else {
    Write-Host "Invalid choice - nothing changed." -ForegroundColor Red
    exit 1
}

Write-Host ""
$confirm = Read-Host "Type I UNDERSTAND to make these changes permanent"
if ($confirm -cne 'I UNDERSTAND') {
    Write-Host "Aborted - nothing changed." -ForegroundColor Cyan
    exit 0
}

$logFile = New-LogFile -Name 'PermanentDebloat'
Write-Log -Message "Permanent debloat started: $($selected -join ', ')" -LogFile $logFile -Level WARN

foreach ($key in $selected) {
    Invoke-IrreversibleOperation -Key $key -LogFile $logFile | Out-Null
}

Write-Log -Message 'Permanent debloat finished. These changes cannot be undone.' -LogFile $logFile -Level WARN
Write-Host ""
Write-Host "Ledger: $(Get-PermanentLedgerPath)" -ForegroundColor Red
Write-Host "These changes are permanent. Undo-All-Changes.ps1 will not revert them." -ForegroundColor Red
