// BluetoothManager.swift

import Foundation
import CoreBluetooth
import SwiftUI
import WebKit
import BackgroundTasks

class BLEManager: NSObject, ObservableObject {
    static let instance = BLEManager()

    @Published var status: String = "Idle"
    @Published var lastMessage: String = "—"
    @Published var isConnected: Bool = false

    // Dedicated serial queue instead of nil (main thread).
    // BLE callbacks on a dedicated queue survive background better and
    // won't be blocked by UI work on the main thread.
    private let bleQueue = DispatchQueue(label: "com.rk.bluewatch", qos: .userInitiated)

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var incomingBuffer = ""
    private var writeCharacteristic: CBCharacteristic?

    // reconnectTimer REMOVED entirely.
    // central.connect(_:options:) in didDisconnectPeripheral is already a
    // persistent reconnect request that survives suspension — a Timer
    // doesn't fire when the app is suspended, so it was redundant and
    // could race with the persistent connect attempt.

    var commandInterpreter = CommandInterpreter.shared

    private let serviceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    private let txUUID      = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    private let rxUUID      = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")

    private var setupComplete = false

    // ── Web Bluetooth bridge ───────────────────────────────────────────────────
    weak var webView: WKWebView?

    private var activeWebNotifications: Set<String> = []

    private var wbServices:        [String: CBService]        = [:]
    private var wbCharacteristics: [String: CBCharacteristic] = [:]

    private var pendingRequestDevice: Int?
    private var pendingServices:  [String: (callId: Int, uuid: String)] = [:]
    private var pendingChars:     [String: (callId: Int, uuid: String)] = [:]
    private var pendingReads:     [String: Int] = [:]
    private var pendingNotify:    [String: Int] = [:]

    // ── Write queue (flow-controlled writeWithoutResponse) ─────────────────────
    private struct WriteJob { let callId: Int; let data: Data; let char: CBCharacteristic }
    private var writeQueue: [WriteJob] = []
    private var writeBusy = false

    // Short-lived background task covering the connect→setup window only.
    // Opened in didConnect, closed at the end of onConnectionFinished().
    // The bluetooth-central background mode (Info.plist) keeps the app alive
    // for actual BLE events — this task just protects the few seconds of
    // service/characteristic discovery so we don't get suspended before
    // "BlueWatch Connected" can be sent. iOS hard-limits background tasks to
    // ~30 seconds, so this must NOT be held for the whole connection.
    private var setupBackgroundTask: UIBackgroundTaskIdentifier = .invalid

    override init() {
        super.init()
        // Pass bleQueue instead of nil so BLE callbacks don't run on main.
        central = CBCentralManager(
            delegate: self,
            queue: bleQueue,
            options: [
                CBCentralManagerOptionRestoreIdentifierKey: "BlueWatchRestorationID",
                CBCentralManagerOptionShowPowerAlertKey: true
            ]
        )
    }

    // MARK: - Background task management

    private func beginSetupBackgroundTask() {
        guard setupBackgroundTask == .invalid else { return }
        setupBackgroundTask = UIApplication.shared.beginBackgroundTask(
            withName: "BLESetup"
        ) { [weak self] in
            self?.endSetupBackgroundTask()
        }
        print("[BLE] Setup background task started: \(setupBackgroundTask.rawValue)")
    }

