import Foundation
import CoreBluetooth
import SwiftUI
import BackgroundTasks

class BLEManager: NSObject, ObservableObject {
    static let shared = BLEManager()
    
    @Published var status: String = "Idle"
    @Published var lastMessage: String = "—"
    @Published var isConnected: Bool = false
    
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var incomingBuffer = ""
    private var writeCharacteristic: CBCharacteristic?
    private var reconnectTimer: Timer?
    
    var commandInterpreter = CommandInterpreter.shared

    private let serviceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    private let txUUID      = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    private let rxUUID      = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
    
    override init() {
        super.init()
        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [
                CBCentralManagerOptionRestoreIdentifierKey: "BlueWatchRestorationID",
                CBCentralManagerOptionShowPowerAlertKey: true
            ]
        )
    }
    
    func connect() {
        guard central.state == .poweredOn else {
            print("Central not powered on: \(central.state.rawValue)")
            return
        }

        // 1. Try to retrieve from system memory first
        if let idString = UserDefaults.standard.string(forKey: "banglePeripheralID"),
           let uuid = UUID(uuidString: idString) {
            
            let peripherals = central.retrievePeripherals(withIdentifiers: [uuid])
            if let p = peripherals.first {
                print("Found saved peripheral: \(p.identifier)")
                setupAndConnect(p)
                return
            } else {
                print("Saved peripheral not found, will scan")
            }
        }

        // 2. Check if already connected peripherals exist
        let connected = central.retrieveConnectedPeripherals(withServices: [serviceUUID])
        if let p = connected.first {
            print("Found already-connected peripheral")
            setupAndConnect(p)
            return
        }

        // 3. Fallback to scanning
        print("Starting scan...")
        status = "Scanning..."
        central.scanForPeripherals(withServices: [serviceUUID], options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
    }

    private func setupAndConnect(_ peripheral: CBPeripheral) {
        self.peripheral = peripheral
        peripheral.delegate = self
        
        // Save the UUID
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: "banglePeripheralID")
        
        print("Connecting to: \(peripheral.identifier)")
        status = "Connecting..."
        
        // Stop any existing scan
        central.stopScan()
        
        // Connect with options for better background handling
        central.connect(peripheral, options: [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
            CBConnectPeripheralOptionNotifyOnNotificationKey: true,
            CBConnectPeripheralOptionStartDelayKey: 0
        ])
    }

    // Single unified send — handles both short commands and large JSON
    func send(_ text: String) {
        guard let p = peripheral, let c = writeCharacteristic, isConnected else {
            print("Cannot send - not connected")
            return
        }

        // JSON gets the ß terminator so the watch knows the full message has arrived
        let payload = text + "ß"

        // Escape backslashes and single quotes so the JS string is valid
        let escaped = payload
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")

        // Chunk the payload — each chunk becomes its own complete JS call
        let maxChunkChars = 140  // leaves room for the ~35-char JS wrapper
        var chunks: [String] = []
        var index = escaped.startIndex

        while index < escaped.endIndex {
            let end = escaped.index(index, offsetBy: maxChunkChars, limitedBy: escaped.endIndex) ?? escaped.endIndex
            chunks.append("require('BlueWatch').receive('\(escaped[index..<end])')\n")
            index = end
        }

        func writeChunk(_ i: Int) {
            guard i < chunks.count,
                  let data = chunks[i].data(using: .utf8) else { return }
            p.writeValue(data, for: c, type: .withResponse)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                writeChunk(i + 1)
            }
        }

        writeChunk(0)
    }
    
    private func scheduleReconnect() {
        // Fallback timer for manual reconnection attempts (iOS will also do this automatically)
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            self?.connect()
        }
    }
}

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("Central state: \(central.state.rawValue)")
        
        switch central.state {
        case .poweredOn:
            status = "Ready"
            connect()
        case .poweredOff:
            status = "Bluetooth Off"
            isConnected = false
        case .resetting:
            status = "Resetting..."
        case .unauthorized:
            status = "Bluetooth Unauthorized"
        case .unsupported:
            status = "Bluetooth Unsupported"
        case .unknown:
            status = "Bluetooth Unknown"
        @unknown default:
            status = "Bluetooth Unknown State"
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        print("Will restore state")
        
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
           let restored = peripherals.first {
            print("Restoring peripheral: \(restored.identifier)")
            self.peripheral = restored
            restored.delegate = self
            status = "Restoring..."
            
            // If it's already connected, discover services
            if restored.state == .connected {
                print("Already connected during restore!")
                isConnected = true
                restored.discoverServices([serviceUUID])
            }
        }
        
        if let scanServices = dict[CBCentralManagerRestoredStateScanServicesKey] as? [CBUUID] {
            print("Was scanning for: \(scanServices)")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print("Discovered: \(peripheral.identifier) RSSI: \(RSSI)")
        setupAndConnect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected!")
        status = "Connected"
        isConnected = true
        reconnectTimer?.invalidate()
        peripheral.discoverServices([serviceUUID])
        
        // Notify the watch
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.send("iPhone Connected")
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect: \(error?.localizedDescription ?? "unknown")")
        status = "Connection Failed"
        isConnected = false
        scheduleReconnect()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected: \(error?.localizedDescription ?? "normal")")
        isConnected = false
        status = "Reconnecting..."
        
        // CRITICAL: Immediately re-queue - iOS will watch for this device
        central.connect(peripheral, options: [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
            CBConnectPeripheralOptionNotifyOnNotificationKey: true
        ])
        
        // Also schedule a manual reconnect attempt as backup
        scheduleReconnect()
    }
}

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("Service discovery error: \(error)")
            return
        }
        
        print("Services discovered: \(peripheral.services?.count ?? 0)")
        peripheral.services?.forEach {
            print("  - \($0.uuid)")
            peripheral.discoverCharacteristics([txUUID, rxUUID], for: $0)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("Characteristic discovery error: \(error)")
            return
        }
        
        print("Characteristics discovered: \(service.characteristics?.count ?? 0)")
        service.characteristics?.forEach { c in
            print("  - \(c.uuid)")
            if c.uuid == txUUID {
                writeCharacteristic = c
                print("TX characteristic ready")
            }
            if c.uuid == rxUUID {
                peripheral.setNotifyValue(true, for: c)
                print("RX notifications enabled")
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value,
              let text = String(data: data, encoding: .utf8) else { return }

        incomingBuffer += text

        while let range = incomingBuffer.range(of: "\n") {
            let line = incomingBuffer[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            incomingBuffer = String(incomingBuffer[range.upperBound...])

            var bgTaskID: UIBackgroundTaskIdentifier = .invalid
            bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "ProcessBLECommand") {
                UIApplication.shared.endBackgroundTask(bgTaskID)
                bgTaskID = .invalid
            }

            DispatchQueue.main.async {
                 self.lastMessage = line
            }

            if let data = line.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let type = json["type"] as? String, type == "health" {
                commandInterpreter.handleHealthData(json)
            } else {
                commandInterpreter.handleCommand(command: line)
            }
            
            UIApplication.shared.endBackgroundTask(bgTaskID)
            bgTaskID = .invalid
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Write error: \(error)")
        }
    }
}
