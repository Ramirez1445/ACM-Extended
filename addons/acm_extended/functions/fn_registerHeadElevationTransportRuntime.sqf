// head elevation: transport mode.
// a drag or a carry of an elevated casualty must never leave the carrier floating. on pickup the elevation
// tears down quietly: the carrier is re-vested onto the body so it renders worn during the move, the prop is
// deleted, the helper is released, and ACE owns every animation. the elevation intent is remembered. as soon as
// the casualty is set down on the ground, the full elevation restores automatically, with the same lift
// animations, the carrier stripped back off, the wedge re-seated and the 30 degree hold. it routes through
// target events, so the work always runs where the patient is local.
["ACME_headElev_transportDown", {
    params ["_patient", ["_requestToken", "", [""]]];
    if (isNull _patient) exitWith {};

    // A pre-carry request waits for this exact token before ACE is allowed to start its carry animation.
    // This matters because headElevateStop may restore the support plate carrier with setUnitLoadout; if that
    // happens after ACE has already requested AinjPfal..._carried_Up, Arma drops the carry animation.
    if !(_patient getVariable ["ACME_headElevated", false]) exitWith {
        if (_requestToken != "") then {
            _patient setVariable ["ACME_headElev_TransportReady", _requestToken, true];
        };
    };

    // Retire any short Semi-Fowler position pin before ACE begins moving the casualty.
    _patient setVariable ["ACME_headElev_pinToken", (_patient getVariable ["ACME_headElev_pinToken", 0]) + 1, false];

    // Manual support requires a provider again after transport.
    private _passive = (_patient getVariable ["ACME_headElev_hold", []]) isEqualTo [];
    _patient setVariable ["ACME_headElev_TransportPending", _passive, true];

    [objNull, _patient, true] call ACME_fnc_headElevateStop;

    // No Semi-Fowler animation lease may survive into ACE carry ownership.
    private _lock = _patient getVariable ["ACME_patientAnimLock", []];
    if ((_lock param [1, ""]) in ["head-elev-lift", "head-elev-lower", "head-elev-flat"]) then {
        private _animToken = _lock param [0, ""];
        if (_animToken != "") then {[_patient, _animToken] call ACME_fnc_patientAnimRelease;};
    };

    if (_requestToken != "") then {
        _patient setVariable ["ACME_headElev_TransportReady", _requestToken, true];
    };
}] call CBA_fnc_addEventHandler;
["ACME_headElev_transportUp", {
    params ["_patient"];
    if (isNull _patient) exitWith {};
    if !(_patient getVariable ["ACME_headElev_TransportPending", false]) exitWith {};
    // settle first. the ACE drop animation and ACM's set-down lying state need a beat to land.
    [{
        params ["_patient"];
        if (isNull _patient || {!alive _patient}) exitWith {};
        if !(_patient getVariable ["ACME_headElev_TransportPending", false]) exitWith {};
        if (_patient getVariable ["ACME_headElevated", false]) exitWith { _patient setVariable ["ACME_headElev_TransportPending", nil, true]; };
        // picked up again, loaded, or otherwise not settled on the ground. leave the intent armed for the next genuine
        // set-down, because a new stoppeddrag or stoppedcarry re-fires this handler.
        if (!(isNull objectParent _patient) || {!(isNull attachedTo _patient)}
            || {_patient call ace_common_fnc_isBeingDragged} || {_patient call ace_common_fnc_isBeingCarried}) exitWith {};
        _patient setVariable ["ACME_headElev_TransportPending", nil, true];
        [objNull, _patient, "", true] call ACME_fnc_headElevateStart;
    }, [_patient], (missionNamespace getVariable ["ACME_headElev_transportSettle", 1.2])] call CBA_fnc_waitAndExecute;
}] call CBA_fnc_addEventHandler;
{
    [_x, {
        params ["_unit", "_target"];
        if (!isNull _target && {_target getVariable ["ACME_headElevated", false]}) then {
            ["ACME_headElev_transportDown", [_target], _target] call CBA_fnc_targetEvent;
        };
    }] call CBA_fnc_addEventHandler;
} forEach ["ace_dragging_setupDrag", "ace_dragging_setupCarry"];
["ace_dragging_stoppedDrag", {
    params ["_unit", "_target"];
    if (!isNull _target) then { ["ACME_headElev_transportUp", [_target], _target] call CBA_fnc_targetEvent; };
}] call CBA_fnc_addEventHandler;
["ace_dragging_stoppedCarry", {
    params ["_unit", "_target", ["_loadCargo", false]];
    if (!isNull _target) then {
        if (_loadCargo isEqualTo true) then {
            // carried straight into a vehicle. there is no ground set-down, so the elevation stays canceled.
            _target setVariable ["ACME_headElev_TransportPending", nil, true];
        } else {
            ["ACME_headElev_transportUp", [_target], _target] call CBA_fnc_targetEvent;
        };
    };
}] call CBA_fnc_addEventHandler;
