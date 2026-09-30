/* Bind the physical vial session when the medic selects a medication row in ACM's backing listbox.
 * One changed selection binds one vial. Re-selecting the same row programmatically only refreshes
 * the existing limit; an intentional same-row visible click is handled by skListSelect.
 */
disableSerialization;
params ["_list", "_index"];
if (isNull _list || {_index < 0}) exitWith {};

private _display = findDisplay 84000;
if (isNull _display) exitWith {};

private _med = _list lbData _index;
if (_med == "") exitWith {};

private _stage = uiNamespace getVariable ["ACME_SK_WasteStage", ""];
private _infusion = !((_display getVariable ["ACME_SK_Return", []]) isEqualTo []);
private _previousMed = missionNamespace getVariable ["ACM_circulation_SyringeDraw_Medication", ""];
private _currentFill = if (_stage in ["compound","draw"]) then {
    ((uiNamespace getVariable ["ACME_SK_WasteFill", 0])
        - (uiNamespace getVariable ["ACME_SK_WasteFloorMl", 0])) max 0
} else {
    missionNamespace getVariable ["ACM_circulation_SyringeDraw_DrawnAmount", 0]
};

// Do not let a hidden/programmatic list event relabel medication already in a Prep Infusion syringe.
// Restore the backing selection to the medication that physically owns the current solution.
if (_infusion && {_currentFill > 0.0005} && {_previousMed != ""} && {_med != _previousMed}) exitWith {
    private _oldIndex = -1;
    for "_i" from 0 to ((lbSize _list) - 1) do {
        if ((_list lbData _i) == _previousMed) exitWith {_oldIndex = _i;};
    };
    if (_oldIndex >= 0 && {(lbCurSel _list) != _oldIndex}) then {
        _list lbSetCurSel _oldIndex;
    };
};

[[["syringeDrawMedication", _med],
  ["syringeDrawMedicationSelectedIndex", _index],
  ["syringeDrawMedicationSelected", true]]] call ACM_circulation_fnc_setLocalUiState;

if (_stage in ["compound","draw"] && {uiNamespace getVariable ["ACME_SK_WasteMoving", false]}) exitWith {};
if (!(_stage in ["compound","draw"]) && {missionNamespace getVariable ["ACM_circulation_SyringeDraw_Moving", false]}) exitWith {};

private _holder = [ACE_player] call ACME_fnc_vialHolder;
if (isNull _holder) exitWith {};

private _rows = _display getVariable ["ACME_SK_MedicationRows", []];
private _ri = _rows findIf {(_x param [1, ""]) == _med};
private _physicalClass = if (_ri >= 0) then {(_rows select _ri) param [3, ""]} else {""};
private _preview = [_holder, _med, 0, _physicalClass] call ACME_fnc_vialPreview;
if ((_preview param [3, 0]) <= 0.000001) exitWith {};

private _reserved = 0;
if (_stage in ["compound","draw"]) then {
    {
        if ((_x param [0, ""]) == _med) then {
            _reserved = _reserved + (_x param [1, 0]);
        };
    } forEach (uiNamespace getVariable ["ACME_SK_CompoundComponents", []]);

    if (_previousMed == _med) then {
        _reserved = _reserved + (((uiNamespace getVariable ["ACME_SK_WasteFill", 0])
            - (uiNamespace getVariable ["ACME_SK_WasteFloorMl", 0])) max 0);
    };
} else {
    if (_previousMed == _med) then {
        _reserved = missionNamespace getVariable ["ACM_circulation_SyringeDraw_DrawnAmount", 0];
    };
};

private _sessions = _display getVariable ["ACME_SK_VialSessions", createHashMap];
private _alreadyBound = !((_sessions getOrDefault [_med, []]) isEqualTo []);

// A true changed selection binds one source vial. A same-med LBSelChanged caused by a UI refresh
// must not advance to the next vial; just recover the current unlocked ceiling.
private _selectedLimit = if (_previousMed != _med || {!_alreadyBound}) then {
    ["select", _med, _reserved, _display] call ACME_fnc_vialSession
} else {
    ["limit", _med, _reserved, _display] call ACME_fnc_vialSession
};

private _size = (missionNamespace getVariable ["ACM_circulation_SyringeDraw_Size", 10]) max 0.1;
[[["syringeDrawMaxDose", (_selectedLimit max 0) min _size]]] call ACM_circulation_fnc_setLocalUiState;
[_display] call ACME_fnc_skMedicationStockRefresh;
