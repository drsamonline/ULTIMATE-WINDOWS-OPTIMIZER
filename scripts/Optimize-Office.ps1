<#
    Optimize-Office.ps1
    Productivity/office profile: removes background-app and consumer-focused
    overhead (Xbox services, Start menu ads, background UWP apps) that has
    no purpose on a work machine, while keeping the system on a balanced,
    predictable power plan. Deliberately does NOT touch GPU scheduling or
    CPU priority separation - those provide no benefit for office workloads
    and are reserved for the Gaming/Extreme/Godlike/Streaming profiles.
#>
. (Join-Path $PSScriptRoot 'Common-Functions.ps1')

$tweaks = @(
    'DisableTelemetry'
    'DisableStartMenuSuggestions'
    'DisableBackgroundApps'
    'DisableXboxServices'
    'VisualEffectsBalanced'
    'PowerPlanBalanced'
    'BalancedPrioritySeparation'
)

Invoke-OptimizationProfile -ProfileName 'Office' -Tweaks $tweaks
