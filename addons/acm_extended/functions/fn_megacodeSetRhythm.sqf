/* Apply an instructor-selected rhythm using the same ACME rhythm contract as the LifePak. */
params ["_key"];
private _d=uiNamespace getVariable ["ACME_MC_target",objNull];
if (isNull _d) exitWith {};
private _k=toLowerANSI _key;
// [legacy panel label, default mechanical HR, pulseless, ACME/native rhythm code, arrest]
private _map=createHashMapFromArray [
    ["sinus",["sinus",78,false,0,false]],
    ["stach",["sinus",130,false,0,false]],
    ["sbrady",["sinus",45,false,0,false]],
    ["afib",["afib",84,false,103,false]],
    ["afibrvr",["afibrvr",150,false,100,false]],
    ["atrialtach",["atrialtach",175,false,101,false]],
    ["svt",["svt",190,false,104,false]],
    ["vt",["vt",180,false,4,false]],
    // 102 is ACME torsades/polymorphic VT. Its native proxy remains PVT underneath, but the AED and Kelly now
    // consume the same custom morphology instead of Kelly silently downgrading the button to generic PVT.
    ["torsades",["torsades",0,true,102,true]],
    ["vfib",["vfib",0,true,2,true]],
    ["asystole",["asystole",0,true,1,true]],
    ["pea",["sinus",0,true,5,true]]
];
private _e=_map getOrDefault [_k,["sinus",78,false,0,false]];
_e params ["_legacy","_hr","_pulseless","_code","_arrest"];
_d setVariable ["ACME_MC_rhythm",_legacy,true];
_d setVariable ["ACME_MC_rhythmKey",_k,true];
_d setVariable ["ACME_MC_pulseless",_pulseless,true];
_d setVariable ["ACME_MC_HR",_hr,true];
_d setVariable ["ACME_MC_HRTgt",_hr,true];
[_d,_code,true,false] call ACME_fnc_rhythmActiveCommit;

// Force a clean electrical-rate/beat-clock handoff. The monitor regenerates on the next tick from the same AED source.
_d setVariable ["ACME_AED_ElectricalRateRhythm",-999,false];
_d setVariable ["ACME_AED_ElectricalRateLastUpdate",-1,false];
_d setVariable ["ACME_AED_ClockRhythm",-999,false];
[_d, [["aedPadsLastBeep", CBA_missionTime]], false] call ACM_circulation_fnc_setRuntimeState;
uiNamespace setVariable ["ACME_MC_waveSig",""];

if (_arrest) then {
    [_d,_code,true] remoteExec ["ACME_fnc_megacodeArrest",_d];
} else {
    if (_d getVariable ["ace_medical_inCardiacArrest",false]) then {[_d,0,false] remoteExec ["ACME_fnc_megacodeArrest",_d];};
    [_d,_code] call ACME_fnc_rhythmSet;
    [_d,[["heartRate",_hr]],true] call ACM_core_fnc_setTargetVitalsState;
};
[[format ["Rhythm: %1",toUpper _k],if (_pulseless) then {"#ff8a8a"} else {"#9be08c"}]] call ACME_fnc_megacodeLog;
[87300,"rhythm"] call ACME_fnc_megacodeMenu;
