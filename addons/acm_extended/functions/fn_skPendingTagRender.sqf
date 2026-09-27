/* B71 live optional-tag editor for the syringe currently being prepared.
   The MAIN Draw Syringe selector uses the same tag-face anchor as the working carousel editor: centered on the
   physical tag area immediately left of the barrel. It exists only on Draw Syringe. The dropdown is a long,
   dark clinical-purpose list and is always layered above the syringe/tag artwork. */
disableSerialization;
private _acmeCanvas = call ACME_fnc_uiCanvas;
_acmeCanvas params ["_uiX", "_uiY", "_uiW", "_uiH"];
private _d = findDisplay 84000;
if (isNull _d || {!(_d getVariable ["ACME_SK_PendingTagReady", false])}) exitWith {};

private _view = uiNamespace getVariable ["ACME_SK_View", "syringe"];
private _infusion = !((_d getVariable ["ACME_SK_Return", []]) isEqualTo []);
private _showSetup = (_view == "syringe"); // B68: never let stale infusion context hide the main Draw Syringe tag editor.

// B189 first-open focus invariant: do not create Draw-page tag controls after Body Map already owns the display.
// The deferred first-frame repair used to call skPendingTagEnsure before checking the page. On a fresh display,
// those late ctrlCreate calls could steal keyboard focus from Seconds to Push over immediately after the click.
if (!_showSetup) exitWith {
    private _listExisting = _d displayCtrl 84611;
    if (!isNull _listExisting) then {_listExisting lbSetCurSel -1; _listExisting ctrlShow false;};
    {private _c = _d displayCtrl _x; if (!isNull _c) then {_c ctrlShow false;};} forEach [84600,84601,84602,84603,84610];
};

call ACME_fnc_skPendingTagEnsure;
private _button = _d displayCtrl 84610;
private _list = _d displayCtrl 84611;
if (isNull _button) exitWith {};

_button ctrlShow true;
_button ctrlEnable true;

private _color = uiNamespace getVariable ["ACME_SK_PendingTagColor", "none"];
if !(_color isEqualType "") then {_color = "none";};
private _short = switch (_color) do {
    case "yellow_induction": {"Yellow"};
    case "orange_benzodiazepine": {"Orange"};
    case "blue_opioid": {"Light Blue"};
    case "blue_stripe_reversal": {"Blue / White"};
    case "red_paralytic": {"Red"};
    case "red_stripe_reversal": {"Red / White"};
    case "violet_vasopressor": {"Violet"};
    case "violet_stripe_hypotensive": {"Violet / White"};
    case "green_anticholinergic": {"Green"};
    case "gray_local_anesthetic": {"Gray"};
    case "salmon_antiemetic": {"Salmon / Pink"};
    case "white_saline_flush": {"White"};
    default {"None"};
};
_button ctrlSetText "Select Syringe Tag";
_button ctrlSetTooltip format ["Select or change this syringe tag. Current: %1. None removes the tag.", _short];

private _size = uiNamespace getVariable ["ACME_SK_CurSize", 10];
private _idx = ([10,5,3,1] find _size) max 0;
private _barrel = _d displayCtrl (84010 + 3 * _idx + 2);

// On first dialog frame ACM can finish laying out its native barrel after ACME creates runtime controls.
// Never let that race remove the button: use the last captured native rectangle until the real barrel is ready.
private _r = if (!isNull _barrel) then {+(ctrlPosition _barrel)} else {+(_d getVariable ["ACME_SK_CarouselNativeRect", []])};
if !(_r isEqualType [] && {count _r == 4} && {(_r select 2) > 0} && {(_r select 3) > 0}) then {
    private _fallbackH = safeZoneH * 0.46;
    private _fallbackW = _fallbackH * 0.19;
    _r = [_uiX + _uiW/2 - _fallbackW/2, safeZoneY + safeZoneH*0.14, _fallbackW, _fallbackH];
};
_r params ["_x","_y","_w","_h"];

// B78: Draw Syringe and Body Map now share the exact same selector geometry. Keep the compact width from the
// Draw view, but use the Body Map tag-face placement: centered under the physical tag area at the same vertical
// anchor. This is derived from the native syringe rectangle, so the result scales with resolution/UI scale.
private _gap = (4 * pixelW) max (_w * 0.010);
private _btnH = safeZoneH / 32;
private _textW = ctrlTextWidth _button;
private _btnW = ((_textW + 12*pixelW) max (safeZoneH*0.090)) min (safeZoneH*0.145);
private _tagCenterX = _x + _w*0.36;
private _btnX = _tagCenterX - _btnW/2;
private _btnY = _y + _h*0.575;
_btnX = (_btnX max (_uiX + 2*pixelW)) min (_uiX + _uiW - _btnW - 2*pixelW);
_button ctrlSetPosition [_btnX,_btnY,_btnW,_btnH];
_button ctrlSetFade 0;
_button ctrlSetTextColor [1,1,1,1];

