/* Stable B187: automatic ventilator disconnect when a definitive/supraglottic airway is removed.
 *
 * Airway removal must tear down both clinical ventilation state and device custody. Clearing only
 * ACME_vent_connected leaves ACME_vent_onPatient/custody alive and can strand the device on a patient
 * who no longer has a usable airway.
 */
params [
    ["_patient", objNull, [objNull]],
    ["_medic", objNull, [objNull]],
    ["_reason", "airway removed", [""]]
];

if (isNull _patient) exitWith {false};
if (!local _patient) exitWith {
    [_patient, "ventAirwayLoss", [_patient, _medic, _reason]] call ACME_fnc_ownerDispatch;
    true
};

private _custody = _patient getVariable ["ACME_vent_custodyId", ""];
private _mounted = _patient getVariable ["ACME_vent_onPatient", false];
private _active = _mounted
    || {_custody != ""}
    || {_patient getVariable ["ACME_vent_connected", false]}
    || {_patient getVariable ["ACME_vent_driving", false]}
    || {_patient getVariable ["ACME_vent_circuit", false]}
    || {_patient getVariable ["ACME_vent_configured", false]};
if (!_active) exitWith {false};

// Stop clinical ventilation immediately on the casualty owner so no breath or BVM sentinel survives the
// airway-removal frame. Final custody cleanup is completed by the server return transaction below.
[_patient, _custody, false] call ACME_fnc_ventPatientClear;

if (!isNull _medic && {alive _medic}) then {
    ["ACME_ventCustodyRequest", ["airwayLoss", _medic, _patient]] call CBA_fnc_serverEvent;
} else {
    // Scripted/owner-side airway removal still needs a recipient. Prefer the captured operator, then supplier.
    private _recipient = _patient getVariable ["ACME_vent_operator", objNull];
    if (isNull _recipient || {!alive _recipient}) then {
        _recipient = _patient getVariable ["ACME_vent_supplier", objNull];
    };
    if (!isNull _recipient && {alive _recipient}) then {
        ["ACME_ventCustodyRequest", ["airwayLoss", _recipient, _patient]] call CBA_fnc_serverEvent;
    } else {
        // No recoverable recipient: make the patient state truthful immediately. The server ledger, if any,
        // remains available for later recovery rather than leaving the circuit clinically active.
        [_patient, _custody, true] call ACME_fnc_ventPatientClear;
    };
};

if (!isNil "ace_medical_treatment_fnc_addToLog") then {
    [_patient, "airway", format ["Ventilator automatically disconnected (%1)", _reason], []]
        call ace_medical_treatment_fnc_addToLog;
};

true
