#!/usr/bin/env python3
"""Phase 122: Get Up stays available until a patient-local release transaction is accepted."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
getup=(ROOT/'addons/core/functions/fnc_getUp.sqf').read_text()
post=(ROOT/'addons/core/XEH_postInit.sqf').read_text()
assert 'if (!local _patient) exitWith' in getup
assert '"ACM_core_getUpRequest"' in getup
assert 'QGVAR(getUpRequest)' in post and 'call FUNC(getUp)' in post
idx_gate=getup.index('if (!_canRelease) exitWith {};')
idx_clear=getup.index('_patient setVariable ["ACM_core_Lying_State", false, true];')
assert idx_clear > idx_gate, 'lying flag is still consumed before release acceptance'
window=getup[getup.index('private _canRelease'):idx_gate]
assert '_wasLying' in window
assert 'stance _patient == "PRONE"' in window
assert 'attachedTo _patient' in getup
assert '(_carryAnim find "carried") >= 0' in getup
print('PASS phase122: Get Up is patient-local and does not consume the lying state before release')
