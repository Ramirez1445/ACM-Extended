#include "..\script_component.hpp"
/*
 * Author: Blue
 * Handle clotting wounds on body part
 *
 * Arguments:
 * 0: Patient <OBJECT>
 * 1: Body Part <STRING>
 * 2: Amount of wounds to clot <NUMBER>
 * 3: Maximum wound severity to treat <NUMBER>
 * 4: Clots are unstable <BOOL>
 * 5: Continued clotting <BOOL>
 *
 * Return Value:
 * None
 *
 * Example:
 * [cursorTarget, "leftleg", 1, 1, true, false] call ACM_damage_fnc_clotWoundsOnBodyPart;
 *
 * Public: No
 */

params ["_patient", "_bodyPart", ["_woundsToClot", 1], ["_maxWoundSeverity", 1], ["_unstable", true], ["_continued", false]];

private _fnc_getWoundsToTreat = {
    params ["_woundsList", "_maximumSeverity"];

    private _lowestID = 99;
    private _woundIndex = -1;

    {
        _x params ["_id", "_amountOf", "_bleeding"];

        private _severityID = _id % 10;
        if (((_severityID + 1) <= _maximumSeverity) && _severityID < (_lowestID % 10) && _amountOf > 0 && _bleeding > 0) then {
            _lowestID = _id;
            _woundIndex = _forEachIndex;
        };
    } forEach _woundsList;

    _woundIndex;
};

private _fnc_handleReopening = {
    params ["_patient", "_bodyPart", "_id", "_unstable", "_plateletCount"];

    // Stable B180: native clot formation may very rarely schedule ONE partial clot failure.
    // Applied bandages/wraps/stitches are never involved, and all clot-pop sources share one cooldown.
    if (!_unstable || {isNull _patient} || {!local _patient}) exitWith {};
    if (serverTime < (_patient getVariable ["ACME_clotPop_nextServer", -1])) exitWith {};

    private _baseChance = missionNamespace getVariable ["ACME_clotPop_nativeChance", 0.0015];
    private _maxChance = missionNamespace getVariable ["ACME_clotPop_nativeMaxChance", 0.003];
    private _strength = (_patient getVariable ["ACME_coag_clotStrength", 1]) max 0.08 min 1.15;
    private _plateletF = linearConversion [2.5, 0.5, _plateletCount, 0.5, 1.5, true];
    private _strengthF = linearConversion [1, 0.25, _strength, 0.5, 1.5, true];
    private _chance = (_baseChance * _plateletF * _strengthF) min _maxChance;
    if (random 1 >= _chance) exitWith {};

    private _delayMid = linearConversion [2.5, 0.5, _plateletCount, 480, 240, true];
    private _delay = random [(_delayMid - 60) max 120, _delayMid, _delayMid + 60];
    private _cooldown = missionNamespace getVariable ["ACME_clotPop_cooldown", 600];

    // Reserve the casualty-wide cooldown now so recursive clotting cannot queue several delayed pops.
    _patient setVariable ["ACME_clotPop_nextServer", serverTime + _delay + _cooldown, true];

    [{
        params ["_patient", "_bodyPart", "_id"];
        if (isNull _patient || {!alive _patient} || {!local _patient}) exitWith {};
        [
            _patient,
            missionNamespace getVariable ["ACME_clotPop_fraction", 0.15],
            _bodyPart,
            _id
        ] call ACME_fnc_popClots;
    }, [_patient, _bodyPart, _id], _delay] call CBA_fnc_waitAndExecute;
};

private _fnc_finalUpdate = {
    params ["_patient", "_bodyPart", "_clearConditionCache"];

    [_patient] call ACEFUNC(medical_status,updateWoundBloodLoss);

    // Reset treatment condition cache for nearby players if we stopped all bleeding
    if (_clearConditionCache) then {
        private _nearPlayers = (_patient nearEntities ["CAManBase", 6]) select {_x call ACEFUNC(common,isPlayer)};
        TRACE_1("clearConditionCaches: clot",_nearPlayers);
        [QACEGVAR(interact_menu,clearConditionCaches), [], _nearPlayers] call CBA_fnc_targetEvent;
    };

    // Check if limping was fixed by this wound getting clotted
    if (ACEGVAR(medical,limping) == 1 && {_bodyPart in ["leftleg", "rightleg"]} && {_patient getVariable [QACEGVAR(medical,isLimping), false]}) then {
        [_patient] call ACEFUNC(medical_engine,updateDamageEffects);
    };
};

