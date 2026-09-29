/*
 * Phase 60: authoritative writer for ACME_blastLung_State.
 *
 * Injury infliction historically published directly; the progression tick used ACME_fnc_setVarNet so unchanged
 * scalar severities did not republish. Hard reset used nil. Preserve all three contracts behind one endpoint.
 */
params [
    ["_patient", objNull, [objNull]],
    ["_severity", 0, [0]],
    ["_public", true, [true]],
    ["_deduplicate", true, [true]],
    ["_clear", false, [true]],
    ["_epsilon", 0, [0]],
    ["_maxAge", 0, [0]]
];
if (isNull _patient) exitWith {_severity};
if (_clear) exitWith {
    _patient setVariable ["ACME_blastLung_State", nil, _public];
    0
};
private _value = (_severity max 0) min 1;
if (_public && {_deduplicate}) then {
    if (_epsilon > 0 || {_maxAge > 0}) then {
        [_patient, "ACME_blastLung_State", _value, _epsilon, _maxAge] call ACME_fnc_setVarNetApprox;
    } else {
        [_patient, "ACME_blastLung_State", _value] call ACME_fnc_setVarNet;
    };
} else {
    _patient setVariable ["ACME_blastLung_State", _value, _public];
};
_value
