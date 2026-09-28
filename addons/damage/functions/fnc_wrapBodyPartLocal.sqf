#include "..\script_component.hpp"
/*
 * Stable B199 physical-dressing invariant.
 *
 * Wrapping is a physical treatment state, not a temporary coagulation roll. Once a bandaged or clotted wound is
 * wrapped, the wrap remains applied until another explicit treatment/state transition changes it. Platelet count,
 * coagulopathy and clot strength may affect unsecured clots elsewhere, but they may never delete a wrap, restore a
 * wrapped wound to the bandaged/clotted pool, or create an open wound from a wrap.
 *
 * Arguments:
 * 0: Medic <OBJECT>
 * 1: Patient <OBJECT>
 * 2: Body Part <STRING>
 * 3: Wrappable Type <NUMBER> (0 = bandaged wound, 1 = clotted wound)
 */
params ["_medic", "_patient", "_bodyPart", "_type"];
private _acmeReconcile = "B199:physicalDressingStable";

if (isNull _patient || {!local _patient}) exitWith {};

private _wrappableList = createHashMap;
private _woundsVar = VAR_BANDAGED_WOUNDS;

if (_type == 1) then {
    _wrappableList = GET_CLOTTED_WOUNDS(_patient);
    _woundsVar = VAR_CLOTTED_WOUNDS;
} else {
    _wrappableList = GET_BANDAGED_WOUNDS(_patient);
};

private _wrappableListOnPart = +(_wrappableList getOrDefault [_bodyPart, []]);
if (_wrappableListOnPart isEqualTo []) exitWith {};

private _openWounds = GET_OPEN_WOUNDS(_patient) getOrDefault [_bodyPart, []];
if (_openWounds isNotEqualTo [] && {[_patient, _bodyPart] call FUNC(isBodyPartBleeding)}) exitWith {};

private _wrappedWounds = GET_WRAPPED_WOUNDS(_patient);
private _wrappedWoundsOnPart = +(_wrappedWounds getOrDefault [_bodyPart, []]);

if (_wrappedWoundsOnPart isEqualTo []) then {
    _wrappedWounds set [_bodyPart, +_wrappableListOnPart];
} else {
    {
        _x params ["_id", "_amountOf"];

        private _index = _wrappedWoundsOnPart findIf {(_x select 0) isEqualTo _id};
        if (_index != -1) then {
            private _current = +(_wrappedWoundsOnPart select _index);
            _current set [1, (_current select 1) + _amountOf];
            _wrappedWoundsOnPart set [_index, _current];
        } else {
            _wrappedWoundsOnPart pushBack (+_x);
        };
    } forEach _wrappableListOnPart;

    _wrappedWounds set [_bodyPart, _wrappedWoundsOnPart];
};

_patient setVariable [VAR_WRAPPED_WOUNDS, _wrappedWounds, true];

// Transfer ownership of this body-part's treated wounds into the persistent physical-wrap state.
// There is intentionally no delayed reopening callback and no platelet/coagulopathy roll here.
_wrappableList deleteAt _bodyPart;
_patient setVariable [_woundsVar, _wrappableList, true];

// Check if wrapping fixed limping caused by a treated leg wound.
if (ACEGVAR(medical,limping) > 0
    && {_patient getVariable [QACEGVAR(medical,isLimping), false]}
    && {_bodyPart in ["leftleg", "rightleg"]}) then {
    [_patient] call ACEFUNC(medical_engine,updateDamageEffects);
};
