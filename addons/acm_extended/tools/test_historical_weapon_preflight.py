"""Current weapon-prep and immediate-treatment bridge contracts.

Weapon holstering remains a presentation helper for ACME-owned provider poses. It must never delay the native
clinical treatment/progress bar.
"""
import re
import pytest

from source_scan import lex
from test_menu_death_lifecycle import ROOT, adapt, execute

F = ROOT / "addons/acm_extended/functions"
TREATMENT = ROOT / "addons/core/overrides/fnc_treatment.sqf"


def source(name):
    return (F / ("fn_" + name + ".sqf")).read_text()


def engine(text):
    for unit in ("_medic", "_m", "_u", "_unit"):
        for prefix, replacement in [
            ("local ", "_localProvider"), ("alive ", "_alive"),
            ("currentWeapon ", "_weaponNow"), ("handgunWeapon ", '"pistol"'),
            ("animationState ", "_animNowFixture"), ("stance ", "_stanceNow"),
            ("objectParent ", "_providerParent"), ("netId ", '"medic"'),
        ]:
            text = re.sub(re.escape(prefix + unit) + r"\b", lambda _: replacement, text)
        text = re.sub(re.escape(unit) + r" setUnitPos ([^;]+);", r"_positions pushBack \1;", text)
    text = text.replace('objectParent _patient', '_patientParent')
    return adapt(text)


def helper_setup(ace=True):
    body = r'''
        private _localProvider=true;
        private _alive=true;
        private _weaponNow="rifle";
        private _animNowFixture="AmovPercMstpSrasWrflDnon";
        private _stanceNow="STAND";
        private _providerParent=objNull;
        private _patientParent=objNull;
        private _positions=[];
        private _holsters=[];
        private _engineHolsters=[];
        private _moves=[];
        CBA_missionTime=10;
    '''
    if ace:
        body += 'ace_weaponselect_fnc_putWeaponAway={_holsters pushBack (_this select 0);};'
    else:
        body += 'ace_weaponselect_fnc_putWeaponAway=nil;'
    body += 'ACME_fnc_medicAnimationPrep={' + engine(source("medicAnimationPrep")) + '};'
    return body


@pytest.mark.parametrize("weapon,delay", [("pistol", .95), ("rifle", .70), ("launcher", .70)])
@pytest.mark.parametrize("ace", [True, False])
def test_one_engine_holster_request_is_retained(weapon, delay, ace):
    execute(helper_setup(ace) + f'_weaponNow="{weapon}"; private _minimum={delay};' + r'''
        private _first=[_medic] call ACME_fnc_medicAnimationPrep;
        [_first==_minimum,"initial settle changed"] call _check;
        private _record=+(_medic getVariable ["ACME_medicAnimationPrep",[]]);
        CBA_missionTime=10.1;
        private _again=[_medic] call ACME_fnc_medicAnimationPrep;
        [_again>0,"pending settle vanished"] call _check;
        [(_medic getVariable ["ACME_medicAnimationPrep",[]]) isEqualTo _record,"pending holster token replaced"] call _check;
        [count _holsters+count _engineHolsters==1,"helper queued multiple holsters"] call _check;
    ''')


@pytest.mark.parametrize("animation", [
    "AmovPknlMstpSnonWnonDnon", "ACME_ChestSealWorkspace",
    "ACME_StethoscopeWork", "ACME_DirectPressureHold", "ACM_GenericContinuous", "ACM_ProneContinuous",
])
def test_visible_empty_hands_do_not_reholster(animation):
    execute(helper_setup() + r'''
        [_medic] call ACME_fnc_medicAnimationPrep;
        _weaponNow="";
    ''' + f'_animNowFixture="{animation}";' + r'''
        private _delay=[_medic] call ACME_fnc_medicAnimationPrep;
        [_delay==0 && {count _holsters==1},"settled hands kept holstering"] call _check;
    ''')


def test_treatment_bridge_contains_no_generic_presentation_wait():
    s = TREATMENT.read_text()
    marker = s.index("// B177 button-responsiveness invariant")
    end = s.index("// A newly accepted head-position action", marker)
    block = s[marker:end]
    assert "CBA_fnc_waitUntilAndExecute" not in block
    assert "CBA_fnc_waitAndExecute" not in block
    assert "CBA_fnc_execNextFrame" not in block
    assert 'call ACME_fnc_medicAnimationPrep' in block


def test_native_treatment_is_called_directly_after_presentation_setup():
    s = TREATMENT.read_text()
    marker = s.index("// B177 button-responsiveness invariant")
    native = s.index("private _started = _nativeArgs call ACM_core_fnc_treatmentNative;", marker)
    assert native > marker


def test_provider_gesture_receives_patient_for_ambulatory_selection():
    s = TREATMENT.read_text()
    assert '[_m, _mode, _window, _patient] call ACME_fnc_treatmentGesture;' in s


def test_no_direct_weapon_reselection_was_reintroduced():
    identifiers={t.value for t in lex(TREATMENT.read_text()) if t.kind=="ident"}
    assert "selectWeapon" not in identifiers
    helper_ids={t.value for t in lex(source("medicAnimationPrep")) if t.kind=="ident"}
    assert "selectWeapon" not in helper_ids
