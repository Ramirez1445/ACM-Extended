from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
CFG=(ROOT/"addons/acm_extended/config.cpp").read_text()
p=ROOT/"addons/core/functions/fnc_getUp.sqf"
assert p.exists()
assert not (ROOT/"addons/acm_extended/overrides/fn_getUp.sqf").exists()
assert "overrides\\fn_getUp.sqf" not in CFG
t=p.read_text()
for tok in ("ACME_AAJT_inguinal","ACME_headElevated","ACME_obtunded","ACME_fnc_animQueue"):
    assert tok in t
print("fork phase 8 getUp native merge checks: PASS")
