using Toybox.Application as App;
using Toybox.Position as Pos;
using Toybox.BluetoothLowEnergy as BLE;

//! CaddyAI watch companion — entry point.
//!
//! Subscribes to position updates from the Garmin golf app and
//! broadcasts detected shots to the paired iPhone over BLE.
class CaddyAIApp extends App.AppBase {
    hidden var _ble;
    hidden var _shots;

    function initialize() {
        App.AppBase.initialize();
    }

    //! Called when the app launches.
    function onStart(state) {
        _ble = new BLEService();
        _shots = new ShotDetector(method(:onShotDetected));
        Pos.enableLocationEvents(Pos.LOCATION_CONTINUOUS, method(:onPosition));
    }

    //! Called when the app is closing.
    function onStop(state) {
        Pos.enableLocationEvents(Pos.LOCATION_DISABLE, null);
    }

    function onPosition(info) {
        _shots.onPosition(info);
    }

    function onShotDetected(shotJson) {
        // BLEService notifies any connected central (the phone).
        _ble.broadcastShot(shotJson);
    }

    function getInitialView() {
        return [ new CaddyAIView() ];
    }
}

class CaddyAIView extends Toybox.WatchUi.View {
    function initialize() { Toybox.WatchUi.View.initialize(); }
}
