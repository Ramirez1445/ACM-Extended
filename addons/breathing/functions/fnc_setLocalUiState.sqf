#include "..\script_component.hpp"
/* Breathing-owned writer for local UI namespace state used by Extended presentation code. */
params [["_changes", [], [[]]]];
private _applied = 0;
{
    if !(_x isEqualType [] && {count _x >= 2}) then {continue;};
    _x params ["_field", "_value"];
    switch (_field) do {
        case "stethoscopeDisplay": {
            uiNamespace setVariable [QGVAR(Stethoscope_DLG), _value];
            _applied = _applied + 1;
        };
    };
} forEach _changes;
_applied
