// a server tick, registered once in postinit at about 0.25 s. it has two jobs.
// 1. the daily restock: when the in-game day rolls over at midnight, reset each restock-enabled fridge to its load.
// 2. the auto open and close: a fridge is in use while any client has pinged it within the timeout, because the
// menu poll pings while a player has the ACE menu on it. on the 0 to 1 transition, swap the visible model and play
// the door sfx. the show-then-hide ordering avoids a one-frame gap where neither model is visible.
if !(missionNamespace getVariable ["ACME_sys_bloodChain", true]) exitWith {};  // the system toggle. fully off means this stops.
if (!isServer) exitWith {};
private _fridges = missionNamespace getVariable ["ACME_bloodFridges", []];
if (_fridges isEqualTo []) exitWith {};

// the interval restock, in configurable in-game hours and minutes since the last restock of each fridge.
// the interval is read live from the addon options, in hours and minutes, defaulting to 24 h. each fridge stores its
// own last-restock time in in-game hours, so a fridge regenerates on its own schedule from when it was placed. a
// per-fridge override, ACME_bf_regenMins, set by eden or zeus, wins over the global setting.
// the elapsed in-game time is derived from dateToNumber, a fraction of the in-game year, so it follows the time
// acceleration of the mission exactly. an interval of 0 disables regeneration.
private _yearHours = 365.25 * 24;
private _nowGameHours = (dateToNumber date) * _yearHours;
{
    private _fridge = _x;
    if (!isNull _fridge && {_fridge getVariable ["ACME_bf_restock", true]}) then {
        // the per-fridge interval override, in minutes, or the global hours plus minutes setting.
        private _intervalMins = _fridge getVariable ["ACME_bf_regenMins", -1];
        if (_intervalMins < 0) then {
            _intervalMins = ((missionNamespace getVariable ["ACME_bf_regenHours", 24]) * 60)
                          + (missionNamespace getVariable ["ACME_bf_regenMinutes", 0]);
        };
        if (_intervalMins > 0) then {
            private _intervalHours = _intervalMins / 60;
            private _last = _fridge getVariable ["ACME_bf_lastRestockGH", -1];
            if (_last < 0) then {
                // the first tick after placement: anchor the clock and do not restock yet.
                [_fridge, "ACME_bf_lastRestockGH", _nowGameHours] call ACME_fnc_setVarNet;
            } else {
                // guard the year-rollover wrap, because dateToNumber resets at jan 1: if now is below last, re-anchor.
                if (_nowGameHours < _last) then {
                    [_fridge, "ACME_bf_lastRestockGH", _nowGameHours] call ACME_fnc_setVarNet;
                } else {
                    if ((_nowGameHours - _last) >= _intervalHours) then {
                        [_fridge, "ACME_bf_stock", +(_fridge getVariable ["ACME_bf_default", []])] call ACME_fnc_setVarNet;
                        [_fridge, "ACME_bf_lastRestockGH", _nowGameHours] call ACME_fnc_setVarNet;
                    };
                };
            };
        };
    };
} forEach _fridges;

// the viewer-driven open and close.
private _now = diag_tickTime;
private _timeout = missionNamespace getVariable ["ACME_bf_viewTimeout", 0.9];
{
    private _anchor = _x;
    if (!isNull _anchor) then {
        private _viewers = _anchor getVariable ["ACME_bf_viewers", createHashMap];
        private _live = false;
        {
            if ((_now - _y) <= _timeout) then { _live = true; };
        } forEach _viewers;

        private _open = _anchor getVariable ["ACME_bf_open", false];
        private _openObj = _anchor getVariable ["ACME_bf_openObj", objNull];

        if (_live && !_open) then {
            [_anchor, "ACME_bf_open", true] call ACME_fnc_setVarNet;
            if (!isNull _openObj) then { _openObj hideObjectGlobal false; };
            _anchor hideObjectGlobal true;
            private _near = allPlayers select {alive _x && {(_x distance _anchor) <= 80}}; if !(_near isEqualTo []) then {["ACME_worldSfx", [_anchor, "ACME_BloodFridgeDoorOpen"], _near] call CBA_fnc_targetEvent;};
        };
        if (!_live && _open) then {
            [_anchor, "ACME_bf_open", false] call ACME_fnc_setVarNet;
            _anchor hideObjectGlobal false;
            if (!isNull _openObj) then { _openObj hideObjectGlobal true; };
            private _near = allPlayers select {alive _x && {(_x distance _anchor) <= 80}}; if !(_near isEqualTo []) then {["ACME_worldSfx", [_anchor, "ACME_BloodFridgeDoorClose"], _near] call CBA_fnc_targetEvent;};
        };
    };
} forEach _fridges;
