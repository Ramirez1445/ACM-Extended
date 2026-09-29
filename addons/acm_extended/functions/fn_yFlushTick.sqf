/* Called at the existing 0.25-second maintenance cadence; replicated jobs survive owner migration. */
params ["_p"];
if (!local _p) exitWith {};
private _jobs = _p getVariable ["ACME_yFlushJobs", createHashMap];
if (count _jobs == 0) exitWith {};
private _map = _p getVariable ["ACM_circulation_IV_Bags", createHashMap];
private _changed = false;
private _jobsChangedTopology = false;
{
    private _key = _x; private _job = _jobs get _key;
    _job params ["_part", "_iv", "_site", "_id", "_remaining", "_rate", "_last", "_medic", "_epoch"];
    if (!alive _p || {_epoch != ([_p] call ACME_fnc_clinicalEpoch)}) then {_jobs deleteAt _key; _jobsChangedTopology = true; continue;};
    private _arr = _map getOrDefault [_part, []];
    private _idx = _arr findIf {(_x param [8, ""]) == _id && {(_x param [3, -1]) == _site} && {(_x param [4, true]) == _iv}};
    if (_idx < 0 || {!([_p, _part, _iv, _site] call ACME_fnc_isYLineAccess)}) then {_jobs deleteAt _key; _jobsChangedTopology = true; [_medic, "Flush stopped: that reserve or access was removed."] call ACME_fnc_clinicalNotice; continue;};
    private _dt = ((CBA_missionTime - _last) max 0) min 5;
    private _partIndex = ACME_infusion_bodyParts find toLowerANSI _part;
    private _blocked = [_p, _partIndex] call ACME_fnc_aajtOccludes;
    private _tq = (_p getVariable ["ace_medical_tourniquets", [0,0,0,0,0,0]]) param [_partIndex, 0];
    if (_tq > 0 && {_iv || {_partIndex > 3}}) then {_blocked = true;};
    private _flow = if (_iv) then {((_p getVariable ["ACM_circulation_FluidBagsFlow_IV", [[1,1,1],[1,1,1],[1,1,1],[1,1,1],[1,1,1],[1,1,1]]]) select _partIndex) param [_site, 0]} else {(_p getVariable ["ACM_circulation_FluidBagsFlow_IO", [1,1,1,1,1,1]]) param [_partIndex, 0]};
    if (_flow <= 0) then {_blocked = true;};
    private _e = +(_arr select _idx);
    private _drain = if (_blocked) then {0} else {(_rate * _dt) min _remaining min (_e select 1)};
    // Same extravasation fraction as the native drainer, not whole-patient rollback.
    private _pass = 1;
    if (([_p, _partIndex, _iv, _site] call ACM_circulation_fnc_getIVFlowRate) <= 0) then {_drain = 0;};
    if (_iv && {missionNamespace getVariable ["ACM_circulation_IVComplications", false]}) then {
        private _rows = _p getVariable ["ACM_circulation_IV_Complication_Placement_Flow", [[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0],[0,0,0]]];
        private _c = (((_rows select _partIndex) param [_site, 0]) max 0) min 2;
        _drain = _drain * ([1,0.9,0.85] select _c);
        _pass = [1,1,0.8] select _c;
    };
    _pass = [_p,_part,if (_iv) then {_site} else {-1}] call ACME_fnc_medicationLineFraction;
    if (_drain > 0) then {
        private _admitted = _drain * _pass;
        [_p, _part, _idx, _e, _drain, _admitted, _dt, true] call ACME_fnc_fluidCommit;
        [_p, [["salineVolume", (_p getVariable ["ACM_circulation_Saline_Volume", 0]) + (_admitted / 1000)]], true] call ACM_circulation_fnc_setRuntimeState;
        _e set [1, ((_e select 1) - _drain) max 0];
        if ((_e select 1) <= 0.01) then {_e set [0, "ACME_EmptySaline"];};
        _arr set [_idx, _e]; _map set [_part, _arr]; _changed = true;
    };
    _remaining = (_remaining - _drain) max 0;
    if (_remaining <= 0.001) then {
        _jobs deleteAt _key;
        _jobsChangedTopology = true;
        {private _m = _p getVariable [_x, createHashMap]; _m set [_key, 0]; [_p, _x, _m] call ACME_fnc_setVarNet;} forEach ["ACME_YLineUnitsSinceFlush", "ACME_YLineVolSinceFlush"];
        private _dirty = _p getVariable ["ACME_YLineDirty", createHashMap]; _dirty set [_key, false]; [_p, "ACME_YLineDirty", _dirty] call ACME_fnc_setVarNet;
        [_p, "ACME_bloodLineDirty", ((values _dirty) findIf {_x}) >= 0] call ACME_fnc_setVarNet;
        [_medic, "Line flushed. Next unit ready."] call ACME_fnc_clinicalNotice;
    } else {_job set [4, _remaining]; _job set [6, CBA_missionTime]; _jobs set [_key, _job];};
} forEach (keys _jobs);
if (_changed) then {[_p, _map, true] call ACME_fnc_ivBagsCommit;};

// Exact scheduler timestamps/remaining volume are owner-local. Replicate the small job map at most once per second
// so locality transfer can resume it, and immediately when a job starts/stops. The old code changed the "last" field
// every 0.25 s, which forced a structured public update every circulation pass.
_p setVariable ["ACME_yFlushJobs", _jobs, false];
private _jobsNow = diag_tickTime;
private _jobsLast = _p getVariable ["ACME_yFlushJobsNetAt", -1];
if (_jobsChangedTopology || {_jobsLast < 0} || {(_jobsNow - _jobsLast) >= 1}) then {
    _p setVariable ["ACME_yFlushJobsNetAt", _jobsNow, false];
    [_p, "ACME_yFlushJobs", _jobs] call ACME_fnc_setVarNet;
} else {
    if (missionNamespace getVariable ["ACME_net_count", false]) then {
        private _saved = missionNamespace getVariable ["ACME_net_saved", createHashMap];
        _saved set ["ACME_yFlushJobs", (_saved getOrDefault ["ACME_yFlushJobs", 0]) + 1];
        missionNamespace setVariable ["ACME_net_saved", _saved];
    };
};
