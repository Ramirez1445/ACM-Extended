#include "..\script_component.hpp"
/*
 * Stable B180: treated-wound reopening is clot-only.
 *
 * Physical bandages, wraps and stitches are mechanically stable and are never removed by coagulation logic.
 * If this helper is re-enabled by a future wound-handler path, it may only destabilize a fraction of one
 * unsecured clotted wound; the newly inflicted trauma itself remains responsible for any new open wound.
 */
params ["_unit", "_bodyPart", "_woundType", "_woundDamage"];

if (isNull _unit || {!local _unit}) exitWith {};

private _clotted = GET_CLOTTED_WOUNDS(_unit);
private _rows = +(_clotted getOrDefault [_bodyPart, []]);
private _index = _rows findIf {
    (_x param [0, -1]) isEqualTo _woundType && {(_x param [1, 0]) > 0.001}
};
if (_index < 0) exitWith {};

private _row = +(_rows select _index);
private _amount = _row param [1, 0];
private _fraction = (missionNamespace getVariable ["ACME_clotPop_fraction", 0.15]) max 0.05 min 0.25;
private _move = _fraction min _amount;
private _remaining = (_amount - _move) max 0;

if (_remaining <= 0.001) then {
    _rows deleteAt _index;
} else {
    _row set [1, _remaining];
    _rows set [_index, _row];
};

_clotted set [_bodyPart, _rows];
_unit setVariable [VAR_CLOTTED_WOUNDS, _clotted, true];

// Deliberately no GET_BANDAGED_WOUNDS / GET_WRAPPED_WOUNDS / GET_STITCHED_WOUNDS fallback.
