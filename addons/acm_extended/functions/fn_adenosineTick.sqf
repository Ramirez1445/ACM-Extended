/* Simplified brief AV-nodal effect. Only modeled SVT (104) can terminate.
   Does not convert VT/AF, change an arrest rhythm, or grant ROSC.
   Returning a bounded slowing TARGET is not forcing a ventricular standstill waveform. */
params ["_patient","_dt"];
if (!local _patient || {_dt <= 0}) exitWith {0};
private _episodes = _patient getVariable ["ACME_adenosineEpisodes",[]];
private _keep = [];
private _effect = 0;
{
    _x params ["_strength","_age","_attempted"];
    _age = _age + _dt;
    if (_age < 15) then {
        private _envelope = if (_age < 1) then {_age} else {
            if (_age < 2) then {1} else {exp (-0.69314718 * (_age - 2) / 2)}
        };
        _effect = _effect + _strength * _envelope;
        if (!_attempted && {_age >= 1}) then {
            _attempted = true;
            if (_strength >= 0.8 && {!(_patient getVariable ["ace_medical_inCardiacArrest",false])}
                && {([_patient] call ACME_fnc_rhythmGet) == 104}) then {
                [_patient] call ACME_fnc_rhythmRelease;
            };
        };
        _keep pushBack [_strength,_age,_attempted];
    };
} forEach _episodes;

// Episode age changes every circulation pass but is only persistence/diagnostic state remotely. Keep exact owner
// state every tick and publish at 1 Hz, or immediately when episode count/attempted state changes.
_patient setVariable ["ACME_adenosineEpisodes", _keep, false];
private _sig = _keep apply {[_x param [0,0], _x param [2,false]]};
private _lastSig = _patient getVariable ["ACME_adenosineNetSig", []];
private _lastAt = _patient getVariable ["ACME_adenosineNetAt", -1];
if (_sig isNotEqualTo _lastSig || {_lastAt < 0} || {diag_tickTime - _lastAt >= 1}) then {
    _patient setVariable ["ACME_adenosineNetSig", _sig, false];
    _patient setVariable ["ACME_adenosineNetAt", diag_tickTime, false];
    [_patient, "ACME_adenosineEpisodes", _keep] call ACME_fnc_setVarNet;
};
if (_patient getVariable ["ace_medical_inCardiacArrest",false]) exitWith {0};
private _hr = _patient getVariable ["ace_medical_heartRate",80];
-((_hr - 45) max 0) * ((_effect max 0) min 1) * 0.7
