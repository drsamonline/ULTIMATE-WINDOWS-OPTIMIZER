# Changelog

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
