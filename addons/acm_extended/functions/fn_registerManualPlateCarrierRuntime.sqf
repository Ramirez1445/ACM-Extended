/* Stable B182: local UI acknowledgement for manual plate-carrier transactions. */
if (!hasInterface) exitWith {};
if (!isNil "ACME_manualPlateCarrierAckEH") exitWith {};

ACME_manualPlateCarrierAckEH = ["ACME_manualPlateCarrierAck", {
    params [
        ["_patient", objNull, [objNull]],
        ["_restore", false, [false]],
        ["_success", false, [false]]
    ];

    if (!_success) exitWith {
        if (!isNull ACE_player) then {
            ["Plate carrier state changed before the action completed.", 1.8, ACE_player, 13]
                call ace_common_fnc_displayTextStructured;
        };
    };

    if (!isNull ACE_player) then {
        [
            ["Plate carrier removed. It will remain off until Replace Plate Carrier is used.",
             "Plate carrier replaced."] select _restore,
            1.8,
            ACE_player,
            13
        ] call ace_common_fnc_displayTextStructured;
    };

    [{
        params ["_patient"];
        private _display = uiNamespace getVariable ["ace_medical_gui_menuDisplay", displayNull];
        if (!isNull _display
            && {(missionNamespace getVariable ["ace_medical_gui_target", objNull]) isEqualTo _patient}
            && {!isNil "ace_medical_gui_fnc_updateActions"}) then {
            [_display] call ace_medical_gui_fnc_updateActions;
        };
    }, [_patient]] call CBA_fnc_execNextFrame;
}] call CBA_fnc_addEventHandler;
