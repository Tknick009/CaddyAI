import Foundation
import CoreBluetooth
import CaddyAICore

/// iOS-side Bluetooth Central for the Garmin Connect IQ companion app.
///
/// The Connect IQ watch app (see `/watch-connectiq`) advertises the
/// service UUID below and exposes a single notify characteristic that
/// pushes a `Shot` JSON object when the Garmin golf app detects a shot.
///
/// v1 status: scaffolding. The GATT handshake and JSON payload wiring
/// are implemented, but the companion watch app isn't finished yet, so
/// this class will simply fail to discover the service in production.
/// The iOS UI gracefully handles "no watch found" by falling back to
/// manual shot entry.
final class GarminBLECentral: NSObject, ObservableObject {
    static let serviceUUID = CBUUID(string: "CADDA100-0000-4F6C-AB9D-CADDY0000001")
    static let shotCharacteristicUUID = CBUUID(string: "CADDA101-0000-4F6C-AB9D-CADDY0000001")

    @Published private(set) var state: CBManagerState = .unknown
    @Published private(set) var connected = false
    @Published var lastShot: Shot?

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?

    func start() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: nil)
        } else if state == .poweredOn {
            central?.scanForPeripherals(withServices: [Self.serviceUUID])
        }
    }

    func stop() {
        central?.stopScan()
        if let p = peripheral { central?.cancelPeripheralConnection(p) }
        peripheral = nil
        connected = false
    }
}

extension GarminBLECentral: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async { self.state = central.state }
        if central.state == .poweredOn {
            central.scanForPeripherals(withServices: [Self.serviceUUID])
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        self.peripheral = peripheral
        central.stopScan()
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([Self.serviceUUID])
        DispatchQueue.main.async { self.connected = true }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        DispatchQueue.main.async { self.connected = false }
    }
}

extension GarminBLECentral: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] where service.uuid == Self.serviceUUID {
            peripheral.discoverCharacteristics([Self.shotCharacteristicUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for ch in service.characteristics ?? [] where ch.uuid == Self.shotCharacteristicUUID {
            peripheral.setNotifyValue(true, for: ch)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        if let shot = try? CaddyAIJSON.decoder.decode(Shot.self, from: data) {
            DispatchQueue.main.async { self.lastShot = shot }
        }
    }
}
