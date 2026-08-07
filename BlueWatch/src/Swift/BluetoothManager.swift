// BluetoothManager.swift
    import Foundation
    import CoreBluetooth
    import SwiftUI
    import WebKit
    import BackgroundTasks

    class BLEManager: NSObject, ObservableObject {
        static let instance = BLEManager()
        private let autoStartKey = "BLEManagerAutoStart"
        private var hasSeenPoweredOn = false
        @Published var status: String = "Idle"
        @Published var lastMessage: String = "—"
        @Published var isConnected: Bool = false
        private var setupWatchdogToken: UUID?
        // handle retries of handshake
        @Published var handshakeSuccessful: Bool = false
        private var handshakeAttempts = 0
        // Dedicated serial queue instead of nil (main thread).
        // BLE callbacks on a dedicated queue survive background better and
        // won't be blocked by UI work on the main thread.
        private let bleQueue = DispatchQueue(label: "com.rk.bluewatch", qos: .userInitiated)

        private var central: CBCentralManager!
        private var peripheral: CBPeripheral?
        private var incomingBuffer = ""
        private var writeCharacteristic: CBCharacteristic?
        
        private var pendingChunks: [Data] = []
        private var currentWriteCharacteristic: CBCharacteristic?
        private var writeInProgress = false
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
        @Published private var started = false
        private var shouldAttemptConnect = false
        @Published var isHandshaking=false
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

        private let sendQueue = DispatchQueue(label: "com.rk.bluewatch.sendQueue")
        private var sendBusy = false
        private var pendingMessages: [(String, Bool)] = []

        
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
            
            // If the user has previously started BLE, auto-start on subsequent app launches/restores
            if UserDefaults.standard.bool(forKey: autoStartKey) {
                // Defer start a little to allow central to finish initialization
                bleQueue.async { [weak self] in
                    self?.start()
                }
            }
            commandInterpreter.ble=self
        }
        // MARK: - bt power-cycle recovery

        private func resetConnectionState() {
            peripheral = nil
            writeCharacteristic = nil
            setupComplete = false
            DispatchQueue.main.async {
                self.isHandshaking = false
                self.handshakeSuccessful = false
            }
            handshakeAttempts = 0
            incomingBuffer = ""
            activeWebNotifications = []
            wbServices = [:]
            wbCharacteristics = [:]
            writeQueue = []
            writeBusy = false
            setupWatchdogToken = nil
            logger.log("[BLE] Connection state reset")
        }

        
        private func recreateCentralManager() {
            logger.log("[BLE] Recreating CBCentralManager after radio power cycle")
            central = CBCentralManager(
                delegate: self,
                queue: bleQueue,
                options: [
                    CBCentralManagerOptionRestoreIdentifierKey: "BlueWatchRestorationID",
                    CBCentralManagerOptionShowPowerAlertKey: true
                ]
            )
        }
        // MARK: - Lifecycle control
        func start() {
            guard !started else { return }
            started = true
            shouldAttemptConnect = true
            UserDefaults.standard.set(true, forKey: autoStartKey)
            // If Bluetooth is already powered on, allow connection flow to begin
            if central.state == .poweredOn {
                connect()
            } else {
                // change display
                switch central.state {
                case .poweredOff:
                    DispatchQueue.main.async { self.status = "Bluetooth Off" }
                case .resetting:
                    DispatchQueue.main.async { self.status = "Resetting..." }
                case .unauthorized:
                    DispatchQueue.main.async { self.status = "Bluetooth Unauthorized" }
                case .unsupported:
                    DispatchQueue.main.async { self.status = "Bluetooth Unsupported" }
                case .unknown:
                    DispatchQueue.main.async { self.status = "Bluetooth Unknown" }
                case .poweredOn:
                    DispatchQueue.main.async { self.status = "Waiting to connect" }
                @unknown default:
                    DispatchQueue.main.async { self.status = "Bluetooth Unknown" }
                }
                // When Bluetooth powers on, centralManagerDidUpdateState will call connect()
            }
        }
        //destructive force-disconnects device from  phone
        func stop(destructive:Bool) {
            // Stop all BLE activity and prevent future actions until start() is called again
            started = false
            shouldAttemptConnect = false
            central.stopScan()
            if let p = peripheral {
                central.cancelPeripheralConnection(p)
            }
            self.handshakeSuccessful = false
            self.handshakeAttempts = 0
            self.isHandshaking = false
            activeWebNotifications = []
            wbServices = [:]
            wbCharacteristics = [:]
            writeQueue = []
            writeBusy = false
            setupComplete = false
            pendingRequestDevice = nil
            pendingServices.removeAll()
            pendingChars.removeAll()
            pendingReads.removeAll()
            pendingNotify.removeAll()
            incomingBuffer = ""
            DispatchQueue.main.async {
                self.isConnected = false
                if(!destructive){
                    self.status = "Inactive"
                }else{
                    self.status = "Disconnected"
                }
            }
            endSetupBackgroundTask()
        }

        // MARK: - Background task management

        private func beginSetupBackgroundTask() {
            guard setupBackgroundTask == .invalid else { return }
            setupBackgroundTask = UIApplication.shared.beginBackgroundTask(
                withName: "BLESetup"
            ) { [weak self] in
                self?.endSetupBackgroundTask()
            }
            logger.log("[BLE] Setup background task started: \(self.setupBackgroundTask.rawValue)")
        }

        private func endSetupBackgroundTask() {
            guard setupBackgroundTask != .invalid else { return }
            UIApplication.shared.endBackgroundTask(setupBackgroundTask)
            logger.log("[BLE] Setup background task ended: \(self.setupBackgroundTask.rawValue)")
            setupBackgroundTask = .invalid
        }

        // MARK: - Connect

        func connect() {
            guard started, shouldAttemptConnect, central.state == .poweredOn else { return }
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
        func sendJSON(data:Codable){
            let encoder = JSONEncoder()
            guard let jsonData = try? encoder.encode(data),
                  let jsonString = String(data: jsonData, encoding: .utf8) else {
                fatalError("Failed to encode JSON")
            }
                
            send(jsonString);
        }
        // DELETE: private let sendQueue = DispatchQueue(label: "com.rk.bluewatch.sendQueue")

        func send(_ text: String, sendRaw: Bool = false) {
            bleQueue.async { [weak self] in
                guard let self = self else { return }
                self.pendingMessages.append((text, sendRaw))
                self.drainSendQueue()
            }
        }
        private func sendNextChunk() {
            guard
                !writeInProgress,
                let p = peripheral,
                let c = currentWriteCharacteristic,
                !pendingChunks.isEmpty
            else {
                if pendingChunks.isEmpty {
                    sendBusy = false
                    drainSendQueue()
                }
                return
            }

            writeInProgress = true

            let chunk = pendingChunks.removeFirst()
            p.writeValue(chunk, for: c, type: .withResponse)
        }
        private func drainSendQueue() {
            guard !sendBusy, !pendingMessages.isEmpty else { return }
            guard started, let p = peripheral, let c = writeCharacteristic, isConnected else {
                pendingMessages.removeAll()
                return
            }
            sendBusy = true
            let (text, sendRaw) = pendingMessages.removeFirst()
            let payload = ((sendRaw ? "RAW: " : "") + text + "|")
            let base64Payload = payload.data(using: .utf8)?.base64EncodedString() ?? ""
            let jsCommand = "\u{10}require('bluewatch').receive(atob('\(base64Payload)'));\n"

            guard let fullData = jsCommand.data(using: .utf8) else {
                sendBusy = false
                drainSendQueue()
                return
            }

            let chunkSize = Settings.instance.optimizedBtChunks ? 15 : 40
            logger.log("ChunkSize \(chunkSize, privacy: .public)")
            pendingChunks.removeAll()

            var offset = 0
            while offset < fullData.count {
                let length = min(chunkSize, fullData.count - offset)
                pendingChunks.append(fullData.subdata(in: offset..<(offset + length)))
                offset += length
            }

            currentWriteCharacteristic = c
            sendNextChunk()
            // sendBusy stays true — cleared only once pendingChunks empties out,
            // inside sendNextChunk()'s guard-else branch.
        }

        // MARK: - Write queue

        private func enqueueWrite(callId: Int, data: Data, char: CBCharacteristic) {
            writeQueue.append(WriteJob(callId: callId, data: data, char: char))
            drainWriteQueue()
        }

        private func drainWriteQueue() {
            guard started, !writeBusy, let p = peripheral, isConnected else { return }
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
            if !started {
                if method == "requestDevice" {
                    // Behave as if no device is available until start() is called
                    return wbReject(id: id, error: "Bluetooth is not started")
                } else {
                    return wbReject(id: id, error: "Bluetooth is not started")
                }
            }
            logger.log("[WB] → \(method) id=\(id)")
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
        func attemptHandshake(){
            
            guard started, isConnected, isHandshaking else{
                logger.log("[BLE] Handshake failed, not connected, started, or handshake already in progress")
                return
            }
            if (handshakeSuccessful) {
                logger.log("Handshake attempt stopped, already successful")
                isHandshaking = false
                return
            }
            if (handshakeAttempts>=10){
                status = "Handshake Failed"
                isHandshaking=false
                logger.log("Handshake attempt stopped, max tries reached")
                handshakeAttempts = 0
                return
            }
            status = "Waiting for response"
            send("BlueWatch Connected")
            handshakeAttempts += 1
            logger.log("Attempted handshake \(self.handshakeAttempts)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.attemptHandshake()
            }
        }

        private func wbRequestDevice(id: Int) {
            guard started else { wbReject(id: id, error: "Bluetooth is not started"); return }
            activeWebNotifications = []
            wbCharacteristics = [:]
            wbServices = [:]
            writeQueue = []
            writeBusy = false
            incomingBuffer = ""

            if let p = peripheral, isConnected, setupComplete {
                let deviceId = p.identifier.uuidString
                let name     = p.name ?? "Bangle.js"
                logger.log("[WB] requestDevice → \(name)")
                DispatchQueue.main.async {
                    self.webView?.evaluateJavaScript(
                        "window.__bluetoothResetSession && window.__bluetoothResetSession()"
                    ) { _, _ in
                        self.wbResolve(id: id, result: ["deviceId": deviceId, "name": name])
                    }
                }
            } else {
                logger.log("[WB] requestDevice parked — waiting for setup")
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
                logger.log("[WB] getPrimaryService: \(sid)")
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
                logger.log("[WB] getCharacteristic: \(cid) isNotifying=\(char.isNotifying) props=\(char.properties.rawValue)")
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
            logger.log("[WB] notify \(bytes.count)B \"\(preview)\"")
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
                hasSeenPoweredOn = true
                if self.started && self.shouldAttemptConnect { self.connect() }
            case .poweredOff:
                DispatchQueue.main.async {
                    self.status = "Bluetooth Off"
                    self.isConnected = false
                }
                endSetupBackgroundTask()
                resetConnectionState()
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
            // Unconditional, before any guard — if this line is missing from the
            // log after an overnight gap, the process never got a background
            // relaunch at all (force-quit, Low Power Mode throttling, or the OS
            // just didn't grant one) as opposed to relaunching and failing later.
            logger.log("[BLE] willRestoreState — process relaunched in background")
            if !started {
                if UserDefaults.standard.bool(forKey: autoStartKey) {
                    start()
                } else {
                    return
                }
            }
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
            guard started else { return }
            setupAndConnect(peripheral)
        }

        func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
            guard started else {
                central.cancelPeripheralConnection(peripheral)
                return
            }
            logger.log("[BLE] Connected — discovering services...")
            beginSetupBackgroundTask()
            writeBusy = false; writeQueue = []
            DispatchQueue.main.async {
                self.status = "Setting up..."
                self.isConnected = true
            }
            setupComplete = false

            // Watchdog: if setup hasn't completed within 15s, force a reconnect
            // instead of hanging on "Setting up..." forever.
            let token = UUID()
            setupWatchdogToken = token
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                guard let self = self,
                      self.started,
                      !self.setupComplete,
                      self.setupWatchdogToken == token,
                      self.peripheral === peripheral else { return }
                logger.log("[BLE] Setup timed out after 15s — forcing reconnect")
                self.central.cancelPeripheralConnection(peripheral)
                // didDisconnectPeripheral will fire and re-issue central.connect(...)
            }

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
                guard let self = self, self.started, self.shouldAttemptConnect else { return }
                self.connect()
            }
        }
        
        func didCompleteHandshake(){
            
            DispatchQueue.main.async{
                
                logger.log("Handshake Successful!")
                self.handshakeSuccessful=true
                self.handshakeAttempts=0
                self.isHandshaking=false;
                self.status = "Connected"
                
                Task {
                    await LocationManager.shared.sendLocation()
                    await WeatherManager.shared.updateWeatherAndSend()
                }
            }
        }
        func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
            logger.log("[BLE] Disconnected: \(error?.localizedDescription ?? "normal")")
            DispatchQueue.main.async {
                self.isConnected = false
                self.status = "Reconnecting..."
                self.handshakeSuccessful = false
                self.handshakeAttempts = 0
                self.isHandshaking = false
                LocalData.shared.battery = "--"
                LocationManager.shared.stopGPSForwarding()
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

            if started && shouldAttemptConnect {
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
    }

    // MARK: - CBPeripheralDelegate

    // MARK: - CBPeripheralDelegate

    extension BLEManager: CBPeripheralDelegate {

        func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
            guard started else { return }

            if let e = error {
                logger.log("[BLE] Service discovery error: \(e.localizedDescription) — forcing reconnect")
                central.cancelPeripheralConnection(peripheral)
                return
            }

            let deviceId = peripheral.identifier.uuidString
            logger.log("[BLE] Services discovered: \(peripheral.services?.map { $0.uuid.uuidString } ?? [], privacy: .public)")

            // Web Bluetooth path (unrelated to native TX/RX setup)
            if let entry = pendingServices.removeValue(forKey: deviceId) {
                if let svc = peripheral.services?.first(where: {
                    $0.uuid.uuidString.caseInsensitiveCompare(entry.uuid) == .orderedSame
                }) {
                    let sid = svc.uuid.uuidString; wbServices[sid] = svc
                    wbResolve(id: entry.callId, result: ["serviceId": sid])
                } else {
                    wbReject(id: entry.callId, error: "Service not found")
                }
                return
            }

            guard let services = peripheral.services, !services.isEmpty else {
                logger.log("[BLE] No services found on peripheral — forcing reconnect")
                central.cancelPeripheralConnection(peripheral)
                return
            }

            services.forEach { peripheral.discoverCharacteristics([txUUID, rxUUID], for: $0) }
        }

        func peripheral(_ peripheral: CBPeripheral,
                        didDiscoverCharacteristicsFor service: CBService, error: Error?) {
            guard started else { return }

            if let e = error {
                logger.log("[BLE] Characteristic discovery error: \(e.localizedDescription) — forcing reconnect")
                central.cancelPeripheralConnection(peripheral)
                return
            }

            let serviceId = service.uuid.uuidString
            logger.log("[BLE] Characteristics for \(serviceId, privacy: .public): \(service.characteristics?.map { $0.uuid.uuidString } ?? [], privacy: .public)")

            // Web Bluetooth path
            if let entry = pendingChars.removeValue(forKey: serviceId) {
                if let char = service.characteristics?.first(where: {
                    $0.uuid.uuidString.caseInsensitiveCompare(entry.uuid) == .orderedSame
                }) {
                    let cid = char.uuid.uuidString; wbCharacteristics[cid] = char
                    wbResolve(id: entry.callId, result: ["charId": cid, "props": char.properties.rawValue])
                } else {
                    wbReject(id: entry.callId, error: "Characteristic not found")
                }
                return
            }

            var foundTX = false, foundRX = false
            service.characteristics?.forEach { c in
                if c.uuid == txUUID {
                    writeCharacteristic = c; foundTX = true
                    logger.log("[BLE] TX ready props=\(c.properties.rawValue)")
                }
                if c.uuid == rxUUID {
                    peripheral.setNotifyValue(true, for: c); foundRX = true
                    logger.log("[BLE] RX ready")
                }
            }

            if foundTX && foundRX {
                setupComplete = true
                setupWatchdogToken = nil   // setup succeeded, cancel the watchdog
                logger.log("[BLE] Setup complete")

                if let id = pendingRequestDevice {
                    pendingRequestDevice = nil
                    logger.log("[WB] requestDevice → \(peripheral.name ?? "Bangle.js") (post-setup)")
                    wbResolve(id: id, result: [
                        "deviceId": peripheral.identifier.uuidString,
                        "name":     peripheral.name ?? "Bangle.js"
                    ])
                }

                DispatchQueue.main.async {
                    self.onConnectionFinished()
                }
            } else {
                logger.log("[BLE] Setup still incomplete — foundTX=\(foundTX) foundRX=\(foundRX). Waiting for further discovery callbacks or watchdog timeout.")
            }
        }

        // `force: true` always restarts the handshake from attempt 0, even if
        // isHandshaking is already true. This matters because the retry chain
        // in attemptHandshake() is a self-scheduled DispatchQueue.main.asyncAfter,
        // which does NOT survive the app being suspended — if that happens
        // mid-retry, isHandshaking is stranded `true` forever (nothing else
        // resets it, since the BLE link itself can stay nominally "connected"
        // all night even though the app-level handshake never finished, so
        // didDisconnectPeripheral never fires to clean it up either). Without
        // `force`, every recovery path (foreground, manual retry) was refusing
        // to act specifically in that stuck state — the one state that needed it.
        func startHandshake(force: Bool = false){
            if isHandshaking && !force {
                logger.log("[BLE] startHandshake: already in progress, ignoring")
                return
            }
            handshakeAttempts = 0
            isHandshaking = true
            attemptHandshake()
        }

        func onConnectionFinished() {
            guard started else { return }
            // force: true — a fresh CB-level connection (we just finished
            // service/characteristic discovery) is an unambiguous signal to
            // start clean, regardless of whatever handshake state was left
            // over from a previous, possibly-interrupted attempt.
            startHandshake(force: true)
            endSetupBackgroundTask()
        }

        func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
            guard started else { return }

            if let error = error {
                print("BLE RX Error: \(error.localizedDescription)")
                return
            }

            guard let data = characteristic.value else {
                print("BLE RX: Empty data packet received")
                return
            }

            let charId = characteristic.uuid.uuidString
            let bytes  = [UInt8](data)

            if let raw = String(data: data, encoding: .utf8) {
                print("RAW RX FROM WATCH: '\(raw)'")
                logger.log("[BLE RAW] charId=\(charId, privacy: .public) bytes=\(bytes.count, privacy: .public) text=\(raw.debugDescription, privacy: .public)")
            } else {
                print("BLE RX: Received non-UTF8 data")
                logger.log("[BLE RAW] charId=\(charId, privacy: .public) bytes=\(bytes.count, privacy: .public) (non-UTF8)")
            }

            if activeWebNotifications.contains(charId) {
                if let id = pendingReads.removeValue(forKey: charId) {
                    wbResolve(id: id, result: bytes)
                } else {
                    wbFireNotification(charId: charId, bytes: bytes)
                }
            }

            guard charId.caseInsensitiveCompare(rxUUID.uuidString) == .orderedSame else { return }

            guard let text = String(data: data, encoding: .utf8) else { return }
            incomingBuffer += text
            logger.log("[Receive] incoming buffer: \(self.incomingBuffer, privacy: .public)")
            while let range = incomingBuffer.range(of: "\n") {
                let line = String(incomingBuffer[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                incomingBuffer = String(incomingBuffer[range.upperBound...])
                logger.log("[Receive] got command: \(line, privacy: .public)")
                guard let range = line.range(of: "bwRX:") else { continue }

                
                print("Command is good, continuing: " + line)
                var bgId: UIBackgroundTaskIdentifier = .invalid
                bgId = UIApplication.shared.beginBackgroundTask(withName: "BLELine") {
                    UIApplication.shared.endBackgroundTask(bgId); bgId = .invalid
                }
                logger.log("[Receive] Command in while: \(line, privacy: .public)")
                DispatchQueue.main.async {
                    let payload = String(line[range.upperBound...])
                    self.lastMessage = payload
                    logger.log("[Receive] Stripped payload in main: \(payload, privacy: .public)")
                    if let d = payload.data(using: .utf8),
                       let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                        // treat any incoming json as completion of handshake
                        if(!self.handshakeSuccessful && self.isHandshaking){ self.didCompleteHandshake() }
                        self.commandInterpreter.handleJSON(j)
                        logger.log("[Receive] registered as json: \(payload, privacy: .public)")
                    } else {
                        // also end handshake here ( TODO: maybe check if its valid )
                        if(!self.handshakeSuccessful && self.isHandshaking){ self.didCompleteHandshake() }
                        self.commandInterpreter.handleCommand(command: payload)
                        logger.log("[Receive] sent as command: \(payload, privacy: .public)")
                    }
                    UIApplication.shared.endBackgroundTask(bgId); bgId = .invalid
                }
            }
        }

        func peripheral(_ peripheral: CBPeripheral,
                        didWriteValueFor characteristic: CBCharacteristic,
                        error: Error?) {

            if let e = error {
                logger.log("[BLE] write error: \(e.localizedDescription)")
                writeInProgress = false
                sendBusy = false
                pendingChunks.removeAll()
                return
            }

            writeInProgress = false
            sendNextChunk()
        }

        func peripheral(_ peripheral: CBPeripheral,
                        didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
            guard started else { return }
            let charId = characteristic.uuid.uuidString
            logger.log("[BLE] notification state: \(charId.prefix(8)) isNotifying=\(characteristic.isNotifying)")
            if let id = pendingNotify.removeValue(forKey: charId) {
                if let e = error { wbReject(id: id, error: e.localizedDescription) }
                else              { wbResolve(id: id, result: [:]) }
            }
        }

        func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
            guard started else { return }
            writeBusy = false
            drainWriteQueue()
        }
    }
