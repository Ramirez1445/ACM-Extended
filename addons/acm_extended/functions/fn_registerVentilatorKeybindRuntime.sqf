// Client presentation/input runtime only. Dedicated servers must not register UI PFHs, controls or keybinds.
if (!hasInterface) exitWith {};

// ventilator SELECT keybind.
// the engine does not deliver a middle-click MouseButtonDown to dialog handlers reliably, so we also expose a
// rebindable select key. it acts only while the ventilator dialog, idd 87700, is open, and otherwise does
// nothing. the default is the middle mouse button. rebind it under configure, controls, ACM extended. this
// routes through the input system, which works where the dialog mouse handler does not.
// CBA mouse codes, from the docs of CBA_fnc_addKeybind: 0xf0 is lmb, 0xf1 is RMB, 0xf2 is MMB, 0xf3 to 0xf7 are
// mouse 4 to 8, and 0xf8 and 0xf9 are wheel up and down. 0x100+2, or 0x102, is not the middle mouse button. it
// is "Custom user action 9", which is why an earlier default bound to Use Action 9 instead of MMB. the correct
// MMB code is 0xf2.
// the keybind id was bumped from acme_vent_dialselect to ACME_vent_dialPress. CBA stores each keybind in the
// player profile and never re-applies a changed default to an entry that already exists there. if that entry
// ever ended up saved as unbound, from a controls reset, a profile carried between builds or a stray rebind, it
// stays unbound forever and no code change can fix it. a bump of the id is the only mechanism that forces the
// 0xf2 MMB default to be written fresh, and the old entry is dropped.
// if middle-click ever dies again, check configure, controls, ACM extended first. an empty binding means this
// happened, and a rebind by hand is the immediate fix.
[
    "ACM Extended",
    "ACME_vent_dialPress",
    "Ventilator: Select (dial press)",
    {
        // down statement. this acts only while the vent dialog is open.
        if (!isNull findDisplay 87700) then {
            call ACME_fnc_ventPanelActivateSel;
            true
        } else { false };
    },
    {false},
    [0xF2, [false, false, false]],  // default: middle mouse button (CBA mouse code 0xf2)
    false
] call CBA_fnc_addKeybind;

// the laryngoscopy controls are not CBA keybinds, and they cannot be. CBA installs its keybind handlers on the
// mission display, and a dialog takes keyboard focus away from it, so none of them fire while the laryngoscopy
// screen is open. that is also why the arrow keys walked through the dialog's own controls instead of rocking
// the blade: nothing claimed them.
// the scheme installs as KeyDown and KeyUp handlers on the dialog itself, in fn_laryngoinit. that both receives
// the keys and consumes them, so the dialog stops navigating.
// rebinding is by dik code and needs no rebuild, for example ACME_laryngo_keyUp = 17. the defaults are listed
// there.
