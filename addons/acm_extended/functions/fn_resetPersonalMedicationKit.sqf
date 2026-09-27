/* Reset hidden medication-container state when a player receives a fresh kit.
 *
 * Prepared syringes and opened-vial remainder are virtual state layered on top of physical inventory.
 * A wholesale kit reload can restore the consumed vial/syringe items without replacing the player object,
 * so these ledgers must be reset explicitly or the old virtual contents duplicate into the fresh loadout.
 */
params [["_unit", objNull, [objNull]]];
if (isNull _unit) exitWith {false};

[_unit, []] call ACME_fnc_narcStoreCommit;
[_unit, createHashMap] call ACME_fnc_openVialStoreCommit;
_unit setVariable ["ACME_narcStoreSerial", 0, false];

if (hasInterface && {_unit isEqualTo ACE_player}) then {
    [_unit] call ACME_fnc_vialLeaseRelease;

    uiNamespace setVariable ["ACME_SK_SelectedSyringeId", ""];
    uiNamespace setVariable ["ACME_SK_CarouselIdx", -1];
    uiNamespace setVariable ["ACME_SK_SelDrawn", -1];
    uiNamespace setVariable ["ACME_SK_SiteIdx", -1];
    uiNamespace setVariable ["ACME_SK_OpenCarouselId", ""];
    uiNamespace setVariable ["ACME_SK_PendingInjection", []];
    uiNamespace setVariable ["ACME_SK_VialHolder", objNull];
    uiNamespace setVariable ["ACME_SK_CompoundComponents", []];
    uiNamespace setVariable ["ACME_SK_CompoundVials", []];
    uiNamespace setVariable ["ACME_SK_WasteStage", ""];
    uiNamespace setVariable ["ACME_SK_DiscardArmedId", ""];
};

true
