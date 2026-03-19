// BLEManager.swift

import Foundation
import CoreBluetooth
import SwiftUI
import WebKit
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

    private var setupComplete = false

    // ── Web Bluetooth bridge ───────────────────────────────────────────────────
    weak var webView: WKWebView?
    private(set) var webBluetoothActive = false

    private var wbServices:        [String: CBService]        = [:]
    private var wbCharacteristics: [String: CBCharacteristic] = [:]

    private var pendingRequestDevice: Int?
    private var pendingServices:  [String: (callId: Int, uuid: String)] = [:]
    private var pendingChars:     [String: (callId: Int, uuid: String)] = [:]
    private var pendingReads:     [String: Int] = [:]
    private var pendingNotify:    [String: Int] = [:]

    // ── Write queue (flow-controlled writeWithoutResponse) ─────────────────────
    // BangleApps sends many rapid 20-byte writeWithoutResponse packets.
    // CoreBluetooth silently drops packets when its TX buffer is full.
    // We must check canSendWriteWithoutResponse and wait for
    // peripheralIsReady(toSendWriteWithoutResponse:) before sending more.
    private struct WriteJob { let callId: Int; let data: Data; let char: CBCharacteristic }
    private var writeQueue: [WriteJob] = []
    private var writeBusy = false

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

    // MARK: - Connect

    func connect() {
        guard central.state == .poweredOn else { return }
        if let idStr = UserDefaults.standard.string(forKey: "banglePeripheralID"),
           let uuid  = UUID(uuidString: idStr),
           let p     = central.retrievePeripherals(withIdentifiers: [uuid]).first {
            setupAndConnect(p); return
        }
        if let p = central.retrieveConnectedPeripherals(withServices: [serviceUUID]).first {
            setupAndConnect(p); return
        }
        status = "Scanning..."
        central.scanForPeripherals(withServices: [serviceUUID], options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
    }

    private func setupAndConnect(_ p: CBPeripheral) {
        peripheral = p; p.delegate = self
        UserDefaults.standard.set(p.identifier.uuidString, forKey: "banglePeripheralID")
        status = "Connecting..."; central.stopScan()
        central.connect(p, options: [
            CBConnectPeripheralOptionNotifyOnConnectionKey:    true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
            CBConnectPeripheralOptionNotifyOnNotificationKey:  true,
            CBConnectPeripheralOptionStartDelayKey:            0
        ])
    }

    // MARK: - Native send (BlueWatch protocol)

    func send(_ text: String) {
        guard !webBluetoothActive else { return }
        guard let p = peripheral, let c = writeCharacteristic, isConnected else { return }
        let payload = (text + "|")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'",  with: "\\'")
        var idx = payload.startIndex
        while idx < payload.endIndex {
            let end = payload.index(idx, offsetBy: 60, limitedBy: payload.endIndex) ?? payload.endIndex
            if let data = "require('BlueWatch').receive('\(payload[idx..<end])')\n".data(using: .utf8) {
                p.writeValue(data, for: c, type: .withResponse)
            }
            idx = end
        }
    }

    private func scheduleReconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            self?.connect()
        }
    }

    // MARK: - Write queue

    private func enqueueWrite(callId: Int, data: Data, char: CBCharacteristic) {
        writeQueue.append(WriteJob(callId: callId, data: data, char: char))
        drainWriteQueue()
    }

    private func drainWriteQueue() {
        guard !writeBusy, let p = peripheral, isConnected else { return }
        while !writeQueue.isEmpty {
            guard p.canSendWriteWithoutResponse else {
                writeBusy = true; return
            }
            let job = writeQueue.removeFirst()
            p.writeValue(job.data, for: job.char, type: .withoutResponse)
            wbResolve(id: job.callId, result: [:])
        }
        writeBusy = false
    }

    // MARK: - Web Bluetooth bridge

    func handleWebBluetoothMessage(id: Int, method: String, args: [String: Any]) {
        print("[WB] → \(method) id=\(id)")
        switch method {
        case "requestDevice":      wbRequestDevice(id: id)
        case "gattConnect":        wbGattConnect(id: id, args: args)
        case "gattDisconnect":     wbGattDisconnect(id: id)
        case "getPrimaryService":  wbGetPrimaryService(id: id, args: args)
        case "getCharacteristic":  wbGetCharacteristic(id: id, args: args)
        case "startNotifications": wbStartNotifications(id: id, args: args)
        case "stopNotifications":  wbStopNotifications(id: id, args: args)
        case "readValue":          wbReadValue(id: id, args: args)
        case "writeValue":         wbWriteValue(id: id, args: args)
        default: wbReject(id: id, error: "Unknown method: \(method)")
        }
    }

    // MARK: requestDevice
    //
    // We do NOT send any REPL reset here.
    //
    // Previously we sent \x03\x03\x10 to try to reset the watch REPL, then
    // waited for a ">" prompt. This was wrong for two reasons:
    //
    //   1. \x10 (Ctrl+P) enters pipe/quiet mode, which SUPPRESSES the ">"
    //      prompt. So the wait always timed out.
    //
    //   2. During the 2s timeout all incoming RX data was dropped. The app
    //      loader sends \x10 itself as part of its own handshake, and the
    //      watch echoes it back. We were dropping that echo, so the app
    //      loader never got confirmation and showed "is programmable set to off?"
    //
    // The app loader (uart.js) handles its own REPL initialisation. Our job
    // is just to provide working write and notification channels, then get
    // out of the way.
    //
    private func wbRequestDevice(id: Int) {
        webBluetoothActive = true
        incomingBuffer = ""   // discard any stale native-protocol data

        if let p = peripheral, isConnected, setupComplete {
            print("[WB] requestDevice → \(p.name ?? "Bangle.js") (setup complete, handing over immediately)")
            wbResolve(id: id, result: [
                "deviceId": p.identifier.uuidString,
                "name":     p.name ?? "Bangle.js"
            ])
        } else {
            print("[WB] requestDevice parked — waiting for setup")
            pendingRequestDevice = id
            if !isConnected { connect() }
        }
    }

    private func wbGattConnect(id: Int, args: [String: Any]) {
        guard let deviceId = args["deviceId"] as? String,
              let p = peripheral, p.identifier.uuidString == deviceId else {
            return wbReject(id: id, error: "Bangle.js not connected")
        }
        wbResolve(id: id, result: ["deviceId": deviceId])
    }

    // gattDisconnect: we do NOT actually disconnect — BLEManager owns the
    // connection. We just clear the web-active flag so the app loader can
    // call requestDevice again for its second connection phase.
    private func wbGattDisconnect(id: Int) {
        webBluetoothActive = false
        // Clear wbCharacteristics so the next requestDevice starts fresh.
        // The underlying CBCharacteristic objects remain valid on the peripheral.
        wbCharacteristics = [:]
        wbServices = [:]
        writeQueue = []
        writeBusy = false
        wbResolve(id: id, result: [:])
    }

    private func wbGetPrimaryService(id: Int, args: [String: Any]) {
        guard let deviceId    = args["deviceId"]    as? String,
              let serviceUUID = args["serviceUUID"] as? String,
              let p           = peripheral,
              p.identifier.uuidString == deviceId else {
            return wbReject(id: id, error: "Device not found")
        }
        if let svc = p.services?.first(where: {
            $0.uuid.uuidString.caseInsensitiveCompare(serviceUUID) == .orderedSame
        }) {
            let sid = svc.uuid.uuidString
            wbServices[sid] = svc
            print("[WB] getPrimaryService: \(sid)")
            return wbResolve(id: id, result: ["serviceId": sid])
        }
        pendingServices[deviceId] = (id, serviceUUID)
        p.discoverServices([CBUUID(string: serviceUUID)])
    }

    private func wbGetCharacteristic(id: Int, args: [String: Any]) {
        guard let serviceId = args["serviceId"] as? String,
              let charUUID  = args["charUUID"]  as? String,
              let service   = wbServices[serviceId] else {
            return wbReject(id: id, error: "Service not found")
        }
        if let char = service.characteristics?.first(where: {
            $0.uuid.uuidString.caseInsensitiveCompare(charUUID) == .orderedSame
        }) {
            let cid = char.uuid.uuidString
            wbCharacteristics[cid] = char
            print("[WB] getCharacteristic: \(cid) isNotifying=\(char.isNotifying) props=\(char.properties.rawValue)")
            return wbResolve(id: id, result: ["charId": cid, "props": char.properties.rawValue])
        }
        pendingChars[serviceId] = (id, charUUID)
        service.peripheral?.discoverCharacteristics([CBUUID(string: charUUID)], for: service)
    }

    private func wbStartNotifications(id: Int, args: [String: Any]) {
        guard let charId = args["charId"] as? String,
              let char   = wbCharacteristics[charId] else {
            return wbReject(id: id, error: "Characteristic not found")
        }
        if char.isNotifying { return wbResolve(id: id, result: [:]) }
        pendingNotify[charId] = id
        char.service?.peripheral?.setNotifyValue(true, for: char)
    }

    private func wbStopNotifications(id: Int, args: [String: Any]) {
        wbResolve(id: id, result: [:])
    }

    private func wbReadValue(id: Int, args: [String: Any]) {
        guard let charId = args["charId"] as? String,
              let char   = wbCharacteristics[charId] else {
            return wbReject(id: id, error: "Characteristic not found")
        }
        pendingReads[charId] = id
        char.service?.peripheral?.readValue(for: char)
    }

    private func wbWriteValue(id: Int, args: [String: Any]) {
        guard let charId = args["charId"] as? String,
              let char   = wbCharacteristics[charId],
              let values = args["value"]  as? [Int] else {
            return wbReject(id: id, error: "Bad write args")
        }
        let data = Data(values.map { UInt8($0) })
        if char.properties.contains(.writeWithoutResponse) {
            enqueueWrite(callId: id, data: data, char: char)
        } else {
            char.service?.peripheral?.writeValue(data, for: char, type: .withResponse)
            wbResolve(id: id, result: [:])
        }
    }

    // MARK: - JS helpers

    func wbResolve(id: Int, result: Any) {
        guard let json = try? JSONSerialization.data(withJSONObject: result),
              let str  = String(data: json, encoding: .utf8) else { return }
        DispatchQueue.main.async {
            self.webView?.evaluateJavaScript("window.__bluetoothCallback(\(id), null, \(str))")
        }
    }

    func wbReject(id: Int, error: String) {
        let safe = error.replacingOccurrences(of: "\"", with: "'")
        DispatchQueue.main.async {
            self.webView?.evaluateJavaScript("window.__bluetoothCallback(\(id), \"\(safe)\", null)")
        }
    }

    private func wbFireNotification(charId: String, bytes: [UInt8]) {
        let arr = bytes.map { Int($0) }
        guard let json = try? JSONSerialization.data(withJSONObject: arr),
              let str  = String(data: json, encoding: .utf8) else { return }
        let preview = String(bytes.prefix(8).compactMap {
            $0 >= 32 && $0 < 127 ? Character(UnicodeScalar($0)) : nil
        })
        print("[WB] notify \(bytes.count)B \"\(preview)\"")
        DispatchQueue.main.async {
            self.webView?.evaluateJavaScript("window.__bluetoothNotify('\(charId)', \(str))")
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:    status = "Ready"; connect()
        case .poweredOff:   status = "Bluetooth Off"; isConnected = false
        case .resetting:    status = "Resetting..."
        case .unauthorized: status = "Bluetooth Unauthorized"
        case .unsupported:  status = "Bluetooth Unsupported"
        case .unknown:      status = "Bluetooth Unknown"
        @unknown default:   status = "Bluetooth Unknown"
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
           let restored    = peripherals.first {
            peripheral = restored; restored.delegate = self; status = "Restoring..."
            if restored.state == .connected {
                isConnected = true; restored.discoverServices([serviceUUID])
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        setupAndConnect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("[BLE] Connected — discovering services...")
        status = "Setting up..."; isConnected = true; setupComplete = false
        writeBusy = false; writeQueue = []; reconnectTimer?.invalidate()
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        isConnected = false; setupComplete = false; status = "Connection Failed"
        if let id = pendingRequestDevice {
            pendingRequestDevice = nil
            wbReject(id: id, error: error?.localizedDescription ?? "Failed to connect")
        }
        scheduleReconnect()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("[BLE] Disconnected: \(error?.localizedDescription ?? "normal")")
        isConnected = false; setupComplete = false; webBluetoothActive = false
        writeBusy = false; writeQueue = []; wbServices = [:]; wbCharacteristics = [:]
        status = "Reconnecting..."
        DispatchQueue.main.async {
            self.webView?.evaluateJavaScript(
                "window.__bluetoothDisconnected && window.__bluetoothDisconnected()"
            )
        }
        central.connect(peripheral, options: [
            CBConnectPeripheralOptionNotifyOnConnectionKey:    true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
            CBConnectPeripheralOptionNotifyOnNotificationKey:  true
        ])
        scheduleReconnect()
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let e = error { print("[BLE] Service error: \(e)"); return }
        let deviceId = peripheral.identifier.uuidString
        if let entry = pendingServices.removeValue(forKey: deviceId) {
            if let svc = peripheral.services?.first(where: {
                $0.uuid.uuidString.caseInsensitiveCompare(entry.uuid) == .orderedSame
            }) {
                let sid = svc.uuid.uuidString; wbServices[sid] = svc
                wbResolve(id: entry.callId, result: ["serviceId": sid])
            } else { wbReject(id: entry.callId, error: "Service not found") }
            return
        }
        peripheral.services?.forEach { peripheral.discoverCharacteristics([txUUID, rxUUID], for: $0) }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let e = error { print("[BLE] Char error: \(e)"); return }
        let serviceId = service.uuid.uuidString
        if let entry = pendingChars.removeValue(forKey: serviceId) {
            if let char = service.characteristics?.first(where: {
                $0.uuid.uuidString.caseInsensitiveCompare(entry.uuid) == .orderedSame
            }) {
                let cid = char.uuid.uuidString; wbCharacteristics[cid] = char
                wbResolve(id: entry.callId, result: ["charId": cid, "props": char.properties.rawValue])
            } else { wbReject(id: entry.callId, error: "Characteristic not found") }
            return
        }
        var foundTX = false, foundRX = false
        service.characteristics?.forEach { c in
            if c.uuid == txUUID { writeCharacteristic = c; foundTX = true; print("[BLE] TX ready props=\(c.properties.rawValue)") }
            if c.uuid == rxUUID { peripheral.setNotifyValue(true, for: c); foundRX = true; print("[BLE] RX ready") }
        }
        if foundTX && foundRX {
            setupComplete = true; status = "Connected"; print("[BLE] Setup complete")
            if let id = pendingRequestDevice {
                pendingRequestDevice = nil
                print("[WB] requestDevice → \(peripheral.name ?? "Bangle.js") (post-setup)")
                wbResolve(id: id, result: [
                    "deviceId": peripheral.identifier.uuidString,
                    "name":     peripheral.name ?? "Bangle.js"
                ])
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        let charId = characteristic.uuid.uuidString
        let bytes  = [UInt8](data)

        // ── Route to Web Bluetooth page ──────────────────────────────────────
        // Route if the page has registered this characteristic via getCharacteristic.
        if wbCharacteristics[charId] != nil {
            if let id = pendingReads.removeValue(forKey: charId) {
                wbResolve(id: id, result: bytes)
            } else {
                wbFireNotification(charId: charId, bytes: bytes)
            }
            return
        }

        // ── Fallback: webBluetoothActive but char not yet registered ─────────
        // The page has requestDevice'd but hasn't called getCharacteristic yet.
        // Forward RX data directly so the app loader's \x10 echo isn't dropped.
        if webBluetoothActive {
            wbFireNotification(charId: charId, bytes: bytes)
            return
        }

        // ── Native BlueWatch path ────────────────────────────────────────────
        guard let text = String(data: data, encoding: .utf8) else { return }
        incomingBuffer += text
        while let range = incomingBuffer.range(of: "\n") {
            let line = incomingBuffer[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            incomingBuffer = String(incomingBuffer[range.upperBound...])
            var bgId: UIBackgroundTaskIdentifier = .invalid
            bgId = UIApplication.shared.beginBackgroundTask(withName: "BLE") {
                UIApplication.shared.endBackgroundTask(bgId); bgId = .invalid
            }
            DispatchQueue.main.async { self.lastMessage = line }
            if let d = line.data(using: .utf8),
               let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               (j["type"] as? String) == "health" {
                commandInterpreter.handleHealthData(j)
            } else {
                commandInterpreter.handleCommand(command: line)
            }
            UIApplication.shared.endBackgroundTask(bgId); bgId = .invalid
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let e = error { print("[BLE] write error: \(e.localizedDescription)") }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        let charId = characteristic.uuid.uuidString
        print("[BLE] notification state: \(charId.prefix(8)) isNotifying=\(characteristic.isNotifying)")
        if let id = pendingNotify.removeValue(forKey: charId) {
            if let e = error { wbReject(id: id, error: e.localizedDescription) }
            else              { wbResolve(id: id, result: [:]) }
        }
    }

    // CoreBluetooth TX buffer has space — resume write queue
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        writeBusy = false
        drainWriteQueue()
    }
}
