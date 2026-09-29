// physiological obtundation: it drives the semi-conscious state from the patient's own vitals instead of a debug
// switch. a patient whose oxygenation or perfusion is marginal, low enough to cloud consciousness and not low
// enough for ACE to knock them fully out, is laid into the obtunded state. they climb back out as the cause is
// corrected, and if they deteriorate past the band, ACE's own unconsciousness and arrest takes over.
// it runs periodically on local alive units only, because the obtunded apply needs to run where the unit is local.
// the band keys off SpO2, where ACE knocks out below about 80, and MAP, where our arrest line is 55, with
// hysteresis so a patient sitting on a threshold does not flicker. medic-forced and zeus-forced manual patients
// are left alone. toggle the whole behavior with ACME_obtunded_autoEnable.
if !(missionNamespace getVariable ["ACME_sys_obtunded", false]) exitWith {};
if !(missionNamespace getVariable ["ACME_obtunded_autoEnable", true]) exitWith {};

// the floor of the band, and where it sits against ACM.
// ACM's own ladder, from addons/main/script_macros.hpp and its handleunitvitals override:
//   85  vision effects start.
//   80  unconsciousness BEGINS, and it is a dice roll rather than a line. the test is
//       "ACM_OXYGEN_UNCONSCIOUS - (random 10) > spo2", so from 80 down to 70 it is a per-tick chance that only
//       becomes certain at 70.
//   67  hypoxia. from here a tick can send them to cardiac arrest instead of unconsciousness.
//   55  death.
// this floor used to be 80, described as the ACE knockout floor. it is not one: 80 is where ACM starts rolling.
// releasing obtundation there left the casualty awake, upright and unobtunded at 75 percent while ACM's dice
// failed to come up, which is a hole rather than a handoff.
// so the floor is now 70, where ACM's knockout is certain, and obtundation is held through the whole roll window.
// the actual handoff is the check below: the moment ACM does knock them out, obtundation lets go.
private _spo2Lo  = missionNamespace getVariable ["ACME_obtunded_spo2EnterLo", 70];
private _spo2Hi  = missionNamespace getVariable ["ACME_obtunded_spo2EnterHi", 90];
private _spo2Rec = missionNamespace getVariable ["ACME_obtunded_spo2Recover", 92];
// the MAP floor stays at 55, because that one genuinely is a line. ACM raises handlefatalvitals below it, which
// is cardiac arrest rather than unconsciousness, so there is no roll window to cover.
private _mapLo   = missionNamespace getVariable ["ACME_obtunded_mapEnterLo", 55];
private _mapHi   = missionNamespace getVariable ["ACME_obtunded_mapEnterHi", 68];
private _mapRec  = missionNamespace getVariable ["ACME_obtunded_mapRecover", 70];

// entering is not instant any more.
// a casualty who dips under a threshold for a second or two is not obtunded. they are a casualty having a bad
// moment, and dropping them on the floor for it made every scratch look like a head injury. so crossing the line
// starts a clock instead of a collapse, and they have to stay across it.
// there are two ways in.
//   the soft trigger: sustained. in the band continuously for ACME_obtunded_dwellEnter seconds. step back out at
//   any point and the clock resets to zero, so it is genuinely continuous rather than cumulative.
//   the hard trigger: profound. far enough below the line that waiting would be dishonest, at
//   ACME_obtunded_hardSpO2 or ACME_obtunded_hardMAP. this is immediate, because a casualty at 82 percent is not
//   having a moment.
private _dwellEnter = missionNamespace getVariable ["ACME_obtunded_dwellEnter", 8];
private _hardSpO2   = missionNamespace getVariable ["ACME_obtunded_hardSpO2", 83];
private _hardMAP    = missionNamespace getVariable ["ACME_obtunded_hardMAP", 59];
// after recovering, they are left alone for a while.
// bouncing straight back under is the thing that makes this system feel broken: the medic fixes them, they stand
// up, and they go down again before anyone can act on it. so a recovery buys a refractory window, and inside it
// only the hard trigger or a much longer sustained dwell can put them back down.
private _refract    = missionNamespace getVariable ["ACME_obtunded_refractory", 45];
private _dwellRe    = missionNamespace getVariable ["ACME_obtunded_dwellReEnter", 20];

