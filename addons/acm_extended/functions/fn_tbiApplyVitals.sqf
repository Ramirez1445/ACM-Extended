// this writes the TBI signature onto the ACM and ACE vitals of the patient, so a raised-ICP brain is observable
// through the normal tools, the hr, the bp cuff, SpO2 and the respiration rate, and the vitals track the ICP
// and CPP state instead of sitting normal. it is phased, and everything scales with ICP severity, compensation
// and the herniation stage.
// compensated cushing, where ICP is at or above the trigger and the reserve is intact, gives malignant
// hypertension with a widened pulse pressure, so the systolic climbs far more than the diastolic, plus reflex
// bradycardia and irregular, cheyne-stokes respirations. the brain is defending CPP. it is ominous and holding.
// decompensating, where the compensation budget is spent or herniation is advancing, is where the surge fails.
// the pressure falls, the pulse pressure narrows, hr slides toward agonal and respirations go ataxic.
// terminal herniation, at stage 3 with bilateral fixed pupils, gives pressure collapse, agonal bradycardia and
// apnea, so SpO2 falls out through ACM's own oxygen sim, then a forced cardiac arrest, which is real damage.
// dysautonomic instability means hr, bp and rr oscillate, through lundberg plateau waves and cheyne-stokes, with
// the amplitude growing as the patient destabilizes, so the numbers never sit still. hr is published to the
// sole-writer wrapper and nudged directly, so it moves even when ACM is not actively ticking the vitals of this
// casualty. all numbers are tunables, the acme_tbi_* set in postinit and CBA.
params ["_patient", "_state", ["_dt", 1]];
if (isNull _patient || {count _state == 0}) exitWith {};
_dt = _dt max 0.001;

private _icp      = _state getOrDefault ["icp", 10];
private _severity = (_state getOrDefault ["severity", 0]) max 0 min 1;
private _stage    = _state getOrDefault ["herniationStage", 0];
private _cushing  = _state getOrDefault ["cushing", false];
private _compFrac = _state getOrDefault ["compFrac", 0];
private _autonomicIntegrity = (_state getOrDefault ["autonomicIntegrity", 1]) max 0.05 min 1;
private _autonomicTone = (_state getOrDefault ["autonomicTone", 0]) max -1 min 1;

private _cushICP  = missionNamespace getVariable ["ACME_tbi_vitalsCushICP", 25];
private _hernICP  = missionNamespace getVariable ["ACME_tbi_herniationICP", 30];

// The full Cushing/brainstem vital pattern engages once pressure is high or herniation has started. B119 also
// allows a resistance-only autonomic path after severe perfusion reserve has failed. That path deliberately does
// not manufacture Cushing bradycardia, abnormal respirations or a hypertensive target when ICP is still low; it
// only lets the already-computed signed autonomic tone alter systemic vascular resistance.
private _engaged = _cushing || {_stage > 0} || {_icp >= _cushICP};
private _autonomicDecomp = (_state getOrDefault ["autonomicDecomp", 0]) max 0 min 1;
private _vascularOnly = (!_engaged)
    && {!(_patient getVariable ["ace_medical_inCardiacArrest", false])}
    && {_autonomicDecomp >= (missionNamespace getVariable ["ACME_tbi_autonomicChaosStart", 0.35])}
    && {abs _autonomicTone >= 0.05};
if (!_engaged && {!_vascularOnly}) exitWith {
    [_patient, "ACME_hrTarget_tbi", -1] call ACME_fnc_setVarNet;
    [_patient, "ACME_rrDrive_tbi", -1] call ACME_fnc_setVarNet;
    [_patient, "ACME_tbi_bpDiaOffset", 0] call ACME_fnc_setVarNet;
    [_patient, "ACME_tbi_bpSysOffset", 0] call ACME_fnc_setVarNet;
    [_patient, "ACME_tbi_pulsePressureTarget", -1] call ACME_fnc_setVarNet;
    [_patient, "ACME_tbi_resistAdd", 0] call ACME_fnc_setVarNet;
    // stop the cheyne-stokes breath sounds we may have started, unless a debug demo owns cs, which is marked by
    // savedrr.
    if ((_patient getVariable ["ACME_cs_active", false]) && {isNil {_patient getVariable "ACME_cs_savedRR"}}) then {
        [_patient, "ACME_cs_active", false] call ACME_fnc_setVarNet;
    };
    if !(isNil {_patient getVariable "ACME_tbi_savedRRTarget"}) then {
        [_patient, "ACME_tbi_savedRRTarget", nil] call ACME_fnc_setVarNet;
    };
    _state set ["termClock", 0];
};

