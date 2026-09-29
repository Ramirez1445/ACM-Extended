// EMMA capnograph HUD. it is local and runs on a short cadence for a smooth waveform, and it self-gates on
// active bagging.
// the HUD shows only while a medic is actively bagging an EMMA patient. the hold is a short anti-flicker bridge
// across the gaps between individual BVM squeezes. as soon as the bagging stops, the HUD drops off within this
// window. it was 12 s, which lingered too long after you stopped.
ACME_emma_holdSec = 2;
ACME_emma_igelRange = 5;

// track real patient contact locally, for patient-side EMMA routing. the last contact wins, which stops
// overlapping casualties from fighting over one EMMA display.
if (isNil "ACME_emma_contactHooksRegistered") then {
    ACME_emma_contactHooksRegistered = true;
    {
        [_x, {
            params [["_medic", objNull], ["_patient", objNull]];
            [_medic, _patient] call ACME_fnc_emmaMarkContact;
        }] call CBA_fnc_addEventHandler;
    } forEach ["ace_treatmentStarted", "ace_treatmentSucceeded", "ace_treatmentSucceded"];
};

if (hasInterface) then {[{call ACME_fnc_emmaTick}, 0.1, []] call CBA_fnc_addPerFrameHandler;};
