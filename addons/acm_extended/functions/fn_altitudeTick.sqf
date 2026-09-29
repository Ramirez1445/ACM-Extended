// Cabin pressure affects existing trapped gas only when pressure changes.
// Hypobaric oxygen availability and transient maneuver stress remain independent.
params ["_patient"];
if (isNull _patient || {!local _patient} || {!alive _patient} || {!(_patient isKindOf "CAManBase")}) exitWith {};
if (!(missionNamespace getVariable ["ACME_sys_flight", true])
    || {!(missionNamespace getVariable ["ACME_altitude_enable", true])}) exitWith {
    // Re-enabling starts at current cabin pressure, without replaying travel while off.
    _patient setVariable ["ACME_alt_ptxSample", nil, false];
    [_patient, "ACME_alt_expanding", false] call ACME_fnc_setVarNet;
};

private _alt = [_patient] call ACME_fnc_altitudeTrue;
if (!finite _alt) exitWith {_patient setVariable ["ACME_alt_ptxSample", nil, false];};
_alt = _alt max 0;
[_patient, "ACME_alt_m", round _alt, 10, 2] call ACME_fnc_setVarNetApprox;
// Clamp the tropospheric approximation before exponentiation, avoiding invalid
// fractional powers on extreme terrain/teleport positions.
private _pressureAlt = _alt min 11000;
private _pRatio = (((1 - (0.0000225577 * _pressureAlt)) ^ 5.25588) max 0.2) min 1;
[_patient, "ACME_alt_pRatio", _pRatio, 0.002, 2] call ACME_fnc_setVarNetApprox;

// Owner-local history is cleared by ownerInit on locality transfer. The epoch
// and short sample age also exclude reset/load/stall catch-up. The first valid
// observation establishes a baseline; it cannot create or worsen an injury.
private _now = CBA_missionTime;
private _epoch = [_patient] call ACME_fnc_clinicalEpoch;
private _sample = _patient getVariable ["ACME_alt_ptxSample", []];
private _sampleValid = _sample isEqualType [] && {count _sample == 4};
if (_sampleValid) then {
    _sample params ["_lastPressure", "_lastOwner", "_lastEpoch", "_lastTime"];
    _sampleValid = _lastPressure isEqualType 0 && {finite _lastPressure}
        && {_lastPressure >= 0.2} && {_lastPressure <= 1}
        && {_lastOwner isEqualTo clientOwner} && {_lastEpoch isEqualTo _epoch}
        && {_lastTime isEqualType 0} && {finite _lastTime}
        && {_now >= _lastTime} && {_now - _lastTime <= 5};
};
_patient setVariable ["ACME_alt_ptxSample", [_pRatio, clientOwner, _epoch, _now], false];
private _expanding = false;
if (_sampleValid) then {
    // Boyle ratio composes across the climb and reverses on descent; fixed
    // altitude gives exactly 1 regardless of elapsed time or number of ticks.
    private _factor = ((_sample select 0) / _pRatio) max 0.2 min 5;
    if (_factor != 1) then {
        [_patient, _factor] call ACME_fnc_ptxAmbientChange;
        _expanding = _factor > 1
            && {(_patient getVariable ["ACM_breathing_Pneumothorax_State", 0]) > 0};
    };
};
[_patient, "ACME_alt_expanding", _expanding] call ACME_fnc_setVarNet;

private _dt = [_patient, "altitude", 0.25, 5] call ACME_fnc_clinicalTickDelta;  // the circ tick period. it is defined here because the flight-g block below runs before the altitude cutoff.

