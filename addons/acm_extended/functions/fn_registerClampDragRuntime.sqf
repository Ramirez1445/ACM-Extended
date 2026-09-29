// Roller-clamp drag/vision presentation is client-only. Dedicated servers must not run an empty every-frame UI PFH.
if (!hasInterface) exitWith {};

[{
    private _display = findDisplay 86200;
    if (isNull _display) exitWith {};

    // watchdog. this initializes the clamp dialog whatever created it.
    call ACME_fnc_onClampLoad;

    // Keep the full-screen darkness shade synchronized with the player's real vision state even when the wheel
    // is not moving. The old one-shot update could sample the dialog-transition frame as normal vision, paint an
    // opaque shade, and then leave that shade latched over native NV. During the short settle window we check every
    // frame; afterward 10 Hz is enough for NV toggles and ambient-light changes while keeping this purely local.
    private _visionNow = diag_tickTime;
    private _visionSettleUntil = uiNamespace getVariable ["ACME_RollerClamp_VisionSettleUntil", 0];
    private _visionNext = uiNamespace getVariable ["ACME_RollerClamp_NextVisionTick", 0];
    if (_visionNow <= _visionSettleUntil || {_visionNow >= _visionNext}) then {
        uiNamespace setVariable [
            "ACME_RollerClamp_NextVisionTick",
            if (_visionNow <= _visionSettleUntil) then {_visionNow} else {_visionNow + 0.10}
        ];
        [_display, [], "ACME_Clamp_Shade"] call ACME_fnc_darknessShade;
        [_display] call ACME_fnc_minigameVisionTick;
    };

    if !(uiNamespace getVariable ["ACME_RollerClamp_Dragging", false]) exitWith {};

    private _track = uiNamespace getVariable ["ACME_RollerClamp_Track", []];
    if (_track isEqualTo []) exitWith {};
    _track params ["_x", "_y", "_w", "_h"];

    private _top = missionNamespace getVariable ["ACME_infusion_clampTravelTop", 0.186];
    private _bottom = missionNamespace getVariable ["ACME_infusion_clampTravelBottom", 0.849];
    private _xRatio = missionNamespace getVariable ["ACME_infusion_clampWheelXRatio", 0.49];

    private _topY = _y + (_h * _top);
    private _bottomY = _y + (_h * _bottom);
    private _pinX = _x + (_w * _xRatio);

    getMousePosition params ["_mouseX", "_mouseY"];
    private _newY = (_mouseY max _topY) min _bottomY;
    setMousePosition [_pinX, _newY];

    private _rel = 0;
    if ((_bottomY - _topY) > 0) then {
        // a drag up, toward a smaller screen y, opens the clamp. the top of the band is openness 1 and the bottom is 0.
        _rel = (1 - (((_newY - _topY) / (_bottomY - _topY)) max 0 min 1)) max 0 min 1;
    };

    uiNamespace setVariable ["ACME_RollerClamp_Position", _rel];
    [_rel] call ACME_fnc_placeClampWheel;
    [_rel] call ACME_fnc_playClampSfx;

    if (CBA_missionTime >= (uiNamespace getVariable ["ACME_RollerClamp_NextCommit", 0])) then {
        uiNamespace setVariable ["ACME_RollerClamp_NextCommit", CBA_missionTime + (missionNamespace getVariable ["ACME_infusion_clampCommitInterval", 0.25])];
        [_rel, true] call ACME_fnc_setClampPosition;
    };
}, 0, []] call CBA_fnc_addPerFrameHandler;
