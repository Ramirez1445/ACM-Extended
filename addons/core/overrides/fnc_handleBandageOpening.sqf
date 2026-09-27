#include "..\script_component.hpp"
/*
 * Stable B180 wound-control invariant.
 *
 * A bandage is a physical dressing. Coagulopathy, platelet count and clot strength may affect formation/stability
 * of an underlying clot, but they do not make an applied dressing disappear. This override therefore performs
 * only the authoritative open -> bandaged wound transfer bookkeeping expected by ACE/ACM. It deliberately
 * schedules NO spontaneous bandage reopening.
 *
 * Clot failure is owned exclusively by ACME_fnc_popClots and may act only on ACM_damage_ClottedWounds.
 */
params ["_target", "_impact", "_bodyPart", "_injuryIndex", "_injury", "_bandage"];
TRACE_6("handleBandageOpening",_target,_impact,_bodyPart,_injuryIndex,_injury,_bandage);

if (isNull _target || {!(_impact isEqualType 0)} || {!finite _impact} || {_impact <= 0}) exitWith {};

_injury params [["_classID", -1, [0]]];
if (_classID < 0) exitWith {};

private _bandagedWounds = GET_BANDAGED_WOUNDS(_target);
private _woundsOnPart = _bandagedWounds getOrDefault [_bodyPart, [], true];
private _index = _woundsOnPart findIf {(_x param [0, -1]) isEqualTo _classID};

if (_index >= 0) then {
    private _row = +(_woundsOnPart select _index);
    private _oldAmount = _row param [1, 0, [0]];
    _row set [1, (_oldAmount + _impact) max 0];
    _woundsOnPart set [_index, _row];
    TRACE_2("adding to existing stable bandaged wound",_classID,_bodyPart);
} else {
    private _bandagedInjury = +_injury;
    _bandagedInjury set [1, _impact];
    _woundsOnPart pushBack _bandagedInjury;
    TRACE_2("adding new stable bandaged wound",_classID,_bodyPart);
};

_bandagedWounds set [_bodyPart, _woundsOnPart];
_target setVariable [VAR_BANDAGED_WOUNDS, _bandagedWounds, true];

// Intentionally no reopening timer. Do not derive dressing failure from platelets/coagulopathy.