if (_vascularOnly) exitWith {
    // Release every pressure-pattern output and leave only the systemic resistance contribution active.
    [_patient, "ACME_hrTarget_tbi", -1] call ACME_fnc_setVarNet;
    [_patient, "ACME_rrDrive_tbi", -1] call ACME_fnc_setVarNet;
    [_patient, "ACME_tbi_bpDiaOffset", 0] call ACME_fnc_setVarNet;
    [_patient, "ACME_tbi_bpSysOffset", 0] call ACME_fnc_setVarNet;
    [_patient, "ACME_tbi_pulsePressureTarget", -1] call ACME_fnc_setVarNet;
    if ((_patient getVariable ["ACME_cs_active", false]) && {isNil {_patient getVariable "ACME_cs_savedRR"}}) then {
        [_patient, "ACME_cs_active", false] call ACME_fnc_setVarNet;
    };
    if !(isNil {_patient getVariable "ACME_tbi_savedRRTarget"}) then {
        [_patient, "ACME_tbi_savedRRTarget", nil] call ACME_fnc_setVarNet;
    };

    private _curTbiResist = _patient getVariable ["ACME_tbi_resistAdd", 0];
    private _baseR = ((_patient getVariable ["ace_medical_peripheralResistance", 100])
        - (_patient getVariable ["ACME_resistanceApplied_tbi", 0])) max 1;
    private _gain = if (_autonomicTone >= 0) then {
        missionNamespace getVariable ["ACME_tbi_autonomicVasoGain", 0.30]
    } else {
        missionNamespace getVariable ["ACME_tbi_autonomicVasodilGain", 0.45]
    };
    private _wantTbiResist = (_baseR * _autonomicTone * _gain) max (1 - _baseR);
    private _resistStep = (missionNamespace getVariable ["ACME_tbi_resistStepPerSec", 40]) * _dt;
    private _nextTbiResist = _curTbiResist + (((_wantTbiResist - _curTbiResist) max (-_resistStep)) min _resistStep);
    [_patient, "ACME_tbi_resistAdd", _nextTbiResist, 0.10, 1] call ACME_fnc_setVarNetApprox;
    _state set ["termClock", 0];
};

// cardiac arrest. once the casualty is in arrest, ACM owns the vitals: hr at 0, an arrest bp and apnea. if we
// keep publishing a cushing or terminal hr target and nudging hr, bp and rr here, ACM and ACM extended fight
// over the numbers every tick, which is the bug where the vitals flicker in arrest with severity 1.0 ICP. so
// the vital pattern stands fully down, clearing the hr target and releasing the bp offset, and ACM runs the
// arrest. fn_tbihandle keeps modeling ICP and herniation, and only the vital writes pause while arrested,
// resuming on ROSC.
if (_patient getVariable ["ace_medical_inCardiacArrest", false]) exitWith {
    [_patient, "ACME_hrTarget_tbi", -1] call ACME_fnc_setVarNet;
    [_patient, "ACME_rrDrive_tbi", -1] call ACME_fnc_setVarNet;
    [_patient, "ACME_tbi_bpDiaOffset", 0] call ACME_fnc_setVarNet;
    [_patient, "ACME_tbi_bpSysOffset", 0] call ACME_fnc_setVarNet;
    [_patient, "ACME_tbi_pulsePressureTarget", -1] call ACME_fnc_setVarNet;
    [_patient, "ACME_tbi_resistAdd", 0] call ACME_fnc_setVarNet;
    // a stage-3 herniation still flags evac, even if arrest reached the patient first.
    if (_stage >= 3 && {!(_patient getVariable ["ACME_tbi_evacFlagged", false])}) then {
        [_patient, "ACME_tbi_evacRequired", true] call ACME_fnc_setVarNet;
        [_patient, "ACME_tbi_evacFlagged", true] call ACME_fnc_setVarNet;
    };
};
// cushing intensity: how deep into the surge we are, from the ICP above the trigger up toward herniation,
// blended with severity.
// cushing comes from pressure, not from how bad the original blow was. this used to floor the surge intensity at
// 60 percent of structural severity, so a casualty with an ICP of zero and a healthy CPP still ran the vital
// pattern of a rising cone, purely because their injury was graded severe. that is the confusion where severity
// sits at 1.00 with no ICP and a great CPP, and it is also why those vitals looked frozen, because the pattern
// was being driven by a number that only ever goes up.
// severity still shapes how hard the response is once pressure is actually rising, and it cannot manufacture the
// response on its own. below the cushing ICP threshold there is no surge.
private _icpDriven = linearConversion [_cushICP, _hernICP + 8, _icp, 0, 1, true];
private _ci = if (_icpDriven <= 0) then { 0 } else { _icpDriven max (_severity * 0.6) };
_ci = _ci max 0 min 1;
// decompensation. a reserve overshoot or herniation progression runs it from 0, defending, to 1, collapsing or
// terminal. the stage contribution of herniation is table-driven, so the lethal collapse concentrates at stage
// 3 and stages 1 and 2 are warning signs. the compensation-reserve overshoot term is unchanged and still drives
// a continuous decline.
private _hernDecomp = missionNamespace getVariable ["ACME_tbi_herniationStageDecomp", [0, 0.15, 0.30, 1.0]];
private _decomp = (((_compFrac - 1) max 0) min 1) max (_hernDecomp param [((_stage min 3) max 0), 0]);
_decomp = _decomp max (((-_autonomicTone) max 0) * 0.85);
_decomp = _decomp max 0 min 1;

