// Send one positional treatment/device sound only to players who can plausibly hear it.
// This replaces all-client remoteExec say3D broadcasts from provider treatment callbacks.
params [
    ["_source", objNull, [objNull]],
    ["_sound", "", [""]],
    ["_range", 80, [0]]
];
if (isNull _source || {_sound == ""}) exitWith {};
_range = (_range max 5) min 250;
private _targets = allPlayers select {alive _x && {(_x distance _source) <= _range}};
if (_targets isEqualTo []) exitWith {};
["ACME_worldSfx", [_source, _sound], _targets] call CBA_fnc_targetEvent;
