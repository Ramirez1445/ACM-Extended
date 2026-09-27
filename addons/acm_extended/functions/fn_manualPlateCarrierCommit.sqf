/* Stable B183: manual plate carrier remove/replace using the normal chest-access choreography. */
params [
    ["_medic", objNull, [objNull]],
    ["_patient", objNull, [objNull]],
    ["_restore", false, [false]]
];

if (isNull _patient || {isNull _medic}) exitWith {false};
if (!local _patient) exitWith {
    [_patient, "manualPlateCarrier", [_medic, _patient, _restore]] call ACME_fnc_ownerDispatch;
    true
};

if !([_medic, _patient, _restore] call ACME_fnc_manualPlateCarrierCanToggle) exitWith {
    ["ACME_manualPlateCarrierAck", [_patient, _restore, false], _medic] call CBA_fnc_targetEvent;
    false
};

if (_restore) exitWith {
    private _lease = _patient getVariable ["ACME_manualPlateCarrierLease", ""];
    private _leases = _patient getVariable ["ACME_chestAccess_leases", createHashMap];
    if !(_leases isEqualType createHashMap) then {_leases = createHashMap;};
    if (_lease != "") then {_leases deleteAt _lease;};
    _patient setVariable ["ACME_chestAccess_leases", _leases, true];
    if ((_patient getVariable ["ACME_chestAccess_readyLease", ""]) == _lease) then {
        _patient setVariable ["ACME_chestAccess_readyLease", "", true];
    };

    _patient setVariable ["ACME_manualPlateCarrierState", "restoring", true];
    [_patient, false, _medic, "access", true] call ACME_fnc_chestAccessVestRestore;

    [{
        params ["_p", "_medic", "_lease"];
        isNull _p
            || {!local _p}
            || {(_p getVariable ["ACME_manualPlateCarrierLease", ""]) != _lease}
            || {((count (_p getVariable ["ACME_chestAccess_vestLoadout", []])) == 0
                && {(vest _p) != ""}
                && {(_p getVariable ["ACME_chestAccess_vestBusy", ""]) == ""})}
    }, {
        params ["_p", "_medic", "_lease"];
        if (isNull _p || {!local _p}) exitWith {};
        if ((_p getVariable ["ACME_manualPlateCarrierLease", ""]) != _lease) exitWith {};

        private _success = (vest _p) != "" && {(count (_p getVariable ["ACME_chestAccess_vestLoadout", []])) == 0};
        if (_success) then {
            _p setVariable ["ACME_manualPlateCarrierState", "", true];
            _p setVariable ["ACME_manualPlateCarrierLease", "", true];
            _p setVariable ["ACME_manualPlateCarrierProvider", objNull, true];
            _p setVariable ["ACME_manualPlateCarrierOriginASL", [], true];
            _p setVariable ["ACME_manualPlateCarrierRemoved", false, true];
            [_p, "activity", ["Plate carrier replaced"], []] call ace_medical_treatment_fnc_addToLog;
        };
        ["ACME_manualPlateCarrierAck", [_p, true, _success], _medic] call CBA_fnc_targetEvent;
    }, [_patient, _medic, _lease], 6, {
        params ["_p", "_medic"];
        if (!isNull _p) then {[_p, "replace-timeout"] call ACME_fnc_manualPlateCarrierAutoReturn;};
        ["ACME_manualPlateCarrierAck", [_p, true, false], _medic] call CBA_fnc_targetEvent;
    }] call CBA_fnc_waitUntilAndExecute;
    true
};

private _serial = (_patient getVariable ["ACME_manualPlateCarrierSerial", 0]) + 1;
_patient setVariable ["ACME_manualPlateCarrierSerial", _serial, false];
private _lease = format ["manualpc:%1:%2:%3", netId _patient, _serial, round (serverTime * 1000)];

_patient setVariable ["ACME_manualPlateCarrierState", "removing", true];
_patient setVariable ["ACME_manualPlateCarrierLease", _lease, true];
_patient setVariable ["ACME_manualPlateCarrierProvider", _medic, true];
_patient setVariable ["ACME_manualPlateCarrierOriginASL", getPosASL _patient, true];
_patient setVariable ["ACME_manualPlateCarrierRemoved", false, true];

// This is the same owner-side transaction used by normal chest access. The persistent lease prevents its custody
// watchdog from restoring the vest after the remove/lower sequence finishes.
[_patient, _medic, _lease, true, "manualplatecarrier", _lease] call ACME_fnc_chestAccessVestEvent;

[{
    params ["_p", "_lease"];
    if (isNull _p || {!local _p}) exitWith {true};
    if ((_p getVariable ["ACME_manualPlateCarrierLease", ""]) != _lease) exitWith {true};
    private _saved = _p getVariable ["ACME_chestAccess_vestLoadout", []];
    private _ready = _p getVariable ["ACME_chestAccess_readyServer", -1];
    (count _saved) == 2
        && {(vest _p) == ""}
        && {_ready >= 0}
        && {serverTime >= _ready}
        && {(_p getVariable ["ACME_chestAccess_vestBusy", ""]) == ""}
}, {
    params ["_p", "_medic", "_lease"];
    if (isNull _p || {!local _p}) exitWith {};
    if ((_p getVariable ["ACME_manualPlateCarrierLease", ""]) != _lease) exitWith {};

    _p setVariable ["ACME_manualPlateCarrierState", "off", true];
    _p setVariable ["ACME_manualPlateCarrierRemoved", true, true];

    [_medic, "chestAccessVestProvider", [_medic, _p, "manualstop", false, "", _lease]]
        call ACME_fnc_ownerDispatch;

    [_p, "activity", ["Plate carrier manually removed"], []] call ace_medical_treatment_fnc_addToLog;
    ["ACME_manualPlateCarrierAck", [_p, false, true], _medic] call CBA_fnc_targetEvent;
}, [_patient, _medic, _lease], 8, {
    params ["_p", "_medic"];
    if (!isNull _p) then {[_p, "remove-timeout"] call ACME_fnc_manualPlateCarrierAutoReturn;};
    ["ACME_manualPlateCarrierAck", [_p, false, false], _medic] call CBA_fnc_targetEvent;
}] call CBA_fnc_waitUntilAndExecute;

true
