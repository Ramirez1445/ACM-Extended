#include "..\script_component.hpp"
/* NA4: compose once, publish once. The four native conditions below are copied
   unchanged from the supplied ACM fnc_updateCirculationState. Reconcile this
   short merge when updating ACM; do not publish a provisional native true and
   then a contradictory Extended false in the same call.

   Extended hypothermia/acidosis/toxicity restrictions are ROSC restrictions:
   they cannot turn a non-arrested patient's native circulation state off. */
params ["_patient"];
private _acmeBinding = "NA4:updateCirculationState";
if (isNull _patient || {!local _patient}) exitWith {};
private _state = true;
switch (true) do {
    case (GET_OXYGEN(_patient) < ACM_OXYGEN_HYPOXIA);
    case (_patient getVariable [QEGVAR(breathing,TensionPneumothorax_State), false]);
    case ((_patient getVariable [QEGVAR(breathing,Hemothorax_Fluid), 0]) > ACM_TENSIONHEMOTHORAX_THRESHOLD);
    case (GET_BLOOD_VOLUME(_patient) < BLOOD_VOLUME_CLASS_4_HEMORRHAGE): {_state = false;};
    default {};
};
private _blocked = "";
if (_state && {IN_CRDC_ARRST(_patient)}
    && {missionNamespace getVariable ["ACME_hcEff_rhythm", false]}
    && {missionNamespace getVariable ["ACME_sys_rhythm", true]}) then {
    if (missionNamespace getVariable ["ACME_sys_hypothermia", true]) then {
        if ((_patient getVariable ["ACME_hypo_temp", 37]) < (missionNamespace getVariable ["ACME_rosc_hypothermiaFloorC", 30])) then {
            _blocked = "HYPOTHERMIA";
        };
    };
    if (_blocked == "" && {missionNamespace getVariable ["ACME_sys_circ", true]}) then {
        private _cs = _patient getVariable ["ACME_circ_State", createHashMap];
        if ((_cs getOrDefault ["paCO2", 40]) >= (missionNamespace getVariable ["ACME_rosc_paCO2BlockMmHg", 85])) then {
            _blocked = "ACIDOSIS";
        };
    };
    if (_blocked == "" && {_patient getVariable ["ACME_lidoTox_arrestFired", false]}) then {_blocked = "LA TOXICITY";};
};
if ((_patient getVariable ["ACME_rosc_blockedBy", ""]) != _blocked) then {
    _patient setVariable ["ACME_rosc_blockedBy", _blocked, true];
};
private _circulationState = _state && {_blocked == ""};
if ((_patient getVariable [QGVAR(CirculationState), true]) isNotEqualTo _circulationState) then {
    _patient setVariable [QGVAR(CirculationState), _circulationState, true];
};
