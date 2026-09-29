// blast lung progression, called per patient from the circulation loop.
// untreated, blast lung deteriorates. the contused lung keeps flooding over the first 20 minutes or so, gas
// exchange falls apart and the casualty hypoxaemically arrests. it cannot be talked out of. the only thing that
// arrests the slide is mechanical ventilation with oxygen, and the lung is stiff, so how you ventilate matters.
// SIMV pc is correct. it caps the pressure, oxygenates, and lets the lung heal.
// SIMV vc ps forces volume into a stiff lung, so the PIP spikes, barotrauma accrues and the blast lung worsens.
// CPAP, or no vent at all, does not ventilate a casualty with no drive, and they die.
// call it as [_patient] call ACME_fnc_blastLungTick.
params ["_patient"];
// the system toggle, read live, so unticking blast lung in addon options stops this system immediately and
// completely with no mission restart.
if !(missionNamespace getVariable ["ACME_sys_blastLung", true]) exitWith {};
if (isNull _patient || {!local _patient} || {!alive _patient} || {!(_patient isKindOf "CAManBase")}) exitWith {};

private _sev = _patient getVariable ["ACME_blastLung_State", 0];
if (_sev <= 0) exitWith {};

private _dt = [_patient, "blastLung", 0.25, 5] call ACME_fnc_clinicalTickDelta;

// is the casualty being properly ventilated for this injury?
private _driving   = _patient getVariable ["ACME_vent_driving", false];
private _effective = [_patient] call ACME_fnc_ventEffectiveSettings;
private _mode = _effective select 1;
private _fio2 = _effective select 4;
private _pipState  = _patient getVariable ["ACME_vent_pipState", 0];  // 2 is danger, from barotrauma.
private _mvAdeq    = _patient getVariable ["ACME_vent_mvAdequacy", 0];
// a blast lung needs real minute ventilation and supplemental oxygen to hold the line.
private _ventilated = _driving && {_mvAdeq > 0.6} && {_fio2 >= (missionNamespace getVariable ["ACME_blastLung_fio2Needed", 50])};

// treatment tier detection, best to worst.
private _bvmProvider = _patient getVariable ["ACM_breathing_BVM_provider", objNull];
private _bvmActive   = (alive _bvmProvider) && {!(_bvmProvider isEqualTo _patient)};  // a real medic bagging, rather than the vent driving through the BVM slot.
private _bvmO2       = _patient getVariable ["ACM_breathing_BVM_ConnectedOxygen", false];
private _o2Assist    = (_driving && {_fio2 >= (missionNamespace getVariable ["ACME_blastLung_fio2Needed", 50])}) || {_patient getVariable ["ACME_nrb_delivering", false]};  // supplemental o2 is present.
private _mildThresh  = missionNamespace getVariable ["ACME_blastLung_mildThreshold", 0.30];
private _isMild      = _sev < _mildThresh;

// the ARDS state.
private _ards = _patient getVariable ["ACME_blastLung_ARDS", false];

// progression and resolution across the treatment ladder.
private _rate = 0;  // a positive value heals and a negative one worsens, per second, applied times _dt.
if (_ventilated && {_pipState < 2}) then {
    // tier 1: correct mechanical ventilation. it gives the strongest recovery.
    _rate = missionNamespace getVariable ["ACME_blastLung_healVentPerSec", 0.0016];
} else {
    if (_driving && {_pipState >= 2}) then {
        // the worst tier: volume control, or a high PIP, into a stiff lung. that is barotrauma, and it is actively
        // destructive.
        _rate = -((missionNamespace getVariable ["ACME_blastLung_worsenBasePerSec", 0.0008]) * (missionNamespace getVariable ["ACME_blastLung_baroWorsenMult", 3]));
    } else {
        if (_bvmActive && {_bvmO2}) then {
            // tier 2: a BVM with oxygen. positive pressure plus o2 recruits alveoli, so it is a real, slower recovery.
            _rate = missionNamespace getVariable ["ACME_blastLung_healBvmO2PerSec", 0.0008];
        } else {
            if (_bvmActive) then {
                // tier 3: a bare BVM with no o2. it buys time, so it is a slowed slide rather than a fix.
                _rate = -(missionNamespace getVariable ["ACME_blastLung_worsenBvmPerSec", 0.0003]);
            } else {
                if (_o2Assist && {_sev < (missionNamespace getVariable ["ACME_blastLung_o2PlateauMax", 0.45])}) then {
                    // tier 4: passive supplemental o2, with no positive pressure. on a mild blast lung it slowly heals, so a walking
                    // wounded rides it out. on a moderate one it only holds the line, at a plateau, and it will not reverse without
                    // positive pressure.
                    if (_isMild) then {
                        _rate = missionNamespace getVariable ["ACME_blastLung_healO2PerSec", 0.00035];
                    } else {
                        _rate = 0;  // a plateau: it neither heals nor worsens.
                    };
                } else {
                    // tier 5: nothing, or o2 on an already severe lung. this is the slide toward ARDS.
                    _rate = -(missionNamespace getVariable ["ACME_blastLung_worsenBasePerSec", 0.0008]);
                    // a mild, untreated blast lung on room air still plateaus rather than progressing, because a minor contusion
                    // does not march to ARDS. only moderate and worse slides.
                    if (_isMild) then { _rate = 0; };
                };
            };
        };
    };
};

