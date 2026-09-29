// render the chlorhexidine and iodine prep trail for the current side: a translucent orange-brown dot at every point
// the medic dragged over, so overlaps build up into a painted swath. the points persist per patient and side.
disableSerialization;
private _display = uiNamespace getVariable ["ACME_Thora_DLG", displayNull];
if (isNull _display) exitWith {};
private _rect = uiNamespace getVariable ["ACME_Thora_BodyRect", []];
private _dots = uiNamespace getVariable ["ACME_Thora_PrepDots", []];
if (count _rect != 4 || {_dots isEqualTo []}) exitWith {};
_rect params ["_bx", "_by", "_bw", "_bh"];
private _side = uiNamespace getVariable ["ACME_Thora_Side", "right"];
private _patient = uiNamespace getVariable ["ACME_Thora_Patient", objNull];
private _prepLocal = uiNamespace getVariable ["ACME_Thora_PrepLocal", createHashMap];
private _pts = if (_prepLocal isEqualType createHashMap && {_side in keys _prepLocal}) then {
    +(_prepLocal get _side)
} else {
    if (isNull _patient) then {[]} else {+(_patient getVariable [format ["ACME_thora_prep_%1", _side], []])}
};
private _sz = _bh * 0.05;
{
    if (_forEachIndex >= (count _pts)) then {
        _x ctrlShow false;
    } else {
        (_pts select _forEachIndex) params ["_pu", "_pv"];
        _x ctrlSetPosition [(_bx + (_pu * _bw)) - (_sz / 2), (_by + (_pv * _bh)) - (_sz / 2), _sz, _sz];
        _x ctrlSetTextColor [0.72, 0.30, 0.08, 0.22];
        _x ctrlShow true;
        _x ctrlCommit 0;
    };
} forEach _dots;
