# Changelog

## v6.1.0 - Undo correctness, idempotency, module packaging

Behaviour-affecting release. The theme is making the reversibility guarantee
hold on the second run, not just the first, and making the shared engine
testable.

- **Registry backup records are written only after the change succeeds.**
  `Set-RegistryValueSafe` called `Add-BackupRecord` *before* `New-ItemProperty`,
  so a failed write left a phantom record that `Undo-All-Changes.ps1` would
  later try to "restore" (or, for a value that never existed, delete). The
  record is now written after the value has actually been set - the same
  ordering the v6.0.1 `powercfg`/`Invoke-NativeCommand` fix introduced for
  native commands.
- **Registry keys created by the toolkit are removed again on undo.** Backup
  records now carry a `KeyCreated` field recording whether the target key had
  to be created. `Restore-RegistryBackupRecord` removes the value as before and
  then removes the key too - but only when the toolkit created it and it is
  still empty (no remaining values, no subkeys), so a key something else has
  since written to is left alone. The removal is logged. Backup files written
  by older versions simply have no `KeyCreated` field and keep the old
  behaviour.
- **Re-running a profile no longer corrupts the original-value baseline.**
  Previously, a second run recorded the already-tweaked value as
  `OriginalValue`, so undo restored the tweak instead of your setting. Two
  changes fix this:
  - `Set-RegistryValueSafe` now compares the current value with the value it is
    about to write and, if they already match, skips both the write and the
    backup record (logged as already-applied).
  - `Undo-All-Changes.ps1` de-duplicates registry records across all backup
    files by `Path\Name` (files are read oldest-first) and restores the
    *earliest* recorded original, so a later run's stale record can never
    override the true pre-toolkit value.
- **`DisableStartMenuSuggestions` is now fully verified.** The tweak writes two
  values but verification only checked `SubscribedContent-338388Enabled`. A new
  multi-value registry map (analogous to the existing multi-service map) lists
  both `SubscribedContent-338388Enabled` and `SystemPaneSuggestionsEnabled`, and
  `Verify-System.ps1` reports `Applied` only when *both* are `0`, naming the
  missing or mismatched value otherwise. The single-value entry was removed.
- **Backup-file retention (new menu option `P`).** Backup JSON files used to
  accumulate indefinitely. `Cleanup-Backups.ps1` prunes them conservatively: a
  file is deleted only if it is **both** outside the newest `-KeepCount`
  (default 20) files **and** older than `-MaxAgeDays` (default 30). Backups that
  have not been undone yet are never pruned unless `-IncludePending` is passed,
  since they are the only record of changes still applied to the machine.
  `-WhatIf` previews; every prune and retention decision is logged.
- **Power plans restore independently of system locale.** The plan GUID is now
  extracted from `powercfg /getactivescheme` at capture time and stored as a
  clean `OriginalGuid` (with the raw output kept as `OriginalSchemeRaw` for
  diagnostics), instead of being regex-parsed out of localized output at undo
  time. Older backup records that only contain the raw string are still parsed
  as a fallback.
- **Hardened the CIM filter in `Set-ServiceStateSafe`.** The original start mode
  is now read from the `ServiceController` object already returned by
  `Get-Service`; the CIM query is only a fallback and escapes the service name
  before interpolating it into the WQL filter. `Verify-System.ps1` escapes its
  service-name filters the same way.
- **The shared engine is now a module.** `scripts/Common-Functions.ps1` became
  `scripts/UWO.psm1` with a `scripts/UWO.psd1` manifest, module-scoped state in
  place of `$Global:` variables, accessor functions
  (`Get-ProfileDefinition`, `Get-ProfileTweak`, `Get-Tweak*Map`,
  `Get-Uwo*Directory`) and an explicit `Export-ModuleMember` surface. Every
  script now uses `Import-Module` instead of dot-sourcing.
  `scripts/Common-Functions.ps1` remains as a thin shim that imports the module
  and re-publishes the old `$Global:*` names, so external scripts that
  dot-source it keep working. `$env:UWO_LOG_ROOT` can redirect the
  logs/backups/snapshots tree (used by the tests).
