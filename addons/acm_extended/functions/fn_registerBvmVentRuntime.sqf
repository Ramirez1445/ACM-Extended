// hearing-impaired BVM ventilation cue, the blue inflating circle. it uses a fast tick for a smooth pulse.
if (hasInterface) then {[{call ACME_fnc_bvmVentTick}, 0.04, []] call CBA_fnc_addPerFrameHandler;};
