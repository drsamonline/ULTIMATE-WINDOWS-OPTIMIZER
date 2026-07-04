<#
    Optimize-Laptop.ps1
    Battery-aware profile for laptops/notebooks.

    Deliberately does the OPPOSITE of the Gaming/Extreme profiles on two
    points, because they would hurt a battery-powered machine:
      - Disables (not enables) Hardware-Accelerated GPU Scheduling on hybrid
        GPU laptops, since HAGS can increase idle power draw on some
        Optimus/hybrid-graphics systems.
      - Never disables hibernation - laptops rely on it for lid-close /
        low-battery safety.
      - Never disables paging executive - that increases RAM residency and
        works against power-saving goals.

    Instead it focuses on: USB selective suspend (saves power on idle USB
    devices), a Balanced power plan, and trimming background overhead.
#>
. (Join-Path $PSScriptRoot 'Common-Functions.ps1')

$tweaks = @(
    'DisableTelemetry'
    'DisableStartMenuSuggestions'
    'DisableBackgroundApps'
    'DisableHAGS'
    'EnableUSBSelectiveSuspend'
    'VisualEffectsBalanced'
    'PowerPlanBalanced'
)

Invoke-OptimizationProfile -ProfileName 'Laptop' -Tweaks $tweaks `
    -Guards @('Hibernation and memory paging settings are intentionally left untouched to preserve battery safety and RAM headroom.')