{
    private _u = _x;
    if !(_u getVariable ["ACME_obtunded_manual", false]) then {
        private _arrest = (_u getVariable ["ace_medical_inCardiacArrest", false]);
        private _spo2 = _u getVariable ["ace_medical_spo2", 97];
        private _bp = [_u] call ace_medical_status_fnc_getBloodPressure;  // wrapped, so it includes our offset.
        _bp params [["_d", 80], ["_s", 120]];
        private _map = _d + ((_s - _d) / 3);
        private _cur = _u getVariable ["ACME_obtunded", false];
        private _wakeStimGrace = CBA_missionTime < (_u getVariable ["ACME_obtunded_wakeStimGraceUntil", 0]);

        private _critical = (_spo2 < _spo2Lo) || {_map < _mapLo};  // ACE and arrest territory.
        private _inZone   = ((_spo2 >= _spo2Lo) && {_spo2 < _spo2Hi}) || {(_map >= _mapLo) && {_map < _mapHi}};
        private _recovered = (_spo2 >= _spo2Rec) && {_map >= _mapRec};

        // B49 has one awake-obtunded posture: free. The physiology decides whether the cognitive state is present; it
        // never decides how the body must lie. Treatment, dragging, movement and the player's current stance own pose.
        private _posture = "free";

        // Are they being worked on right now? Recovery still waits until the active treatment ends so state changes do not
        // land in the middle of a procedure. Deterioration to real unconsciousness is never delayed.
        private _beingTreated = CBA_missionTime < (_u getVariable ["ACME_beingTreated_until", 0]);

        // has ACM already taken them? that is the handoff, and it is what makes the transition smooth rather than a
        // race between two systems. obtundation lets go without standing them up, so they slump where they are and
        // ACM owns them from that point.
        private _koNow = _u getVariable ["ACE_isUnconscious", false];

        if (_cur) then {
            // B39 rapid arousal treatment: ACM's ammonia inhalant already records LastUse and only
            // wakes medically unconscious patients when vitals are stable. Obtundation is deliberately
            // awake/semi-conscious, so native ACM would otherwise never clear it. A NEW ammonia use
            // while recovery-compatible vitals are present rapidly terminates obtundation, restores all
            // PP/voice/motor state through the normal setter cleanup, and grants the existing wake-stimulus
            // grace so the auto evaluator cannot immediately knock them back down. It does not repair
            // persistent hypoxia/shock; if vitals are not stable, the stimulus cannot cure the cause.
            private _ammLast = _u getVariable ["ACM_circulation_AmmoniaInhalant_LastUse", -1];
            private _ammSeen = _u getVariable ["ACME_obtunded_ammoniaSeen", -1];
            if (_ammLast > _ammSeen) then {
                _u setVariable ["ACME_obtunded_ammoniaSeen", _ammLast];
                private _stable = if (!isNil "ace_medical_status_fnc_hasStableVitals") then {[_u] call ace_medical_status_fnc_hasStableVitals} else {_recovered};
                private _forced = if (!isNil "ACM_core_fnc_isForcedUnconscious") then {[_u] call ACM_core_fnc_isForcedUnconscious} else {false};
                if (_stable && {!_forced} && {!_arrest}) then {
                    _u setVariable ["ACME_obtunded_wakeStimGraceUntil", CBA_missionTime + (missionNamespace getVariable ["ACME_obtunded_ammoniaGrace", 20]), true];
                    _u setVariable ["ACME_obtunded_refractoryUntil", CBA_missionTime + _refract];
                    _u setVariable ["ACME_obtunded_dwellSince", -1];
                    [_u, false, false, _posture, "recover"] call ACME_fnc_obtundedSet;
                    continue;
                };
            };
            if (_koNow) exitWith {
                [_u, false, false, _posture, "deteriorate"] call ACME_fnc_obtundedSet;
            };
            if (_arrest || {_critical}) then {
                // the end of the cascade: fall into ko in place, which is allowed even mid-care.
                [_u, false, false, _posture, "deteriorate"] call ACME_fnc_obtundedSet;
            } else {
                if (_recovered) then {
                    if (!_beingTreated) then {
                        // they recovered on their own vitals, so give them a window before this can take them
                        // again. inside it only the hard trigger or a much longer dwell counts.
                        _u setVariable ["ACME_obtunded_refractoryUntil", CBA_missionTime + _refract];
                        _u setVariable ["ACME_obtunded_dwellSince", -1];
                        [_u, false, false, _posture, "recover"] call ACME_fnc_obtundedSet;  // do not stand them up mid-care.
                    };
                };
                // there are no mid-episode posture shifts, because the landing decided the pose.
            };
        } else {
            // not obtunded. decide whether they are on their way there.
            private _profound = (_spo2 < _hardSpO2) || {_map < _hardMAP};
            // an unconscious casualty is not a candidate. obtundation is an awake state, and applying it on top of
            // ACM's knockout would have two systems driving one body.
            private _blocked  = _wakeStimGrace || _arrest || _critical || _koNow;

            if (_blocked || {!_inZone && {!_profound}}) then {
                // out of the band, so the clock resets. it has to be continuous time under the line, because a
                // casualty who keeps bobbing across it is being kept alive rather than deteriorating.
                _u setVariable ["ACME_obtunded_dwellSince", -1];
            } else {
                private _since = _u getVariable ["ACME_obtunded_dwellSince", -1];
                if (_since < 0) then {
                    _since = CBA_missionTime;
                    _u setVariable ["ACME_obtunded_dwellSince", _since];
                };
                // how long they have held it, and how long they need to.
                private _held = CBA_missionTime - _since;
                private _inRefractory = CBA_missionTime < (_u getVariable ["ACME_obtunded_refractoryUntil", 0]);
                private _need = if (_inRefractory) then {_dwellRe} else {_dwellEnter};

                // profound goes straight down, refractory or not. that is what profound means: there is no version
                // of a saturation in the low eighties that should be waited out.
                if (_profound || {_held >= _need}) then {
                    _u setVariable ["ACME_obtunded_dwellSince", -1];
                    [_u, true, false, _posture] call ACME_fnc_obtundedSet;
                };
            };
        };
    };
} forEach ((missionNamespace getVariable ["ACME_clinical_ownedUnits", []]) select {alive _x && {isPlayer _x}});
