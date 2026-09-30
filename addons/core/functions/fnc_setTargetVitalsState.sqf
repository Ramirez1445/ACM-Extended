#include "..\script_component.hpp"
/*
 * Author: ACM Extended Fork
 * Core-owned mutation endpoint for native ACM target vitals.
 *
 * Public scalar writes retain owner-local publication deduplication so high-frequency ventilator/altitude paths do
 * not rebroadcast an unchanged target. A locality/owner change invalidates the publication cache.
 *
 * Arguments:
 * 0: Patient <OBJECT>
 * 1: Changes <ARRAY> of [field,value,epsilon,maxAge]
 *    epsilon/maxAge are optional. When supplied, the exact owner value is kept locally while publication is
 *    threshold/heartbeat bounded. Supported fields: heartRate, respirationRate, oxygenSaturation
 * 2: Public <BOOL> (default true)
 *
 * Return Value:
 * Number of accepted publications <NUMBER>
 *
 * Public: Yes
 */
params [
    ["_patient", objNull, [objNull]],
    ["_changes", [], [[]]],
    ["_public", true, [true]]
];
if (isNull _patient) exitWith {0};

private _ownerKey = QGVAR(TargetVitals_ForkPublishOwner);
private _cacheKey = QGVAR(TargetVitals_ForkPublished);
private _cache = _patient getVariable [_cacheKey, createHashMap];
if (_public && {local _patient}) then {
    private _ownerStamp = [owner _patient, local _patient];
    if !((_patient getVariable [_ownerKey, []]) isEqualTo _ownerStamp) then {
        _cache = createHashMap;
        _patient setVariable [_cacheKey, _cache, false];
        _patient setVariable [_ownerKey, _ownerStamp, false];
    };
};

private _approxKey = QGVAR(TargetVitals_ForkApprox);
private _approx = _patient getVariable [_approxKey, createHashMap];
if !(_approx isEqualType createHashMap) then {_approx = createHashMap;};

private _publish = {
    params ["_var", "_value", ["_epsilon", 0, [0]], ["_maxAge", 0, [0]]];
    private _k = toLowerANSI _var;

    if (_public && {local _patient} && {(_epsilon > 0) || {_maxAge > 0}}) exitWith {
        private _row = _approx getOrDefault [_k, []];
        private _now = diag_tickTime;
        private _send = count _row < 2;
        if (!_send) then {
            private _last = _row param [0, _value];
            private _lastAt = _row param [1, -1];
            private _moved = if (_value isEqualType 0 && {_last isEqualType 0}) then {
                if (_epsilon > 0) then {abs (_value - _last) >= _epsilon} else {_value != _last}
            } else {
                _value isNotEqualTo _last
            };
            private _aged = _maxAge > 0 && {_lastAt < 0 || {_now - _lastAt >= _maxAge}};
            _send = _moved || _aged;
        };

        _patient setVariable [_var, _value, false];
        if (_send) then {
            _patient setVariable [_var, _value, true];
            _approx set [_k, [_value, _now]];
            _patient setVariable [_approxKey, _approx, false];
        };
        _send
    };

    if (_public && {local _patient}) then {
        private _old = _patient getVariable _var;
        private _published = _cache get _k;
        if (!isNil "_old" && {!isNil "_published"} && {_old isEqualTo _value} && {_published isEqualTo _value}) exitWith {false};
        _cache set [_k, _value];
    };
    _patient setVariable [_var, _value, _public];
    true
};

private _applied = 0;
{
    if (_x isEqualType [] && {count _x >= 2}) then {
        private _field = _x param [0, "", [""]];
        private _value = _x param [1, 0];
        private _epsilon = _x param [2, 0, [0]];
        private _maxAge = _x param [3, 0, [0]];
        private _accepted = false;
        switch (_field) do {
            case "heartRate": { _accepted = [QGVAR(TargetVitals_HeartRate), _value, _epsilon, _maxAge] call _publish; };
            case "respirationRate": { _accepted = [QGVAR(TargetVitals_RespirationRate), _value, _epsilon, _maxAge] call _publish; };
            case "oxygenSaturation": { _accepted = [QGVAR(TargetVitals_OxygenSaturation), _value, _epsilon, _maxAge] call _publish; };
        };
        if (_accepted) then {_applied = _applied + 1;};
    };
} forEach _changes;
_applied