- **Profile definitions are the single source of truth for tweak lists.** Each
  `Optimize-*.ps1` hard-coded a `$tweaks` array duplicating the catalog entry;
  they now call `Get-ProfileTweak`, so the two cannot drift. `Optimize-Extreme`
  and `Optimize-Godlike` strip the hardware-gated `DisablePagingExecutive` /
  `DisableSysMain` from the catalog list and re-append them at runtime behind
  the existing RAM >= 16GB and SSD checks, exactly as before.
- **Tests and CI.** New `tests/` Pester suite covering backup-after-success,
  `KeyCreated` tracking and created-key removal, the idempotent skip, valid
  empty-array backup files, value restore, the oldest-wins de-duplication,
  power-plan GUID extraction, WQL escaping, and retention. Registry tests only
  touch `HKCU:\Software\UWO-Test` and are skipped on non-Windows hosts. The
  suite is intended to run under Windows PowerShell 5.1 on `windows-latest`
  together with `PSScriptAnalyzer` (settings in `PSScriptAnalyzerSettings.psd1`).
- **Smaller fixes.** `Cleanup-System.ps1` now tells the user when a negative
  measured delta was clamped to 0 GB, and `Compatibility-Check.ps1` no longer
  assigns an unused restore-point variable.

## v6.0.1 - Bug-fix release

This release fixes several correctness bugs in v6.0 that were found by an
independent code review. No new features were added; the goal was to make
the safety guarantees that v6.0 advertises actually hold in practice.

- **Backup files were created empty instead of as `[]`.** `New-BackupFile`
  used `@() | ConvertTo-Json | Set-Content`, which on PowerShell 5.1
  produces an empty file (no output is sent down the pipeline). The
  downstream `Add-BackupRecord` then produced JSON arrays beginning with a
  spurious `$null` entry, which polluted every backup file in
  `%USERPROFILE%\OptimizationLogs\Backups`. Fixed by writing the literal
  `'[]'` to the file. `Add-BackupRecord` now also defensively coerces
  null/empty/unreadable files to an empty array and filters out any
  pre-existing `$null` entries when reading.
- **Power-plan GUID was captured AFTER switching, not BEFORE.**
  `PowerPlanHighPerformance` recorded `(powercfg /getactivescheme)` *after*
  calling `powercfg /setactive SCHEME_MIN`, so the backup stored the new
  High-Performance GUID instead of the user's original plan. Combined with
  the next item, this made power-plan changes effectively irreversible
  through the toolkit. Fixed by capturing the active scheme BEFORE switching.
- **`PowerPlanBalanced` tweak wrote no backup record at all.** Even after
  the previous fix, this tweak had no undo record, so `Undo-All-Changes.ps1`
  could not restore it. Fixed with symmetric backup handling.
- **Power-plan changes are now actually restored by Undo-All-Changes.ps1.**
  Previously, the undo script only logged a warning telling the user to
  restore the plan manually via Control Panel. It now parses the GUID out
  of the recorded `powercfg /getactivescheme` output and calls
  `powercfg /setactive <guid>` to actually restore it. If parsing fails
  (e.g. old v6.0 backup files), it falls back to the warning.
- **`DisableHibernation` / PowerPlan tweaks recorded backups even when
  `powercfg` failed.** PowerShell's `&` operator does not throw on
  non-zero exit codes from native commands, so the `try`/`catch` block
  never triggered. The backup record was then written unconditionally,
  and `Undo-All-Changes.ps1` would later try to "restore" something that
  was never changed. Fixed by a new `Invoke-NativeCommand` wrapper that
  checks `$LASTEXITCODE` and throws on failure.