// ARDS modifies the rate. it heals far slower and worsens faster, because it is refractory and the lung is
// stiff.
if (_ards) then {
    if (_rate > 0) then { _rate = _rate * (missionNamespace getVariable ["ACME_blastLung_ardsHealMult", 0.35]); }
    else { _rate = _rate * (missionNamespace getVariable ["ACME_blastLung_ardsWorsenMult", 1.5]); };
};

_sev = _sev + (_rate * _dt);

// ARDS progression. a sustained severe blast lung converts to ARDS, which is the actual damage endpoint.
private _ardsEnter = missionNamespace getVariable ["ACME_blastLung_ardsEnterSev", 0.85];
if (!_ards) then {
    if (_sev >= _ardsEnter) then {
        private _since = _patient getVariable ["ACME_blastLung_ardsClock", -1];
        if (_since < 0) then { [_patient, objNull, CBA_missionTime, true, false] call ACME_fnc_blastLungArdsCommit; }
        else {
            if ((CBA_missionTime - _since) >= (missionNamespace getVariable ["ACME_blastLung_ardsEnterSecs", 60])) then {
                [_patient, true, objNull, true, true] call ACME_fnc_blastLungArdsCommit;
                _ards = true;
            };
        };
    } else {
        [_patient, objNull, -1, true, true] call ACME_fnc_blastLungArdsCommit;  // it fell back below the threshold, so reset the clock.
    };
};
// once ARDS has latched, severity can never recover below the scarred-lung floor. it needs evac for definitive
// care.
if (_ards) then {
    _sev = _sev max (missionNamespace getVariable ["ACME_blastLung_ardsSevFloor", 0.35]);
    [_patient, true, true, true, false] call ACME_fnc_evacuationRequirementCommit;
}
else { _sev = _sev max 0; };
_sev = _sev min 1;
[_patient, _sev, true, true, false, 0.002, 1] call ACME_fnc_blastLungStateCommit;

if (_sev <= 0.001) exitWith {
    // resolved, so hand the breathing ability back to ACM.
    [_patient, 0, true, true] call ACME_fnc_blastLungStateCommit;
    [_patient, "ACME_blastLung_rrDrive", -1] call ACME_fnc_setVarNet;  // release the air-hunger rr drive.
    if (_patient getVariable ["ACME_blastLung_ownsBreathVar", false]) then {
        [_patient, 1, true] call ACM_CBRN_fnc_setBreathingAbilityState;
        [_patient, "ACME_blastLung_ownsBreathVar", false] call ACME_fnc_setVarNet;
    };
};

// degrade the gas exchange through ACM's own breathing-state multiplier.
// ACM's getBreathingState multiplies by ACM_CBRN_BreathingAbility_State, which defaults to 1, and that flows
// natively into its whole oxygen and CO2 sim. we only touch it when cbrn is disabled, so we can never fight the
// cbrn system for ownership of that variable, and if cbrn is on we fall back to acting on saturation directly,
// below.
// if a ventilator is driving this patient, it owns the oxygenation, so hands off. fn_ventoxygenation already
// accounts for this blast lung, as recruitable shunt, and it is the thing PEEP acts on. if we also crush the
// breathing ability here, the same injury gets counted twice, through two different mechanisms, updating on two
// different clocks: ACM's own oxygen sim on one cadence and our saturation pin on the circulation tick. that is
// why the saturation was falling off a cliff, and why it fell out of step with every other vital on the debug
// readout. one injury, one owner.
// off the vent, the ability crush stays exactly as it was, and it is precisely what makes a blast lung a reason
// to intubate in the first place.
if (_patient getVariable ["ACME_vent_driving", false]) exitWith {
    if (_patient getVariable ["ACME_blastLung_ownsBreathVar", false]) then {
        [_patient, 1, true] call ACM_CBRN_fnc_setBreathingAbilityState;
        [_patient, "ACME_blastLung_ownsBreathVar", false] call ACME_fnc_setVarNet;
    };
};

private _cbrnOn = missionNamespace getVariable ["ACM_CBRN_enable", false];

