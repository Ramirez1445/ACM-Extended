/* Stable B183: eligibility for the persistent manual plate-carrier chest-access lease. */
params [
    ["_medic", objNull, [objNull]],
    ["_patient", objNull, [objNull]],
    ["_restore", false, [false]]
];

if (isNull _medic || {isNull _patient} || {!(_patient isKindOf "CAManBase")}) exitWith {false};
if (_medic isEqualTo _patient) exitWith {false};
if (!alive _medic || {!([_medic] call ace_common_fnc_isAwake}) || {!alive _patient}) exitWith {false};

private _state = _patient getVariable ["ACME_manualPlateCarrierState", ""];
private _manualLease = _patient getVariable ["ACME_manualPlateCarrierLease", ""];
private _leases = _patient getVariable ["ACME_chestAccess_leases", createHashMap];
if !(_leases isEqualType createHashMap) then {_leases = createHashMap;};
private _otherLeases = (keys _leases) select {_x != _manualLease};

private _procedureBusy =
    (_patient getVariable ["ACME_CS_ProcedureActive", false])
    || {_patient getVariable ["ACME_Thora_ChestAccessActive", false]}
    || {(count _otherLeases) > 0}
    || {[_patient] call ACME_fnc_chestAccessManeuverActive}
    || {(_patient getVariable ["ACME_CS_vestBusy", ""]) != ""}
    || {(_patient getVariable ["ACME_CS_vestLoadout", []]) isNotEqualTo []};
if (_procedureBusy) exitWith {false};

private _accessSaved = +(_patient getVariable ["ACME_chestAccess_vestLoadout", []]);
private _worn = vest _patient;

if (_restore) exitWith {
    _state == "off"
        && {_manualLease != ""}
        && {(count _accessSaved) == 2}
        && {_worn == ""}
};

// A fresh removal is a down-casualty intervention. Once the casualty is awake or transported, the watchdog
// immediately returns the carrier instead of allowing persistent chest exposure during independent movement.
if (_state != "" || {_manualLease != ""} || {_worn == ""}) exitWith {false};
if (!isNull objectParent _patient || {!isNull attachedTo _patient}) exitWith {false};
if (_patient call ace_common_fnc_isBeingDragged || {_patient call ace_common_fnc_isBeingCarried}) exitWith {false};

private _awake = !(_patient getVariable ["ACE_isUnconscious", false])
    && {!(_patient getVariable ["ace_medical_unconscious", false])};
private _lyingRaw = _patient getVariable ["ACM_core_Lying_State", false];
private _lying = if (_lyingRaw isEqualType true) then {_lyingRaw} else {_lyingRaw > 0};

!_awake || {_lying}
