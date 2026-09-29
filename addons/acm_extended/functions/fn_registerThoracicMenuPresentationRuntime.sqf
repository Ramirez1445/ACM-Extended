// Client presentation/input runtime only. Dedicated servers must not register UI PFHs, controls or keybinds.
if (!hasInterface) exitWith {};

// chest tube body marker. whenever ACE refreshes the medical menu body image, the mod shows or hides the torso
// chest tube markers per side, based on whether a tube is in place. it uses the ACE event, so it does not
// override the function.
["ace_medical_gui_updateBodyImage", {
    params ["_ctrlGroup", "_target"];
    if (isNull _ctrlGroup || {isNull _target}) exitWith {};
    private _cr = _ctrlGroup controlsGroupCtrl 70190;
    private _cl = _ctrlGroup controlsGroupCtrl 70191;
    if (!isNull _cr) then { _cr ctrlShow (_target getVariable ["ACME_thora_tube_right", false]); };
    if (!isNull _cl) then { _cl ctrlShow (_target getVariable ["ACME_thora_tube_left", false]); };

    // chest bruising overlay. this shows for blast lung and for genuine extensive chest bruising, and both use
    // the same artwork on purpose. a blast casualty and a hemothorax casualty both present with a bruised chest,
    // and the provider must work out which. the thresholds mirror ACM's own updateinjurylist, with hemothorax
    // fluid above 0.5 or torso internal bleeding above 0.15, so the picture and the text agree.
    private _br = _ctrlGroup controlsGroupCtrl 70192;
    private _bl = _ctrlGroup controlsGroupCtrl 70193;
    if (!isNull _br || {!isNull _bl}) then {
        private _blast = (_target getVariable ["ACME_blastLung_State", 0]) > 0;
        private _htx = (_target getVariable ["ACM_breathing_Hemothorax_Fluid", 0]) > 0.5;
        private _ib = 0;
        if (!isNil "ACM_damage_fnc_getBodyPartInternalBleeding") then {
            _ib = [_target, 1] call ACM_damage_fnc_getBodyPartInternalBleeding;  // 1 = torso
        };
        private _bruised = _blast || _htx || {_ib > 0.15};
        if (!isNull _br) then { _br ctrlShow _bruised; };
        if (!isNull _bl) then { _bl ctrlShow _bruised; };
    };
}] call CBA_fnc_addEventHandler;

// bilateral chest tubes. this relabels the torso thoracostomy entry to "Bilateral Chest Tubes Placed". it uses
// the ACE injury list event and edits the entries array in place, passed by reference, so it needs no function
// override.
["ace_medical_gui_updateInjuryListPart", {
    params ["_ctrl", "_target", "_selectionN", "_entries"];
    if (_selectionN != 1 || {isNull _target}) exitWith {};
    if !((_target getVariable ["ACME_thora_tube_left", false]) && {_target getVariable ["ACME_thora_tube_right", false]}) exitWith {};
    // this matches any thoracostomy incision line by its localized prefix, the part before the %1. that keeps it
    // safe against the state wording, and it survives a re-render when the medic switches limb or menu.
    private _fmtRaw = localize "STR_ACM_Breathing_GUI_ThoracostomyIncision_%1";
    private _cut = _fmtRaw find "%1";
    private _prefix = if (_cut > 0) then { _fmtRaw select [0, _cut] } else { _fmtRaw };
    {
        _x params ["_txt", "_col"];
        if (_prefix != "" && {(_txt find _prefix) == 0}) then {
            _entries set [_forEachIndex, ["Bilateral Chest Tubes Placed", _col]];
        };
    } forEach _entries;
}] call CBA_fnc_addEventHandler;
