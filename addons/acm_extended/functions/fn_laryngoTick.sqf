/* Keep the visual pass after every procedural early return. */
private _acmeNVArgs = if (isNil "_this") then {[]} else {_this};
_acmeNVArgs call {
// per-frame state machine for the intubation screen.
// the states run idle, scopeheld, inserted, lifting, exposed, tubeheld, tubing, done.
// the art is layered from the bundle. the mouth is a composited scene, and the blade, its lamp and the tube are
// overlay layers. there are two tools with two feels.
// the laryngoscope magnetises to the tongue. grabbed from the tray it trails the cursor sluggishly, through
// fn_laryngodrag, and is pulled toward the tongue seat. inside the magnet radius it snaps seated, which is the
// inserted state. then hold left mouse and pull up to lever the mouth open. the pull is heavy, across a long
// liftspan, and the trailed lag gives it weight. the tongue depresses through its five-state crossfade as the
// view opens.
// the et tube is click and drag. line the tip up on the cords, press, and drag it in. the push depth drives the
// six-stage crossfade, in fn_laryngotubeframes, so the tube reads as being fed through the cords. at full depth
// it seats on the cords, or goes down the esophagus off them, and the aim is locked at the click.
// there are three failure routes, all through fn_laryngoabort: the apnea clock, which is no view, a snatch that
// trips the jerk gate, which is trauma, and an esophageal pass. the grade, from fn_airwaygrade and read once
// at init, sets the lift needed, how much of the cords the view shows, and how small and high the target is.
disableSerialization;
private _dlg = uiNamespace getVariable ["ACME_laryngo_dlg", displayNull];
if (isNull _dlg) exitWith {};
if (uiNamespace getVariable ["ACME_laryngo_done", false]) exitWith {};

// clamped. every spring in here integrates explicitly, so one long frame, from an alt-tab, a hitch or a loading
// spike, multiplies velocity by a huge step and throws the tool across the screen. nothing needs more than a
// twentieth of a second of simulation in a single tick.
private _dt    = (diag_deltaTime min 0.05) max 0;
private _state = uiNamespace getVariable ["ACME_laryngo_state", "idle"];
private _held  = uiNamespace getVariable ["ACME_laryngo_held", ""];
// motion. this is the same shake the chest seal, iv and thoracostomy screens ride. uiShakeApply moves every
// control in the dialog as one object, and the same offset is folded into the rects below so the zones move
// with the picture. miss the cords in a hard bank because the airway moved, not because the hit test stayed
// behind the anatomy.
([_dlg, "ACME_Laryngo_ShakeBase"] call ACME_fnc_uiShakeApply) params ["_shdx", "_shdy"];

private _rect  = uiNamespace getVariable ["ACME_laryngo_rect", [0,0,0.2,0.2]];
_rect = [(_rect select 0) + _shdx, (_rect select 1) + _shdy, _rect select 2, _rect select 3];
_rect params ["_rx","_ry","_rw","_rh"];
(uiNamespace getVariable ["ACME_laryngo_frame", _rect]) params ["_fx","_fy","_fw","_fh"];

// which set of teeth is showing, every frame. it is driven off the casualty's own record, so someone who lost a
// tooth on a previous attempt still shows the cracked art the moment the screen opens on them again.
[_dlg] call ACME_fnc_laryngoTeethArt;
["tick"] call ACME_fnc_laryngoCuffDeflate;
_fx = _fx + _shdx; _fy = _fy + _shdy;
private _cur = uiNamespace getVariable ["ACME_laryngo_cur", [_rx+_rw/2, _ry+_rh/2]];
_cur params ["_cx","_cy"];

private _maxReveal  = uiNamespace getVariable ["ACME_laryngo_maxReveal", 1];
private _restReveal = uiNamespace getVariable ["ACME_laryngo_restReveal", 0.1];
private _liftThresh = uiNamespace getVariable ["ACME_laryngo_liftThresh", 0.6];
(uiNamespace getVariable ["ACME_laryngo_mouthZone", [0.5,0.5,0.42]]) params ["_mzx","_mzy","_mzr"];

// the tongue seat, which is where the blade magnetises to, and the magnet radius, both in screen coords.
// the seat is derived rather than hardcoded. what matters is where the blade tip lands, which is the vallecula,
// at frame v 0.4092 on the midline, from head v 0.1904 plus the head offset. the grip has to sit wherever puts
// the tip there, and because the blade is drawn scaled, the grip-to-tip distance scales with it. working the
// grip out from the tip every frame means a change to ACME_laryngo_bladeScale can never knock the blade off the
// mouth again, which is exactly what going to 1.65x did.
private _bScl = missionNamespace getVariable ["ACME_laryngo_bladeScale", 1.65];
(missionNamespace getVariable ["ACME_laryngo_gripUV", [0.4997, 0.5957]]) params ["_gpU", "_gpV"];
(missionNamespace getVariable ["ACME_laryngo_bladeTipUV", [0.4785, 0.8032]]) params ["_btpU", "_btpV"];
(missionNamespace getVariable ["ACME_laryngo_tipTargetUV", [0.4997, 0.4180]]) params ["_ttU", "_ttV"];
// horizontal is neutral. the blade art is already drawn on the midline, so correcting for the small x offset of
// the tip only pushed the whole instrument to the right. the grip goes on the centerline.
private _seatX = _fx + ((missionNamespace getVariable ["ACME_laryngo_seatU", 0.4997]) * _fw);
private _seatY = _fy + ((_ttV - ((_btpV - _gpV) * _bScl)) * _fh);
private _magR  = _fh * (missionNamespace getVariable ["ACME_laryngo_magnetRadius", 0.075]);

// whether the trailed tip is inside the mouth. it is still used for the lift-release fall-out check.
private _tipInMouth = {
    params ["_tx","_ty"];
    private _fx = (_tx - _rx) / (_rw max 1e-5);
    private _fy = (_ty - _ry) / (_rh max 1e-5);
    ((((_fx - _mzx)^2) + ((_fy - _mzy)^2)) <= (_mzr * _mzr))
};

// set ACME_LG_ToothContact from a tool position. it is true when the tip rides up onto the upper-incisor band
// across the top of the mouth. fn_laryngodrag reads this to decide whether a snatch chips teeth or tears soft
// tissue.
private _teethSet = {
    params ["_tx","_ty"];
    private _fx = (_tx - _rx) / (_rw max 1e-5);
    private _fy = (_ty - _ry) / (_rh max 1e-5);
    (missionNamespace getVariable ["ACME_LG_ToothBand", [0.210, 0.247, 0.087]]) params ["_tbYmin","_tbYmax","_tbHW"];
    uiNamespace setVariable ["ACME_LG_ToothContact",
        (_fy >= _tbYmin) && {_fy <= _tbYmax} && {(abs (_fx - 0.5)) <= _tbHW}];
};

// seat the blade and the lamp on the head rect, at offset 0. it is used once the blade is in the mouth.
// the blade is held by its handle.
// the call is [_gripx, _gripy, _liftFrac, _alpha, _lampalpha] call _bladePlace.
// the blade is positioned so that ACME_laryngo_gripUV, the point on the handle where a hand actually closes
// round it, sits exactly on the given screen point. it is measured off the reference composite, where the grip
// mark lands at u 0.4997 and v 0.5957 inside the blade texture. everything else about the blade follows from
// that, which is why the instrument now hangs off the cursor instead of floating below it.
// the blade is drawn on the frame rather than the head rect, because it is not part of the face.
private _bladePlace = {
    params ["_gx", "_gy", "_lf", "_a", "_lampA"];
    (missionNamespace getVariable ["ACME_laryngo_gripUV", [0.4997, 0.5957]]) params ["_guu", "_gvv"];
    // drawn larger than the face art, so the instrument reads at the size a laryngoscope actually is in a hand.
    private _bs = missionNamespace getVariable ["ACME_laryngo_bladeScale", 1.65];
    private _bw = _fw * _bs;
    private _bh = _fh * _bs;
    private _ox = _gx - (_guu * _bw);
    private _oy = _gy - (_gvv * _bh);
    {
        (_dlg displayCtrl _x) ctrlSetPosition [_ox, _oy, _bw, _bh];
        (_dlg displayCtrl _x) ctrlCommit 0;
    } forEach [87802, 87811, 87812];
    // the lamp is on the business end. its texture is a radial glow centerd at exactly [0.5,0.5] of its own canvas,
    // so drawing it on the rect of the blade put the glow in the middle of the frame, which is why it sat up on the
    // handle. it is offset here so its center lands on the blade tip instead.
    // because the glow is centerd at [0.5,0.5] of its own canvas, the control has to be placed so that its own
    // center lands on the blade tip. the old line subtracted half the blade size while drawing at frame size, which
    // is what threw the light up and to the left as soon as the blade was scaled.
    (missionNamespace getVariable ["ACME_laryngo_bladeTipUV", [0.4785, 0.8032]]) params ["_ltU", "_ltV"];
    private _lsc = missionNamespace getVariable ["ACME_laryngo_lightScale", 1.0];
    private _lw = _fw * _lsc;
    private _lh = _fh * _lsc;
    private _tipX = _ox + (_ltU * _bw);
    private _tipY = _oy + (_ltV * _bh);
    (_dlg displayCtrl 87809) ctrlSetPosition [_tipX - (_lw / 2), _tipY - (_lh / 2), _lw, _lh];
    (_dlg displayCtrl 87809) ctrlCommit 0;
    // a hard switch with no crossfade: master at rest, lever1 on the up arrow and lever2 on the down arrow.
    // registration matters. the three poses are not drawn on the same centerline. measured from the art, the handle
    // center sits at u 0.5002 on master, 0.5017 on lever1 and 0.4971 on lever2. anchoring all three at the same
    // grip point therefore made the instrument jump sideways every time the picture changed. each frame carries its
    // own nudge, so the handle stays put through a switch.
    private _bf = uiNamespace getVariable ["ACME_laryngo_bladePic", 0];
    // no offset. the fine fulcrum frames are drawn on exactly the same registration as the master, because every
    // one puts its tip at v 0.7969 on the same centerline, so they go in exactly the same place and any nudge at
    // all is wrong. every previous version of this shifted them, and that is what kept moving.
    // all six are repositioned every tick, so a hidden one can never hold a stale position.
    {
        private _cc = _dlg displayCtrl _x;
        _cc ctrlSetPosition [_ox, _oy, _bw, _bh];
        _cc ctrlCommit 0;
        _cc ctrlSetTextColor [1, 1, 1, (if (_forEachIndex == _bf) then {_a} else {0})];
    } forEach [87802, 87811, 87812, 87911, 87912, 87913];
    // the 87809 glow sprite stays hidden. it was a picture of brightness that lit nothing, and the bespoke pool
    // that replaced it caused more trouble than the problem it solved. darkness in this screen is handled by the
    // same cursor flashlight as every other minigame.
    (_dlg displayCtrl 87809) ctrlSetTextColor [1, 1, 1, 0];
    uiNamespace setVariable ["ACME_laryngo_bladeOrigin", [_ox, _oy]];
    // no ctrlSetAngle on the blade. side to side is out, and committing a rotation about an off-center origin every
    // frame was itself nudging the controls around.
};
// seated. the grip sits at the seat point, which is where the reference puts it when the blade is home.
private _seatBlade = {
    [_seatX, _seatY, 0, (missionNamespace getVariable ["ACME_laryngo_bladeAlphaHeld", 1]), 1] call _bladePlace
};

// the fulcrum, adjustable at any point.
// it is read before the state switch, so a medic can work the handle whenever the blade is in the airway:
// during the pull, while holding the view, and while the tube is going in. it was previously read during the
// initial pull only, which meant that once you were holding the view you were stuck with whatever angle you
// happened to stop on.
// it has to land on the right angle. every airway wants a specific amount of lever, rolled per patient across
// the full range, and finding it is the job. short of it the tongue has not cleared. past it the leverage rolls
// off the other side and the tongue comes back down, so overshooting is a real error rather than a free win.
private _stateNow = uiNamespace getVariable ["ACME_laryngo_state", "idle"];
if (_stateNow in ["inserted", "lifting", "held", "seated"]) then {
    private _pic = uiNamespace getVariable ["ACME_laryngo_bladePic", 0];
    private _rocking = false;
    if (diag_tickTime >= (uiNamespace getVariable ["ACME_laryngo_fulcNext", 0])) then {
        private _rate = missionNamespace getVariable ["ACME_laryngo_fulcStep", 0.16];
        if (uiNamespace getVariable ["ACME_laryngo_kFulcFwd", false]) then {
            _pic = (_pic + 1) min 5; _rocking = true;
            uiNamespace setVariable ["ACME_laryngo_fulcNext", diag_tickTime + _rate];
        };
        if (uiNamespace getVariable ["ACME_laryngo_kFulcBack", false]) then {
            _pic = (_pic - 1) max 0; _rocking = true;
            uiNamespace setVariable ["ACME_laryngo_fulcNext", diag_tickTime + _rate];
        };
    };
    uiNamespace setVariable ["ACME_laryngo_bladePic", _pic];
    private _tf = (uiNamespace getVariable ["ACME_laryngo_reveal", 0]) * 3;
    private _room = _tf >= ((missionNamespace getVariable ["ACME_laryngo_fulcGateFrame", 2]) - 0.05);
    // held back, not merely moved back. it used to count only on the frame an arrow key was actually pressed, so
    // leaving the handle levered on an unopened airway cost nothing at all as long as you stopped touching the
    // keys. the load is there for as long as the handle is there.
    uiNamespace setVariable ["ACME_laryngo_fulcUnsafe", ((_pic > 0) && {!_room})];
};

// grip strength.
// a fist on a laryngoscope under load does not stay closed. while the grip key is down, grip bleeds away, and a
// fading grip both pulls less and holds less. releasing for an instant and closing again restores it, because
// the keybind resets this to 1 on every press. release for longer and nothing is holding the airway at all.
private _gripHeld = uiNamespace getVariable ["ACME_laryngo_regripHeld", false];
private _gripStr = uiNamespace getVariable ["ACME_laryngo_gripStr", 0];
if (_gripHeld) then {
    _gripStr = (_gripStr - ((missionNamespace getVariable ["ACME_laryngo_gripFade", 0.42]) * _dt)) max 0;
} else {
    _gripStr = 0;
};
uiNamespace setVariable ["ACME_laryngo_gripStr", _gripStr];

// taking the laryngoscope out.
// the grip key is released constantly during the pulse rhythm, so a brief release is a re-grip and a sustained
// one is you withdrawing the blade. anything past ACME_laryngo_scopeOutTime counts as withdrawing.
// doing that with a tube half in is how you drag it back out of the cords. it must be fully home, at stage 8
// with the depth at 1, before the blade comes out, or the tube tears the airway on the way.
if ((uiNamespace getVariable ["ACME_laryngo_state", "idle"]) == "seated") then {
    private _rel = uiNamespace getVariable ["ACME_laryngo_relSince", -1];
    if (uiNamespace getVariable ["ACME_laryngo_regripHeld", false]) then {
        uiNamespace setVariable ["ACME_laryngo_relSince", -1];
    } else {
        if (_rel < 0) then { uiNamespace setVariable ["ACME_laryngo_relSince", diag_tickTime]; }
        else {
            if ((diag_tickTime - _rel) >= (missionNamespace getVariable ["ACME_laryngo_scopeOutTime", 0.55])) then {
                uiNamespace setVariable ["ACME_laryngo_relSince", -1];
                // wherever you left it is where it stays. taking the blade out no longer demands the tube be buried to maximum.
                // past the first three frames it is through the cords and it is staying there, so the chosen depth of the medic
                // is respected rather than overruled.
                // the first three frames are the exception, and they have to be. that is a tube sitting in the larynx rather
                // than the trachea, and pulling the blade on that drags it straight back out.
                private _fr8 = 1 + (round ((uiNamespace getVariable ["ACME_laryngo_tubeDepth", 0]) * 7));
                if (_fr8 >= (uiNamespace getVariable ["ACME_laryngo_requiredSeatFrame", missionNamespace getVariable ["ACME_ETT_MinSeatFrame", 5]])) then {
                    // the tube is home, so the blade has nothing left to do. it comes out, goes back in the tray by itself, and the
                    // mouth closes around the tube. the cuff is next, then the collar.
                    uiNamespace setVariable ["ACME_laryngo_state", "cuff"];
                    uiNamespace setVariable ["ACME_laryngo_airwayOpen", false];
                    uiNamespace setVariable ["ACME_laryngo_held", ""];
                    uiNamespace setVariable ["ACME_laryngo_bladeLocked", false];
                    uiNamespace setVariable ["ACME_laryngo_bladePic", 0];
                    uiNamespace setVariable ["ACME_laryngo_lift", 0];
                    uiNamespace setVariable ["ACME_laryngo_reveal", 0];
                    [] call ACME_fnc_laryngoRefreshSlots;
                    playSound "ACME_VentClick";
                } else {
                    ["trauma"] call ACME_fnc_laryngoAbort;
                };
            };
        };
    };
};

// depth.
// this is how far the blade is in, on the wheel, in fn_laryngoscroll. it has no score of its own: it multiplies
// the two systems that already exist. in the vallecula the lift engages the hyoepiglottic ligament and pays
// full value. short of it the tip is on the tongue base and lifting only rolls the tongue. past it the blade is
// over the epiglottis and the view closes again. either way the same pull buys less view and loads the teeth
// harder, so depth is felt through the lift and the view rather than through a meter.
private _depth = uiNamespace getVariable ["ACME_laryngo_depth", 0.5];
(uiNamespace getVariable ["ACME_laryngo_depthBand", [0.52, 0.68]]) params ["_dbLo", "_dbHi"];
private _depthQual = switch (true) do {
    case (_depth < _dbLo): { 1 - (((_dbLo - _depth) / (_dbLo max 1e-5)) min 1) };
    case (_depth > _dbHi): { 1 - (((_depth - _dbHi) / ((1 - _dbHi) max 1e-5)) min 1) };
    default { 1 };
};
_depthQual = (0.12 + (0.88 * (_depthQual max 0))) min 1;
uiNamespace setVariable ["ACME_laryngo_depthQual", _depthQual];

// the tube, held by the tip.
// the tip is where your fingers are, so the tip is what follows the cursor, and the length of the tube hangs off
// it. there are two springs.
// 1. the tip itself lags the cursor slightly, so the tube feels held rather than welded to the pointer.
// 2. the tube swings about the tip. measured from the art, the tube hangs almost straight up from the tip, at
// 4.4 percent off vertical, so sideways movement of the tip torques it. drag left and the top is left behind to
// the right, then it swings back through center and overshoots before settling. it is underdamped on purpose,
// at a damping ratio of about 0.5, because the overshoot is what makes it read as a weighted object on the end
// of your fingers rather than a sprite being slid around.
// it returns the settled tip position, so the caller can read the aim off it.
private _tubeTick = {
    params ["_targetX", "_targetY"];
    private _tp = uiNamespace getVariable ["ACME_laryngo_tubeTipPos", []];
    if (count _tp < 2) then { _tp = [_targetX, _targetY]; };
    _tp params ["_px", "_py"];

    private _f = 1 - (exp (-((missionNamespace getVariable ["ACME_laryngo_tubeTipLag", 18]) * _dt)));
    private _nx = _px + ((_targetX - _px) * _f);
    private _ny = _py + ((_targetY - _py) * _f);
    private _vx = if (_dt > 1e-5) then { (_nx - _px) / _dt } else { 0 };
    uiNamespace setVariable ["ACME_laryngo_tubeTipPos", [_nx, _ny]];

    private _ang = uiNamespace getVariable ["ACME_laryngo_tubeAng", 0];
    private _av  = uiNamespace getVariable ["ACME_laryngo_tubeAngVel", 0];
    // the sign is flipped. the anchor moved from the connector end to the tip, which is the other end of the tube,
    // so the length now hangs off the opposite side of the held point and has to trail the opposite way.
    private _acc = ((missionNamespace getVariable ["ACME_laryngo_tubeSwingDrive", 540]) * _vx)
                 - ((missionNamespace getVariable ["ACME_laryngo_tubeSwingK", 55]) * _ang)
                 - ((missionNamespace getVariable ["ACME_laryngo_tubeSwingDamp", 14]) * _av);
    _av = _av + (_acc * _dt);
    _ang = _ang + (_av * _dt);
    private _lim = missionNamespace getVariable ["ACME_laryngo_tubeSwingMax", 14];
    _ang = (_ang max (-_lim)) min _lim;
    uiNamespace setVariable ["ACME_laryngo_tubeAng", _ang];
    uiNamespace setVariable ["ACME_laryngo_tubeAngVel", _av];

    [_dlg, _nx, _ny, _ang] call ACME_fnc_laryngoTubePose;
    [_nx, _ny]
};

// holding the airway open by hand.
// this is shared by every state where the view is already open. the lift is no longer locked: it bleeds away,
// and each tap of the re-grip key tops it back up. the bump is eased in here rather than applied on the
// keypress, so the blade rises in small smooth increments instead of jumping. run this in held, tubeheld and
// tubing.
private _regripTick = {
    // ctrl alone holds it. w is not a requirement, it is a nudge. the blade sags slowly the whole time it is in
    // there, and w eases it back up while s lets it down, so the height is under fine control instead of being a
    // switch that is either fully on or falling. that is also what makes the last of the fulcrum reveal worth
    // aiming for rather than something you hold by brute force.
    if (!(uiNamespace getVariable ["ACME_laryngo_airwayOpen", false])) exitWith {};
    private _thr  = uiNamespace getVariable ["ACME_laryngo_liftThresh", 0.6];
    private _hold = uiNamespace getVariable ["ACME_laryngo_regripHeld", false];
    private _lf   = uiNamespace getVariable ["ACME_laryngo_lift", _thr];
    private _lv   = uiNamespace getVariable ["ACME_laryngo_liftVel", 0];

    // the same incremental pull the lift itself uses, so w and s feel identical either side of the handover.
    private _pr = missionNamespace getVariable ["ACME_laryngo_pullRate", 3.4];
    if (uiNamespace getVariable ["ACME_laryngo_kUp", false])   then { _lv = _lv + (_pr * _dt); };
    if (uiNamespace getVariable ["ACME_laryngo_kDown", false]) then { _lv = _lv - (_pr * _dt); };
    _lv = _lv * (exp (-((missionNamespace getVariable ["ACME_laryngo_pullDamp", 4.5]) * _dt)));
    uiNamespace setVariable ["ACME_laryngo_liftVel", _lv];

    // a slow sag while gripped, and a real fall once the fist opens.
    private _sag = if (_hold) then {
        missionNamespace getVariable ["ACME_laryngo_holdSag", 0.045]
    } else {
        missionNamespace getVariable ["ACME_laryngo_holdDecay", 0.30]
    };
    _lf = (((_lf + (_lv * _dt)) - (_sag * _dt)) max 0) min _thr;
    uiNamespace setVariable ["ACME_laryngo_lift", _lf];

    private _pic = uiNamespace getVariable ["ACME_laryngo_bladePic", 0];
    private _need = uiNamespace getVariable ["ACME_laryngo_fulcNeed", 3];
    private _frac = (_lf / (_thr max 1e-5)) min 1;
    ([_frac, _depthQual, _pic, _need] call ACME_fnc_laryngoView) params ["_shown", "_viewOK"];
    uiNamespace setVariable ["ACME_laryngo_fulcOK", _viewOK];
    uiNamespace setVariable ["ACME_laryngo_reveal", _shown];

    // let it fall far enough and the airway has closed on you. it is recoverable, by going back to working the
    // lift.
    if (_lf < (_thr * (missionNamespace getVariable ["ACME_laryngo_collapseFrac", 0.45]))) then {
        uiNamespace setVariable ["ACME_laryngo_state", "lifting"];
        uiNamespace setVariable ["ACME_laryngo_airwayOpen", false];
    };
};
// apnea clock.
private _started = uiNamespace getVariable ["ACME_laryngo_attemptStarted", false];
if (!_started && {_state in ["inserted","lifting","held","tubeHeld","tubing"]}) then {
    _started = true;
    uiNamespace setVariable ["ACME_laryngo_attemptStarted", true];
};
if (_started) then {
    private _clk = (uiNamespace getVariable ["ACME_laryngo_attemptClock", 0]) + _dt;
    uiNamespace setVariable ["ACME_laryngo_attemptClock", _clk];
    // the clock still runs and still matters to the patient, and it no longer throws the medic out of the screen.
    // deciding when to stop is the medic's call, not the game's.
};
if (uiNamespace getVariable ["ACME_laryngo_done", false]) exitWith {};

// the blade picture and the lean both return to rest whenever nobody is actively working the blade.
if !(_state in ["lifting","held","seated"]) then { uiNamespace setVariable ["ACME_laryngo_bladePic", 0]; };
if (_state != "lifting") then {
    uiNamespace setVariable ["ACME_laryngo_bladeYaw",
        (uiNamespace getVariable ["ACME_laryngo_bladeYaw", 0]) * (exp (-(6 * _dt)))];
};

switch (_state) do {
    case "idle": {
        uiNamespace setVariable ["ACME_laryngo_reveal", 0];
        [_seatX, _seatY, 0, 0, 0] call _bladePlace;
        { (_dlg displayCtrl _x) ctrlSetTextColor [1,1,1,0]; } forEach [87900,87901,87902,87903,87904,87905,87906,87907,87908];
        ([_dlg] call ACME_fnc_laryngoTeethArt);
    };

    case "scopeHeld": {
        // the blade is in hand, trailing and magnetising to the tongue. the offset from the seat shrinks fast inside the
        // magnet radius, so the blade is pulled onto the tongue, and a small clamp keeps it from flying off to the
        // tray. the lamp is off until it seats. there is no jerk gate out here.
        ([_cx, _cy, "scope"] call ACME_fnc_laryngoDrag) params ["_tx","_ty"];
        uiNamespace setVariable ["ACME_LG_ToothContact", false];
        uiNamespace setVariable ["ACME_laryngo_reveal", 0];

        private _oX = _tx - _seatX;
        private _oY = _ty - _seatY;
        private _dist = sqrt ((_oX*_oX) + (_oY*_oY));
        private _mag = if (_dist <= _magR && {_magR > 1e-5}) then { (_dist / _magR) ^ (missionNamespace getVariable ["ACME_laryngo_magnetPow", 1.6]) } else { 1 };
        // the grip is drawn where the hand is, pulled toward the seat as it gets close.
        [_seatX + (_oX * _mag), _seatY + (_oY * _mag), 0, 1, 0] call _bladePlace;

        if (_dist <= _magR * (missionNamespace getVariable ["ACME_laryngo_snapFrac", 0.35])) then {
            call _seatBlade;
            uiNamespace setVariable ["ACME_laryngo_state", "inserted"];
        };
    };

    case "inserted": {
        // the blade is seated on the tongue with the lamp on. the jerk gate is live. a press and hold, in
        // fn_laryngoclick, begins the lift. pulling the trailed tip well clear of the seat, outside the magnet radius,
        // un-seats it.
        (uiNamespace getVariable ["ACME_LG_DragPt", [_cx,_cy]]) params ["_ppx","_ppy"];
        [_ppx, _ppy] call _teethSet;
        ([_cx, _cy, "scope"] call ACME_fnc_laryngoDrag) params ["_tx","_ty"];
        // seated and not yet lifting. the tongue stays exactly where it was, because a blade resting on a tongue has
        // not displaced it, and starting the crossfade here made the airway appear to open on its own.
        uiNamespace setVariable ["ACME_laryngo_reveal", 0];
        call _seatBlade;
        uiNamespace setVariable ["ACME_laryngo_pryPressure", 0];
        uiNamespace setVariable ["ACME_laryngo_pryReveal", 0];
        ([_dlg] call ACME_fnc_laryngoTeethArt);
        // closing your fist on it is what starts the lift. nothing else does, now that the mouse is only aiming.
        if (uiNamespace getVariable ["ACME_laryngo_holding", false]) then {
            uiNamespace setVariable ["ACME_laryngo_state", "lifting"];
        };
        // the mouse is locked out. the moment the blade is gripped it is handed to the left hand and the pointer stops
        // having any say over it for the rest of the attempt. a brief release is part of the re-grip rhythm, so keying
        // this off the live grip flag left a window every pulse where a mouse move would flick the blade back out of
        // the mouth. the latch only clears when the blade goes back in the tray.
        if (uiNamespace getVariable ["ACME_laryngo_holding", false]) then {
            // the first grip is when the blade goes in, and that is the moment the sympathetic response fires. it happens
            // once per attempt, because the surge is the stimulus of instrumenting the airway rather than a per-frame
            // cost.
            if (!(uiNamespace getVariable ["ACME_laryngo_bladeLocked", false])) then {
                [uiNamespace getVariable ["ACME_laryngo_patient", objNull]] call ACME_fnc_laryngoIcpSurge;
            };
            uiNamespace setVariable ["ACME_laryngo_bladeLocked", true];
        };
        if (!(uiNamespace getVariable ["ACME_laryngo_bladeLocked", false])) then {
            private _dist = sqrt (((_tx-_seatX)^2) + ((_ty-_seatY)^2));
            if (_dist > _magR) then { uiNamespace setVariable ["ACME_laryngo_state", "scopeHeld"]; };
        };
    };

    case "lifting": {
        // the mouse is not involved in this state at all. it is not read, not trailed and not tested. the blade is on
        // the keyboard now and the pointer belongs to the other hand.
        // the trailing drag used to be called here for the tooth-contact test, and the jerk gate inside it fired on the
        // huge cursor jump you make when you go to click the tray, which is how reaching for the tube could injure the
        // airway. tooth contact is computed from the blade's own geometry instead.
        private _holding = uiNamespace getVariable ["ACME_laryngo_holding", false];
        private _lift    = uiNamespace getVariable ["ACME_laryngo_lift", 0];

        (missionNamespace getVariable ["ACME_laryngo_liftAxis", [0, -1]]) params ["_axX","_axY"];
        private _axN = sqrt ((_axX*_axX) + (_axY*_axY));
        if (_axN < 1e-6) then { _axX = 0; _axY = -1; _axN = 1; };
        _axX = _axX / _axN; _axY = _axY / _axN;

        // let go of the grip and the tongue pushes the blade straight back down.
        if (!_holding) then {
            _lift = (_lift - ((missionNamespace getVariable ["ACME_laryngo_liftDecay", 1.2]) * _dt)) max 0;
            uiNamespace setVariable ["ACME_laryngo_lift", _lift];
            uiNamespace setVariable ["ACME_laryngo_liftVel", 0];
            // it does not depend on the mouse. the blade is seated, so where the pointer happens to be is irrelevant, and
            // dropping out of the lift because the medic moved the mouse toward the tray was the reason you could not go
            // and fetch the tube while holding the blade.
            if (_lift <= 0.001) then {
                uiNamespace setVariable ["ACME_laryngo_state", "inserted"];
            };
        };

        // the blade is held, and you work it with the other hand.
        // ctrl keeps your fist closed on it. w and s add small smooth increments of pull that decay away, so the blade
        // creeps rather than jumps and tapping works as well as holding. a and d fight the roll. the whole time you
        // are pulling, the instrument wants to fall to one side, and which side is chosen at random and changed every
        // second or two, so keeping it straight is an active job rather than a thing that happens.
        private _liftFrac = (_lift / (_liftThresh max 1e-5)) min 1;
        private _gsNow = ((uiNamespace getVariable ["ACME_laryngo_gripStr", 0]) max 0) min 1;

        // w and s give an incremental pull with decay.
        private _lv = uiNamespace getVariable ["ACME_laryngo_liftVel", 0];
        // faster and fuller, and the tongue pushes back as it runs out of give, so the last of the travel feels like it
        // is under pressure rather than sliding.
        private _pr = missionNamespace getVariable ["ACME_laryngo_pullRate", 3.4];
        private _near = (_lift / (_liftThresh max 1e-5)) min 1;
        _pr = _pr * (1 - (0.45 * (_near ^ 2)));
        if (uiNamespace getVariable ["ACME_laryngo_kUp", false])   then { _lv = _lv + (_pr * _dt); };
        if (uiNamespace getVariable ["ACME_laryngo_kDown", false]) then { _lv = _lv - (_pr * _dt); };
        _lv = _lv * (exp (-((missionNamespace getVariable ["ACME_laryngo_pullDamp", 4.5]) * _dt)));
        uiNamespace setVariable ["ACME_laryngo_liftVel", _lv];

        // side to side and the random roll are out for now, so the lift is one clean axis while the rest of it is
        // settled. ACME_laryngo_kLeft and kright are still bound and still read as false, so putting the roll back is a
        // matter of restoring this block.
        private _yawLoss = 1;
        uiNamespace setVariable ["ACME_laryngo_bladeYaw", 0];

        // the arrows are handled once, before the state switch, so a medic can adjust the fulcrum at any point the
        // blade is in there rather than only while the initial pull happens.

        // apply.
        _lift = ((_lift + (_lv * _yawLoss * _dt)) max 0) min 1.2;
        uiNamespace setVariable ["ACME_laryngo_lift", _lift];
        _liftFrac = (_lift / (_liftThresh max 1e-5)) min 1;

        private _travel = _fh * (missionNamespace getVariable ["ACME_laryngo_liftTravel", 0.045]);
        // the artwork carries the fulcrum entirely, so the anchor does not move for it at all.
        private _gX = _seatX + (_axX * _travel * _liftFrac);
        private _gY = _seatY + (_axY * _travel * _liftFrac);
        [_gX, _gY, _liftFrac, (missionNamespace getVariable ["ACME_laryngo_bladeAlphaHeld", 1]), 1] call _bladePlace;
        private _bOX = _gX - _seatX;
        private _bOY = _gY - _seatY;

        // is the blade shaft riding on the upper incisors?
        // this is the perpendicular distance from the incisor point to the blade shaft, taken as a segment from the
        // blade tip through the pivot and on up the handle. it stays correct wherever the blade sits on screen, which a
        // fixed screen band does not.
        (missionNamespace getVariable ["ACME_laryngo_bladeTipUV", [0.4785, 0.8032]]) params ["_btU","_btV"];
        (missionNamespace getVariable ["ACME_laryngo_bladePivotUV", [0.5000, 0.7764]]) params ["_bpU","_bpV"];
        (missionNamespace getVariable ["ACME_laryngo_incisorPt", [0.502, 0.223]]) params ["_icU","_icV"];
        (uiNamespace getVariable ["ACME_laryngo_bladeOrigin", [_fx, _fy]]) params ["_bogX", "_bogY"];
        private _bsc = missionNamespace getVariable ["ACME_laryngo_bladeScale", 1.65];
        private _tipSX = _bogX + (_btU * _fw * _bsc);
        private _tipSY = _bogY + (_btV * _fh * _bsc);
        private _endSX = _bogX + (_bpU * _fw * _bsc) + (_axX * _fh * 0.55);
        private _endSY = _bogY + (_bpV * _fh * _bsc) + (_axY * _fh * 0.55);
        private _icX = _rx + (_icU * _rw);
        private _icY = _ry + (_icV * _rh);
        private _abX = _endSX - _tipSX; private _abY = _endSY - _tipSY;
        private _apX = _icX - _tipSX;   private _apY = _icY - _tipSY;
        private _ab2 = (((_abX*_abX) + (_abY*_abY))) max 1e-9;
        private _tSeg = ((((_apX*_abX) + (_apY*_abY)) / _ab2) max 0) min 1;
        private _qX = _tipSX + (_abX * _tSeg);
        private _qY = _tipSY + (_abY * _tSeg);
        private _cDist = sqrt ((((_icX-_qX)^2) + ((_icY-_qY)^2)) max 0);
        private _contact = _cDist <= (_rh * (missionNamespace getVariable ["ACME_laryngo_incisorRadius", 0.020]));

        // tooth load, and it scales with how hard you are levering.
        // rocking the handle back before the tongue is out of the way puts the heel of the blade on the upper incisors.
        // how fast that ends in a fracture depends entirely on how far back you have taken it, which is what the fine
        // fulcrum stages are for.
        // Increasing fulcrum load shortens the correction window. No pre-break warning sound.
        // there is no contact test on this path. levering back before there is room is the heel on the teeth, by
        // definition, so there is nothing to check for.
        private _fStage = if (uiNamespace getVariable ["ACME_laryngo_fulcUnsafe", false]) then {
            (uiNamespace getVariable ["ACME_laryngo_bladePic", 0]) max 0 min 5
        } else { 0 };
        private _harm = if (_fStage > 0) then {
            (missionNamespace getVariable ["ACME_laryngo_fulcHarm", [0.033, 0.052, 0.081, 0.130, 0.217]]) select (_fStage - 1)
        } else { 0 };
        private _perpN = _harm * _dt;
        private _press = uiNamespace getVariable ["ACME_laryngo_pryPressure", 0];
        if (_holding && {_perpN > 0}) then {
            _press = _press + (_perpN * (missionNamespace getVariable ["ACME_laryngo_pryGain", 1.0]) * (2 - _depthQual));
        } else {
            _press = (_press - ((missionNamespace getVariable ["ACME_laryngo_pryDecay", 0.35]) * _dt)) max 0;
        };
        private _warn = missionNamespace getVariable ["ACME_laryngo_pryWarn", 0.10];
        private _chip = missionNamespace getVariable ["ACME_laryngo_pryChip", 0.26];
        private _warned = uiNamespace getVariable ["ACME_laryngo_pryWarned", false];

        // Silent correction window: damage accumulates only while the handle remains loaded.
        if (_press >= _warn && {!_warned}) then {
            uiNamespace setVariable ["ACME_laryngo_pryWarned", true];
        };
        if (_press < (_warn * 0.6)) then { uiNamespace setVariable ["ACME_laryngo_pryWarned", false]; };
        if (_press >= _chip) then {
            _press = _warn * 0.5;
            uiNamespace setVariable ["ACME_laryngo_pryWarned", false];
            [uiNamespace getVariable ["ACME_laryngo_patient", objNull]] call ACME_fnc_laryngoTeeth;
            uiNamespace setVariable ["ACME_laryngo_teethBroken", true];
        };
        uiNamespace setVariable ["ACME_laryngo_pryPressure", _press];
        // No tint or warning creak. A real fracture changes the persistent teeth artwork.

        // prying closes the view, because the tip levers down and the epiglottis drops in.
        private _pryRev = uiNamespace getVariable ["ACME_laryngo_pryReveal", 0];
        if (_holding) then {
            _pryRev = _pryRev + (_perpN * (missionNamespace getVariable ["ACME_laryngo_pryViewGain", 1.2]));
        };
        _pryRev = ((_pryRev - ((missionNamespace getVariable ["ACME_laryngo_pryViewDecay", 0.5]) * _dt)) max 0)
                    min (missionNamespace getVariable ["ACME_laryngo_pryViewMax", 0.55]);
        uiNamespace setVariable ["ACME_laryngo_pryReveal", _pryRev];

        // the pull stops one frame short, on purpose. squashing the tongue gets you to the second-to-last state and no
        // further, and the last one belongs to the fulcrum. letting the pull run all the way there and then handing
        // over to the held state is what made it play the final frame and then jump back a frame.
        private _gateCap = ((missionNamespace getVariable ["ACME_laryngo_fulcGateFrame", 2]) / 3);
        private _reveal = (_restReveal + ((_maxReveal - _restReveal) * _liftFrac * _depthQual)) min _maxReveal min _gateCap;
        _reveal = (_reveal - (_pryRev * (_maxReveal - _restReveal))) max 0;
        uiNamespace setVariable ["ACME_laryngo_reveal", _reveal];

        // there is no progress bar. the appearing cords are the readout, because how much of the glottis the lift has
        // bought you is the thing a laryngoscopist actually reads, and cormack-lehane already governs how much of it
        // shows. the view will not lock while it is being pried shut, so a pry cannot be muscled into a success.
        if (_lift >= (_liftThresh * 0.80) && {_pryRev < (missionNamespace getVariable ["ACME_laryngo_pryLockBlock", 0.15])}) then {
            uiNamespace setVariable ["ACME_laryngo_state", "held"];
            // where the blade ends up is where the left hand now holds it, for as long as the rhythm lasts.
            uiNamespace setVariable ["ACME_laryngo_bladeGrip", [_gX, _gY]];
            uiNamespace setVariable ["ACME_laryngo_airwayOpen", true];
            // this does not clear the grip flag. the key is physically still down, and saying otherwise flipped the decay to
            // the released rate the instant you reached a full lift, so the view began collapsing fast while you were still
            // holding it. the KeyUp handler owns that flag.
            ([_dlg] call ACME_fnc_laryngoTeethArt);
            playSound "ACME_VentClick";
            [] call ACME_fnc_laryngoRefreshSlots;
        };
    };

    case "held": {
        // the view is open and nothing is holding it but you. the lift no longer locks: it bleeds away, and each tap of
        // the re-grip key, fn_laryngoregrip, restores a little. it is eased in here so the blade nudges up in small
        // smooth steps rather than snapping. keep the rhythm and the view holds. this is what frees the mouse for the
        // tube.
        call _regripTick;
        (uiNamespace getVariable ["ACME_laryngo_bladeGrip", [_seatX, _seatY]]) params ["_hgX", "_hgY"];
        [_hgX, _hgY, 1, (missionNamespace getVariable ["ACME_laryngo_bladeAlphaHeld", 1]), 1] call _bladePlace;
        { (_dlg displayCtrl _x) ctrlSetTextColor [1,1,1,0]; } forEach [87900,87901,87902,87903,87904,87905,87906,87907,87908];
    };

    case "seated": {
        // the tube is home in the cords and the blade is still in the mouth holding the view. the only thing left is
        // taking the blade out cleanly: let go of the grip key and stay off it.
        uiNamespace setVariable ["ACME_laryngo_reveal", _maxReveal];
        (uiNamespace getVariable ["ACME_laryngo_bladeGrip", [_seatX, _seatY]]) params ["_sgX", "_sgY"];
        [_sgX, _sgY, 1, (missionNamespace getVariable ["ACME_laryngo_bladeAlphaHeld", 1]), 1] call _bladePlace;
        [_dlg, (uiNamespace getVariable ["ACME_laryngo_tubeDepth", 1])] call ACME_fnc_laryngoTubeFrames;

        // the blade falls, then it leaves. let go of ctrl and w and the lift decays on its own, which it already did.
        // what was missing is that reaching the bottom meant nothing. the old rule was a 0.55 s timer on the grip being
        // released, which fired while the blade was still halfway up and did not match what the medic was doing with
        // their hands.
        // it is the obvious thing now: no grip, no lift, blade all the way down, so it comes out and goes back in the
        // tray. the tube stays exactly where it was placed, at whatever depth that was.
        private _lift = uiNamespace getVariable ["ACME_laryngo_lift", 0];
        if (_gripHeld || {_lift > 0.02}) then {
            uiNamespace setVariable ["ACME_laryngo_downSince", -1];
        } else {
            private _down = uiNamespace getVariable ["ACME_laryngo_downSince", -1];
            if (_down < 0) then {
                uiNamespace setVariable ["ACME_laryngo_downSince", CBA_missionTime];
            } else {
                if ((CBA_missionTime - _down) >= (missionNamespace getVariable ["ACME_laryngo_bladeOutSec", 0.35])) then {
                    uiNamespace setVariable ["ACME_laryngo_downSince", -1];
                    uiNamespace setVariable ["ACME_laryngo_held", ""];
                    uiNamespace setVariable ["ACME_laryngo_lift", 0];
                    uiNamespace setVariable ["ACME_laryngo_liftVel", 0];
                    uiNamespace setVariable ["ACME_laryngo_bladePic", 0];
                    uiNamespace setVariable ["ACME_laryngo_bladeLocked", false];
                    uiNamespace setVariable ["ACME_laryngo_state", "cuff"];
                    ["stow"] call ACME_fnc_laryngoFlash;
                    [] call ACME_fnc_laryngoRefreshSlots;
                };
            };
        };
    };

    case "collar": {
        // the blade is out and the tube is in. take the collar from the tray. the shared in-hand block below handles
        // the cursor-follow and the magnetise, so this only holds the scene steady.
        uiNamespace setVariable ["ACME_laryngo_reveal", _maxReveal];
        [_seatX, _seatY, 1, 0, 0] call _bladePlace;
        [_dlg, (uiNamespace getVariable ["ACME_laryngo_tubeDepth", 1])] call ACME_fnc_laryngoTubeFrames;
    };

    case "cuff": {
        // the collar is on, the blade is out and the tube is secured. all that is left is putting air in the cuff. the
        // syringe comes out of the tray and magnetises onto the pilot balloon, whose position was measured off the
        // marked reference at frame uv [0.5164, 0.4112].
        uiNamespace setVariable ["ACME_laryngo_reveal", _maxReveal];
        [_seatX, _seatY, 1, 0, 0] call _bladePlace;
        [_dlg, (uiNamespace getVariable ["ACME_laryngo_tubeDepth", 1])] call ACME_fnc_laryngoTubeFrames;
        // the syringe is a floating tool now, handled in the shared in-hand block below.
    };

    case "migrated": {
        // feeding a displaced tube back to depth. there is nothing to lift and nothing to aim, because it is already
        // through the cords and has just slid out. wheel it home and the collar step follows.
        uiNamespace setVariable ["ACME_laryngo_reveal", 0];
        uiNamespace setVariable ["ACME_laryngo_tubeCanFeed", true];
        private _d = uiNamespace getVariable ["ACME_laryngo_tubeDepth", 1];
        private _pt = uiNamespace getVariable ["ACME_laryngo_patient", objNull];
        // B204: the laryngoscopy PFH runs every rendered frame. Tube migration is therefore a local visual until a
        // bounded owner-authoritative snapshot is due. The old path broadcast depth/frame/mainstem every frame from
        // the provider, which is catastrophic at 60-144 FPS on a remote-owned casualty.
        private _fr9 = 1 + (round (_d * 7));
        private _ideal9 = uiNamespace getVariable ["ACME_laryngo_idealFrame", 8];
        private _deep9 = _fr9 > _ideal9;
        private _syncNow = diag_tickTime;
        private _syncNext = uiNamespace getVariable ["ACME_laryngo_migrationSyncNext", 0];
        private _syncLast = uiNamespace getVariable ["ACME_laryngo_migrationSyncLast", [-1, -1, false]];
        private _changed9 = abs (_d - (_syncLast param [0, -1])) >= 0.015
            || {_fr9 != (_syncLast param [1, -1])}
            || {_deep9 != (_syncLast param [2, false])};
        if (!isNull _pt && {_changed9} && {_syncNow >= _syncNext}) then {
            [_pt, "placement", [_d, _fr9, _deep9]] call ACME_fnc_ettMigrationStateCommit;
            uiNamespace setVariable ["ACME_laryngo_migrationSyncLast", [_d, _fr9, _deep9]];
            uiNamespace setVariable ["ACME_laryngo_migrationSyncNext", _syncNow + 0.20];
        };
        if (_d >= 0.999) then {
            uiNamespace setVariable ["ACME_laryngo_state", "collar"];
            uiNamespace setVariable ["ACME_laryngo_tubeInHand", false];
            uiNamespace setVariable ["ACME_laryngo_held", ""];
            if (!isNull _pt) then {
                private _finalFrame = 8;
                private _finalDeep = _finalFrame > (uiNamespace getVariable ["ACME_laryngo_idealFrame", 8]);
                [_pt, "placement", [1, _finalFrame, _finalDeep]] call ACME_fnc_ettMigrationStateCommit;
                [_pt, "obstruction", [false]] call ACME_fnc_ettMigrationStateCommit;
                uiNamespace setVariable ["ACME_laryngo_migrationSyncLast", [1, _finalFrame, _finalDeep]];
            };
            [] call ACME_fnc_laryngoRefreshSlots;
            playSound "ACME_VentClick";
        };
    };

    case "suctionOnly": {
        // suction on its own. there is nothing to lift and nothing to place. the mouth is however the casualty left it,
        // and the only tool is the one in your hand.
        uiNamespace setVariable ["ACME_laryngo_reveal", 0];
    };

    case "complete": {
        // the fastened collar is on the tube, on the face. it was positioned once when a medic clicked it on and never
        // again, so it stayed put while the head moved. it is repositioned every frame against the shaken frame, like
        // everything else that is physically on the casualty.
        // ctrlshown is unary. written as a binary operator it is a parse error, and a parse error here kills the whole
        // tick every frame: no darkness shade, no tray refresh and no state machine. that is why the airway screen was
        // fully lit in the dark and would not hand over a tool.
        if (ctrlShown (_dlg displayCtrl 87910)) then {
            (missionNamespace getVariable ["ACME_laryngo_collarUV", [0.4991, 0.4925]]) params ["_kcU", "_kcV"];
            (missionNamespace getVariable ["ACME_laryngo_collarTarget", [0.4991, 0.3558]]) params ["_ktU", "_ktV"];
            (_dlg displayCtrl 87910) ctrlSetPosition [_fx + ((_ktU - _kcU) * _fw), _fy + ((_ktV - _kcV) * _fh), _fw, _fh];
            (_dlg displayCtrl 87910) ctrlCommit 0;
        };
        // done, and staying open. the operator closes this with the done button when they are ready.
        uiNamespace setVariable ["ACME_laryngo_reveal", _maxReveal];
        [_seatX, _seatY, 1, 0, 0] call _bladePlace;
        [_dlg, (uiNamespace getVariable ["ACME_laryngo_tubeDepth", 1])] call ACME_fnc_laryngoTubeFrames;
    };
};

// the tube lives in the other hand.
// it is not a state of the laryngoscope, it is a second instrument. it follows the cursor by its tip until you
// press and hold left mouse, and that press anchors it exactly where the cursor was. from then on the tube does
// not move at all while the button is down, wherever the mouse goes, so the placement you committed to is the
// placement you get. let go and it follows the cursor again.
private _tih = uiNamespace getVariable ["ACME_laryngo_tubeInHand", false];
if (_tih) then {
    private _grip  = uiNamespace getVariable ["ACME_laryngo_tubeGrip", false];
    private _depth = uiNamespace getVariable ["ACME_laryngo_tubeDepth", 0];
    private _anch  = uiNamespace getVariable ["ACME_laryngo_tubeAnchored", false];

    // the tongue is a floor, not a wall. the tube draws under the tongue layer, which is what makes it look right
    // going in, and it also meant the tube could be slid about freely under there. it is bounded now. it can go
    // deeper than the near edge of the tongue, which is the whole point, because it disappears under it on the way
    // to the cords, and it can never come back up over the top of it. the near edge of the tongue is measured from
    // the art at head v 0.117, which is frame v 0.117 plus the head offset.
    // a committed tube rides with the head. the anchor is held as a fraction of the frame, so the shaken frame
    // computed at the top turns it back into a screen position that moves with the anatomy. keeping it as an
    // absolute screen point is what left the tube nailed to the monitor while the casualty vibrated behind it.
    private _tgt = if (_anch) then {
        private _ar = uiNamespace getVariable ["ACME_laryngo_tubeAnchorRel", []];
        if ((count _ar) >= 2) then {
            [_fx + ((_ar select 0) * _fw), _fy + ((_ar select 1) * _fh)]
        } else { [_cx, _cy] };
    } else { [_cx, _cy] };
    _tgt params ["_wantX", "_wantY"];
    private _floorV = (missionNamespace getVariable ["ACME_laryngo_tongueNearV", 0.117])
                    + (missionNamespace getVariable ["ACME_laryngo_headOffsetV", 0.2188]);
    private _floorY = _fy + (_floorV * _fh);
    if (_wantY < _floorY) then { _wantY = _floorY; };
    private _tipNow = [_wantX, _wantY] call _tubeTick;
    _tipNow params ["_tSX", "_tSY"];

    // do you actually have a view. three things have to be true before a tube goes anywhere: the blade has to be in
    // the mouth, the airway has to be open, and the tip has to be sitting on the cords. with any of them missing
    // the tube meets resistance instead, which is the blocked frame, and it springs back.
    private _bladeIn = _state in ["inserted", "lifting", "held", "seated"];
    private _open = uiNamespace getVariable ["ACME_laryngo_airwayOpen", false];
    private _tfx = (_tSX - _rx) / (_rw max 1e-5);
    private _tfy = (_tSY - _ry) / (_rh max 1e-5);
    (uiNamespace getVariable ["ACME_laryngo_cordsZone", [0.502, 0.142, 0.022]]) params ["_ccx","_ccy","_cr"];
    private _aimD = sqrt ((((_tfx - _ccx)^2) + ((_tfy - _ccy)^2)) max 0);
    // while anchored, the verdict locked in at the click is what counts. the tube has not moved since, so
    // re-deriving it from a spring that is still settling only introduces noise.
    private _lock = uiNamespace getVariable ["ACME_laryngo_tubeAimLock", ""];
    private _live = if (_aimD <= _cr) then {"cords"} else {
        if (_aimD <= (missionNamespace getVariable ["ACME_laryngo_oesophRadius", 0.045])) then {"esoph"} else {""}
    };
    private _aim = if (_anch) then { _lock } else { _live };
    private _onCords = _aim == "cords";
    // and the fulcrum has to have opened the last of the view. a tongue pulled up and not levered back leaves the
    // cords behind their final state, so there is nothing to aim at yet.
    private _canFeed = _bladeIn && {_open} && {_onCords} && {uiNamespace getVariable ["ACME_laryngo_fulcOK", false]};
    uiNamespace setVariable ["ACME_laryngo_tubeCanFeed", _canFeed];

    // once it is in, it stays as it is. a placed tube is not a blocked one. the blocked frame is for a tube being
    // pushed at an airway that will not take it, and showing it after a successful placement rewrote a finished job
    // as a failed one. that is what happened the moment the blade came out and canfeed went false. a fully sunk
    // tube shows the last frame and holds it for the rest of the procedure.
    private _placed = (_depth >= 0.999) || {_state in ["seated","cuff","collar","complete"]};
    private _balk = (diag_tickTime < (uiNamespace getVariable ["ACME_laryngo_tubeBalkUntil", 0]));
    switch (true) do {
        case (_placed): {
            (_dlg displayCtrl 87908) ctrlSetTextColor [1,1,1,0];
            [_dlg, (uiNamespace getVariable ["ACME_laryngo_tubeDepth", 1])] call ACME_fnc_laryngoTubeFrames;
        };
        // a balk only. the old condition also fired on _depth > 0 && !_canFeed, which is true the instant the blade
        // leaves the mouth, so a tube already partway through the cords was redrawn as blocked simply because the view
        // had closed behind it. the blocked art means the airway will not take the tube, and losing the view is not
        // that.
        case (_balk): {
            { (_dlg displayCtrl _x) ctrlSetTextColor [1,1,1,0]; } forEach [87900,87901,87902,87903,87904,87905,87906,87907];
            (_dlg displayCtrl 87908) ctrlSetTextColor [1,1,1,1];
        };
        default {
            (_dlg displayCtrl 87908) ctrlSetTextColor [1,1,1,0];
            [_dlg, _depth] call ACME_fnc_laryngoTubeFrames;
        };
    };

    // momentum. the wheel gives the tube a push, and here it coasts and decays. depth integrates velocity, so the
    // frames run on smoothly after the last click and settle rather than stopping dead.
    private _oldDepthB39 = _depth;
    private _tv = uiNamespace getVariable ["ACME_laryngo_tubeVel", 0];
    if ((abs _tv) > 1e-4) then {
        if (_canFeed || {_tv < 0}) then {
            _depth = ((_depth + (_tv * _dt)) max 0) min 1;
            uiNamespace setVariable ["ACME_laryngo_tubeDepth", _depth];
        } else {
            _tv = 0;
        };
        _tv = _tv * (exp (-((missionNamespace getVariable ["ACME_laryngo_tubeGlide", 3.8]) * _dt)));
        if ((abs _tv) < 1e-4) then { _tv = 0; };
        uiNamespace setVariable ["ACME_laryngo_tubeVel", _tv];
    };

    // B39: deliberate withdrawal all the way out is a real extubation path. Reverse the
    // insertion frames, restore the tube/tray state, and clear cuff/placement state rather
    // than leaving an invisible depth-zero tube committed to the casualty.
    if (_oldDepthB39 > 0.001 && {_depth <= 0.001} && {!(uiNamespace getVariable ["ACME_laryngo_ejecting", false])}) then {
        uiNamespace setVariable ["ACME_laryngo_tubeDepth", 0.02];
        ["withdrawn", true] call ACME_fnc_laryngoTubeEject;
    };

    // let go before it is home and it slides back out.
    // a tube that has been accepted does not slide back out on its own. before that, letting go still loses it.
    // a tube through the cords does not back itself out. the decay existed so a tube dropped mid-insertion would
    // slide free, which is right while it is still being aimed and wrong the moment it is actually in. past the
    // minimum seating frame it stays exactly where the medic left it, and the only things that move it are the
    // wheel, migration from handling, and extubate.
    private _seatedNow = _state in ["seated", "cuff", "collar", "complete", "migrated"];
    private _frNow = 1 + (round (_depth * 7));
    if (_frNow >= (uiNamespace getVariable ["ACME_laryngo_requiredSeatFrame", missionNamespace getVariable ["ACME_ETT_MinSeatFrame", 5]])) then { _seatedNow = true; };
    if (!_seatedNow && {!_grip} && {_depth > 0} && {_depth < 0.999}) then {
        _depth = (_depth - ((missionNamespace getVariable ["ACME_laryngo_tubeDecay", 0.55]) * _dt)) max 0;
        uiNamespace setVariable ["ACME_laryngo_tubeDepth", _depth];
        if (_depth <= 0.001) then { uiNamespace setVariable ["ACME_laryngo_tubeAnchored", false]; };
    };

    // through the cords is placed. it does not have to be buried.
    // this used to require a depth of 0.999, the very last frame, before the tube counted as in. so the only way to
    // finish an intubation was to sink the tube to maximum, and any depth the medic actually wanted was
    // unreachable. it also meant the state never became seated, so the blade auto-withdraw added for that state
    // never fired either and the laryngoscope sat in the mouth forever. both complaints, one line.
    // it seats at the minimum seating frame now, the same threshold everything else in the addon uses for a tube
    // being in the trachea. the depth stays fully adjustable afterwards, because the wheel is gated on the tube
    // being in hand rather than on the state, and the carina detent still stops it going too deep.
    private _seatFr = 1 + (round (_depth * 7));
    if (_seatFr >= (uiNamespace getVariable ["ACME_laryngo_requiredSeatFrame", missionNamespace getVariable ["ACME_ETT_MinSeatFrame", 5]]) && {_state != "seated"} && {_canFeed}) then {
        // Grade changes difficulty, never the final success verdict.
        [] call ACME_fnc_laryngoPassTube;
    };
} else {
    // not in hand does not mean not in the patient. this used to require the state to have reached seated before it
    // would keep drawing the tube, so a tube advanced partway and then let go of vanished from the screen even
    // though its depth was still set. depth is the truth: anything above zero is a tube that is in there.
    private _dOut = uiNamespace getVariable ["ACME_laryngo_tubeDepth", 0];
    if (_state in ["seated", "collar", "cuff", "complete"] || {_dOut > 0.001}) then {
        (_dlg displayCtrl 87908) ctrlSetTextColor [1,1,1,0];
        [_dlg, (uiNamespace getVariable ["ACME_laryngo_tubeDepth", 1])] call ACME_fnc_laryngoTubeFrames;
    } else {
        { (_dlg displayCtrl _x) ctrlSetTextColor [1,1,1,0]; } forEach [87900,87901,87902,87903,87904,87905,87906,87907,87908];
    };
};

// the collar and the syringe follow the cursor whenever they are the thing in your hand, whatever step we are
// on.
// the syringe positioning, the magnetise and the held inflation all live in fn_laryngocuff, so it is driven from
// one place whenever it is the thing in hand rather than being half here and half there.
if ((uiNamespace getVariable ["ACME_laryngo_held", ""]) == "syringe") then {
    ["tick"] call ACME_fnc_laryngoCuff;
} else {
    {(_dlg displayCtrl _x) ctrlSetTextColor [1,1,1,0];} forEach [87814,87817,87818];
};

private _inHand = uiNamespace getVariable ["ACME_laryngo_held", ""];
if (_inHand == "collar") then {
    (missionNamespace getVariable ["ACME_laryngo_collarUV", [0.4991, 0.4925]]) params ["_coU", "_coV"];
    (missionNamespace getVariable ["ACME_laryngo_collarTarget", [0.4991, 0.3558]]) params ["_ctU", "_ctV"];
    private _tgX = _fx + (_ctU * _fw);
    private _tgY = _fy + (_ctV * _fh);
    private _mR = _fh * (missionNamespace getVariable ["ACME_laryngo_collarMagnet", 0.10]);
    private _oX = _cx - _tgX;
    private _oY = _cy - _tgY;
    private _oD = sqrt (((_oX*_oX) + (_oY*_oY)) max 0);
    private _mg = if (_oD <= _mR && {_mR > 1e-5}) then { (_oD / _mR) ^ 1.5 } else { 1 };
    private _snap = _oD <= (_mR * 0.6);
    uiNamespace setVariable ["ACME_laryngo_collarSnapped", _snap];
    (_dlg displayCtrl 87909) ctrlSetPosition [(_tgX + (_oX * _mg)) - (_coU * _fw), (_tgY + (_oY * _mg)) - (_coV * _fh), _fw, _fh];
    (_dlg displayCtrl 87909) ctrlCommit 0;
    (_dlg displayCtrl 87909) ctrlSetTextColor [1, 1, 1, (if (_snap) then {1} else {0.5})];
} else {
    if ((uiNamespace getVariable ["ACME_laryngo_state", ""]) != "collar") then {
        (_dlg displayCtrl 87909) ctrlSetTextColor [1,1,1,0];
    };
    uiNamespace setVariable ["ACME_laryngo_collarSnapped", false];
};

[] call ACME_fnc_laryngoFluid;
[] call ACME_fnc_laryngoSuction;

// B13: no second suction/debit pass in the same frame.

// a snatch that trips the jerk gate has just torn the airway, either the teeth or soft tissue, and either way it
// bleeds. that ends the look, and the attempt is abandoned as trauma. the flag is set inside fn_laryngodrag and
// consumed here.
if (uiNamespace getVariable ["ACME_laryngo_jerkTripped", false]) exitWith {
    uiNamespace setVariable ["ACME_laryngo_jerkTripped", false];
    ["trauma"] call ACME_fnc_laryngoAbort;
};

// the mouth opening is the tongue depressing. it is a five-frame crossfade, rest through s4, driven by the shown
// reveal.
[_dlg, uiNamespace getVariable ["ACME_laryngo_reveal", 0]] call ACME_fnc_laryngoFrames;

private _instr = switch (_state) do {
    case "idle":      { "Grab the laryngoscope from the tray." };
    case "scopeHeld": { "Bring the blade to the mouth. It seats itself on the tongue." };
    case "inserted":  { "Hold CTRL to grip. W lifts, S eases it back down." };
    case "lifting":   { "Hold CTRL and pull with W. S eases it back down." };
    case "held": {
        if (uiNamespace getVariable ["ACME_laryngo_fulcOK", false]) then {
            "Cords in view. Take the tube, click to place, wheel to feed."
        } else {
            "Tongue is up. Lever back with the DOWN ARROW until the cords open."
        };
    };
    case "seated":    { "Tube is home. Let go of CTRL to bring the blade out." };
    case "collar":    { "Cuff is up. Take the collar and click it over the tube." };
    case "cuff":      { "Blade is out. Take the syringe and inflate the cuff at the pilot balloon." };
    case "complete":  { "Airway secured. Press Done when you are finished." };
    case "suctionOnly": {
        if ((uiNamespace getVariable ["ACME_suction_type", -1]) == 0) then {
            "Click to squeeze the suction bag. Place its tip in the mouth."
        } else {"Hold left mouse to suction. Middle-click in the mouth parks ACCUVAC for SALAD."}
    };
    case "migrated":  { "The tube has backed out. Wheel it forward until it is seated." };
    default { "" };
};
if (_state != "cuff") then { (_dlg displayCtrl 87810) ctrlSetText _instr; };

// darkness. the airway view is shaded like every other minigame. to see, the medic turns on a real flashlight
// through the ACE picker, same as the chest seal and iv screens. there is no special blade lamp.

};
[] call ACME_fnc_suctionPublish;
[] call ACME_fnc_suctionObservers;
[uiNamespace getVariable ["ACME_laryngo_dlg", displayNull]] call ACME_fnc_laryngoTeethArt;
[uiNamespace getVariable ["ACME_laryngo_dlg", displayNull], uiNamespace getVariable ["ACME_laryngo_rect", []], "ACME_LG_Shade"] call ACME_fnc_darknessShade;
[uiNamespace getVariable ["ACME_laryngo_dlg", displayNull]] call ACME_fnc_minigameVisionTick;

