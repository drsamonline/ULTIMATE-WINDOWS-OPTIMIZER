<#
    Optimize-Streaming.ps1
    Profile for content creators running a game plus capture/streaming
    software (OBS, XSplit, etc.) at the same time. Unlike the pure Gaming
    profile, this lowers SystemResponsiveness so background multimedia
    tasks (encoding/capture) are not starved of CPU time by the foreground
    game - a real, documented tweak used by streaming-focused guides.
#>
. (Join-Path $PSScriptRoot 'Common-Functions.ps1')

$tweaks = @(
    'DisableTelemetry'
    'EnableHAGS'
    'GamingPriorityBoost'
    'DisableNetworkThrottling'
    'LowerSystemResponsivenessForMultimedia'
    'PowerPlanHighPerformance'
    'VisualEffectsBestPerformance'
)

Invoke-OptimizationProfile -ProfileName 'Streaming' -Tweaks $tweaks `
    -Guards @('SystemResponsiveness lowered so capture/encoding software is not starved of CPU by the foreground game.')
