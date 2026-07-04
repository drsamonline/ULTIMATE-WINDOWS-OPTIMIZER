# Ultimate Windows Optimizer v6.0

A PowerShell + batch toolkit for applying documented, reversible Windows
performance tweaks, organized into profiles for different use cases.

> **v6.0 is a full rewrite of the earlier v5.1 release.** In v5.1, all 8
> "profiles" secretly ran the same four registry tweaks under different
> labels, and several utility scripts printed hard-coded success messages
> instead of doing real work. v6.0 fixes both problems: every profile below
> applies a genuinely different, explicit set of tweaks, and every utility
> script measures or checks the real system state. See `CHANGELOG.md` for
> the full list of changes.

## What this is (and isn't)

This is a set of well-known, individually-documented Windows tweaks
(disabling telemetry, adjusting CPU priority separation, GPU scheduling,
power plans, visual effects, etc.) wired up with:

- **Real logging** to `%USERPROFILE%\OptimizationLogs`
- **Real backups** of every registry value and service state changed, so
  `Undo-All-Changes.ps1` can put your system back exactly as it was
- **Real verification and benchmarking** utilities that check actual system
  state instead of printing canned numbers

This is **not** a magic performance multiplier. Results depend entirely on
your hardware and workload. No specific percentage improvement is promised
anywhere in this toolkit - use `Performance-Monitor.ps1` before and after to
measure your own real before/after numbers with `Compare-Results.ps1`.

## Requirements

- Windows 10 (build 17763+) or Windows 11
- PowerShell 5.1+ (built in to Windows)
- Administrator rights
- Run `Compatibility-Check.ps1` first (menu option `9`) to confirm your machine meets these

## Quick start

1. Extract the ZIP anywhere.
2. Right-click `scripts\00_Ultimate_Master_v6.0.bat` -> **Run as administrator**.
3. Choose option `9` (Compatibility Check) first.
4. Choose option `S` to create a System Restore point (recommended before your first run).
5. Choose option `M` (Performance Snapshot) and label it `Baseline`.
6. Pick a profile (1-8).
7. Optionally take another snapshot (`M`, label it e.g. `AfterGaming`) and run `R` (Compare Two Snapshots) to see real before/after numbers.
8. If you ever want to revert everything this toolkit changed, choose `U` (Undo All Tracked Changes).

## Profiles - what each one actually does differently

| Profile | Key tweaks | Notably does NOT do |
|---|---|---|
| **Daily Home** | Disable telemetry, disable Start Menu ads, disable background apps, balanced visual effects, Balanced power plan | No GPU/priority/memory tweaks |
| **Gaming** | GPU hardware scheduling, foreground priority boost, network throttling removed, Game DVR off, High Performance power plan | Not recommended for battery-powered laptops |
| **Office** | Background-app + Xbox-service removal, explicit balanced priority separation | No GPU scheduling or priority boost |
| **Laptop** | USB selective suspend, **disables** HAGS (saves power on hybrid-GPU laptops), Balanced power plan | Never disables hibernation or memory paging |
| **Extreme** | Everything in Gaming + hibernation removed; `DisablePagingExecutive` only if RAM ≥ 16GB; Superfetch disabled only if system drive is confirmed SSD | Desktop only |
| **Godlike** | Everything in Extreme + Windows Search indexing disabled + Xbox services disabled. **Requires typing `CONFIRM`** because it trades away Start-menu/file search speed | Desktop enthusiast machines only |
| **Server** | Disables Search indexing and Xbox services, removes hibernation, favors background-service CPU priority over foreground apps (opposite of Gaming) | No GPU/gaming tweaks |
| **Streaming** | Gaming-profile tweaks + `SystemResponsiveness` lowered so capture/encoding software isn't CPU-starved by the foreground game | - |

Full tweak definitions live in `scripts/Common-Functions.ps1` under
`Invoke-Tweak` and `$Global:ProfileDefinitions` - read them before running
anything you don't understand.

## Utilities

- **Compatibility-Check.ps1** - real PASS/FAIL checks (admin rights, OS build, PowerShell version, RAM, disk space, System Restore availability)
- **Hardware-Detection.ps1** - real CPU/GPU/RAM/disk/motherboard info via CIM
- **Performance-Monitor.ps1** - saves a labeled, real snapshot (CPU load, RAM, disk free, top processes)
- **Compare-Results.ps1** - diffs two real snapshots you choose; refuses to run with fewer than 2 snapshots
- **Cleanup-System.ps1** - clears temp/cache/Recycle Bin and reports the actual GB freed (measured, not estimated)
- **Advanced-Modules.ps1** - runs 8 independent tweaks and reports a real success/fail count
- **Verify-System.ps1** - checks current registry/service state against what a chosen profile should have applied
- **System-Rollback.ps1** - creates a real Windows System Restore point, or opens System Restore
- **Undo-All-Changes.ps1** - reads every backup file this toolkit has written and restores every tracked registry value, service, and hibernation setting to its original state

## Safety notes

- Every registry/service change is backed up **before** it's applied. Nothing is a one-way door.
- `Undo-All-Changes.ps1` supports `-WhatIf` to preview what it would restore without changing anything.
- The `Godlike` profile requires typed confirmation because it disables Windows Search indexing, which has a real usability cost.
- The optional dependency downloader (menu `D`) only opens official vendor download pages - it does not silently run anything, and does not claim to verify file signatures for you.

## License

BSD 3-Clause. See `LICENSE`.

Created by Dr. Sohil Momin (Coding For Fun / @DrSamOnline).
