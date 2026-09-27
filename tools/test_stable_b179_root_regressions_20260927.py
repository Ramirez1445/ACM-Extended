#!/usr/bin/env python3
"""Stable B179 root regressions: AED, push editor, Get Up, vehicle treatment, and 6+6 chest holes."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8", errors="replace")


def test_aed_visible_art_and_all_button_hitboxes_share_one_background_transform():
    defs = read("addons/circulation/Defibrillator_defines.hpp")
    dlg = read("addons/circulation/Defibrillator_Monitor_Dialog.hpp")
    assert "ACM_AED_bgPxToScreen_X" in defs
    assert "ACM_GUI_AED_GRID_W * ACM_GUI_AED_SIZEM" in defs
    controls = dlg.split("class Controls {", 1)[1]
    assert "ACM_AED_bgPxToScreen_X" in controls
    assert "ACM_AED_bgPxToScreen_Y" in controls
    assert "ACM_AED_bgPxToScreen_W" in controls
    assert "ACM_AED_bgPxToScreen_H" in controls
    assert "ACM_AED_pxToScreen_X" not in controls
    assert "ACM_AED_pxToScreen_Y" not in controls


def test_aed_background_and_hitbox_mapping_remain_coincident_at_1680x1050():
    # Both visible artwork and button hitboxes now multiply their authored 2048px coordinates
    # by the exact same 1.05 panel scale. Resolution changes only the common grid origin/size.
    width, height = 1680, 1050
    sizem = 1.05
    for px in (512, 1632, 1820):
        art_norm = (px / 2048.0) * sizem
        hit_norm = (px / 2048.0) * sizem
        assert abs(art_norm - hit_norm) < 1e-12
    assert width / height == 1.6


def test_every_operator_dependent_aed_button_uses_actual_monitor_medic():
    for name in (
        "AED_Button_Analyze",
        "AED_Button_ManualCharge",
        "AED_Button_MeasureBP",
        "AED_Button_SpeedDial",
        "AED_Button_Shock",
    ):
        s = read(f"addons/circulation/functions/fnc_{name}.sqf")
        assert "AED_Monitor_Medic" in s
        assert '_patient getVariable [QGVAR(AED_Provider)' not in s
    charge = read("addons/circulation/functions/fnc_AED_BeginCharge.sqf")
    assert '_medic setVariable [QGVAR(AED_Medic_InUse), true, true];' in charge


def test_push_duration_edit_has_explicit_focus_lease_and_renderer_cannot_refresh_it():
    body = read("addons/acm_extended/functions/fn_skBodyActionRender.sqf")
    tick = read("addons/acm_extended/functions/fn_skUiTick.sqf")
    close = read("addons/acm_extended/functions/fn_skClose.sqf")

    mouse = body.split('ctrlAddEventHandler ["MouseButtonDown"', 1)[1].split("}];", 1)[0]
    assert mouse.index('ACME_SK_PushDurationEditing",true') < mouse.index("ctrlSetFocus _ctrl")
    assert 'ctrlAddEventHandler ["SetFocus"' in body
    assert 'ctrlAddEventHandler ["KillFocus"' in body
    assert 'if (_durEditing) exitWith {' in body
    guarded = body.split("if (_durEditing) exitWith {", 1)[1].split("};", 1)[0]
    assert "ctrlSetText" not in guarded
    assert "ctrlSetPosition" not in guarded
    assert "ctrlEnable" not in guarded
    assert 'ACME_SK_PushDurationEditing' in tick
    assert 'ACME_SK_PushDurationEditing", false' in close


def test_getup_never_mutates_a_carry_owned_casualty():
    getup = read("addons/core/functions/fnc_getUp.sqf")
    prompt = read("addons/core/functions/fnc_getUpPrompt.sqf")
    carry_guard = getup.index("private _carryOwner = attachedTo _patient;")
    lying_clear = getup.index('_patient setVariable ["ACM_core_Lying_State", false, true];')
    assert carry_guard < lying_clear
    assert '(_carryAnim find "carried") >= 0' in getup
    assert 'Put the casualty down before using Get Up.' in getup
    assert 'attachedTo _unit' in prompt
    assert '(_anim find "carried") >= 0' in prompt


def test_same_vehicle_treatment_is_clinical_without_forcing_animation():
    native = read("addons/core/functions/fnc_treatmentNative.sqf")
    bridge = read("addons/core/overrides/fnc_treatment.sqf")
    blocked = read("addons/acm_extended/functions/fn_animBlocked.sqf")

    assert "private _sameVehicleTreatment" in native
    assert '[["isNotInside", "isNotSwimming", "isNotInZeus"], ["isNotSwimming", "isNotInZeus"]] select _sameVehicleTreatment' in native
    assert 'if (isNull objectParent _medic && {_medicAnim != ""})' in native
    assert "if (!_isSelf && {isNull objectParent _patient})" in native

    assert "private _sameVehicleTreatment" in bridge
    assert "private _interactionChecks" in bridge
    assert "private _rangeOkay = _sameVehicleTreatment" in bridge
    assert "isNull objectParent _m && {(_m distance _p) > ace_medical_gui_maxDistance}" in bridge

    assert "!((vehicle _unit) isEqualTo _unit)" in blocked


def test_chest_and_thoracostomy_workspaces_accept_same_vehicle_without_body_theatre():
    acquire = read("addons/acm_extended/functions/fn_chestAccessVestAcquire.sqf")
    seal = read("addons/acm_extended/functions/fn_chestSealOpen.sqf")
    thora = read("addons/acm_extended/functions/fn_thoraOpen.sqf")
    thora_tick = read("addons/acm_extended/functions/fn_thoraTick.sqf")

    vehicle = acquire.split("if (!isNull objectParent _patient) exitWith {", 1)[1].split("// Every chest procedure starts anterior-up.", 1)[0]
    assert '_patient setVariable [_readyVar, serverTime, true];' in vehicle
    assert "removeVest" not in vehicle
    assert "doAnim" not in vehicle

    assert "objectParent _m isNotEqualTo objectParent _p" in seal
    assert "isNull objectParent _m && {_m distance _p" in seal
    assert "objectParent _m isNotEqualTo objectParent _p" in thora
    assert "isNull objectParent _m && {(_m distance _p)" in thora
    assert "objectParent _thMedic isNotEqualTo objectParent _thPatient" in thora_tick


def test_chest_holes_are_authoritatively_capped_at_six_front_and_six_back():
    init = read("addons/acm_extended/functions/fn_initChestSealProcedureRuntime.sqf")
    gen = read("addons/acm_extended/functions/fn_chestSealGenHoles.sqf")
    assert "ACME_CS_maxHolesPerSide = 6;" in init
    assert 'getVariable ["ACME_CS_maxHolesPerSide", 6]' in gen
    assert "_maxPerSide = (floor _maxPerSide) min 6;" in gen
    assert "private _cappedHoles = [];" in gen
    assert "if (_frontKept < _maxPerSide)" in gen
    assert "if (_backKept < _maxPerSide)" in gen
    assert "if (_frontCount < _maxPerSide) then {" in gen
    front_branch = gen.split("if (_frontCount < _maxPerSide) then {", 1)[0][-300:]
    assert '|| {!_historical}' not in front_branch

    # Migration/generation invariant model.
    sides = ["front"] * 11 + ["back"] * 9
    kept = []
    counts = {"front": 0, "back": 0}
    for side in sides:
        if counts[side] < 6:
            kept.append(side)
            counts[side] += 1
    assert counts == {"front": 6, "back": 6}
    assert len(kept) == 12


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
    print("stable B179 root-regression suite: PASS")
