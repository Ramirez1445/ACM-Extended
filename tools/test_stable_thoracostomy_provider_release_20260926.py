#!/usr/bin/env python3
"""Stable regression: thoracostomy chest-access provider theatre must never strand the medic."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8", errors="replace")

def test_thoracostomy_releases_chest_access_pose_before_opening_workspace():
    open_fn = read("addons/acm_extended/functions/fn_thoraOpen.sqf")
    assert '[_patient,_medic,_vestLease,true,"thoracostomy",_vestLease] call ACME_fnc_chestAccessVestEvent;' in open_fn
    assert 'private _releaseProvider = {' in open_fn
    assert '[_m,_p,"stop",_handoff,_token] call ACME_fnc_chestAccessVestProvider;' in open_fn
    assert '(_entry param [3,""]) != _lease' in open_fn
    assert '[_m,_p,_lease,false] call _releaseProvider;' in open_fn
    assert open_fn.index('[_m,_p,_lease,false] call _releaseProvider;') < open_fn.index('["ACME_Thoracostomy_Dialog"] call ACME_fnc_minigameOpen;')

def test_thoracostomy_timeout_and_close_also_release_provider_pose():
    open_fn = read("addons/acm_extended/functions/fn_thoraOpen.sqf")
    close_fn = read("addons/acm_extended/functions/fn_thoraClose.sqf")
    timeout = open_fn.split('Chest-access preparation timed out', 1)[1]
    assert '[_m,_p,_lease,false] call _releaseProvider;' in timeout
    assert 'ACME_Thora_EntryCancelToken' in open_fn
    assert 'ACME_Thora_EntryKeys' in open_fn
    assert 'call ACME_fnc_chestAccessPreparing' in open_fn
    assert 'ACME_chestAccessProvider' in close_fn
    assert '[_mHE,_pHE,"stop",false,_providerToken] call ACME_fnc_chestAccessVestProvider;' in close_fn

def test_late_thoracostomy_provider_packet_cannot_reacquire_frozen_medic4():
    provider = read("addons/acm_extended/functions/fn_chestAccessVestProvider.sqf")
    assert 'private _thoracostomyEntry = (_episodeToken find "vest:access:") == 0' in provider
    assert '(_preparationToken find "thora:") == 0' in provider
    assert '(uiNamespace getVariable ["ACME_Thora_ChestAccessLease", ""]) != _preparationToken' in provider
    assert '(uiNamespace getVariable ["ACME_Thora_Medic", objNull]) isNotEqualTo _medic' in provider
    assert '(uiNamespace getVariable ["ACME_Thora_Patient", objNull]) isNotEqualTo _patient' in provider
    assert '[_patient, _epoch, _episodeToken, _preparationToken]' in provider

if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
    print("stable thoracostomy provider-release regression: PASS")
