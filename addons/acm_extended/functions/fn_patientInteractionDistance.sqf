/* Treatment proximity contract shared by ACME medical actions.
 *
 * ACE treats occupants of the same vehicle as mutually reachable regardless of seat/model separation.
 * Mirror that rule here so a later ACME range check cannot reject an intervention that ACE already allowed.
 * Different vehicles, or one unit inside while the other is outside, retain ordinary world-space distance.
 */
params [["_medic", objNull, [objNull]], ["_patient", objNull, [objNull]]];
if (isNull _medic || {isNull _patient}) exitWith {1e10};

private _medicVehicle = objectParent _medic;
private _patientVehicle = objectParent _patient;
if (!isNull _medicVehicle && {_medicVehicle isEqualTo _patientVehicle}) exitWith {0};

private _distance = _medic distance _patient;
if (!isNull _medicVehicle || {!isNull _patientVehicle}) exitWith {_distance};

if !(_patient getVariable ["ACME_headElevated", false]) exitWith {_distance};
private _helper = _patient getVariable ["ACME_headElev_helper", objNull];
if (isNull _helper || {(typeOf _helper) != "ACME_RopeHelper"}
    || {attachedTo _patient != _helper}) exitWith {_distance};
private _anchor = _patient getVariable ["ACME_headElev_basePosASL", []];
if (count _anchor != 3 || {(_anchor findIf {!(_x isEqualType 0) || {!finite _x}}) >= 0}) exitWith {_distance};
if ((getPosASL _helper) vectorDistance _anchor > 2
    || {(getPosASL _patient) vectorDistance _anchor > 3}) exitWith {_distance};
_distance min ((getPosASL _medic) vectorDistance _anchor)