// oscillation, with a per-unit phase so casualties do not pulse in lockstep.
private _phase = _state getOrDefault ["wavePhase", -1];
if (_phase < 0) then { _phase = random 360; _state set ["wavePhase", _phase]; };
private _ws   = (missionNamespace getVariable ["ACME_tbi_waveSpeed", 0.16]) * (1 + (_decomp * (missionNamespace getVariable ["ACME_tbi_waveDecompAccel", 0.25])));  // a mild speed-up as it destabilizes. it was *(1+_decomp), which gave 2x at terminal and read as the vitals updating twice as fast. set 0 to keep the base cadence.
private _tDeg = ((CBA_missionTime * _ws * 57.2958) + _phase) % 360;
private _wave  = sin _tDeg;  // the primary slow wave.
private _wave2 = sin (_tDeg * 1.7 + 40);  // a faster secondary wave, the respiratory irregularity.
private _instab = (0.22 + (0.43 * _decomp) + (0.35 * (1 - _autonomicIntegrity))) min 1;

// heart rate.
// cushing bradycardia, where a deeper surge gives a lower hr, sliding to a terminal arrest-range hr as it
// decompensates.
private _hrBrady = linearConversion [0, 1, _ci, 62, (missionNamespace getVariable ["ACME_tbi_cushingHR", 45])];
private _hrT = linearConversion [0, 1, _decomp, _hrBrady, (missionNamespace getVariable ["ACME_tbi_terminalArrestHR", 26])];
_hrT = _hrT + (_wave * (missionNamespace getVariable ["ACME_tbi_hrWaveAmp", 7]) * _instab);
_hrT = _hrT max 12 min 200;
// B67: only terminal stage 3 ICP is allowed to make TBI itself cross ACM's fatal-rate line.
// Earlier stages retain clinically obvious bradycardia, but their TBI target stays just above ACM's <40 arrest gate.
if (_stage < 3) then {
    _hrT = _hrT max (missionNamespace getVariable ["ACME_tbi_nonterminalMinHR", 42]);
};

// publish the hr target only. exactly one writer eases the actual heart rate toward this: ACM's native
// updateheartrate, easing toward ACM_core_TargetVitals_HeartRate, which fn_circhandle sets each circ tick to
// the most lethal of the circ and TBI drives, through selectmin.
// we deliberately do not also write ace_medical_heartRate here. doing so made three things move the same number
// at three different cadences: the target set of circhandle at 0.25 s, this direct nudge at 0.25 s, and ACM's
// own easing at ACM's frame cadence. so hr lurched faster than the normal tick and kept getting slammed back
// down toward the bradycardic target, which is exactly the herniation bug where the vitals update too fast and
// the hr keeps resetting downward as though overridden. one target, one easer, normal cadence.
[_patient, "ACME_hrTarget_tbi", _hrT, 0.25, 1] call ACME_fnc_setVarNetApprox;

