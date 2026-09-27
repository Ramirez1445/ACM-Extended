from historical_source import read_source
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(rel: str) -> str:
    return read_source(ROOT / rel, encoding="utf-8-sig", errors="strict")


def test_fresh_kit_reset_clears_virtual_syringes_and_partial_vials():
    s = read("functions/fn_resetPersonalMedicationKit.sqf")
    assert '[_unit, []] call ACME_fnc_narcStoreCommit;' in s
    assert '[_unit, createHashMap] call ACME_fnc_openVialStoreCommit;' in s
    assert 'ACME_narcStoreSerial' in s
    assert 'ACME_SK_SelectedSyringeId' in s
    assert 'ACME_SK_VialHolder' in s


def test_ace_arsenal_load_and_import_are_explicit_reset_boundaries():
    s = read("functions/fn_registerSyringeLifecycleRuntime.sqf")
    assert '["ace_arsenal_onLoadoutLoad",' in s
    assert '["ace_arsenal_loadoutImported",' in s
    assert s.count("call ACME_fnc_resetPersonalMedicationKit;") >= 3
    assert 'ace_arsenal_displayClosed' not in s


def test_reset_function_is_registered():
    cfg = read("config.cpp")
    assert "class resetPersonalMedicationKit {};" in cfg
    assert "class registerSyringeLifecycleRuntime {};" in cfg


def test_death_keeps_the_partial_vial_ledger_on_the_corpse():
    s = read("functions/fn_registerSyringeLifecycleRuntime.sqf")
    killed = s.split('player addEventHandler ["Killed"', 1)[1].split('player addEventHandler ["Respawn"', 1)[0]
    assert "ACME_fnc_narcStoreCommit" in killed
    assert "ACME_fnc_resetPersonalMedicationKit" not in killed
