// bump the thoracostomy state version on the patient. every write of the per-side chest state calls this.
// call it as [_patient] call ACME_fnc_thoraBumpVer.
// the per-side incision, prep, opening, tube and site state is already written to the patient and broadcast, so
// it replicates on its own. what was missing was any way for a screen that is already open to notice. a medic
// working the other side of the same chest saw whatever it looked like when they opened it, and found out about
// the other medic's incision when they closed and reopened.
// a monotonically increasing version lets an open dialog detect that cheaply. see the poll in fn_thoratick.
// the version we just produced is recorded locally at the same time. this only ever runs on the client that made
// the change, so a later mismatch means somebody else edited the patient, which is exactly the condition the poll
// is looking for. without recording it, our own writes would read as remote and the screen would rebuild itself
// in a loop.
// it is a separate function rather than one bump at the end of fn_thoramouseup, because that function commits
// through several exitwith branches. a bump at the end would only ever run for the last of them.
params ["_patient"];
if (isNull _patient) exitWith {};
if (!local _patient) exitWith {
    [_patient, "thoraBumpVer", [_patient]] call ACME_fnc_ownerDispatch;
};
_patient setVariable ["ACME_thora_ver", (_patient getVariable ["ACME_thora_ver", 0]) + 1, true];
uiNamespace setVariable ["ACME_thora_verSeen", (_patient getVariable ["ACME_thora_ver", 0])];
