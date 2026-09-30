#!/usr/bin/env python3
"""Static diagnostic for Extended code that actually writes native ACM-owned state directly.

This intentionally ignores reads and calls to the native owner APIs. It reports only literal native-key
setVariable/missionNamespace/uiNamespace writes and native-key use through ACME's generic network writer.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
EXT = ROOT / "addons" / "acm_extended" / "functions"

PREFIXES = ("ACM_core_", "ACM_breathing_", "ACM_circulation_", "ACM_airway_")

for prefix in PREFIXES:
    q = re.escape(prefix)
    patterns = [
        re.compile(r'\bsetVariable\s*\[\s*["\']' + q),
        re.compile(r'\bmissionNamespace\s+setVariable\s*\[\s*["\']' + q),
        re.compile(r'\buiNamespace\s+setVariable\s*\[\s*["\']' + q),
        re.compile(r'ACME_fnc_setVarNet(?:Approx)?[^\n]*["\']' + q),
    ]
    rows = []
    for p in sorted(EXT.glob("*.sqf")):
        for n, line in enumerate(p.read_text(errors="ignore").splitlines(), 1):
            if any(rx.search(line) for rx in patterns):
                rows.append((p.name, n, line.strip()))
    print(f"=== {prefix} actual direct/native writes: {len(rows)} ===")
    for p, n, line in rows:
        print(f"{p}:{n}: {line}")
