/* Stable B183: UI acknowledgement plus owner-local manual-carrier return watchdog. */
if (isNil "ACME_manualPlateCarrierWatchPFH") then {
    ACME_manualPlateCarrierWatchPFH = [{
        {
            private _p = _x;
            if (!local _p) then {continue};

            private _state = _p getVariable ["ACME_manualPlateCarrierState", ""];
            if (_state == "") then {continue};

            private _awake = alive _p
                && {!(_p getVariable ["ACE_isUnconscious", false])}
                && {!(_p getVariable ["ace_medical_unconscious", false])};
            private _transported = !isNull objectParent _p
                || {!isNull attachedTo _p}
                || {_p call ace_common_fnc_isBeingDragged}
                || {_p call ace_common_fnc_isBeingCarried};

            private _origin = _p getVariable ["ACME_manualPlateCarrierOriginASL", []];
            private _moved = _origin isEqualType [] && {count _origin == 3}
                && {_p distance2D _origin > 0.35};

            private _externalVest = _state in ["off", "restoring"] && {(vest _p) != ""};

            if (_awake || {_transported} || {_moved} || {_externalVest}) then {
                private _reason = if (_awake) then {"awake"} else {
                    if (_transported) then {"transport"} else {
                        if (_externalVest) then {"external-restore"} else {"moved"}
                    }
                };
                [_p, _reason] call ACME_fnc_manualPlateCarrierAutoReturn;
            };
        } forEach allUnits;
    }, 0.20, []] call CBA_fnc_addPerFrameHandler;
};

// Drag/carry setup gets an immediate return instead of waiting for the 0.20 s watchdog pass.
if (isNil "ACME_manualPlateCarrierTransportEH") then {
    ACME_manualPlateCarrierTransportEH = [];
    {
        private _eh = [_x, {
            params ["_unit", "_target"];
            if (!isNull _target && {(_target getVariable ["ACME_manualPlateCarrierState", ""]) != ""}) then {
                [_target, "transport"] call ACME_fnc_manualPlateCarrierAutoReturn;
            };
        }] call CBA_fnc_addEventHandler;
        ACME_manualPlateCarrierTransportEH pushBack _eh;
    } forEach ["ace_dragging_setupDrag", "ace_dragging_setupCarry"];
};

if (hasInterface && {isNil "ACME_manualPlateCarrierAckEH"}) then {
    ACME_manualPlateCarrierAckEH = ["ACME_manualPlateCarrierAck", {
        params [
            ["_patient", objNull, [objNull]],
            ["_restore", false, [false]],
            ["_success", false, [false]]
        ];

        if (!_success) exitWith {
            if (!isNull ACE_player) then {
                ["Plate carrier action could not be completed.", 1.8, ACE_player, 13]
                    call ace_common_fnc_displayTextStructured;
            };
        };

        if (!isNull ACE_player) then {
            [
                ["Plate carrier removed and parked above the casualty.",
                 "Plate carrier returned to the casualty."] select _restore,
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
};
