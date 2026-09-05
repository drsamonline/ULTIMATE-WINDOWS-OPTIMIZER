<#
    Optimize-Office.ps1
    Productivity/office profile: removes background-app and consumer-focused
    overhead (Xbox services, Start menu ads, background UWP apps) that has
    no purpose on a work machine, while keeping the system on a balanced,
    predictable power plan. Deliberately does NOT touch GPU scheduling or
    CPU priority separation - those provide no benefit for office workloads
    and are reserved for the Gaming/Extreme/Godlike/Streaming profiles.
#>
Import-Module (Join-Path $PSScriptRoot 'UWO.psd1') -Force

$tweaks = Get-ProfileTweak -ProfileName 'Office'

Invoke-OptimizationProfile -ProfileName 'Office' -Tweaks $tweaks