// flight stress: g-loading on a hypovolemic casualty.
// it runs at every altitude, before the altitude cutoff below, because the hardest g in casevac is
// nap-of-the-earth flying, down low, where the aircraft is banking hard and pulling out of terrain. that has
// nothing to do with how high you are.
// a climb or a hard banked turn loads the casualty toward their feet. a patient with normal volume compensates
// without you ever noticing. a hypovolemic one has nothing left to compensate with: venous return falls and the
// pressure goes with it, transiently, every time the aircraft maneuvers, recovering when it settles. this is why
// you fill a casualty before the flight rather than during it, and why the pressure you were happy with on the
// ground is not the pressure you will have in the turn.
// it reaches the cuff through peripheral resistance, the same additive lever every other bp effect uses, so it
// composes with pressors, the TBI and ACM's hardcore offsets rather than fighting them.
private _gDrop = 0;
if (missionNamespace getVariable ["ACME_flightG_enable", true]) then {
    private _veh = vehicle _patient;
    if (_veh != _patient && {_veh isKindOf "Air"} && {isEngineOn _veh}) then {
        // the maneuver magnitude: the climb rate and the bank angle, whichever is loading them harder.
        private _climb = ((velocity _veh) select 2) max 0;
        private _climbFrac = linearConversion [1, (missionNamespace getVariable ["ACME_flightG_climbRateFull", 8]), _climb, 0, 1, true];
        private _upZ = (vectorUp _veh) select 2;  // 1.0 is wings level, and cos(bank) in a turn.
        private _bankFrac = linearConversion [0.98, (missionNamespace getVariable ["ACME_flightG_bankFull", 0.72]), _upZ, 0, 1, true];
        private _gStress = _climbFrac max _bankFrac;

        // the volume status: how little they have left to compensate with.
        private _bvNorm = missionNamespace getVariable ["ACME_hypo_bloodNormal", 6];
        private _deficit = (_bvNorm - (_patient getVariable ["ACM_circulation_Blood_Volume", _bvNorm])) max 0;
        private _hypoFrac = linearConversion [
            (missionNamespace getVariable ["ACME_flightG_hypoStartL", 0.5]),
            (missionNamespace getVariable ["ACME_flightG_hypoFullL", 2.0]),
            _deficit, 0, 1, true
        ];

        _gDrop = -((missionNamespace getVariable ["ACME_flightG_maxResistDrop", 28]) * _gStress * _hypoFrac);
        [_patient, "ACME_flightG_stress", _gStress, 0.02, 1] call ACME_fnc_setVarNetApprox;
    } else {
        [_patient, "ACME_flightG_stress", 0] call ACME_fnc_setVarNet;
    };
};
// ease it, so the pressure sags into the turn and recovers out of it rather than stepping.
private _curG = _patient getVariable ["ACME_flightG_resistAdd", 0];
private _gStep = (missionNamespace getVariable ["ACME_flightG_stepPerSec", 18]) * _dt;
[_patient, "ACME_flightG_resistAdd", (_curG + (((_gDrop - _curG) max (-_gStep)) min _gStep)), 0.10, 1] call ACME_fnc_setVarNetApprox;

private _minAlt = missionNamespace getVariable ["ACME_altitude_minMetres", 500];
if (_alt < _minAlt) exitWith {
    [_patient, "ACME_alt_hypoxia", 0] call ACME_fnc_setVarNet;
};

// 2. hypobaric hypoxia: the thin air.
// the effective alveolar oxygen scales with the pressure rather than the percentage. supplemental o2 buys it
// straight back, which is the whole reason it is given: at 8000 ft on room air the alveolar oxygen is only about
// 74 percent of sea level, and at an FiO2 of 60 percent it is far above it and the altitude stops mattering.
private _fio2 = 21;
if (_patient getVariable ["ACME_vent_driving", false]) then {
    _fio2 = ([_patient] call ACME_fnc_ventEffectiveSettings) select 4;
} else {
    if (_patient in (missionNamespace getVariable ["ACME_nrb_activePatients", []])) then { _fio2 = 70; };
};
private _alveolarRatio = (_fio2 * _pRatio) / 21;  // 1.0 is sea level room air.

private _targetSat = 99;
if (_alveolarRatio < 1) then {
    _targetSat = linearConversion [0.55, 1.0, _alveolarRatio, 78, 99, true];
};
[_patient, "ACME_alt_hypoxia", (99 - _targetSat), 0.20, 2] call ACME_fnc_setVarNetApprox;

// only one function can own the saturation.
// if a ventilator is driving this patient, the shunt model of the vent, fn_ventoxygenation, owns it, and it
// already folds the altitude in through the pressure ratio we published above. writing here as well would
// overwrite the shunt model every tick and quietly delete the entire effect of PEEP on anyone above 500 m. two
// writers is not a tuning problem, it is a bug, and it is invisible from the outside.
if (_patient getVariable ["ACME_vent_driving", false]) exitWith {};
// fold in the suction drain. a yankauer left running past its limit is pulling gas out of the airway, and this
// is the only place saturation is allowed to be written, so it is subtracted here rather than fought over.
_targetSat = (_targetSat
    - (_patient getVariable ["ACME_o2Drain_mainstem", 0])
    - (_patient getVariable ["ACME_o2Drain_vili", 0])) max 0;
[_patient, [["oxygenSaturation", _targetSat]], true] call ACM_core_fnc_setTargetVitalsState;