// blood pressure, from a widened pulse pressure to collapse, eased so it moves visibly rather than
// instantly.
private _sysT = linearConversion [0, 1, _ci, (missionNamespace getVariable ["ACME_tbi_cushSysBase", 150]), (missionNamespace getVariable ["ACME_tbi_cushSysPeak", 205])];
private _diaT = linearConversion [0, 1, _ci, (missionNamespace getVariable ["ACME_tbi_cushDiaBase", 92]),  (missionNamespace getVariable ["ACME_tbi_cushDiaPeak", 108])];
_sysT = linearConversion [0, 1, _decomp, _sysT, (missionNamespace getVariable ["ACME_tbi_collapseSys", 70])];
_diaT = linearConversion [0, 1, _decomp, _diaT, (missionNamespace getVariable ["ACME_tbi_collapseDia", 44])];
// plateau-wave swings on the systolic, with a smaller share on the diastolic.
private _toneLability = 0.65 + (0.55 * (1 - _autonomicIntegrity)) + (0.20 * abs _autonomicTone);
private _bpWave = _wave * (missionNamespace getVariable ["ACME_tbi_bpWaveAmp", 20]) * _instab * _toneLability;
_sysT = (_sysT + _bpWave) max 40 min 260;
_diaT = (_diaT + (_bpWave * 0.4)) max 25 min (_sysT - 12);

// convert the desired absolute bp into the dia and sys offset on ACM's native, un-offset bp, eased toward it.
// Native and other systems remain in the baseline; remove only this TBI contribution to prevent feedback.
private _base = [_patient, true, true] call ACME_fnc_bpCompute;
_base params [["_bDia", 80], ["_bSys", 120]];
[_patient, "ACME_tbi_pulsePressureTarget", (_sysT - _diaT) max 0, 0.50, 1] call ACME_fnc_setVarNetApprox;
// Legacy offsets are retired, not stacked on top of the same SVR effect.
[_patient, "ACME_tbi_bpDiaOffset", 0] call ACME_fnc_setVarNet;
[_patient, "ACME_tbi_bpSysOffset", 0] call ACME_fnc_setVarNet;
private _tbiMAPtarget = _diaT + ((_sysT - _diaT) / 3);
private _tbiMAPnative = _bDia + ((_bSys - _bDia) / 3);
// B67: stages 0-2 may create Cushing hypertension and later hypotension, but TBI alone cannot push an otherwise
// viable native MAP through ACM's <55 fatal-vitals threshold. If another pathology has already driven native MAP
// below the safety floor, do not rescue it; simply prevent the nonterminal TBI contribution from making it worse.
if (_stage < 3) then {
    private _nonterminalMAPFloor = missionNamespace getVariable ["ACME_tbi_nonterminalMinMAP", 60];
    _tbiMAPtarget = _tbiMAPtarget max (_tbiMAPnative min _nonterminalMAPFloor);
};
private _tbiMAPdelta  = _tbiMAPtarget - _tbiMAPnative;
private _curTbiResist = _patient getVariable ["ACME_tbi_resistAdd", 0];
// Derive mmHg per resistance unit from the same BP calculation. A fixed multiplier
// overshoots when cardiac output changes (including during airway instrumentation).
private _baseR = ((_patient getVariable ["ace_medical_peripheralResistance", 100])
    - (_patient getVariable ["ACME_resistanceApplied_tbi", 0])) max 1;
private _probe = [_patient, true, true, _baseR + 100] call ACME_fnc_bpCompute;
private _probeMAP = (_probe select 0) + (((_probe select 1) - (_probe select 0)) / 3);
private _slope = (_probeMAP - _tbiMAPnative) / 100;
private _wantTbiResist = 0;
if (_slope > 0.001 && {finite _slope}) then {
    _wantTbiResist = (_tbiMAPdelta / _slope) max (1 - _baseR);
};
// The desired pressure says what the brain wants; autonomic integrity/tone says how coherently it can achieve it
// through systemic vascular resistance. This still feeds the single native peripheral-resistance composition path.
if (_wantTbiResist >= 0) then {
    private _symp = _autonomicTone max 0;
    private _capacity = ((0.60 + (0.40 * _autonomicIntegrity)) * (0.55 + (0.45 * _symp))) max 0.20 min 1;
    _wantTbiResist = _wantTbiResist * _capacity;
} else {
    private _failure = (-_autonomicTone) max 0;
    private _collapseCapacity = (0.25 + (0.55 * _failure) + (0.35 * (1 - _autonomicIntegrity))) min 1;
    _wantTbiResist = _wantTbiResist * _collapseCapacity;
};
// ease the resistance add at the same visible rate as the bp tells, and let it go negative in decompensated
// collapse, where the failing brain drops MAP below native and gives vasodilation and hypotension, so
// decompensation actually tanks the pressure through the same lever.
private _resistStep = (missionNamespace getVariable ["ACME_tbi_resistStepPerSec", 40]) * _dt;
[_patient, "ACME_tbi_resistAdd", (_curTbiResist + (((_wantTbiResist - _curTbiResist) max (-_resistStep)) min _resistStep)), 0.10, 1] call ACME_fnc_setVarNetApprox;

