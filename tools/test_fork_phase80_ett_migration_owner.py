from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[1]
FUN=ROOT/'addons/acm_extended/functions'
owner=FUN/'fn_ettMigrationStateCommit.sqf'
assert owner.exists()
assert 'class ettMigrationStateCommit {};' in (ROOT/'addons/acm_extended/config.cpp').read_text(errors='ignore')
fields=['ACME_ETT_Depth','ACME_ETT_Frame','ACME_ETT_Mainstem','ACME_ETT_Obstructing','ACME_ETT_ObstructUntil']
pat=re.compile(r'setVariable\s*\[\s*["\']('+'|'.join(map(re.escape,fields))+r')["\']')
viol=[]
for p in FUN.glob('*.sqf'):
    if p==owner: continue
    for m in pat.finditer(p.read_text(errors='ignore')): viol.append((p.name,m.group(1)))
assert not viol, viol
for n in ['fn_laryngoPassTube.sqf','fn_laryngoTubeEject.sqf','fn_ettMigrate.sqf']:
    assert 'ACME_fnc_ettMigrationStateCommit' in (FUN/n).read_text(errors='ignore')

# Deliberate extubation is now a patient-owner transaction. The UI entry never mutates migration state remotely;
# ownerDispatch performs all placement/obstruction/tip commits atomically after accepting the extubation.
extubate=(FUN/'fn_laryngoExtubate.sqf').read_text(errors='ignore')
dispatch=(FUN/'fn_ownerDispatch.sqf').read_text(errors='ignore')
assert '[_patient, "ettExtubate", [_medic]] call ACME_fnc_ownerDispatch;' in extubate
ett_case=dispatch.split('case "ettExtubate": {',1)[1].split('case "laryngoConsequence"',1)[0]
assert ett_case.count('ACME_fnc_ettMigrationStateCommit') >= 3
print('phase80 ett migration owner: PASS')
