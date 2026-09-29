// Client presentation/input runtime only. Dedicated servers must not register UI PFHs, controls or keybinds.
if (!hasInterface) exitWith {};

// UI refreshers are presentation-only. Never register duplicate PFHs on client re-init/hot reload.
if (missionNamespace getVariable ["ACME_transfusionUiRuntimeRegistered", false]) exitWith {};
missionNamespace setVariable ["ACME_transfusionUiRuntimeRegistered", true];

private _txPFH = [{
    if (!isNull (findDisplay 86000)) then {call ACME_fnc_updateTransfusionControls;};
}, 0.25, []] call CBA_fnc_addPerFrameHandler;
missionNamespace setVariable ["ACME_transfusionUiPFH", _txPFH];

private _clampPFH = [{
    if (!isNull (findDisplay 86200)) then {call ACME_fnc_updateClampDialog;};
}, 0.20, []] call CBA_fnc_addPerFrameHandler;
missionNamespace setVariable ["ACME_clampUiPFH", _clampPFH];
