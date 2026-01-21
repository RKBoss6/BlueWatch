import Foundation
import CoreBluetooth
import SwiftUI

class BLEManager: NSObject, ObservableObject {
    static let shared = BLEManager()
    
    // MARK: - Published UI State
    @Published var status: String = "Idle"
    @Published var lastMessage: String = "—"
    @Published var isConnected: Bool = false
    
    // MARK: - Bluetooth
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var incomingBuffer = ""
    private var writeCharacteristic: CBCharacteristic?
    private var commandInterpreter=CommandInterpreter.shared
    // Nordic UART UUIDs
    private let serviceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    private let txUUID      = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    private let rxUUID      = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
    
    private override init() {
        super.init()
        commandInterpreter.ble=self
        print("set")
        // Enable state restoration with a unique identifier
        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [
                CBCentralManagerOptionRestoreIdentifierKey: "BlueWatchCentral"
            ]
        )
        
    }
    
    // MARK: - Public API
    
    func connect() {
        guard central.state == .poweredOn else { return }
        status = "Searching..."

        // 1. Try saved identifier
        if let id = loadSavedPeripheral(),
           let p = central.retrievePeripherals(withIdentifiers: [id]).first {
            status = "Found saved watch..."
            connect(to: p)
            return
        }

        // 2. Check if already connected to iOS (System-level)
        let connected = central.retrieveConnectedPeripherals(withServices: [serviceUUID])
        if let p = connected.first {
            status = "Re-linking connected watch..."
            connect(to: p)
            return
        }

        // 3. Otherwise, Scan
        status = "Scanning..."
        central.scanForPeripherals(withServices: [serviceUUID], options: nil)
    }
    
    func disconnect() {
        if let p = peripheral {
            central.cancelPeripheralConnection(p)
        }
    }
    
    func send(_ text: String) {
        guard let p = peripheral,
              let c = writeCharacteristic,
              isConnected else { return }
        
        let data = "require('BlueWatch').receive('\(text)')\n".data(using: .utf8)!
        
        p.writeValue(data, for: c, type: .withResponse)
    }
    
    // MARK: - Helpers
    
    private func connect(to peripheral: CBPeripheral) {
        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral)
    }
    
    private func savePeripheral(_ peripheral: CBPeripheral) {
        UserDefaults.standard.set(
            peripheral.identifier.uuidString,
            forKey: "banglePeripheralID"
        )
    }
    
    private func loadSavedPeripheral() -> UUID? {
        guard let s = UserDefaults.standard.string(forKey: "banglePeripheralID") else {
            return nil
        }
        return UUID(uuidString: s)
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEManager: CBCentralManagerDelegate {
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            status = "Bluetooth ready"
 
            self.connect()
        } else {
            status = "Bluetooth unavailable"
        }
    }
    
    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String : Any],
        rssi RSSI: NSNumber
    ) {
        status = "Found \(peripheral.name ?? "device")"
        central.stopScan()
        connect(to: peripheral)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        status = "Connected"
        isConnected = true
        savePeripheral(peripheral)
        peripheral.discoverServices([serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        status = "Disconnected"
        isConnected = false
        writeCharacteristic = nil
        
        // Auto-reconnect
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.connect()
        }
    }
    
    // ✅ State restoration
    func centralManager(
        _ central: CBCentralManager,
        willRestoreState dict: [String : Any]
    ) {
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
           let p = peripherals.first {
            self.peripheral = p
            p.delegate = self
            central.connect(p)
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BLEManager: CBPeripheralDelegate {
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        peripheral.services?.forEach {
            peripheral.discoverCharacteristics(nil, for: $0)
        }
    }
    
    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        service.characteristics?.forEach { c in
            if c.uuid == txUUID {
                writeCharacteristic = c
                send("iPhone Connected")

            }
            if c.uuid == rxUUID {
                peripheral.setNotifyValue(true, for: c)
            }
        }
    }
    
    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let data = characteristic.value,
              let text = String(data: data, encoding: .utf8) else { return }

        incomingBuffer += text

        // Process lines
        while let range = incomingBuffer.range(of: "\n") {
            let line = incomingBuffer[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            incomingBuffer = String(incomingBuffer[range.upperBound...])

            DispatchQueue.main.async {
                self.lastMessage = line
            }

            // First, try JSON
            if let data = line.data(using: .utf8) {
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let type = json["type"] as? String, type == "health" {
                        commandInterpreter.handleHealthData(json)
                        continue // Already handled, skip command checks
                    }
                } catch {
                    // JSON failed to parse, fallback to command checks
                }
            }

            // If not JSON or not a health packet, check commands
            commandInterpreter.handleCommand(command: line)
        }

    }
}

