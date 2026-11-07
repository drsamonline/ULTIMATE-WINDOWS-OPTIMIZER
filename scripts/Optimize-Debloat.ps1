<#
    Optimize-Debloat.ps1
    Privacy / debloat profile: removes the consumer and telemetry surface that
    ships switched on - the CEIP and Application Experience scheduled tasks,
    Copilot, Recall, Bing/web suggestions in Start, the Widgets feed, activity
    history, the advertising ID, feedback prompts and app-launch tracking.

    Everything here is a registry value or a scheduled-task state, so every
    change is written to a backup record first and Undo-All-Changes.ps1 puts it
    back. Nothing is uninstalled and no app is removed - unlike most debloat
    scripts, this profile never deletes anything it cannot restore.
#>
Import-Module (Join-Path $PSScriptRoot 'UWO.psd1') -Force

$tweaks = Get-ProfileTweak -ProfileName 'Debloat'

Invoke-OptimizationProfile -ProfileName 'Debloat' -Tweaks $tweaks `
    -Guards @('Disables telemetry scheduled tasks, Copilot, Recall, web search suggestions in Start, Widgets, activity history and the advertising ID. All changes are reversible with Undo-All-Changes.ps1 - no apps are uninstalled.')
