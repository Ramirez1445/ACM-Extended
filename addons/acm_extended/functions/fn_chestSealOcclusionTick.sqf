/* Blood/debris changes patency; it never directly creates pleural gas.
Dry treated wounds have no mandatory clog timer. */
params [["_patient",objNull,[objNull]]];
if (isNull _patient || {!local _patient} || {!alive _patient}) exitWith {};
private _context=[_patient] call ACME_fnc_ptxContext;
private _dt=[_patient,"sealOcclusion",0.25,5] call ACME_fnc_clinicalTickDelta;
if !(_context select 6) exitWith {
    [_patient,"ACME_CS_sealOcclusion",0] call ACME_fnc_setVarNet;
    [_patient,"ACME_CS_sealVenting",1] call ACME_fnc_setVarNet;
};
private _blood=_context select 3;
private _rate=if (missionNamespace getVariable ["ACME_hcEff_cs",false]) then {0.006} else {0.0022};
private _occ=((_patient getVariable ["ACME_CS_sealOcclusion",0]) max 0 min 1);
_occ=(_occ+_blood*_rate*_dt) min 1;
[_patient,"ACME_CS_sealOcclusion",_occ,0.005,1] call ACME_fnc_setVarNetApprox;
[_patient,"ACME_CS_sealVenting",1-_occ,0.005,1] call ACME_fnc_setVarNetApprox;
