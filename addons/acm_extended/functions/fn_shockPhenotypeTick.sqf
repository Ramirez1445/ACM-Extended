/*
 * Shock phenotypes layered onto ACM's existing hemodynamics.
 * The native blood-volume/pleural/circulation systems remain authoritative for the cause; this layer shapes
 * compensatory SVR/HR and exposes a phenotype for pulse/skin/training systems.
 */
private _now = CBA_missionTime;
{
    private _u = _x;
    if (isNull _u || {!local _u} || {!alive _u}) then {continue};

    private _type = "none";
    private _sev = 0;
    private _forced = _u getVariable ["ACME_shock_forced", []];
    if (_forced isEqualType [] && {count _forced >= 2}) then {
        private _until = _forced param [2,-1];
        if (_until < 0 || {_now <= _until}) then {
            _type = toLowerANSI (_forced param [0,"none"]);
            _sev = (_forced param [1,0]) max 0 min 1;
        } else {
            [_u,"ACME_shock_forced",[]] call ACME_fnc_setVarNet;
        };
    };

    if (_type == "none") then {
        // Obstructive shock outranks hypovolemia because its pulse/pressure character is clinically distinct.
        private _tension = _u getVariable ["ACM_breathing_TensionPneumothorax_State", false];
        private _htx = (_u getVariable ["ACM_breathing_Hemothorax_Fluid",0]) max 0;
        if (_tension || {_htx >= 0.75}) then {
            _type = "obstructive";
            _sev = (if (_tension) then {0.70} else {0}) max (linearConversion [0.5,1.5,_htx,0.25,1,true]);
        } else {
            private _circ = _u getVariable ["ACME_circ_State", createHashMap];
            if (_circ isEqualType createHashMap && {_circ getOrDefault ["shockActive",false]} && {!(_u getVariable ["ACME_shock_ownsCirc",false])}) then {
                _type = "distributive";
                _sev = (_circ getOrDefault ["shockSeverity",0.4]) max 0 min 1;
            } else {
                private _blood = _u getVariable ["ACM_circulation_Blood_Volume",6];
                if (_blood < 5.1) then {
                    _type = "hemorrhagic";
                    _sev = linearConversion [5.1,2.8,_blood,0.12,1,true];
                };
            };
        };
    };

    private _svrAdj = 0;
    private _hrAdj = 0;
    switch (_type) do {
        case "hemorrhagic":  {_svrAdj = 28 * _sev; _hrAdj = 48 * _sev;};
        case "distributive": {_svrAdj = -48 * _sev; _hrAdj = 38 * _sev;};
        case "cardiogenic":  {_svrAdj = 24 * _sev; _hrAdj = 26 * _sev;};
        case "obstructive":  {_svrAdj = 30 * _sev; _hrAdj = 36 * _sev;};
        case "neurogenic":   {_svrAdj = -38 * _sev; _hrAdj = -32 * _sev;};
    };

    // Publish source-separated hemodynamic drives. The authoritative fork-native HR/resistance endpoints
    // compose these once with native physiology; this PFH never fights those writers directly.
    [_u,"ACME_shock_resistDelta",_svrAdj,0.10,2] call ACME_fnc_setVarNetApprox;
    [_u,"ACME_shock_hrAdj",_hrAdj,0.10,2] call ACME_fnc_setVarNetApprox;

    // Forced cardiogenic/neurogenic shock needs a pressure-failure component even with preserved blood volume.
    // Reuse ACME's established shock MAP-drop state, and relinquish it cleanly when this layer no longer owns it.
    private _ownsCirc = _u getVariable ["ACME_shock_ownsCirc",false];
    if (_type in ["cardiogenic","neurogenic","obstructive"]) then {
        private _circ = _u getVariable ["ACME_circ_State",createHashMap];
        if !(_circ isEqualType createHashMap) then {_circ = createHashMap;};
        private _oldActive = _circ getOrDefault ["shockActive",false];
        private _oldSeverity = _circ getOrDefault ["shockSeverity",0];
        _circ set ["shockActive",true];
        _circ set ["shockSeverity",_sev];
        if (!_oldActive || {abs (_oldSeverity - _sev) >= 0.005}) then {
            [_u, _circ] call ACME_fnc_circStateCommit;
        } else {
            _u setVariable ["ACME_circ_State",_circ,false];
        };
        _u setVariable ["ACME_shock_ownsCirc",true,false];
        if (!isNil "ACME_circ_activePatients") then {ACME_circ_activePatients pushBackUnique _u;};
    } else {
        if (_ownsCirc) then {
            private _circ = _u getVariable ["ACME_circ_State",createHashMap];
            if (_circ isEqualType createHashMap) then {
                private _wasActive = _circ getOrDefault ["shockActive",false];
                private _wasSeverity = _circ getOrDefault ["shockSeverity",0];
                _circ set ["shockActive",false];
                _circ set ["shockSeverity",0];
                if (_wasActive || {_wasSeverity != 0}) then {
                    [_u, _circ] call ACME_fnc_circStateCommit;
                } else {
                    _u setVariable ["ACME_circ_State",_circ,false];
                };
            };
            _u setVariable ["ACME_shock_ownsCirc",false,false];
        };
    };

    [_u,"ACME_shock_phenotype",_type] call ACME_fnc_setVarNet;
    [_u,"ACME_shock_severity",_sev,0.002,2] call ACME_fnc_setVarNetApprox;
    [_u,"ACME_shock_warm",(_type == "distributive" || {_type == "neurogenic"})] call ACME_fnc_setVarNet;
} forEach allUnits;
