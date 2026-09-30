// stage 2 complete: the pressure bandage is applied, taking the state from packed to wrapped.
// this is the hemorrhage-control step: the arterial drain stops, because the bleed pfh sees wrapped and excludes the
// part, and we clot the underlying ACE wound to secure hemostasis. it plays the tie-off sfx and stops the wrap
// loop. on a conscious patient the wrap hurts, moderately, and the pack plus wrap total stays below the maximum of
// a tourniquet.
params ["_medic", "_patient", "_bodyPart"];
private _p = toLower _bodyPart;

// stop the wrap-sfx loop and always play the tie-off when the timer completes.
[_medic] call ACME_fnc_junctionalWrapSfxStop;
if (!isNull _medic) then {[_medic, "ACME_JunctionalTie"] call ACME_fnc_worldSfxNearby;};

// Junctional state, hemostasis and pain mutate durable casualty state and therefore commit on its owner.
[_patient, "junctionalWrapDone", [_medic, _p]] call ACME_fnc_ownerDispatch;

["Pressure bandage secured. junctional hemorrhage controlled.", 3] call ace_common_fnc_displayTextStructured;

// record the completed intervention in the activity log of the patient.
[_patient, "activity",
 "%1 controlled a junctional wound (%2) with a pressure bandage",
 "Hemorrhage controlled, pressure dressing, %2, %1",
 [[_medic, false, true] call ace_common_fnc_getName, [_p, "short"] call ACME_fnc_bodyPartName]] call ACME_fnc_medLog;
