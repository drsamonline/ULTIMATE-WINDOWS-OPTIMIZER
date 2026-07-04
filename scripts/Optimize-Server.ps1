<#
    Optimize-Server.ps1
    Profile for machines used as a headless/background file, media, or app
    server. Assumes no local gaming/graphics workload and no need for local
    Windows Search indexing or Xbox integration. Prioritizes consistent
    background service throughput over foreground desktop responsiveness -
    the opposite of the Gaming profile's priority boost.
#>
. (Join-Path $PSScriptRoot 'Common-Functions.ps1')

$tweaks = @(
    'DisableTelemetry'
    'DisableSearchIndexingService'
    'DisableXboxServices'
    'DisableHibernation'
    'PowerPlanHighPerformance'
    'VisualEffectsBestPerformance'
    'ServerPrioritySeparation'
)

Invoke-OptimizationProfile -ProfileName 'Server' -Tweaks $tweaks `
    -Guards @('Assumes a headless/background-service machine: Windows Search indexing is disabled and CPU priority favors background services over foreground apps.')
