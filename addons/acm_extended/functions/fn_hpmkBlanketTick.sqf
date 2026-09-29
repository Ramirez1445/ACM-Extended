// HPMK state/blanket safety net. Wrapped-patient world visuals are intentionally disabled elsewhere; this function
// never creates or attaches an object to a casualty. Dropped HPMKs keep their existing shared world anchor so they
// can still be picked up after a non-Get-Up mobility transition.
if (!isServer) exitWith {};

private _class = missionNamespace getVariable ["ACME_hpmk_blanketClass", ""];

private _fnc_killLegacy = {
    params ["_unit"];
    private _b = _unit getVariable ["ACME_hpmk_blanket", objNull];
    if (!isNull _b) then { deleteVehicle _b; };
    [_unit, "ACME_hpmk_blanket", objNull] call ACME_fnc_setVarNet;
};

// If the feature is disabled, tear down any legacy wrapped anchor that may have survived from an older state.
if !(missionNamespace getVariable ["ACME_sys_hpmk", true]) exitWith {
    private _tracked = missionNamespace getVariable ["ACME_hpmk_serverPatients", []];
    { if (!isNull _x) then { [_x] call _fnc_killLegacy; }; } forEach _tracked;
    missionNamespace setVariable ["ACME_hpmk_serverPatients", []];
};

{
    private _p = _x;
    private _state = _p getVariable ["ACME_hpmk_state", ""];
    private _legacy = _p getVariable ["ACME_hpmk_blanket", objNull];

    // A networked/attached blanket anchor is legacy state and is never retained on a casualty.
    if (!isNull _legacy) then { [_p] call _fnc_killLegacy; };
    if (_state == "") then { continue; };
    if (_p getVariable ["ACME_hpmk_returnPending", false]) then { continue; };

    private _lyingState = _p getVariable ["ACM_core_Lying_State", false];
    private _isLying = if (_lyingState isEqualType true) then {_lyingState} else {_lyingState > 0};
    private _fullyMobile = alive _p && {!(_p getVariable ["ACE_isUnconscious", false])} && {!_isLying};
    if (!_fullyMobile) then { continue; };

    if (_state == "prepped") then {
        // A staged but not-yet-wrapped kit has no dropped blanket presentation. Cancel the prep and return the reusable
        // kit to its recorded provider, or to the casualty if legacy state has no provider metadata.
        private _receiver = _p getVariable ["ACME_hpmk_provider", objNull];
        if (isNull _receiver) then { _receiver = _p; };
        _p setVariable ["ACME_hpmk_returnPending", true, true];
        ["ACME_ownerCommand", [_p, "hpmkRemove", [_receiver, _p, true]], _p] call CBA_fnc_targetEvent;
    } else {
        // For a wrapped/exposed casualty that becomes mobile by some path other than ACM Get Up, preserve the existing
        // dropped-HPMK behavior. Explicit Get Up clears state synchronously first, so it never reaches this fallback.
        if (_class != "") then {
            private _drop = [_class, getPosATL _p] call ACME_fnc_hpmkSpawnBlanket;
            if (!isNull _drop) then {
                _drop setPosATL (getPosATL _p);
                _drop setDir (getDir _p);
                [_drop, "ACME_hpmk_dropped", true] call ACME_fnc_setVarNet;
            };
        };
        [_p, "", true, true] call ACME_fnc_hpmkStateCommit;
        _p setVariable ["ACME_hpmk_provider", objNull, true];
        _p setVariable ["ACME_hpmk_returnPending", false, true];
        private _near = allPlayers select {alive _x && {(_x distance _p) <= 80}}; if !(_near isEqualTo []) then {["ACME_worldSfx", [_p, "ACM_HPMK_Remove"], _near] call CBA_fnc_targetEvent;};
        if (!isNil "ace_medical_treatment_fnc_addToLog") then {
            [_p, "activity", "HPMK slipped off (patient became mobile)", []] call ace_medical_treatment_fnc_addToLog;
        };
    };
} forEach (+(missionNamespace getVariable ["ACME_hpmk_serverPatients", []]));

ACME_hpmk_serverPatients = (missionNamespace getVariable ["ACME_hpmk_serverPatients", []]) select {
    !isNull _x && {
        (_x getVariable ["ACME_hpmk_state", ""]) != ""
            || {!isNull (_x getVariable ["ACME_hpmk_blanket", objNull])}
    }
};
