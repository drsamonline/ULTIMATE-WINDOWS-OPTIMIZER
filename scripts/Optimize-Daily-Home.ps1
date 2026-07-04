<#
    Optimize-Daily-Home.ps1
    Balanced profile for everyday home/family PCs: browsing, email, video calls,
    light office work. Prioritizes stability and battery/thermal friendliness
    over raw throughput. Does NOT touch GPU scheduling, priority separation,
    or memory paging - those are reserved for the Gaming/Extreme/Godlike profiles.
#>
. (Join-Path $PSScriptRoot 'Common-Functions.ps1')

$tweaks = @(
    'DisableTelemetry'
    'DisableStartupDelay'
    'DisableStartMenuSuggestions'
    'DisableBackgroundApps'
    'VisualEffectsBalanced'
    'PowerPlanBalanced'
)

Invoke-OptimizationProfile -ProfileName 'Daily-Home' -Tweaks $tweaks
