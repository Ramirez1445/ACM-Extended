
// put the head back. fn_thoraopen suspends head elevation on the way in and nothing ever resumed it, so the plate
// carrier was left lying on the ground superior to the head and the casualty stayed flat, permanently. it is the
// same delayed resume the chest seal screen uses, so ACM has finished whatever it was doing first.
private _pHE = uiNamespace getVariable ["ACME_Thora_Patient", objNull];
private _mHE = uiNamespace getVariable ["ACME_Thora_Medic", objNull];

private _entryKeyState = uiNamespace getVariable ["ACME_Thora_EntryKeys",[]];
{
    if (!(_x isEqualTo -1) && {!(_x isEqualTo "")}) then {[_x,"keydown"] call CBA_fnc_removeKeyHandler;};
} forEach (_entryKeyState param [1,[]]);
uiNamespace setVariable ["ACME_Thora_EntryKeys",[]];
uiNamespace setVariable ["ACME_Thora_EntryCancelToken",""];
[false,_mHE,_pHE,uiNamespace getVariable ["ACME_Thora_ChestAccessLease",""]] call ACME_fnc_chestAccessPreparing;

// Defensive provider cleanup. Normal entry releases chestAccess before the panel opens, but a close/abort racing
// a delayed provider packet must still be able to free the player immediately.
if (!isNull _mHE && {local _mHE}) then {
    private _providerEntry = _mHE getVariable ["ACME_chestAccessProvider", []];
    if ((_providerEntry param [0,objNull]) isEqualTo _pHE) then {
        private _providerToken = _providerEntry param [2,""];
        private _providerPrep = _providerEntry param [3,""];
        private _activeLease = uiNamespace getVariable ["ACME_Thora_ChestAccessLease",""];
        if (_providerToken != "" && {_providerPrep != ""} && {_providerPrep == _activeLease}) then {
            [_mHE,_pHE,"stop",false,_providerToken] call ACME_fnc_chestAccessVestProvider;
        };
    };
};

private _vestLease = uiNamespace getVariable ["ACME_Thora_ChestAccessLease",""];
if (_vestLease != "") then {
    uiNamespace setVariable ["ACME_Thora_ChestAccessLease",""];
    if (!isNull _pHE) then {[_pHE,_mHE,_vestLease,false,"thoracostomy"] call ACME_fnc_chestAccessVestEvent;};
};
if (!isNull _pHE) then {[_pHE, "ui:thora:" + str clientOwner, false] call ACME_fnc_ecgJostleRequest;};
if (!isNull _pHE && {_pHE getVariable ["ACME_headElev_Suspended", false]}) then {
    _pHE setVariable ["ACME_headElev_ResumePending", true, true];
    [{ _this call ACME_fnc_headElevTryResume }, _pHE, (missionNamespace getVariable ["ACME_headElev_resumeDelay", 0.75])] call CBA_fnc_waitAndExecute;
};
// the diagnostic first, before anything else in this function can run or fail.
// the order is the whole answer: if this fires before ACE's menu appears, the closedialog loop of ACE killed the
// panel and display mode is impossible. if it fires after a selection, something in the action path is closing
// it.

// onunload: kill the tick pfh and restore ACE's medical-menu pfh. we neutralized it on open so it could not yank
// this dialog shut mid-procedure, and if left dead the buttons of the medical menu stop working and it stops
// refreshing state until it is reopened. the visual and persistent state lives on the patient.
private _pfh = uiNamespace getVariable ["ACME_Thora_PFH", -1];
if (_pfh isEqualType 0 && {_pfh >= 0}) then { _pfh call CBA_fnc_removePerFrameHandler; };
uiNamespace setVariable ["ACME_Thora_PFH", -1];

call ACM_GUI_fnc_resumeMedicalMenuPFH;

uiNamespace setVariable ["ACME_Thora_Held", ""];
uiNamespace setVariable ["ACME_Thora_Palpating", false];
uiNamespace setVariable ["ACME_Thora_Cutting", false];
uiNamespace setVariable ["ACME_Thora_Prepping", false];
uiNamespace setVariable ["ACME_Thora_TubeSnap", false];
uiNamespace setVariable ["ACME_Thora_KellyArmed", false];
uiNamespace setVariable ["ACME_Thora_LMBDown", false];
uiNamespace setVariable ["ACME_Thora_DLG", displayNull];

// drop the captured resting layout and the last shake offset, or the next open would measure from stale
// positions.
uiNamespace setVariable ["ACME_Thora_ShakeBase", []];
uiNamespace setVariable ["ACME_Thora_ShakeBase_off", [0, 0]];

// the darkness panels die with the dialog, so clear the handles and the z-order count and the next open rebuilds
// cleanly.
uiNamespace setVariable ["ACME_Thora_Shade", []];
uiNamespace setVariable ["ACME_Thora_Shade_n", -1];

// the flashlights self-action is gated on this. left set, ACE would offer it forever.
uiNamespace setVariable ["ACME_minigame_open", false];

// drop back into the medical menu, at the airway category, instead of exiting to the game. it is a no-op during the
// flashlight close and reopen, which is guarded inside the helper.
[uiNamespace getVariable ["ACME_Thora_Patient", objNull], "airway"] call ACME_fnc_reopenMedicalMenu;
