from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
CORE=ROOT/'addons/core'
EXT=ROOT/'addons/acm_extended/functions'
prep=(CORE/'XEH_PREP.hpp').read_text()
for token in ['PREP(setTargetVitalsState);','PREP(setLyingState);','PREP(setWasTreated);','PREP(setContinuousActionActive);']:
    assert token in prep,token
assert 'TargetVitals_HeartRate' in (CORE/'functions/fnc_setTargetVitalsState.sqf').read_text()
assert 'TargetVitals_RespirationRate' in (CORE/'functions/fnc_setTargetVitalsState.sqf').read_text()
assert 'TargetVitals_OxygenSaturation' in (CORE/'functions/fnc_setTargetVitalsState.sqf').read_text()
assert 'Lying_State' in (CORE/'functions/fnc_setLyingState.sqf').read_text()
assert 'WasTreated' in (CORE/'functions/fnc_setWasTreated.sqf').read_text()
assert 'ContinuousAction_Active' in (CORE/'functions/fnc_setContinuousActionActive.sqf').read_text()
viol=[]
for p in EXT.glob('*.sqf'):
    for line in p.read_text().splitlines():
        if 'setVariable ["ACM_core_' in line:
            viol.append((p.name,line.strip()))
assert not viol,viol
for required in ['fn_megacodeScenarioTick.sqf','fn_megacodeSetVital.sqf','fn_megacodeResetUnit.sqf','fn_megacodeSetRhythm.sqf']:
    assert 'ACM_core_fnc_setTargetVitalsState' in (EXT/required).read_text(),required
for required in ['fn_clearAllAilments.sqf','fn_obtundedApply.sqf','fn_megacodeSpawn.sqf','fn_directPressureFracturePain.sqf']:
    assert 'ACM_core_fnc_setLyingState' in (EXT/required).read_text(),required
# Manual BP no longer toggles the shared gate itself. It defers to native ACM measureBP, whose
# beginContinuousAction path owns the complete controller lifetime.
bp=(EXT/'fn_measureBPWrap.sqf').read_text()
assert 'ACM_circulation_fnc_measureBP' in bp
assert 'ACM_core_ContinuousAction_' not in bp
# Phase 124: direct pressure is deliberately non-exclusive. It must not own/clear ACM's shared continuous-action lock.
for forbidden in ['fn_directPressureStop.sqf','fn_directPressureTorso.sqf']:
    assert 'call ACM_core_fnc_setContinuousActionActive' not in (EXT/forbidden).read_text(),forbidden
print('fork phase 50 core state ownership checks: PASS')