// respirations.
// save the real rr target once, so it can be restored when the TBI pattern stands down.
if (isNil {_patient getVariable "ACME_tbi_savedRRTarget"}) then {
    [_patient, "ACME_tbi_savedRRTarget", (_patient getVariable ["ACM_core_TargetVitals_RespirationRate", 16])] call ACME_fnc_setVarNet;
};

// this runs once the compensation reserve is critical, meaning the budget is nearly or fully spent, or once
// herniation has begun. that is the critical timer running, before frank herniation. breathing turns central
// and ataxic: wild and irregular, with no concurrent pattern, runs of fast then slow, deep then shallow, and
// random apneic pauses. it drives the actual respiration rate, so a medic reads it and ACM derives the EtCO2
// and capnography from it, rather than a display number. below the critical threshold it is the milder, eased
// compensated-cushing irregularity.
private _rrCritical = (missionNamespace getVariable ["ACME_tbi_cheyneStokes", true])
    && {(_compFrac >= (missionNamespace getVariable ["ACME_tbi_cheyneCompFrac", 0.9])) || {_stage > 0}};

if (_rrCritical) then {
    private _t = CBA_missionTime;
    // several incommensurate oscillators give a jagged, non-repeating envelope, with deliberately no fixed
    // period.
    private _chaos = ((sin (_t * 47 + _phase)) + (0.8 * sin (_t * 113 + 30)) + (0.6 * sin (_t * 23 + 80)) + (0.9 * sin (_t * 71 + 200))) / 3.3;
    // the baseline jumps on an irregular interval, which gives fast runs against slow runs.
    private _walk = _state getOrDefault ["csWalk", 0];
    if (_t >= (_state getOrDefault ["csWalkNext", 0])) then {
        _walk = (random 26) - 13;
        _state set ["csWalk", _walk];
        _state set ["csWalkNext", _t + (0.6 + random 2.6)];
    };
    // apneic pauses. it occasionally near-stops breathing entirely, which is the apnea of central and ataxic
    // patterns.
    private _apnea = _state getOrDefault ["csApnea", 0];
    if (_t >= (_state getOrDefault ["csApneaNext", 0])) then {
        _apnea = [0, 1] select (random 1 < 0.28);
        _state set ["csApnea", _apnea];
        _state set ["csApneaNext", _t + (1.5 + random 4.5)];
    };
    private _rr = 15 + (_chaos * 17) + _walk;  // the per-frame (random 8)-4 is removed. it was the rapid jitter.
                                                  // the chaos oscillators and the interval walk already give irregularity.
    if (_apnea > 0) then { _rr = _rr * (0.10 + random 0.15); };  // a pause, or hypopnea.
    _rr = _rr - (_decomp * 6);  // it trends agonal toward terminal.
    _rr = round (_rr max 0 min 45);
    // B67: nonterminal ICP can remain irregular/slow but cannot by itself sustain arrest-level apnea.
    if (_stage < 3) then {_rr = _rr max (missionNamespace getVariable ["ACME_tbi_nonterminalMinRR", 12]);};
    // publish the live rr as a drive. the updateRespirationRate sole-writer, in fn_postInit, eases the actual rate
    // toward it and is the only thing that writes ACM_breathing_RespirationRate, so ACM's own per-tick easing
    // toward its oxygen-derived target never runs and cannot fight us. that fight was the reset and jitter where
    // ACM still seemed to be hooking respirations. the easing of the wrapper smooths the run-to-run jumps into a
    // clean swing.
    // the target must stay nonzero, because ACM's updateoxygen divides by it and would throw a zero divisor, and the
    // live drive may hit 0.

    [_patient, "ACME_rrDrive_tbi", _rr, 0.25, 1] call ACME_fnc_setVarNetApprox;

    // cheyne-stokes breath sounds. the critical stage is the cheyne-stokes phase, so the audible breathing must
    // match it. ACME_cs_active gates the cheyne breath-sound pfh, in fn_breathsoundsstart, so it is set here and
    // the sounds start if they are not already running.
    // there is one exception. a seizing patient is apneic, because tensed muscles cannot breathe, so no breath
    // sounds play while the seizure is active, and they resume when the seizure ends if cheyne-stokes is still
    // present.
    // ACME_cs_active is used purely as the sound gate here. the TBI drive above still owns the rr number, because
    // the patient is not added to ACME_cs_activePatients, so fn_cheynestokestick does not also drive rr and there
    // is no fight.
    private _seizingNow = (_patient getVariable ["ACME_lido_seizureState", ""]) isEqualTo "active";
    if (_seizingNow) then {
        // apneic during the fit, so silence the cheyne-stokes sounds.
        if (_patient getVariable ["ACME_cs_active", false]) then { [_patient, "ACME_cs_active", false] call ACME_fnc_setVarNet; };
    } else {
        if !(_patient getVariable ["ACME_cs_active", false]) then { [_patient, "ACME_cs_active", true] call ACME_fnc_setVarNet; };
        if ((_patient getVariable ["ACME_bs_pfh", -1]) == -1) then { [_patient, "cheyne"] call ACME_fnc_breathSoundsStart; };
    };
} else {
    // not in the cheyne-stokes stage, so make sure its breath sounds are stopped, because ACME_cs_active at false
    // self-kills the cheyne pfh. it is guarded so we do not stomp a debug-toggled cheyne-stokes demo that set this
    // independently.
    if ((_patient getVariable ["ACME_cs_active", false]) && {isNil {_patient getVariable "ACME_cs_savedRR"}}) then {
        [_patient, "ACME_cs_active", false] call ACME_fnc_setVarNet;
    };
    private _rrT = linearConversion [0, 1, _decomp, (missionNamespace getVariable ["ACME_tbi_cushRR", 11]), (missionNamespace getVariable ["ACME_tbi_terminalRR", 3])];
    _rrT = _rrT + (_wave2 * (missionNamespace getVariable ["ACME_tbi_rrWaveAmp", 6]) * (1 - (_decomp * 0.5)));
    _rrT = _rrT max 0 min 40;

    // publish the eased compensated-cushing target. the sole-writer eases the live rate to it, so there is no
    // double-easing here and no direct ACM_breathing_RespirationRate write, because the wrapper owns the live value
    // now.
    private _rrPublish = round _rrT;
    if (_stage < 3) then {_rrPublish = _rrPublish max (missionNamespace getVariable ["ACME_tbi_nonterminalMinRR", 12]);};
    [_patient, "ACME_rrDrive_tbi", _rrPublish, 0.25, 1] call ACME_fnc_setVarNetApprox;
};

// terminal, and real damage. a sustained stage 3, with bilateral fixed pupils, forces a cardiac arrest and sets
// the evac flag.
if (_stage >= 3) then {
    private _tc = (_state getOrDefault ["termClock", 0]) + _dt;
    _state set ["termClock", _tc];
    if (!(_patient getVariable ["ACME_tbi_evacFlagged", false])) then {
        [_patient, "ACME_tbi_evacRequired", true] call ACME_fnc_setVarNet;
        [_patient, "ACME_tbi_evacFlagged", true] call ACME_fnc_setVarNet;
        // the activity-log line is removed, because it revealed the condition of the patient.
    };
    if (_tc >= (missionNamespace getVariable ["ACME_tbi_terminalArrestSecs", 20])
        && {alive _patient}
        && {!(_patient getVariable ["ace_medical_inCardiacArrest", false])}
        && {!isNil "ace_medical_status_fnc_setCardiacArrestState"}) then {
        [_patient, 1] call ACME_fnc_arrestLocal;  // brainstem death, which gives arrest.
        // the activity-log line is removed, because it revealed the condition of the patient.
    };
} else {
    _state set ["termClock", 0];
};
