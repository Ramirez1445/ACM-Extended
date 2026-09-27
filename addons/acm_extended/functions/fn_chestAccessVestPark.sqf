// Park the removed chest-access carrier once beyond the casualty's head.
// The first call captures a fixed world-space target on the prop. Later patient movement/rolls never drag it.
params [["_patient", objNull, [objNull]]];
if (isNull _patient || {!local _patient}) exitWith {};

private _prop = _patient getVariable ["ACME_chestAccess_vestProp", objNull];
if (isNull _prop) exitWith {};

// While Semi-Fowler is borrowing this manually removed carrier, the fixed chest-access watchdog must not yank the
// prop back to the ground park. Re-seat the same object behind the upper back instead.
if ((_patient getVariable ["ACME_headElev_manualCarrierBorrowed", false])
    && {_patient getVariable ["ACME_headElevated", false]}
    && {!(_patient getVariable ["ACME_headElev_Suspended", false])}) exitWith {
    _prop setVariable ["ACME_chestFixedPark", nil, false];
    [_patient] call ACME_fnc_headElevPropApply;
};

private _park = _prop getVariable ["ACME_chestFixedPark", []];
if !(_park isEqualType [] && {count _park == 3}) then {
    private _pel = _patient modelToWorldVisual (_patient selectionPosition "pelvis");
    private _hed = _patient modelToWorldVisual (_patient selectionPosition "head");
    private _dx = (_hed select 0) - (_pel select 0);
    private _dy = (_hed select 1) - (_pel select 1);
    private _mag = sqrt ((_dx * _dx) + (_dy * _dy));
    if (_mag < 0.05) then {
        private _dir = getDir _patient;
        _dx = sin _dir;
        _dy = cos _dir;
        _mag = 1;
    };
    private _axis = [_dx / _mag, _dy / _mag, 0];
    private _gap = missionNamespace getVariable ["ACME_headElev_propGroundGap", 0.45];
    private _px = (_hed select 0) + ((_axis select 0) * _gap);
    private _py = (_hed select 1) + ((_axis select 1) * _gap);
    private _pos = [_px, _py, 0.02];
    private _up = surfaceNormal [_px, _py];
    _park = [_pos, _axis, _up];
    _prop setVariable ["ACME_chestFixedPark", +_park, false];
};

_park params ["_pos", "_axis", "_up"];
detach _prop;
_prop disableCollisionWith _patient;
_patient disableCollisionWith _prop;
[_prop, _pos, _axis, _up, missionNamespace getVariable ["ACME_headElev_propEaseTime", 0.24]] call ACME_fnc_propEaseTo;
