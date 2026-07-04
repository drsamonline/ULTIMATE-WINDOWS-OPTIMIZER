<#
    Optimize-Gaming.ps1
    Desktop gaming profile: hardware-accelerated GPU scheduling, foreground
    priority boost for games, network throttling removed, Game DVR overhead
    removed, High Performance power plan. Intended for desktops, not laptops
    on battery (see Optimize-Laptop.ps1 for the battery-aware equivalent).
#>
. (Join-Path $PSScriptRoot 'Common-Functions.ps1')

$tweaks = @(
    'DisableTelemetry'
    'EnableHAGS'
    'GamingPriorityBoost'
    'DisableNetworkThrottling'
    'DisableGameDVR'
    'PowerPlanHighPerformance'
    'VisualEffectsBestPerformance'
)

Invoke-OptimizationProfile -ProfileName 'Gaming' -Tweaks $tweaks `
    -Guards @('This profile sets a High Performance power plan, which increases power draw. Not recommended for battery-powered laptops - use Optimize-Laptop.ps1 instead.')