- **`Invoke-Tweak` swallowed inner failures.** Every tweak's `switch` case
  called `Set-RegistryValueSafe` / `Set-ServiceStateSafe` (which return
  `$true`/`$false`) but the result was discarded. `Invoke-OptimizationProfile`
  and `Advanced-Modules.ps1` therefore always incremented their "applied"
  counters unconditionally, even when the underlying tweak silently failed.
  Fixed: every `Invoke-Tweak` case now returns the boolean result of its
  underlying calls, and callers capture and act on it. The "real success/fail
  count" promise in the v6.0 CHANGELOG now actually holds.
- **`Undo-All-Changes.ps1` aborted the entire undo run on a single
  corrupted backup file.** `Get-Content -Raw | ConvertFrom-Json` was not
  wrapped in a try/catch, and with `$ErrorActionPreference = 'Stop'` a
  single malformed file would halt the run mid-stream, leaving later
  backup files unrestored. Fixed with a try/catch around the parse, with
  the corrupted file logged and skipped rather than crashing.
- **`Restore-ServiceBackupRecord` silently downgraded Boot/System services
  to Manual.** Win32_Service `StartMode` can be `Boot` or `System` for
  kernel drivers, but `Set-Service -StartupType` only accepts
  `Automatic`/`Manual`/`Disabled`. The old code defaulted unknown modes to
  `Manual`, which would have misconfigured any kernel driver this toolkit
  had touched. Fixed: it now logs a clear warning and skips the
  startup-type restore for Boot/System services.
- **`Verify-System.ps1` couldn't verify power plans, Xbox services, Start
  menu suggestions, or hibernation.** All four were reported as "Unknown -
  not automatically verifiable" even though they're real, checkable
  changes. Fixed: `Common-Functions.ps1` now exposes `$Global:TweakPowerPlanMap`,
  `$Global:TweakMultiServiceMap`, and entries in the existing maps for
  `DisableStartMenuSuggestions`. `Verify-System.ps1` checks the active
  power plan via `powercfg /getactivescheme`, walks every service in a
  multi-service tweak, and checks hibernation via `powercfg /a`.
- **`$Global:ProfileDefinitions` for Extreme/Godlike didn't include the
  hardware-gated tweaks** (`DisablePagingExecutive`, `DisableSysMain`),
  even though README/CHANGELOG claimed those profiles apply them.
  `Verify-System.ps1` therefore reported an incomplete verification
  result for those profiles. Fixed: the gated tweaks are now listed in
  `ProfileDefinitions`. (The runtime gating in `Optimize-Extreme.ps1` and
  `Optimize-Godlike.ps1` still happens as before - if the hardware gate
  fails at runtime, the .ps1 script skips the tweak, and Verify-System
  then correctly reports it as "Not Applied".)
- **`Compatibility-Check.ps1` PowerShell version check was too loose.**
  `$psVersion.Major -ge 5` would pass on the unreleased PowerShell 5.0
  preview. README says "5.1+ required" - the check now uses
  `$psVersion -ge [version]'5.1'`.
- **`Compatibility-Check.ps1` System Restore check was misleading.** It
  returned PASS if the `Checkpoint-Computer` cmdlet existed, which is true
  on every modern Windows. It did not actually check whether System
  Restore was enabled on the system drive. Fixed: it now queries
  `root/default:SystemRestoreConfig.RPSessionInterval` and falls back to
  enumerating restore points before falling back to the cmdlet-existence
  check.
- **`System-Rollback.ps1` silently chose option 2 for any non-1 input.**
  Typing 'q', 'x', or anything other than '1' would silently launch the
  restore-point-listing UI. Fixed: only '1' and '2' are accepted;
  anything else aborts with a clear message.
- **`Cleanup-System.ps1` could report a negative "space freed" number.**
  If a background service wrote a large file between the before/after
  measurements, the math could go negative. Fixed: the value is clamped
  to 0 with a warning log line in that case.