    private func endSetupBackgroundTask() {
        guard setupBackgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(setupBackgroundTask)
        print("[BLE] Setup background task ended: \(setupBackgroundTask.rawValue)")
        setupBackgroundTask = .invalid
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
        DispatchQueue.main.async { self.status = "Scanning..." }
        central.scanForPeripherals(withServices: [serviceUUID], options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
    }

    private func setupAndConnect(_ p: CBPeripheral) {
        peripheral = p; p.delegate = self
        UserDefaults.standard.set(p.identifier.uuidString, forKey: "banglePeripheralID")
        DispatchQueue.main.async { self.status = "Connecting..." }
        central.stopScan()
        central.connect(p, options: [
            CBConnectPeripheralOptionNotifyOnConnectionKey:    true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
            CBConnectPeripheralOptionNotifyOnNotificationKey:  true,
            CBConnectPeripheralOptionStartDelayKey:            0
        ])
    }

    // MARK: - Native send (BlueWatch protocol)

    func send(_ text: String, sendRaw:Bool = false) {
        guard let p = peripheral, let c = writeCharacteristic, isConnected else { return }
        let payload = ((sendRaw ? "RAW: " : "")+text + "|")
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

    private func wbRequestDevice(id: Int) {
        activeWebNotifications = []
        wbCharacteristics = [:]
        wbServices = [:]
        writeQueue = []
        writeBusy = false
        incomingBuffer = ""

        if let p = peripheral, isConnected, setupComplete {
            let deviceId = p.identifier.uuidString
            let name     = p.name ?? "Bangle.js"
            print("[WB] requestDevice → \(name)")
            DispatchQueue.main.async {
                self.webView?.evaluateJavaScript(
                    "window.__bluetoothResetSession && window.__bluetoothResetSession()"
                ) { _, _ in
                    self.wbResolve(id: id, result: ["deviceId": deviceId, "name": name])
                }
            }
        } else {
            print("[WB] requestDevice parked — waiting for setup")
            DispatchQueue.main.async {
                self.webView?.evaluateJavaScript(
                    "window.__bluetoothResetSession && window.__bluetoothResetSession()"
                )
            }
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

    private func wbGattDisconnect(id: Int) {
        activeWebNotifications = []
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
        activeWebNotifications.insert(charId)
        if char.isNotifying { return wbResolve(id: id, result: [:]) }
        pendingNotify[charId] = id
        char.service?.peripheral?.setNotifyValue(true, for: char)
    }

    private func wbStopNotifications(id: Int, args: [String: Any]) {
        if let charId = args["charId"] as? String {
            activeWebNotifications.remove(charId)
        }
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

    // MARK: JS helpers

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
        case .poweredOn:
            DispatchQueue.main.async { self.status = "Ready" }
            connect()
        case .poweredOff:
            DispatchQueue.main.async {
                self.status = "Bluetooth Off"
                self.isConnected = false
            }
            endSetupBackgroundTask()
        case .resetting:
            DispatchQueue.main.async { self.status = "Resetting..." }
        case .unauthorized:
            DispatchQueue.main.async { self.status = "Bluetooth Unauthorized" }
        case .unsupported:
            DispatchQueue.main.async { self.status = "Bluetooth Unsupported" }
        case .unknown:
            DispatchQueue.main.async { self.status = "Bluetooth Unknown" }
        @unknown default:
            DispatchQueue.main.async { self.status = "Bluetooth Unknown" }
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
           let restored    = peripherals.first {
            peripheral = restored
            restored.delegate = self
            DispatchQueue.main.async { self.status = "Restoring..." }

            if restored.state == .connected {
                // Already connected — discover services to finish setup.
                DispatchQueue.main.async { self.isConnected = true }
                beginSetupBackgroundTask()
                restored.discoverServices([serviceUUID])
            } else {
                // App was terminated while disconnected. The old persistent
                // connect() request died with the process, so re-issue it now.
                // centralManagerDidUpdateState(.poweredOn) → connect() also runs,
                // but having it here too means we cover the race where poweredOn
                // fires before willRestoreState completes.
                central.connect(restored, options: [
                    CBConnectPeripheralOptionNotifyOnConnectionKey:    true,
                    CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
                    CBConnectPeripheralOptionNotifyOnNotificationKey:  true,
                    CBConnectPeripheralOptionStartDelayKey:            0
                ])
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        setupAndConnect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("[BLE] Connected — discovering services...")
        // Open a short background task covering service/characteristic discovery.
        // This protects the few seconds between didConnect and onConnectionFinished()
        // so iOS can't suspend us before "BlueWatch Connected" is sent.
        // It is ended inside onConnectionFinished() once the sends are queued.
        // Do NOT hold this open for the whole connection — bluetooth-central handles that.
        beginSetupBackgroundTask()
        writeBusy = false; writeQueue = []
        DispatchQueue.main.async {
            self.status = "Setting up..."
            self.isConnected = true
        }
        setupComplete = false
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        DispatchQueue.main.async {
            self.isConnected = false
            self.status = "Connection Failed"
        }
        setupComplete = false
        endSetupBackgroundTask()
        if let id = pendingRequestDevice {
            pendingRequestDevice = nil
            wbReject(id: id, error: error?.localizedDescription ?? "Failed to connect")
        }
        // No Timer — use a plain asyncAfter on a background queue so it fires
        // even if the main queue is busy, and doesn't need a run loop like Timer does.
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.connect()
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("[BLE] Disconnected: \(error?.localizedDescription ?? "normal")")
        DispatchQueue.main.async {
            self.isConnected = false
            self.status = "Reconnecting..."
            LocalData.shared.battery = "--"
        }
        setupComplete = false
        activeWebNotifications = []
        writeBusy = false; writeQueue = []
        wbServices = [:]; wbCharacteristics = [:]

        DispatchQueue.main.async {
            self.webView?.evaluateJavaScript(
                "window.__bluetoothDisconnected && window.__bluetoothDisconnected()"
            )
        }

        // This single persistent connect call is enough.
        // iOS keeps this request alive even when the app is suspended and
        // will reconnect as soon as the peripheral is in range.
        central.connect(peripheral, options: [
            CBConnectPeripheralOptionNotifyOnConnectionKey:    true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
            CBConnectPeripheralOptionNotifyOnNotificationKey:  true
        ])
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
            if c.uuid == txUUID {
                writeCharacteristic = c; foundTX = true
                print("[BLE] TX ready props=\(c.properties.rawValue)")
            }
            if c.uuid == rxUUID {
                peripheral.setNotifyValue(true, for: c); foundRX = true
                print("[BLE] RX ready")
            }
        }
        if foundTX && foundRX {
            setupComplete = true
            print("[BLE] Setup complete")
            if let id = pendingRequestDevice {
                pendingRequestDevice = nil
                print("[WB] requestDevice → \(peripheral.name ?? "Bangle.js") (post-setup)")
                wbResolve(id: id, result: [
                    "deviceId": peripheral.identifier.uuidString,
                    "name":     peripheral.name ?? "Bangle.js"
                ])
            }
            // Must dispatch to main: isConnected was set via DispatchQueue.main.async
            // in didConnect. Calling onConnectionFinished() directly here (on bleQueue)
            // races with that async — isConnected may still be false, causing send() to
            // silently bail. On main, isConnected is guaranteed true before this runs.
            DispatchQueue.main.async {
                self.onConnectionFinished()
            }
        }
    }

    func onConnectionFinished() {
        // Already on main thread (dispatched from didDiscoverCharacteristicsFor).
        // isConnected is true here, so send() will pass its guard.
        status = "Connected"
        
        send("BlueWatch Connected")
        send("Request System Info")
        
        // Setup is done — end the short background task now.
        endSetupBackgroundTask()
        Task {
            await LocationManager.shared.sendLocation()
            await WeatherManager.shared.updateWeatherAndSend()
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        let charId = characteristic.uuid.uuidString
        let bytes  = [UInt8](data)

        if activeWebNotifications.contains(charId) {
            if let id = pendingReads.removeValue(forKey: charId) {
                wbResolve(id: id, result: bytes)
            } else {
                wbFireNotification(charId: charId, bytes: bytes)
            }
            return
        }

        if let id = pendingReads[charId], wbCharacteristics[charId] != nil {
            pendingReads.removeValue(forKey: charId)
            wbResolve(id: id, result: bytes)
            return
        }

        guard let text = String(data: data, encoding: .utf8) else { return }
        incomingBuffer += text

        // The background task wraps only the async processing work and
        // is ended INSIDE the async block — not immediately after it.
        // Ending it outside gave it zero effective lifetime, which let iOS
        // suspend the app before the command was actually processed.
        while let range = incomingBuffer.range(of: "\n") {
            let line = incomingBuffer[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            incomingBuffer = String(incomingBuffer[range.upperBound...])

            var bgId: UIBackgroundTaskIdentifier = .invalid
            bgId = UIApplication.shared.beginBackgroundTask(withName: "BLELine") {
                UIApplication.shared.endBackgroundTask(bgId); bgId = .invalid
            }

            DispatchQueue.main.async {
                self.lastMessage = line

                if let d = line.data(using: .utf8),
                   let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                    self.commandInterpreter.handleJSON(j)
                } else {
                    self.commandInterpreter.handleCommand(command: line)
                }

                // End the task here, AFTER the async work has actually run.
                UIApplication.shared.endBackgroundTask(bgId); bgId = .invalid
            }
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

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        writeBusy = false
        drainWriteQueue()
    }
}
