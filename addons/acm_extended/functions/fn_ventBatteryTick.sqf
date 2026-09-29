// the ventilator battery.
// the sparrow is turbine-driven, so it does not consume oxygen to operate: it draws ambient air and ventilates on
// room air indefinitely as far as gas goes. oxygen is optional enrichment rather than fuel. that means the real
// clock on this machine is electrical, and it is the constraint worth modeling.
// the real spec is up to 4.5 hours on the internal battery. that is a whole mission with nothing to manage, so the
// in-game figure is deliberately shortened, through ACME_vent_batteryMinutes. the intent is not realism for its
// own sake but pressure: a ventilated casualty should be a reason to move, and the battery is what makes that
// true.
// the drain is not flat. a turbine works harder against stiff lungs, high PEEP and a fast rate, so the settings
// that keep a bad casualty alive are the same ones that eat the battery. that is the interesting part: the sicker
// the patient, the less time you have to get them somewhere.
// external power is the answer, and it is why vehicles matter. plugged into aircraft or vehicle power the battery
// stops draining and slowly recharges, so reaching the bird is a real objective rather than just a ride home.

params ["_pat"];
if (isNull _pat) exitWith {};

// the battery model is off. a mission that does not want an electrical clock on the machine can switch the whole
// thing off in addon options, and then the ventilator simply runs. it is held at full and marked externally
// powered, so every readout, icon and alarm downstream reads fine without any of them needing to know the setting
// exists, and so a mission that toggles it mid-session cannot strand a casualty on a half-empty battery that will
// never refill.
if !(missionNamespace getVariable ["ACME_vent_batteryEnabled", true]) exitWith {
    [_pat, "ACME_vent_battery", 100] call ACME_fnc_setVarNet;
    [_pat, "ACME_vent_battExternal", true] call ACME_fnc_setVarNet;
    [_pat, "ACME_vent_battWarned", 0] call ACME_fnc_setVarNet;
};

if !(_pat getVariable ["ACME_vent_connected", false]) exitWith {};

private _now = CBA_missionTime;
private _last = _pat getVariable ["ACME_vent_battLastT", -1];
_pat setVariable ["ACME_vent_battLastT", _now, false];
if (_last < 0) exitWith {};
private _dt = (_now - _last) min 10;  // a clamp, so a lag spike cannot dump the whole battery at once.
if (_dt <= 0) exitWith {};

private _capMin = missionNamespace getVariable ["ACME_vent_batteryMinutes", 55];
private _pct = _pat getVariable ["ACME_vent_battery", 100];

// external power. in a vehicle with the engine running, the vent is on ship power, so there is no drain and a slow
// recharge.
private _veh = objectParent _pat;
private _onShipPower = !isNull _veh && {isEngineOn _veh};
if (_onShipPower) then {
    private _rechargeMin = missionNamespace getVariable ["ACME_vent_batteryRechargeMinutes", 90];
    _pct = (_pct + ((_dt / 60) / _rechargeMin) * 100) min 100;
    [_pat, "ACME_vent_battery", _pct, 0.10, 2] call ACME_fnc_setVarNetApprox;
    [_pat, "ACME_vent_battExternal", true] call ACME_fnc_setVarNet;
} else {
    [_pat, "ACME_vent_battExternal", false] call ACME_fnc_setVarNet;

    // the load factor. the baseline is 1.0 at gentle settings. the turbine has to generate more pressure, more often,
    // against stiffer lungs, so each of those costs current.
    private _load = 1;
    private _effective = [_pat] call ACME_fnc_ventEffectiveSettings;
    private _peep = if (_effective select 0) then {_effective select 5} else {_pat getVariable ["ACME_vent_peep", 5]};
    _load = _load * (linearConversion [5, 20, _peep, 1, (missionNamespace getVariable ["ACME_vent_battPeepMult", 1.35]), true]);
    // Delivered rate and measured pressure are published by fn_ventDriveTick.sqf.
    private _rr = _pat getVariable ["ACME_vent_measRR", (if (_effective select 0) then {_effective select 2} else {_pat getVariable ["ACME_vent_bpm", 12]})];
    _load = _load * (linearConversion [10, 35, _rr, 1, (missionNamespace getVariable ["ACME_vent_battRateMult", 1.30]), true]);
    private _pip = _pat getVariable ["ACME_vent_pip", 20];
    _load = _load * (linearConversion [20, 50, _pip, 1, (missionNamespace getVariable ["ACME_vent_battPipMult", 1.40]), true]);

    _pct = (_pct - (((_dt / 60) / _capMin) * 100 * _load)) max 0;
    [_pat, "ACME_vent_battery", _pct, 0.10, 2] call ACME_fnc_setVarNetApprox;
};

// warnings and the cutoff. there are two warnings and then a stop, because a ventilator that dies without having
// said anything is a gotcha rather than a lesson. the medic should always have had the chance to act on it.
private _warned = _pat getVariable ["ACME_vent_battWarned", 0];
private _lowAt = missionNamespace getVariable ["ACME_vent_batteryLowPct", 25];
private _critAt = missionNamespace getVariable ["ACME_vent_batteryCritPct", 10];

// the alarms are a list that fn_ventalarmtick rebuilds each pass rather than something raised by a call, so the
// battery publishes a level and the alarm tick picks it up like every other condition. the warned flags only gate
// the one-shot chirp rather than the alarm itself, so the alarm persists while the condition does.
if (_pct <= _lowAt && {_warned < 1}) then { _pat setVariable ["ACME_vent_battWarned", 1, true]; };
if (_pct <= _critAt && {_warned < 2}) then { _pat setVariable ["ACME_vent_battWarned", 2, true]; };

if (_pct <= 0) then {
    // the vent stops. it does not quietly keep ventilating an unpowered patient, and it does not kill them either: it
    // hands them back to the medic, who now has to bag. losing the machine should mean work rather than death.
    [_pat, "ACME_vent_connected", false] call ACME_fnc_setVarNet;
    [_pat, "ACME_vent_driving", false] call ACME_fnc_setVarNet;
    [_pat, "ACME_vent_battWarned", 0] call ACME_fnc_setVarNet;
    ["Ventilator has shut down: battery exhausted. Ventilate manually.", 3, ACE_player] call ace_common_fnc_displayTextStructured;
};