// how far into the deterioration are we? blast lung floods over minutes, and it does not switch gas exchange off
// the instant the wave hits. the penalty ramps in from the onset time, so a fresh injury starts near-normal and
// slides toward its full effect over a couple of minutes. without this ramp the crush landed at full severity on
// the first tick and ACM's oxygen sim drove the casualty from injury to hypoxic arrest in a few seconds, which
// was the bug.
private _onsetT = _patient getVariable ["ACME_blastLung_Onset", CBA_missionTime];
private _rampSecs = missionNamespace getVariable ["ACME_blastLung_effectRampSecs", 150];  // about 2.5 min to full effect.
private _ramp = ((CBA_missionTime - _onsetT) / (_rampSecs max 1)) max 0 min 1;
private _effSev = _sev * _ramp;  // the gas-exchange penalty scales with how far the flooding has progressed.

if (!_cbrnOn) then {
    // the gas-exchange penalty as a breathing-ability multiplier. it is a gentler curve with a much higher floor than
    // before, so even a maximal, fully progressed blast lung leaves enough exchange to desaturate the casualty over
    // minutes, which is the reason to intubate, rather than to arrest them in seconds. the old curve, 1 minus 0.75
    // times sev with a floor of 0.15, meant a fresh severe hit sat at 0.15 to 0.32 gas exchange immediately, which
    // ACM reads as near-total respiratory failure and converts to a hypoxic arrest almost at once.
    private _floor = missionNamespace getVariable ["ACME_blastLung_abilityFloor", 0.45];
    // ARDS is refractory hypoxemia, so the floor drops and the achievable oxygenation is worse. even supported, the
    // SpO2 sits lower than a plain blast lung, which is the hallmark of ARDS.
    if (_ards) then { _floor = _floor * (missionNamespace getVariable ["ACME_blastLung_ardsFloorMult", 0.8]); };
    private _ability = 1 - ((1 - _floor) * _effSev);
    if (_ventilated) then { _ability = _ability + ((1 - _ability) * 0.6); };  // the vent buys back most of it.
    _ability = (_ability max _floor) min 1;
    // Native CBRN state writes are public. Gate this continuously changing multiplier locally so the native
    // setter is not called four times per second for sub-visible changes.
    private _lastAbility = _patient getVariable ["ACME_blastLung_lastAbilityPublished", -1];
    private _lastAbilityAt = _patient getVariable ["ACME_blastLung_lastAbilityAt", -1];
    if (_lastAbility < 0 || {abs (_ability - _lastAbility) >= 0.005}
        || {_lastAbilityAt < 0 || {CBA_missionTime - _lastAbilityAt >= 1}}) then {
        [_patient, _ability, true] call ACM_CBRN_fnc_setBreathingAbilityState;
        _patient setVariable ["ACME_blastLung_lastAbilityPublished", _ability, false];
        _patient setVariable ["ACME_blastLung_lastAbilityAt", CBA_missionTime, false];
    };
    [_patient, "ACME_blastLung_ownsBreathVar", true] call ACME_fnc_setVarNet;
} else {
    // cbrn owns that variable, so act on saturation directly instead. ease SpO2 gently toward a ceiling that also
    // ramps in, so the desaturation is a slide over minutes rather than a cliff.
    private _ceiling = 100 - (45 * _effSev);
    if (_ventilated) then { _ceiling = _ceiling + (30 * _effSev); };
    // ARDS is refractory hypoxemia, so the achievable SpO2 ceiling drops further and even a supported ARDS lung sits
    // lower than a plain blast lung.
    if (_ards) then { _ceiling = _ceiling - (missionNamespace getVariable ["ACME_blastLung_ardsSpO2Drop", 8]); };
    _ceiling = (_ceiling max 50) min 100;
    private _spo2 = _patient getVariable ["ace_medical_spo2", 97];
    if (_spo2 > _ceiling) then {
        // 0.5 percent per second: a gradual decline the medic can catch and treat, not a plunge.
        [_patient, [["spo2", ((_spo2 - (0.5 * _dt)) max _ceiling), true, true]]] call ACM_core_fnc_setAceMedicalState;
    };
};

// air hunger. the casualty tries to breathe their way out of it and cannot.
// the air-hunger rate is published as a drive that the updateRespirationRate sole-writer consumes, below the
// vent, seizure and TBI drives, rather than writing the live rate here. so blast-lung tachypnea composes with
// the central patterns instead of fighting them on a polytrauma casualty. it is only meaningful off the vent,
// because the rate of a driven patient is the machine's, and it is released, at -1, when on the vent. a nonzero
// target floor is still set, so ACM's oxygen divisor is safe.
if (!_driving) then {
    private _rrTarget = 18 + round (16 * _sev);
    [_patient, "ACME_blastLung_rrDrive", _rrTarget] call ACME_fnc_setVarNet;

} else {
    [_patient, "ACME_blastLung_rrDrive", -1] call ACME_fnc_setVarNet;
};;
