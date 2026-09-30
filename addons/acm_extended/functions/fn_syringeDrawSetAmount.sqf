/* Keep the native ACM syringe amount, hit control and visible plunger in one state.
 * Use this whenever ACME has to correct/reset a draw outside ACM's live drag loop.  Updating only
 * SyringeDraw_DrawnAmount leaves the artwork behind and is the source of the "broken plunger" look.
 */
disableSerialization;
params [
    ["_amount", 0, [0]],
    ["_display", displayNull, [displayNull]],
    ["_stopMoving", false, [false]]
];
if (isNull _display) then {_display = findDisplay 84000;};
if (isNull _display || {!finite _amount}) exitWith {false};

private _size = (missionNamespace getVariable ["ACM_circulation_SyringeDraw_Size", 10]) max 0.1;
_amount = (_amount max 0) min _size;
[[["syringeDrawDrawnAmount", _amount]]] call ACM_circulation_fnc_setLocalUiState;
if (_stopMoving) then {
    [[["syringeDrawMoving", false]]] call ACM_circulation_fnc_setLocalUiState;
};

private _top = missionNamespace getVariable ["ACM_circulation_SyringeDraw_Ctrl_LimitTop", -1];
private _bottom = missionNamespace getVariable ["ACM_circulation_SyringeDraw_Ctrl_LimitBottom", -1];
if (_top < 0 || {_bottom < 0}) exitWith {true};

private _y = linearConversion [0, _size, _amount, _top, _bottom, true];
private _hit = _display displayCtrl 84009;
if (!isNull _hit) then {
    (ctrlPosition _hit) params ["_x", "", "_w", "_h"];
    _hit ctrlSetPosition [_x, _y, _w, _h];
    _hit ctrlCommit 0;
};

private _visualIdc = missionNamespace getVariable ["ACM_circulation_SyringeDraw_Ctrl_PlungerVisual", -1];
private _visual = if (_visualIdc >= 0) then {_display displayCtrl _visualIdc} else {controlNull};
if (!isNull _visual) then {
    private _adjust = missionNamespace getVariable ["ACM_circulation_SyringeDraw_Ctrl_PlungerAdjustment", 0];
    (ctrlPosition _visual) params ["_vx", "", "_vw", "_vh"];
    _visual ctrlSetPosition [_vx, _y - _adjust, _vw, _vh];
    _visual ctrlCommit 0;
};
true
