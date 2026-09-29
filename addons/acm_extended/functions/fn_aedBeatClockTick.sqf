/*
    ACM Extended AED beat-clock metadata tick.

    v0.9.331 cleanup: this function no longer plays AED HR beeps and no longer
    suppresses ACM_circulation_AED_Pads_LastBeep. ACM owns audible AED beeps.
    The waveform generators may read ACM's LastBeep timestamp for phase anchoring,
    but ACME does not write it.
*/
if !(hasInterface) exitWith {};
if !(missionNamespace getVariable ["ACME_aedBeatClockEnabled", false]) exitWith {};

private _now = CBA_missionTime;
{
    private _patient = _x;
    if (isNull _patient) then { continue; };

    private _padsState = if (!isNil "ACM_circulation_fnc_hasAED") then {
        [_patient, "", 1] call ACM_circulation_fnc_hasAED
    } else {
        _patient getVariable ["ACM_circulation_AED_Placement_Pads", false]
    };
    if (!_padsState) then {
        _patient setVariable ["ACME_AED_BeatClockActive", false, false];
        continue;
    };

    // Engine-dead corpses cannot generate a live monitor rate. Clear any stale display/clock state once.
    if (!alive _patient || {(lifeState _patient) isEqualTo "DEAD"}) then {
        if ((round (_patient getVariable ["ACM_circulation_AED_Pads_Display", 0])) != 0) then {
            [_patient, [["aedPadsDisplay", 0]], true] call ACM_circulation_fnc_setRuntimeState;
        };
        _patient setVariable ["ACME_AED_BeatClockActive", false, false];
        _patient setVariable ["ACME_AED_BeatHR", 0, false];
        continue;
    };

    private _hr = if (!isNil "ACM_circulation_fnc_getEKGHeartRate") then {
        [_patient] call ACM_circulation_fnc_getEKGHeartRate
    } else {
        _patient getVariable ["ace_medical_heartRate", 0]
    };

    // a custom rhythm, meaning torsades at 102, SVT, AFib-RVR and the rest, uses its pinned rate rather than the
    // proxy-derived ekg rate of ACM.
    // torsades proxies as PVT, whose getekgheartrate returns a random 200 to 240, which made the monitor hr jump around
    // and drove the beep off the true rhythm rate. the own target rate of the rhythm is the honest number for both the
    // beep clock and the readout.
    private _customCode = _patient getVariable ["ACME_rhythm_active", 0];
    if (_customCode >= 100) then {
        private _rhythmRate = _patient getVariable ["ACME_rhythm_targetHR", _hr];
        if (_rhythmRate > 0) then {
            _hr = _rhythmRate;
            // correct the shown hr number of ACM too. its handleaed sets aed_pads_display from getekgheartrate every few
            // seconds, and for a custom rhythm that is the random rate of the proxy, so torsades into PVT gives 200 to 240.
            // pin the readout to the true rhythm rate, so the big number matches the rhythm, the beep and the trace.
            if ((round (_patient getVariable ["ACM_circulation_AED_Pads_Display", 0])) != (round _rhythmRate)) then {
                [_patient, [["aedPadsDisplay", (round _rhythmRate)]], true] call ACM_circulation_fnc_setRuntimeState;
            };
        };
    };

    if (_hr <= 0) then {
        _patient setVariable ["ACME_AED_BeatClockActive", false, false];
        continue;
    };

    _patient setVariable ["ACME_AED_BeatPeriod", (60 / (_hr max 1)) max 0.18, false];
    _patient setVariable ["ACME_AED_BeatHR", _hr, false];
    _patient setVariable ["ACME_AED_BeatClockActive", true, false];
    _patient setVariable ["ACME_AED_BeatLastTime", _patient getVariable ["ACM_circulation_AED_Pads_LastBeep", _now], false];
} forEach (missionNamespace getVariable ["ACME_clinical_ownedUnits", []]);
