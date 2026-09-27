// open the thoracostomy mini-game, idd 86600. it mirrors fn_chestsealopen: stash the medic and patient on
// uinamespace, then createdialog after a short beat, and after lowering an elevated head, the same as the chest
// seal.
// call it as [_medic, _patient, _bodyPart] call ACME_fnc_thoraOpen.
params ["_medic", "_patient", ["_bodyPart", ""]];
if (isNull _patient || {isNull _medic}) exitWith {};
if !([_medic, _patient] call ACME_fnc_thoraCanOpen) exitWith {};
private _ecgJostleKey = "ui:thora:" + str clientOwner;
[_patient, _ecgJostleKey, true] call ACME_fnc_ecgJostleRequest;

uiNamespace setVariable ["ACME_Thora_Medic", _medic];
uiNamespace setVariable ["ACME_Thora_Patient", _patient];
uiNamespace setVariable ["ACME_Thora_BodyPart", _bodyPart];

// Hold an identified chest-access gear lease for the entire minigame. It is independent from head elevation: a
// backpack-supported casualty still has the worn plate carrier parked above the head until this screen closes.
private _vestSerial = (uiNamespace getVariable ["ACME_Thora_ChestAccessSerial",0]) + 1;
uiNamespace setVariable ["ACME_Thora_ChestAccessSerial",_vestSerial];
private _vestLease = format ["thora:%1:%2:%3",clientOwner,floor(CBA_missionTime*1000),_vestSerial];
uiNamespace setVariable ["ACME_Thora_ChestAccessLease",_vestLease];
// Pass the procedure lease as the presentation token too. A delayed patient-owner provider-start packet must be
// rejected after this exact thoracostomy entry is cancelled or closed.
[_patient,_medic,_vestLease,true,"thoracostomy",_vestLease] call ACME_fnc_chestAccessVestEvent;

// Provider-side chest access is presentation only. Once the casualty transaction is ready, retire that exact
// medic4 episode synchronously before opening the long thoracostomy workspace. This is the same rule used by
// ordinary chest-access treatments: a patient-owner completion packet must never leave the provider frozen.
private _releaseProvider = {
    params ["_m","_p",["_handoff",false,[false]]];
    if (isNull _m || {!local _m}) exitWith {};
    private _entry = _m getVariable ["ACME_chestAccessProvider", []];
    if ((_entry param [0,objNull]) isNotEqualTo _p) exitWith {};
    private _token = _entry param [2,""];
    if (_token == "") exitWith {};
    [_m,_p,"stop",_handoff,_token] call ACME_fnc_chestAccessVestProvider;
};

// The chest-access lease now owns Semi-Fowler lowering plus any lift/remove/park/lower carrier choreography.
// Open the thoracostomy UI only after that patient-side transaction is genuinely ready.
private _open = {
    params ["_p","_m","_lease","_releaseProvider"];
    if ((uiNamespace getVariable ["ACME_Thora_ChestAccessLease",""]) != _lease) exitWith {};
    if (isNull _p || {isNull _m} || {!alive _m} || {!local _m}) exitWith {
        [_m,_p,false] call _releaseProvider;
        uiNamespace setVariable ["ACME_Thora_ChestAccessLease",""];
        if (!isNull _p) then {[_p,_m,_lease,false,"thoracostomy"] call ACME_fnc_chestAccessVestEvent;};
    };

    // The minigame itself does not own a provider animation. Exit medic4 to the normal unarmed crouch now;
    // never leave the player frozen for the lifetime of the panel.
    [_m,_p,false] call _releaseProvider;

    ["ACME_Thoracostomy_Dialog"] call ACME_fnc_minigameOpen;

    [{
        params ["_p","_m","_lease"];
        if ((uiNamespace getVariable ["ACME_Thora_ChestAccessLease",""]) != _lease) exitWith {};
        if (isNull (findDisplay 86600)) then {
            uiNamespace setVariable ["ACME_Thora_ChestAccessLease",""];
            if (!isNull _p) then {[_p,_m,_lease,false,"thoracostomy"] call ACME_fnc_chestAccessVestEvent;};
        };
    }, [_p,_m,_lease], 0.25] call CBA_fnc_waitAndExecute;
};

[{
    params ["_p","_m","_lease"];
    if (isNull _p || {isNull _m} || {!alive _m}
        || {(uiNamespace getVariable ["ACME_Thora_ChestAccessLease",""]) != _lease}) exitWith {true};
    private _readyLease = _p getVariable ["ACME_chestAccess_readyLease",""];
    private _ready = _p getVariable ["ACME_chestAccess_readyServer",-1];
    (_readyLease == _lease) && {_ready isEqualType 0} && {_ready >= 0} && {serverTime >= _ready}
}, {
    params ["_p","_m","_lease","_releaseProvider","_open"];
    [_p,_m,_lease,_releaseProvider] call _open;
}, [_patient,_medic,_vestLease,_releaseProvider,_open], 12, {
    params ["_p","_m","_lease","_releaseProvider"];
    if ((uiNamespace getVariable ["ACME_Thora_ChestAccessLease",""]) != _lease) exitWith {
        [_m,_p,false] call _releaseProvider;
    };
    diag_log format ["[ACME THORACOSTOMY] Chest-access preparation timed out on %1.", netId _p];
    [_m,_p,false] call _releaseProvider;
    uiNamespace setVariable ["ACME_Thora_ChestAccessLease",""];
    if (!isNull _p) then {[_p,_m,_lease,false,"thoracostomy"] call ACME_fnc_chestAccessVestEvent;};
}] call CBA_fnc_waitUntilAndExecute;