// Immediate selection feedback without widening the button: a selected purpose tints the selector while the
// physical wrap appears on the syringe on the same render pass.
private _btnBg = switch (_color) do {
    case "yellow_induction": {[0.38,0.31,0.04,0.92]};
    case "orange_benzodiazepine": {[0.42,0.20,0.04,0.92]};
    case "blue_opioid": {[0.08,0.28,0.46,0.92]};
    case "blue_stripe_reversal": {[0.08,0.28,0.46,0.92]};
    case "red_paralytic": {[0.42,0.07,0.07,0.92]};
    case "red_stripe_reversal": {[0.42,0.07,0.07,0.92]};
    case "violet_vasopressor": {[0.30,0.14,0.40,0.92]};
    case "violet_stripe_hypotensive": {[0.30,0.14,0.40,0.92]};
    case "green_anticholinergic": {[0.08,0.30,0.15,0.92]};
    case "gray_local_anesthetic": {[0.24,0.24,0.24,0.92]};
    case "salmon_antiemetic": {[0.43,0.20,0.22,0.92]};
    case "white_saline_flush": {[0.36,0.36,0.36,0.92]};
    default {[0.05,0.05,0.05,0.82]};
};
_button ctrlSetBackgroundColor _btnBg;
_button ctrlShow true;
_button ctrlEnable true;
_button ctrlCommit 0;

// B72: the menu is LEFT-ALIGNED directly below the selector. Never flip it above/left. It is deliberately wide
// enough for the complete clinical-purpose descriptions and tall enough for the full list on normal aspect ratios.
private _menuW = (_uiW * 0.24) min (safeZoneH * 0.78);
private _menuX = _btnX max (_uiX + _gap);
_menuX = _menuX min (_uiX + _uiW - _menuW - _gap);
private _menuY = _btnY + _btnH + 2*pixelH;
private _maxBelow = (safeZoneY + safeZoneH - _gap - _menuY) max (safeZoneH*0.12);
private _menuH = (safeZoneH * 0.58) min _maxBelow;
if (!isNull _list) then {
    _list ctrlSetPosition [_menuX,_menuY,_menuW,_menuH];
    _list ctrlSetBackgroundColor [0.04,0.04,0.04,0.96];
    _list ctrlEnable true;
    _list ctrlCommit 0;
};

private _tag = _d displayCtrl 84600;
private _hasTag = !(_color in ["", "none"]);
if (_hasTag) then {
    _tag ctrlSetText format ["\acm_extended\ui\syringe_tags\%1mL\tag_overlay_%1mL_%2.paa", str _size, _color];
    _tag ctrlSetPosition _r;
    _tag ctrlSetTextColor [1,1,1,1];
    _tag ctrlShow true;
    _tag ctrlCommit 0;
} else {
    _tag ctrlShow false;
};

// B72: QEDaveMergens replaces the old handwriting family. If its Arma-native bitmap assets are not installed,
// keep the editable text visible with Caveat; the stored string is unchanged and QEDaveMergens takes over when
// its generated .fxy/.paa assets are present.
private _tagFont = _d getVariable ["ACME_SK_TagFont", ""];
if (_tagFont == "") then {
    _tagFont = if (fileExists "\acm_extended\ui\fonts\QEDaveMergens\QEDaveMergens96.fxy") then {"ACME_QEDaveMergens"} else {"Caveat"};
    _d setVariable ["ACME_SK_TagFont", _tagFont];
};

private _lines = uiNamespace getVariable ["ACME_SK_PendingTagText", ["","",""]];
if !(_lines isEqualType []) then {_lines = ["","",""];};
// B73: never repaint text into the edit control that currently owns keyboard focus. The 10 Hz main-page repaint
// used to ctrlSetText the old value between KeyDown and KeyUp, deleting every character the provider typed. While
// any pending-tag field is focused, the live controls become authoritative and are copied back into pending state.
private _focus = focusedCtrl _d;
private _focusIDC = if (isNull _focus) then {-1} else {ctrlIDC _focus};
private _editingPending = _focusIDC in [84601,84602,84603];
if (_editingPending) then {
    for "_n" from 0 to 2 do {_lines set [_n, ctrlText (_d displayCtrl (84601 + _n))];};
    uiNamespace setVariable ["ACME_SK_PendingTagText", _lines];
};
private _lineY = [0.443,0.480,0.517];
private _lineH = 0.038;
private _lineFontH = 0.031; // B78: restore the original handwritten tag size; taller controls prevent ascender/descender clipping.
for "_ln" from 0 to 2 do {
    private _e = _d displayCtrl (84601 + _ln);
    _e ctrlSetFont _tagFont;
    private _lineText = (_lines param [_ln,"",[""]]) select [0,25];
    if (_focusIDC != (84601 + _ln)) then {_e ctrlSetText _lineText;};
    _e ctrlSetPosition [_x + _w*0.247, _y + _h*(_lineY select _ln), _w*0.245, _h*_lineH];
    _e ctrlSetFontHeight (_h*_lineFontH);
    _e ctrlSetBackgroundColor [0,0,0,0];
    _e ctrlSetTextColor [0.08,0.08,0.08,1];
    _e ctrlShow _hasTag;
    _e ctrlEnable _hasTag;
    _e ctrlCommit 0;
};
