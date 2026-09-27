// ACME override of ACM_circulation_fnc_AED_AnalyzeRhythm.
// B67 cardiac audit: AED advice is reserved for pulseless shockable rhythms. VF (2), pVT (3) and ACME torsades
// (102) charge the AED. Native VT with a pulse (4), SVT and the other organized tachyarrhythmias do not: they
// belong on the synchronized-cardioversion path. This fixes the old contradiction where ACM could announce
// "shock advised" for perfusing VT and the downstream unsynchronized discharge could itself create arrest.
// _this is [_medic, _patient, _retry].
params ["_medic", "_patient", ["_retry", false]];

if ((_patient getVariable ["ACM_circulation_AED_TrackingCPR", false]) || ((_patient getVariable ["ACM_circulation_AED_Analyze_Busy", false]) && !_retry)) exitWith {};

_patient setVariable ["ACM_circulation_AED_AnalyzeRhythm_State", false, true];

_patient setVariable ["ACM_circulation_AED_InUse", true, true];
_medic setVariable ["ACM_circulation_AED_Medic_InUse", true, true];

private _timeToAnalyze = (4 + (random 4)) + 4 * (1 - ((_patient getVariable ["ace_medical_bloodVolume", 6]) / 7));

playSound3D ["\x\acm\addons\circulation\sound\aed_analyzingnow.wav", _patient, false, getPosASL _patient, 15, 1, 15];  // 3.074 s.

_patient setVariable ["ACM_circulation_AED_Analyze_Busy", true, true];

[{
    params ["_medic", "_patient"];

    private _bvmProvider = _patient getVariable ["ACM_breathing_BVM_provider", objNull];
    private _realBvmMotion = !isNull _bvmProvider && {_bvmProvider isNotEqualTo _patient} && {alive _bvmProvider};
    !([_patient, "", 1] call ACM_circulation_fnc_hasAED)
        || {!(_patient getVariable ["ACM_circulation_AED_Analyze_Busy", false])}
        || {alive (_patient getVariable ["ace_medical_CPR_provider", objNull])}
        || {_realBvmMotion};
}, {
    params ["_medic", "_patient"];

    if (!([_patient, "", 1] call ACM_circulation_fnc_hasAED) || !(_patient getVariable ["ACM_circulation_AED_Analyze_Busy", false])) then {
        playSound3D ["\x\acm\addons\circulation\sound\aed_3beep.wav", _patient, false, getPosASL _patient, 15, 1, 15];  // 0.624 s.

        _patient setVariable ["ACM_circulation_AED_InUse", false, true];
        _medic setVariable ["ACM_circulation_AED_Medic_InUse", false, true];

        if (_patient getVariable ["ACM_circulation_AED_Analyze_Busy", false]) then {
            _patient setVariable ["ACM_circulation_AED_Analyze_Busy", false, true];
        };
    } else {
        [_medic, _patient] call ACM_circulation_fnc_AED_MotionDetected;
    };
}, [_medic, _patient], _timeToAnalyze,
{
    params ["_medic", "_patient"];

    _patient setVariable ["ACM_circulation_AED_AnalyzeRhythm_State", true, true];

    // B67: AED shock advice is reserved for pulseless shockable rhythms: VF (2), pVT (3) and ACME torsades (102).
    // Native rhythm 4 is VT WITH a pulse; it belongs on the synchronized-cardioversion path and must never cause an
    // AED to advise an unsynchronized defibrillation that can itself create arrest.
    private _shockableRhythms = [2, 3] + (missionNamespace getVariable ["ACME_sync_defibrillatableRhythms", [102]]);
    private _shockable = (((([_patient] call ACME_fnc_rhythmGet)) in _shockableRhythms) && !([_patient] call ACM_circulation_fnc_recentAEDShock));
    private _adviceDelay = 2;

    if (_shockable) then {
        playSound3D ["\x\acm\addons\circulation\sound\aed_shockadvised.wav", _patient, false, getPosASL _patient, 15, 1, 15];  // 1.662 s.
        _adviceDelay = 1.7;
    } else {
        playSound3D ["\x\acm\addons\circulation\sound\aed_noshockadvised.wav", _patient, false, getPosASL _patient, 15, 1, 15];  // 1.99 s.
    };

    [{
        params ["_patient", "_medic", "_shockable"];

        if (_shockable) then {
            [_medic, _patient] call ACM_circulation_fnc_AED_BeginCharge;
        } else {
            _patient setVariable ["ACM_circulation_AED_InUse", false, true];
            _medic setVariable ["ACM_circulation_AED_Medic_InUse", false, true];

            [_patient] call ACM_circulation_fnc_AED_TrackCPR;
            playSound3D ["\x\acm\addons\circulation\sound\aed_startcpr.wav", _patient, false, getPosASL _patient, 15, 1, 15];  // 1.858 s.

            [{
                params ["_patient", "_medic"];

                _patient setVariable ["ACM_circulation_AED_Analyze_Busy", false, true];
            }, [_patient, _medic], 2] call CBA_fnc_waitAndExecute;
        };

    }, [_patient, _medic, _shockable], _adviceDelay] call CBA_fnc_waitAndExecute;
}] call CBA_fnc_waitUntilAndExecute;
