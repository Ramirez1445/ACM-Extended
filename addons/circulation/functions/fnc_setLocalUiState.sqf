#include "..\script_component.hpp"
/*
 * Author: ACM Extended Fork
 * Circulation-owned writer for the local missionNamespace state backing circulation UI workflows.
 */
params [["_changes", [], [[]]]];
private _applied = 0;
{
    if (_x isEqualType [] && {count _x >= 2}) then {
        _x params ["_field", "_value"];
        switch (_field) do {
            case "transfusionSelectIV": { missionNamespace setVariable [QGVAR(TransfusionMenu_SelectIV), _value]; _applied = _applied + 1; };
            case "transfusionSelectedBodyPart": { missionNamespace setVariable [QGVAR(TransfusionMenu_Selected_BodyPart), _value]; _applied = _applied + 1; };
            case "transfusionSelectedAccessSite": { missionNamespace setVariable [QGVAR(TransfusionMenu_Selected_AccessSite), _value]; _applied = _applied + 1; };
            case "medicationVialList": { missionNamespace setVariable [QGVAR(MedicationVialList), _value]; _applied = _applied + 1; };
            case "syringeDrawInventorySelection": { missionNamespace setVariable [QGVAR(SyringeDraw_InventorySelection), _value]; _applied = _applied + 1; };
            case "transfusionSelectedInventory": { missionNamespace setVariable [QGVAR(TransfusionMenu_Selected_Inventory), _value]; _applied = _applied + 1; };
            case "aedMonitorTarget": { missionNamespace setVariable [QGVAR(AED_Monitor_Target), _value]; _applied = _applied + 1; };
            case "syringeDrawMoving": { missionNamespace setVariable [QGVAR(SyringeDraw_Moving), _value]; _applied = _applied + 1; };
            case "syringeDrawMaxDose": { missionNamespace setVariable [QGVAR(SyringeDraw_MaxDose), _value]; _applied = _applied + 1; };
            case "syringeDrawMedication": { missionNamespace setVariable [QGVAR(SyringeDraw_Medication), _value]; _applied = _applied + 1; };
            case "syringeDrawMedicationSelectedIndex": { missionNamespace setVariable [QGVAR(SyringeDraw_MedicationSelected_Index), _value]; _applied = _applied + 1; };
            case "syringeDrawMedicationSelected": { missionNamespace setVariable [QGVAR(SyringeDraw_MedicationSelected), _value]; _applied = _applied + 1; };
            case "syringeDrawDrawnAmount": { missionNamespace setVariable [QGVAR(SyringeDraw_DrawnAmount), _value]; _applied = _applied + 1; };
        };
    };
} forEach _changes;
_applied
