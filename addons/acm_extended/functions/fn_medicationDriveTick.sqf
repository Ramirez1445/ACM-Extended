/* B121 called once by patient-owner circulation. The total-rate keys preserve the historical API; source-specific
   keys are also published for diagnostics/future tuning. */
params ["_patient","_dt"];
private _rates = createHashMap;
if (isNull _patient || {!local _patient}) exitWith {_rates};
if (!alive _patient) exitWith {
    [_patient] call ACME_fnc_deadPhysiologyFreeze;
    _rates
};
if (_dt <= 0) exitWith {_rates};
private _queue = _patient getVariable ["ACME_medicationDriveQueue",[]];
private _keep = [];
{
    _x params ["_base","_mass","_remaining",["_source","bolus"]];
    private _step = _dt min (_remaining max 0.000001);
    private _delivered = _mass * (_step / (_remaining max 0.000001));
    private _rate = _delivered*60/_dt;
    _rates set [_base,(_rates getOrDefault [_base,0])+_rate];
    _rates set [format ["%1#%2",_base,_source],(_rates getOrDefault [format ["%1#%2",_base,_source],0])+_rate];
    if (_remaining > _dt+0.000001) then {_keep pushBack [_base,(_mass-_delivered) max 0,_remaining-_dt,_source];};
} forEach _queue;

// Exact remaining mass/time is owner-local every circulation tick. A structural completion publishes immediately;
// otherwise one snapshot per second is sufficient for locality migration and diagnostics.
_patient setVariable ["ACME_medicationDriveQueue", _keep, false];
private _driveNow = diag_tickTime;
private _driveLast = _patient getVariable ["ACME_medicationDriveNetAt", -1];
if ((count _keep) != (count _queue) || {_driveLast < 0} || {_driveNow - _driveLast >= 1}) then {
    _patient setVariable ["ACME_medicationDriveNetAt", _driveNow, false];
    [_patient, "ACME_medicationDriveQueue", _keep] call ACME_fnc_setVarNet;
};
[_patient,"ACME_ketRapidLoad",(_patient getVariable ["ACME_ketRapidLoad",0])*(0.5^(_dt/20)),0.005,1] call ACME_fnc_setVarNetApprox;
{
    _x params ["_key","_half"];
    [_patient,_key,(_patient getVariable [_key,0])*(0.5^(_dt/_half)),0.005,1] call ACME_fnc_setVarNetApprox;
} forEach [["ACME_hcMed_rapidPropofol",35],["ACME_hcMed_rapidMidazolam",45],["ACME_hcMed_rapidOpioid",45],["ACME_hcMed_rapidRocuronium",60]];
_rates
