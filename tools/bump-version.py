#!/usr/bin/env python3
"""bump-version.py - set the product version once and propagate it.

VERSION is the single source of truth for the product version. Every artefact
that states the version has to agree with it, and tests/UWO.Version.Tests.ps1
enforces exactly that in CI. A bump therefore has to touch all of them; this
does it in one command instead of by hand.

    python3 tools/bump-version.py 6.2.2            # set VERSION and propagate
    python3 tools/bump-version.py                  # propagate the current VERSION
    python3 tools/bump-version.py 6.2.2 --dry-run  # show what would change

Line endings are preserved byte for byte (the launcher is CRLF, everything else
is LF) and no BOM is written.

After a real run, re-record the two generated files so MANIFEST.json stays
clean - the script prints the exact command to run.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VERSION_FILE = ROOT / "VERSION"
VERSION_RE = re.compile(r"^\d+\.\d+\.\d+$")

# (relative path, regex whose group(s) wrap the version, replacement template)
# Every pattern is anchored on surrounding text so it cannot match a version
# that means something else (e.g. a historical changelog entry).
TARGETS: list[tuple[str, str, str]] = [
    ("scripts/UWO.psd1",               r"(ModuleVersion\s*=\s*')[^']+(')",         r"\g<1>{v}\g<2>"),
    ("scripts/00_Ultimate_Master.bat", r"(title Ultimate Windows Optimizer v)[\d.]+", r"\g<1>{v}"),
    ("scripts/00_Ultimate_Master.bat", r"(ULTIMATE WINDOWS OPTIMIZER v)[\d.]+",   r"\g<1>{v}"),
    ("QUICK_START.txt",                r"(ULTIMATE WINDOWS OPTIMIZER v)[\d.]+",   r"\g<1>{v}"),
    ("README.md",                      r"(version-)[\d.]+(-)",                    r"\g<1>{v}\g<2>"),
    ("docs/index.html",                r'("softwareVersion":\s*")[\d.]+(")',       r"\g<1>{v}\g<2>"),
    ("docs/index.html",                r'(<span class="badge">v)[\d.]+(</span>)', r"\g<1>{v}\g<2>"),
    ("docs/index.html",                r"(ULTIMATE WINDOWS OPTIMIZER v)[\d.]+",   r"\g<1>{v}"),
    ("docs/__dbg.html",                r'("softwareVersion":\s*")[\d.]+(")',       r"\g<1>{v}\g<2>"),
    ("docs/__dbg.html",                r'(<span class="badge">v)[\d.]+(</span>)', r"\g<1>{v}\g<2>"),
    ("docs/__dbg.html",                r"(ULTIMATE WINDOWS OPTIMIZER v)[\d.]+",   r"\g<1>{v}"),
    ("docs/images/main-menu.svg",      r"(ULTIMATE WINDOWS OPTIMIZER v)[\d.]+",   r"\g<1>{v}"),
]


def read_text(path: Path) -> str:
    # newline="" keeps CRLF intact (Path.read_text would translate it to LF).
    with path.open("r", encoding="utf-8", newline="") as f:
        return f.read()


def write_text(path: Path, text: str) -> None:
    with path.open("w", encoding="utf-8", newline="") as f:
        f.write(text)


def current_version() -> str:
    if not VERSION_FILE.exists():
        sys.exit(f"no VERSION file at {VERSION_FILE}")
    return read_text(VERSION_FILE).strip()


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="set and propagate the product version")
    ap.add_argument("version", nargs="?", help="X.Y.Z to set (default: current VERSION)")
    ap.add_argument("--dry-run", action="store_true", help="report without writing")
    a = ap.parse_args(argv)

    version = a.version or current_version()
    if not VERSION_RE.match(version):
        sys.exit(f"refuse: '{version}' is not a plain X.Y.Z version")

    # Group the rewrites by file so each file is read and written once.
    by_file: dict[str, list[tuple[str, str]]] = {}
    for rel, pattern, repl in TARGETS:
        by_file.setdefault(rel, []).append((pattern, repl.format(v=version)))

    failures = 0
    for rel, edits in by_file.items():
        path = ROOT / rel
        if not path.exists():
            print(f"MISSING  {rel}", file=sys.stderr)
            failures += 1
            continue
        text = original = read_text(path)
        for pattern, repl in edits:
            text, n = re.subn(pattern, repl, text)
            if n == 0:
                print(f"NO MATCH {rel}: {pattern}", file=sys.stderr)
                failures += 1
        if text != original:
            if not a.dry_run:
                write_text(path, text)
            print(f"{'would update' if a.dry_run else 'updated'}  {rel}")
        else:
            print(f"unchanged  {rel}")

    old = current_version()
    if old != version:
        if not a.dry_run:
            write_text(VERSION_FILE, version + "\n")
        print(f"{'would set' if a.dry_run else 'set'}    VERSION: {old} -> {version}")
    else:
        print(f"unchanged  VERSION ({version})")

    if failures:
        print(f"\n{failures} target(s) did not match - the file shape probably changed; "
              "update TARGETS in this script.", file=sys.stderr)
        return 3

    print("\nNext, keep the provenance manifest clean:")
    print(f"  python3 tools/manifest.py record README.md docs/index.html --producer bump@{version}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
