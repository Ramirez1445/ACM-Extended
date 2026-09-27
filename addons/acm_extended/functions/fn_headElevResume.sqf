// Restore the elevated animation after a temporary flat maneuver, provided elevation itself was not canceled.
// B122: the Semi-Fowler support carrier was never re-worn during suspension, so resume only re-seats that same
// prop. A backpack-supported temporary chest-access vest is restored separately after its final chest-access lease.
params ["_patient", ["_frontNormalized", false, [false]]];
if (isNull _patient) exitWith {};
if (!local _patient) exitWith {[_patient, "headElevResume", [_patient, _frontNormalized]] call ACME_fnc_ownerDispatch;};
if (!alive _patient) exitWith {[_patient] call ACME_fnc_headElevDeathRelease;};
if !(_patient getVariable ["ACME_headElevated", false]) exitWith {};
if !(_patient getVariable ["ACME_headElev_Suspended", false]) exitWith {};

// Suspension ends in the stable face-up rest by construction. Resume directly into the authored grab/hold;
// reclassifying transient body geometry here could spuriously roll the casualty before re-elevation.
_patient setVariable ["ACME_CS_facing","front",true];

// If the elevated patient has no backpack and a manually removed carrier is still under persistent custody,
// borrow that exact carrier as the Semi-Fowler support before resuming. Other chest-access carriers keep their
// ordinary restore path and never get converted implicitly.
private _manualSupport = _patient getVariable ["ACME_headElev_manualCarrierBorrowed", false];
if (!_manualSupport
    && {(backpack _patient) == ""}
    && {(_patient getVariable ["ACME_manualPlateCarrierState", ""]) == "off"}) then {
    _manualSupport = [_patient, "borrow"] call ACME_fnc_manualPlateCarrierHeadElevSupport;
};

if (!_manualSupport) then {
    // If the elevated patient uses a backpack, a chest-access action may have temporarily parked the worn carrier.
    // Restore it only when no chest-access owner still needs the chest clear.
    [_patient] call ACME_fnc_chestAccessVestRestore;
};

_patient setVariable ["ACME_headElev_suspendKeepVestOut", false, true];
_patient setVariable ["ACME_headElev_suspendVestLoadout", [], false];
_patient setVariable ["ACME_headElev_suspendReadyAt", -1, false];
_patient setVariable ["ACME_headElev_Suspended", false, true];
_patient setVariable ["ACME_headElev_basePosASL", getPosASL _patient, true];
_patient setVariable ["ACME_headElev_baseDir", getDir _patient, true];

// No-backpack Semi-Fowler: release the fixed chest-workspace park, then move the same support carrier
// back behind the upper back. Backpack Semi-Fowler has no head-elevation carrier prop.
private _headProp = _patient getVariable ["ACME_headElev_propObj", objNull];
if (!isNull _headProp) then {_headProp setVariable ["ACME_chestFixedPark", nil, false];};
[_patient] call ACME_fnc_headElevPropApply;
private _resumed = [_patient] call ACME_fnc_headElevApplyTilt;
if !(_resumed isEqualTo true) then {
    // Keep the logical episode suspended and retry after the competing animation lease retires. Never publish an
    // elevated logical state while the casualty is still visually flat.
    _patient setVariable ["ACME_headElev_Suspended", true, true];
    _patient setVariable ["ACME_headElev_ResumePending", true, true];
    [{_this call ACME_fnc_headElevTryResume;}, [_patient, _patient getVariable ["ACME_headElev_poseToken", ""]], 0.15]
        call CBA_fnc_waitAndExecute;
};
