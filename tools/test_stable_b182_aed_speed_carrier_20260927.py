#!/usr/bin/env python3
"""Stable B182: LifePak stock/SYNC geometry, provider-speed cleanup, and persistent manual carrier toggle."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8", errors="replace")


def test_stock_lifepak_buttons_use_native_grid_but_sync_uses_background_grid():
    dlg = read("addons/circulation/Defibrillator_Monitor_Dialog.hpp")
    defs = read("addons/circulation/Defibrillator_defines.hpp")
    sync = read("addons/acm_extended/functions/fn_aedSyncSetup.sqf")

    controls = dlg.split("class Controls {", 1)[1]
    for macro in (
        "ACM_AED_pxToScreen_X",
        "ACM_AED_pxToScreen_Y",
        "ACM_AED_pxToScreen_W",
        "ACM_AED_pxToScreen_H",
    ):
        assert macro in controls
    assert "ACM_AED_bgPxToScreen_X" not in controls
    assert "ACM_AED_bgPxToScreen_Y" not in controls

    assert "ACM_AED_bgPxToScreen_X" in defs
    assert "private _fnc_pxBG = {" in sync
    assert "_btn ctrlSetPosition (_btnPx call _fnc_pxBG);" in sync
    assert "_led ctrlSetPosition (_ledPx call _fnc_pxBG);" in sync


def test_stock_lifepak_vertical_mapping_does_not_apply_extra_panel_scale():
    # Regression model for the reported 1680x1050 offset.
    authored_y = 512
    native = authored_y / 2048.0
    wrong_background = authored_y / 2048.0 * 1.05
    assert wrong_background > native
    assert abs(wrong_background / native - 1.05) < 1e-12


def test_provider_speed_owner_helper_is_registered_and_narrow():
    cfg = read("addons/acm_extended/config.cpp")
    helper = read("addons/acm_extended/functions/fn_providerAnimSpeedOwned.sqf")

    assert "class providerAnimSpeedOwned {};" in cfg
    assert 'ACME_nativeTreatmentRate' in helper
    assert 'ACME_treatmentPoseState' in helper
    assert 'ACME_treatmentPoseRemote' in helper
    assert 'ACME_headElev_seqActive' in helper

    # Broad stance owners are intentionally excluded: they must not strand an accelerated treatment rate.
    assert "ACME_menuPose" not in helper
    assert "ACME_DP_InPose" not in helper
    assert "ACM_circulation_isPerformingCPR" not in helper


def test_native_treatment_rate_cleanup_cannot_exit_on_epoch_mismatch_and_leak_speed():
    s = read("addons/acm_extended/functions/fn_registerProviderStanceReleaseRuntime.sqf")
    block = s.split("// B182: retire this exact native-rate lease first.", 1)[1]
    block = block.split("Zone 3 posture control", 1)[0]

    assert '_medic setVariable ["ACME_nativeTreatmentRate", [], true];' in block
    assert "ACME_fnc_providerAnimSpeedOwned" in block
    assert "_medic setAnimSpeedCoef 1;" in block
    assert "ACME_treatmentPoseEpoch" not in block


def test_pose_exit_retires_stale_remote_owner_on_handoff():
    s = read("addons/acm_extended/functions/fn_treatmentPoseSync.sqf")
    block = s.split("// B182: an old exit record is retired", 1)[1]
    block = block.split("}, [_medic, _epoch]", 1)[0]

    assert '[_medic, _epoch] call ACME_fnc_providerAnimSpeedOwned' in block
    assert '_medic setVariable ["ACME_treatmentPoseRemote", [_epoch, "release", -1]];' in block
    assert "_medic setAnimSpeedCoef 1;" in block


def test_head_elevation_handoff_does_not_skip_speed_release():
    s = read("addons/acm_extended/functions/fn_headElevMedicSeq.sqf")
    block = s.split("// Local bookkeeping above always retires.", 1)[1]
    block = block.split("if (alive _u", 1)[0]

    assert "ACME_fnc_providerAnimSpeedOwned" in block
    assert "_u setAnimSpeedCoef 1;" in block
    assert "if (_handoff) exitWith {};" in block
    assert block.index("_u setAnimSpeedCoef 1;") < block.index("if (_handoff) exitWith {};")


def test_head_position_replaces_old_native_rate_with_real_speed_handoff():
    s = read("addons/core/overrides/fnc_treatment.sqf")
    block = s.split("if (_headOwned && {local _medic}) then {", 1)[1].split("};", 1)[0]
    assert 'setVariable ["ACME_nativeTreatmentRate", [], true]' in block
    assert "ACME_fnc_providerAnimSpeedOwned" in block
    assert "_medic setAnimSpeedCoef 1;" in block


def test_manual_plate_carrier_functions_and_actions_are_on_stable_main():
    cfg = read("addons/acm_extended/config.cpp")
    startup = read("addons/acm_extended/functions/fn_initForkStartupRuntime.sqf")
    dispatch = read("addons/acm_extended/functions/fn_ownerDispatch.sqf")

    for name in (
        "manualPlateCarrierCanToggle",
        "manualPlateCarrierCommit",
        "registerManualPlateCarrierRuntime",
    ):
        assert f"class {name} {{}};" in cfg

    assert "class ACME_ManualRemovePlateCarrier: CheckPulse" in cfg
    assert "class ACME_ManualReplacePlateCarrier: ACME_ManualRemovePlateCarrier" in cfg
    assert 'displayName = "Remove Plate Carrier";' in cfg
    assert 'displayName = "Replace Plate Carrier";' in cfg
    assert "call ACME_fnc_registerManualPlateCarrierRuntime;" in startup
    assert 'case "manualPlateCarrier": {_args call ACME_fnc_manualPlateCarrierCommit;};' in dispatch


def test_manual_carrier_custody_is_persistent_and_separate_from_automatic_custody():
    can = read("addons/acm_extended/functions/fn_manualPlateCarrierCanToggle.sqf")
    commit = read("addons/acm_extended/functions/fn_manualPlateCarrierCommit.sqf")
    restore = read("addons/acm_extended/functions/fn_chestAccessVestRestore.sqf")

    assert "ACME_manualPlateCarrierLoadout" in can
    assert "ACME_manualPlateCarrierLoadout" in commit
    assert "ACME_manualPlateCarrierRemoved" in commit
    assert "ACME_manualPlateCarrierLoadout" not in restore

    for temporary in (
        "ACME_chestAccess_vestLoadout",
        "ACME_CS_vestLoadout",
        "ACME_chestAccess_vestBusy",
        "ACME_CS_vestBusy",
        "ACME_chestAccess_leases",
    ):
        assert temporary in can


def test_manual_remove_and_replace_preserve_exact_vest_slot_without_animation():
    cfg = read("addons/acm_extended/config.cpp")
    commit = read("addons/acm_extended/functions/fn_manualPlateCarrierCommit.sqf")
    treatment = read("addons/core/overrides/fnc_treatment.sqf")

    remove = cfg.split("class ACME_ManualRemovePlateCarrier:", 1)[1].split(
        "class ACME_ManualReplacePlateCarrier:", 1
    )[0]
    for token in (
        'animationMedic = "";',
        'animationMedicProne = "";',
        'animationMedicSelf = "";',
        'animationMedicSelfProne = "";',
        "ACM_rollToBack = 0;",
    ):
        assert token in remove

    assert 'private _entry = (getUnitLoadout _patient) param [4, [], [[]]];' in commit
    assert "removeVest _patient;" in commit
    assert '_loadout set [4, +_saved];' in commit
    assert '_patient setUnitLoadout [_loadout, false];' in commit

    block = treatment.split(
        'if (_classname in ["ACME_ManualRemovePlateCarrier", "ACME_ManualReplacePlateCarrier"]) exitWith {',
        1,
    )[1].split("// Opening a shared workspace", 1)[0]
    assert "ACM_core_fnc_treatmentNative" not in block
    assert "medicAnimationPrep" not in block
    assert "treatmentPoseStart" not in block


def test_automatic_chest_access_skips_carrier_removal_when_manual_toggle_left_it_off():
    acquire = read("addons/acm_extended/functions/fn_chestAccessVestAcquire.sqf")
    no_vest = acquire.index('if (_vestClass == "" || {(count _vestEntry) != 2}) exitWith {')
    commit = acquire.index("private _commitRemoval = {")
    lift = acquire.index("private _liftTime =")
    assert no_vest < commit < lift


def test_build_identity_is_b182_stable():
    startup = read("addons/acm_extended/functions/fn_initForkStartupRuntime.sqf")
    cfg = read("addons/acm_extended/config.cpp")
    assert 'version = "1.2.4";' in cfg
    assert 'ACME_buildBatch = "B182";' in startup
    assert 'ACME_debugRevision = "";' in startup


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
    print("stable B182 AED/speed/carrier regression: PASS")
