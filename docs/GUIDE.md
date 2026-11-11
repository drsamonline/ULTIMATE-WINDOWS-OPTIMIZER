# Ultimate Windows Optimizer — user guide

**Version 6.5.0 · MIT · PowerShell scripts, no installer**

A set of well-known, individually documented Windows tweaks — telemetry, CPU priority separation,
GPU scheduling, power plans, visual effects — wired up with real logging, real backups and real
verification.

## What this is, and what it is not

It is **not** a magic performance multiplier. Results depend entirely on your hardware and your
workload, and **no percentage improvement is promised anywhere in the toolkit**. What it gives you is
the means to measure your own before and after with `Performance-Monitor.ps1` and
`Compare-Results.ps1`.

What it does give you, on every change:

- **Logging** to `%USERPROFILE%\OptimizationLogs`.
- **Backups** of every registry value and service state changed, so `Undo-All-Changes.ps1` can put
  the system back exactly as it was.
- **Verification** that reads actual system state instead of printing canned numbers.

**Nothing here needs the internet.** The toolkit makes no outbound calls, sends no telemetry and
reads no credentials.

## Before you run anything

1. Read the script you are about to run. They are short and commented; that is the point of shipping
   scripts rather than an installer.
2. Take a restore point or a registry export first. The toolkit backs up what *it* changes; it cannot
   back up what you change by hand afterwards.
3. Run `Performance-Monitor.ps1` **before** applying tweaks. Without a baseline, "it feels faster" is
   the only measurement you will have.

## Undoing

`Undo-All-Changes.ps1` reverses everything the toolkit changed, using the backups it wrote. That is
why the backups are per-value rather than a single blob: a partial undo has to be possible.

## Licence

MIT — see [LICENSE](../LICENSE).
