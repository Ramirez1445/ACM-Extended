/* B53: populate ACM's native medication listbox (IDC 84006) from one validated row source.
 *
 * Native ACM owns the proven listbox renderer. ACME supplies exact medication identity/physical vial metadata and
 * the separate Contents/Vials accounting. All data is normalized before it reaches lbSet* so one malformed source
 * entry cannot turn the entire list into anonymous rows or cascade Type Any errors through the UI.
 *
 * Return row: [displayName, medicationKey, picture, displayVialClass]
 */
disableSerialization;
params [["_display", displayNull, [displayNull]]];
if (isNull _display) exitWith {[]};
private _list = _display displayCtrl 84006;
if (isNull _list) exitWith {[]};

// B189: lbClear/lbSetCurSel on the hidden native selector can still take keyboard focus on a fresh display.
// While Seconds to Push over owns the keyboard, return the already-published row model without touching the list.
private _durationFocus = focusedCtrl _display;
private _durationEditing = (uiNamespace getVariable ["ACME_SK_PushDurationEditing", false])
    || {!isNull _durationFocus && {(ctrlIDC _durationFocus) == 84831}};
if (_durationEditing) exitWith {
    +(_display getVariable ["ACME_SK_MedicationRows", []])
};

private _infusion = !((_display getVariable ["ACME_SK_Return", []]) isEqualTo []);
private _rawRows = [_infusion] call ACME_fnc_medicationSourceRows;

// Normalize once. Downstream code only ever receives four-string rows.
private _rows = [];
{
    if !(_x isEqualType []) then {continue};
    private _label = _x param [0, ""];
    private _med = _x param [1, ""];
    private _picture = _x param [2, ""];
    private _physicalClass = _x param [3, ""];

    if !(_label isEqualType "") then {_label = "";};
    if !(_med isEqualType "") then {_med = "";};
    if !(_picture isEqualType "") then {_picture = "";};
    if !(_physicalClass isEqualType "") then {_physicalClass = "";};

    if (_med == "" && {_physicalClass != ""}) then {_med = [_physicalClass] call ACME_fnc_vialMedication;};
    if (_med == "") then {continue};

    if (_label == "" && {_physicalClass != ""}) then {
        private _cfg = configFile >> "CfgWeapons" >> _physicalClass;
        if (isClass _cfg) then {_label = getText (_cfg >> "displayName");};
    };
    if (_label == "") then {_label = _med;};

    if (_picture == "" && {_physicalClass != ""}) then {
        private _cfg = configFile >> "CfgWeapons" >> _physicalClass;
        if (isClass _cfg) then {_picture = getText (_cfg >> "picture");};
    };

    _rows pushBack [_label, _med, _picture, _physicalClass];
} forEach _rawRows;

private _expected = _rows apply {[_x param [1, ""], _x param [0, ""], _x param [2, ""]]};
private _present = [];
for "_i" from 0 to ((lbSize _list) - 1) do {
    _present pushBack [_list lbData _i, _list lbText _i, _list lbPicture _i];
};

if !(_present isEqualTo _expected) then {
    private _sel = lbCurSel _list;
    private _oldMed = if (_sel >= 0) then {_list lbData _sel} else {""};
    lbClear _list;

    {
        _x params ["_label", "_med", "_picture", "_physicalClass"];
        private _i = _list lbAdd _label;
        _list lbSetData [_i, _med];
        _list lbSetPicture [_i, _picture];
        _list lbSetTooltip [_i, _label];
        _list lbSetTextRight [_i, ""];
    } forEach _rows;

    if (_oldMed != "") then {
        for "_i" from 0 to ((lbSize _list) - 1) do {
            if ((_list lbData _i) == _oldMed) exitWith {_list lbSetCurSel _i;};
        };
    };
};

_display setVariable ["ACME_SK_MedicationRows", +_rows];
_list ctrlShow false;
[_display] call ACME_fnc_skMedicationStockRefresh;
_rows
