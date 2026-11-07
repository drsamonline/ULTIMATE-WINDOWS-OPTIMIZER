#Requires -Version 5.1
<#
    Version consistency tests.

    VERSION is the single source of truth for the product version. Every
    artefact that states the version must agree with it, or this suite fails -
    which is what stops the version drifting again after a hand edit.

    Pure file reads (no registry, no services), so this runs on any platform
    PowerShell supports.
#>

BeforeDiscovery {
    # -ForEach data is evaluated at discovery time, so it has to live here
    # rather than in BeforeAll.
    $script:VersionSources = @(
        @{ File = 'scripts/UWO.psd1';              Pattern = 'ModuleVersion\s*=\s*''(\d+\.\d+\.\d+)''' }
        @{ File = 'scripts/00_Ultimate_Master.bat'; Pattern = 'title Ultimate Windows Optimizer v(\d+\.\d+\.\d+)' }
        @{ File = 'scripts/00_Ultimate_Master.bat'; Pattern = 'ULTIMATE WINDOWS OPTIMIZER v(\d+\.\d+\.\d+)' }
        @{ File = 'QUICK_START.txt';                Pattern = 'ULTIMATE WINDOWS OPTIMIZER v(\d+\.\d+\.\d+)' }
        @{ File = 'README.md';                      Pattern = 'version-(\d+\.\d+\.\d+)-' }
        @{ File = 'docs/index.html';                Pattern = '"softwareVersion":\s*"(\d+\.\d+\.\d+)"' }
        @{ File = 'docs/index.html';                Pattern = '<span class="badge">v(\d+\.\d+\.\d+)</span>' }
        @{ File = 'docs/index.html';                Pattern = 'ULTIMATE WINDOWS OPTIMIZER v(\d+\.\d+\.\d+)' }
        @{ File = 'docs/__dbg.html';                Pattern = '"softwareVersion":\s*"(\d+\.\d+\.\d+)"' }
        @{ File = 'docs/__dbg.html';                Pattern = '<span class="badge">v(\d+\.\d+\.\d+)</span>' }
        @{ File = 'docs/__dbg.html';                Pattern = 'ULTIMATE WINDOWS OPTIMIZER v(\d+\.\d+\.\d+)' }
        @{ File = 'docs/images/main-menu.svg';      Pattern = 'ULTIMATE WINDOWS OPTIMIZER v(\d+\.\d+\.\d+)' }
    )
}

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:VersionFile = Join-Path $script:RepoRoot 'VERSION'
    $script:Version = if (Test-Path $script:VersionFile) {
        (Get-Content -Path $script:VersionFile -Raw).Trim()
    } else { '' }
}

Describe 'Version consistency' {

    It 'has a VERSION file holding a plain X.Y.Z version' {
        Test-Path $script:VersionFile | Should -BeTrue -Because 'VERSION is the single source of truth'
        $script:Version | Should -Match '^\d+\.\d+\.\d+$' -Because "VERSION held '$($script:Version)'"
    }

    It 'states the current version in <File> (<Pattern>)' -ForEach $script:VersionSources {
        $path = Join-Path $script:RepoRoot $File
        Test-Path $path | Should -BeTrue -Because "$File is part of the shipped artefacts"

        $text = Get-Content -Path $path -Raw
        $match = [regex]::Match($text, $Pattern)
        $match.Success | Should -BeTrue -Because "$File should still contain a version string matching $Pattern"

        $match.Groups[1].Value | Should -Be $script:Version -Because "$File must agree with VERSION ($($script:Version))"
    }
}