private _openWounds = GET_OPEN_WOUNDS(_patient);
private _openWoundsOnPart = _openWounds getOrDefault [_bodyPart, []];

private _woundIndex = [_openWoundsOnPart, _maxWoundSeverity] call _fnc_getWoundsToTreat;

if (_woundIndex isEqualTo -1) exitWith {
    if (_continued) then {
        [_patient, _bodyPart, true] call _fnc_finalUpdate;
    };
};

private _clearConditionCache = false;

(_openWoundsOnPart select _woundIndex) params ["_woundID", "_woundCount", "_woundBleeding", "_woundDamage"];
private _openWoundEntry = [_woundID, _woundCount, _woundBleeding, _woundDamage];

private _woundSeverity = (_woundID % 10) + 1;
_woundsToClot = _woundsToClot / _woundSeverity;

private _clotSuccess = false;

private _woundsRemaining = _woundCount - _woundsToClot;
private _amountClotted = _woundsToClot;

if (_woundsRemaining <= 0) then {
    _woundsRemaining = 0;
    _amountClotted = _woundCount;
    _clearConditionCache = true;
};

private _bloodVolumeEffect = (GET_EFF_BLOOD_VOLUME(_patient) / 5.2) min 1;
private _TXAEffect = (1 + ([_patient, "TXA_IV", false] call ACEFUNC(medical_status,getMedicationCount))) min 1.5;

if (_woundSeverity > 1) then {
    _clotSuccess = (random 1) <= ((1 - 0.9 * (_woundSeverity / 3)) * _TXAEffect * _bloodVolumeEffect);
} else {
    _clotSuccess = true;
};

if (_clotSuccess) then {
    private _clottedWounds = GET_CLOTTED_WOUNDS(_patient);
    private _clottedWoundsOnPart = _clottedWounds getOrDefault [_bodyPart, []];
    private _clottedWoundEntry = [_woundID, _woundCount, _woundBleeding, _woundDamage];
    _clottedWoundEntry set [1, _amountClotted];

    _clottedWoundEntry params ["_clottedID"];

    // Handle incrementing or creating new entry for clotted wounds
    if (_clottedWoundsOnPart isEqualTo []) then {
        _clottedWoundsOnPart insert [-1, [_clottedWoundEntry]];
    } else {
        private _foundIndex = _clottedWoundsOnPart findIf {(_x select 0) isEqualTo _clottedID};

        if (_foundIndex isEqualTo -1) then {
            _clottedWoundsOnPart insert [-1, [_clottedWoundEntry]];
        } else {
            private _foundClottedWoundEntry = _clottedWoundsOnPart select _foundIndex;
            _foundClottedWoundEntry params ["_id", "_amountOf", "_bleeding", "_damage"];
            _clottedWoundsOnPart set [_foundIndex, [_id, (_amountOf + _amountClotted), _bleeding, _damage]];
        };
    };

    _clottedWounds set [_bodyPart, _clottedWoundsOnPart];
    _patient setVariable [VAR_CLOTTED_WOUNDS, _clottedWounds, true];

    _woundsToClot = _woundsToClot - _amountClotted;

    _openWoundEntry set [1, _woundsRemaining];
    _openWoundsOnPart set [_woundIndex, _openWoundEntry];
    _openWounds set [_bodyPart, _openWoundsOnPart];

    _patient setVariable [VAR_OPEN_WOUNDS, _openWounds, true];

    private _plateletCount = _patient getVariable [QEGVAR(circulation,Platelet_Count), 3];
    private _hasTXA = ([_patient, "TXA_IV", false] call ACEFUNC(medical_status,getMedicationCount)) > 0.05;

    // Exactly one rare scheduling decision for this clotting episode. TXA-stabilized or explicitly stable clots
    // do not enter the spontaneous-pop path at all.
    if (_unstable && {!_hasTXA}) then {
        [_patient, _bodyPart, _clottedID, true, _plateletCount] call _fnc_handleReopening;
    };
};

if (_woundsToClot > 0) then { // Clot more wounds if able
    [_patient, _bodyPart, _woundsToClot, _maxWoundSeverity, _unstable, true] call FUNC(clotWoundsOnBodyPart);
} else {
    [_patient, _bodyPart, _clearConditionCache] call _fnc_finalUpdate;
};
