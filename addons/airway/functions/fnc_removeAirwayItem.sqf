#include "..\script_component.hpp"
/*
 * Author: Blue
 * Remove inserted airway item
 *
 * Arguments:
 * 0: Medic <OBJECT>
 * 1: Patient <OBJECT>
 * 2: Nasal Airway <BOOL>
 *
 * Return Value:
 * None
 *
 * Example:
 * [player, cursorTarget, false] call ACM_airway_fnc_removeAirwayItem;
 *
 * Public: No
 */

params ["_medic", "_patient", ["_nasalAirway", false]];

if (_nasalAirway) then {
    private _airway = _patient getVariable [QGVAR(AirwayItem_Nasal), ""];

    _patient setVariable [QGVAR(AirwayItem_Nasal), "", true];
} else {
    private _airway = _patient getVariable [QGVAR(AirwayItem_Oral), ""];

    // An i-gel/SGA is a valid Ventway airway. Removing it must immediately sever the ventilator circuit and
    // return the mounted device through its custody transaction before the oral-airway slot is cleared.
    if (_airway == "SGA" && {!isNil "ACME_fnc_ventAirwayLoss"}) then {
        [_patient, _medic, "i-gel removed"] call ACME_fnc_ventAirwayLoss;
    };

    _patient setVariable [QGVAR(AirwayItem_Oral), "", true];
};
