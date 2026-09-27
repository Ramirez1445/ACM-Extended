/* Stable B182: owner-local persistent plate-carrier remove/replace transaction.
 *
 * No provider or patient animation is played here. Temporary chest-access custody uses different variables and
 * therefore cannot auto-restore this carrier.
 */
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

private _ok = [_medic, _patient, _restore] call ACME_fnc_manualPlateCarrierCanToggle;
if (!_ok) exitWith {
    ["ACME_manualPlateCarrierAck", [_patient, _restore, false], _medic] call CBA_fnc_targetEvent;
    false
};

private _success = false;
if (_restore) then {
    private _saved = +(_patient getVariable ["ACME_manualPlateCarrierLoadout", []]);
    private _vestClass = _saved param [0, "", [""]];

    if ((count _saved) == 2 && {_vestClass != ""} && {(vest _patient) == ""}) then {
        private _loadout = getUnitLoadout _patient;
        if ((count _loadout) > 4) then {
            _loadout set [4, +_saved];
            _patient setUnitLoadout [_loadout, false];
            _success = (vest _patient) == _vestClass;
        };
    };

    if (_success) then {
        _patient setVariable ["ACME_manualPlateCarrierLoadout", [], true];
        _patient setVariable ["ACME_manualPlateCarrierRemoved", false, true];
    };
} else {
    private _entry = (getUnitLoadout _patient) param [4, [], [[]]];
    private _vestClass = vest _patient;

    if (_vestClass != "" && {(count _entry) == 2}) then {
        removeVest _patient;
        _success = (vest _patient) == "";
        if (_success) then {
            _patient setVariable ["ACME_manualPlateCarrierLoadout", +_entry, true];
            _patient setVariable ["ACME_manualPlateCarrierRemoved", true, true];
            _patient setVariable ["ACME_acmSpawnerPlateCarrierDone", true, true];
        };
    };
};

if (_success) then {
    [_patient, "activity", ["Plate carrier replaced", "Plate carrier manually removed"] select (!_restore), []]
        call ace_medical_treatment_fnc_addToLog;
};

["ACME_manualPlateCarrierAck", [_patient, _restore, _success], _medic] call CBA_fnc_targetEvent;
_success
