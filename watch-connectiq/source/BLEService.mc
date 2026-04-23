using Toybox.BluetoothLowEnergy as BLE;

//! GATT server exposing a single notify characteristic.
//! UUIDs must match ios/CaddyAI/Sources/CaddyAI/Services/GarminBLECentral.swift.
class BLEService {
    hidden const SERVICE_UUID = "CADDA100-0000-4F6C-AB9D-CADDY0000001";
    hidden const SHOT_CHAR_UUID = "CADDA101-0000-4F6C-AB9D-CADDY0000001";

    hidden var _server;
    hidden var _shotCharacteristic;

    function initialize() {
        // TODO: Connect IQ's BLE peripheral-mode API varies by device.
        // On wearables that do NOT support peripheral mode we will fall
        // back to broadcasting via Garmin Connect Mobile's relay.
        // _server = new BLE.GattServer(...);
        // _shotCharacteristic = ...
    }

    function broadcastShot(payload) {
        // Encode payload dict as a UTF-8 JSON string and push to any
        // subscribed central. On devices without peripheral mode this
        // is a no-op until we ship the Connect Mobile relay path.
        // var json = encodeJson(payload);
        // _shotCharacteristic.notify(json);
    }
}
