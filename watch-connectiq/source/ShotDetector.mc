using Toybox.Time as T;
using Toybox.Position as Pos;

//! Very simple shot detector: remember the last GPS point; when the next
//! point arrives more than `SHOT_MIN_DISTANCE_M` away, treat it as a shot
//! of (that distance) yards from the previous club. In v2 we'll hook into
//! the Garmin Golf app's own shot-detected event via the Complications
//! / data-field API on supported devices.
class ShotDetector {
    hidden const SHOT_MIN_DISTANCE_M = 25.0;       // filter putts / walking
    hidden const SHOT_MAX_DISTANCE_M = 320.0;      // discard GPS jumps

    hidden var _callback;
    hidden var _prev = null;
    hidden var _currentClub = "unknown";

    function initialize(callback) {
        _callback = callback;
    }

    //! Called by the app whenever a new position fix arrives.
    function onPosition(info) {
        if (info == null || info.position == null) { return; }
        if (_prev == null) { _prev = info; return; }
        var dist = info.position.distanceTo(_prev.position);
        if (dist >= SHOT_MIN_DISTANCE_M && dist <= SHOT_MAX_DISTANCE_M) {
            var yards = dist * 1.09361;
            var payload = {
                :id => T.now().value().toString(),
                :club_id => _currentClub,
                :distance_yards => yards,
                :ts => T.Moment.getNow().toString(),
                :source => "garmin_watch",
                :result => "unknown",
            };
            _callback.invoke(payload);
            _prev = info;
        } else if (dist > SHOT_MAX_DISTANCE_M) {
            _prev = info;   // GPS jump, reset
        }
    }

    function setClub(clubId) {
        _currentClub = clubId;
    }
}
