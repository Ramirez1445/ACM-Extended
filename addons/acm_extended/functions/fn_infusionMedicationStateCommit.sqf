/*
 * Authoritative mutation gate for medicated infusion-bag state.
 *
 * B204 network contract:
 * - exact medication/bag bookkeeping stays owner-local at the 0.25 s infusion cadence;
 * - the full structured entry array is replicated at most once per second while only rates/timestamps/remaining
 *   quantities are changing;
 * - entry identity/topology changes publish immediately;
 * - HasBagMedications is a scalar transition and remains immediately deduplicated.
 */
params [
    ["_patient", objNull, [objNull]],
    ["_entries", [], [[]]],
    ["_public", true, [true]]
];
if (isNull _patient) exitWith {false};

_patient setVariable ["ACME_infusion_BagMedications", _entries, false];
private _has = !(_entries isEqualTo []);
if (!_public) exitWith {
    _patient setVariable ["ACME_infusion_HasBagMedications", _has, false];
    true
};

if (!local _patient) exitWith {
    _patient setVariable ["ACME_infusion_BagMedications", _entries, true];
    _patient setVariable ["ACME_infusion_HasBagMedications", _has, true];
    true
};

// Structural identity only. Dynamic dose/rate/time fields intentionally do not force a public packet.
private _sig = _entries apply {
    [
        _x param [23, ""], // stable bag uid
        _x param [11, ""], // medication class
        _x param [1, ""],  // body part
        _x param [4, -1],  // access site
        _x param [5, true] // IV/IO
    ]
};
private _now = diag_tickTime;
private _lastAt = _patient getVariable ["ACME_infusion_netAt", -1];
private _lastSig = _patient getVariable ["ACME_infusion_netSig", []];
private _interval = missionNamespace getVariable ["ACME_infusion_stateNetInterval", 1.0];
if !(_interval isEqualType 0 && {finite _interval}) then {_interval = 1.0;};
_interval = _interval max 0.25;

private _publish = (_lastAt < 0)
    || {_sig isNotEqualTo _lastSig}
    || {(_now - _lastAt) >= _interval};

if (_publish) then {
    _patient setVariable ["ACME_infusion_netAt", _now, false];
    _patient setVariable ["ACME_infusion_netSig", _sig, false];
    [_patient, "ACME_infusion_BagMedications", _entries] call ACME_fnc_setVarNet;
} else {
    private _counting = missionNamespace getVariable ["ACME_net_count", false];
    if (_counting) then {
        private _saved = missionNamespace getVariable ["ACME_net_saved", createHashMap];
        _saved set ["ACME_infusion_BagMedications", (_saved getOrDefault ["ACME_infusion_BagMedications", 0]) + 1];
        missionNamespace setVariable ["ACME_net_saved", _saved];
    };
};

[_patient, "ACME_infusion_HasBagMedications", _has] call ACME_fnc_setVarNet;
true
