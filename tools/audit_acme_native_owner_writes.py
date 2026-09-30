#!/usr/bin/env python3
"""Static diagnostic for Extended code writing native ACM-owned state directly."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXT = ROOT / "addons" / "acm_extended" / "functions"

PREFIXES = ("ACM_core_", "ACM_breathing_", "ACM_circulation_", "ACM_airway_")

for prefix in PREFIXES:
    rows = []
    for p in sorted(EXT.glob("*.sqf")):
        for n, line in enumerate(p.read_text(errors="ignore").splitlines(), 1):
            if prefix not in line:
                continue
            if "setVariable [" in line or "missionNamespace setVariable [" in line or "ACME_fnc_setVarNet" in line:
                rows.append((p.name, n, line.strip()))
    print(f"=== {prefix} direct/native writes: {len(rows)} ===")
    for p, n, line in rows:
        print(f"{p}:{n}: {line}")