- **SSD detection in `Optimize-Extreme.ps1` and `Optimize-Godlike.ps1`
  was fragile.** It compared `Get-PhysicalDisk`.DeviceId (a string that
  may be `'0'`, `'\\\\.\\PHYSICALDRIVE0'`, etc. depending on the storage
  stack) with `Get-Partition`.DiskNumber (an integer). Type coercion made
  `'0' -eq 0` true on most systems, but the comparison silently failed
  on storage stacks that return non-numeric DeviceIds. The try/catch
  then defaulted to "not an SSD", which meant Superfetch/SysMain would
  remain enabled on some SSD-only systems. Fixed by using the supported
  cmdlet chain: `Get-Partition | Get-Disk | Get-PhysicalDisk`.
- **Both `.bat` launcher files used Unix LF line endings instead of
  Windows CRLF.** Modern `cmd.exe` usually tolerates this, but
  multi-line `if (...) ( ... )` blocks and `set /p` prompts have
  historically broken on certain Windows versions, especially when
  launched via "Run as administrator" double-click rather than from an
  existing `cmd.exe` window. Both files re-saved with CRLF.
- **README's "Nothing is a one-way door" wording was inaccurate.** Power
  plans and Boot/System services are not fully restorable via this
  toolkit. Wording tightened to reflect what is actually restored and
  what isn't.
- **`QUICK_START.txt` did not mention the `Snapshots` subfolder** used by
  `Performance-Monitor.ps1` / `Compare-Results.ps1`. Now listed alongside
  the `Backups` folder.

## v6.0 - Full rewrite

This version replaces v5.1 entirely. Every issue below was found by an
independent code review of v5.1 and fixed here:

- **Profiles were identical.** In v5.1, `Optimize-Gaming.ps1`,
  `Optimize-Server.ps1`, `Optimize-Laptop.ps1`, etc. were byte-for-byte
  identical apart from a log filename and a printed label, despite the
  README advertising different tweaks and different percentage gains per
  profile. v6.0 gives each of the 8 profiles an explicit, genuinely
  different tweak list defined in `scripts/Common-Functions.ps1`.
- **Fabricated benchmark numbers.** `Compare-Results.ps1` printed hard-coded
  strings like "Boot Time: 60-90s to 10-15s (-80%)" regardless of the
  machine. v6.0's `Compare-Results.ps1` diffs two real snapshots captured
  by `Performance-Monitor.ps1` and refuses to run if fewer than two exist.
- **Fake "modules executed" output.** `Advanced-Modules.ps1` printed
  "[SUCCESS] 8 modules executed" without doing anything. v6.0 runs 8 real,
  independent tweaks and reports an actual success/fail count.
- **Fake cleanup numbers.** The old "Quick Cleanup" menu option printed
  "freed 5-15GB" unconditionally. `Cleanup-System.ps1` now measures free
  disk space before and after and reports the real delta.
- **Incomplete rollback.** `Undo-All-Changes.ps1` in v5.1 only restarted
  the DiagTrack service. v6.0's version reads every JSON backup record
  written by any profile or module run and restores every tracked
  registry value, service state, and hibernation setting.
- **No verification.** v5.1 had no way to check whether a tweak actually
  took effect. v6.0 adds `Verify-System.ps1`, which checks current
  registry/service state against what a chosen profile should have set.
- **Unsafe/contradictory tweaks.** v5.1 applied `DisablePagingExecutive`
  and Superfetch-disabling to every profile, including Laptop, regardless
  of RAM size or drive type. v6.0 gates these to profiles where they make
  sense (`Extreme`/`Godlike`, and only when RAM ≥ 16GB or the drive is
  confirmed SSD), and the Laptop profile explicitly avoids them.
- **Dependency downloader.** v5.1 attempted to fetch a version-pinned
  `.exe` URL with no checksum verification. v6.0's downloader opens the
  official vendor download pages instead and is explicit that it does not
  verify signatures for you.
