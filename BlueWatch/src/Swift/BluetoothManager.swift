//
//  BluetoothManager.swift
//

import Foundation
import CoreBluetooth
import SwiftUI
import WebKit
import BackgroundTasks
import UIKit

final class BLEManager: NSObject, ObservableObject {

    static let shared = BLEManager()

    // MARK: - Published UI state

    @Published var status: String = "Idle"
    @Published var lastMessage: String = "—"
    @Published var isConnected: Bool = false
    @Published var handshakeSuccessful: Bool = false
    @Published var isHandshaking: Bool = false

    // MARK: - Constants

    private let autoStartKey = "BLEManagerAutoStart"

    private let serviceUUID = CBUUID(
        string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
    )

    private let txUUID = CBUUID(
        string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
    )

    private let rxUUID = CBUUID(
        string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
    )

    // MARK: - BLE queue

    /*
     IMPORTANT:

     Every BLE state-machine variable is owned by this queue.

     CoreBluetooth callbacks already arrive here.
     Public methods dispatch onto this queue.
     Handshake timers dispatch onto this queue.

     This prevents the old:
         BLE queue -> main -> BLE queue -> main
     race condition.
     */
    private let bleQueue = DispatchQueue(
        label: "com.rk.bluewatch",
        qos: .userInitiated
    )

    private var central: CBCentralManager!

    // MARK: - Connection state

    private var peripheral: CBPeripheral?

    /*
     iOS may restore a peripheral before CBCentralManager has reached
     .poweredOn.

     Keep the restored peripheral here until CoreBluetooth is ready
     to perform GATT operations.
     */
    private var restoredPeripheralPendingSetup: CBPeripheral?

    private var bleConnected = false
    private var setupComplete = false
    private var notificationsReady = false
    private var connectionInProgress = false

    private var started = false
    private var shouldAttemptConnect = false

    /*
     Every physical connection gets a new generation.

     Any delayed operation from an old connection checks this UUID.
     If it doesn't match, the operation is stale and does nothing.
     */
    private var connectionGeneration = UUID()

    // MARK: - Setup watchdog

    private var setupWatchdogWorkItem: DispatchWorkItem?

    private let setupTimeout: TimeInterval = 15

    // MARK: - Handshake state

    private var handshakeAttempts = 0

    private let maxHandshakeAttempts = 10
    private let handshakeRetryInterval: TimeInterval = 5
    private let handshakeTimeout: TimeInterval = 60

    private var handshakeRetryWorkItem: DispatchWorkItem?
    private var handshakeWatchdogWorkItem: DispatchWorkItem?

    private var handshakeState = false
    private var handshakingState = false

    // MARK: - Incoming BLE data

    private var incomingBuffer = ""

    // MARK: - Native write queue

    private var writeCharacteristic: CBCharacteristic?

    private var pendingChunks: [Data] = []
    private var currentWriteCharacteristic: CBCharacteristic?
    private var writeInProgress = false

    private var sendBusy = false
    private var pendingMessages: [(String, Bool)] = []

    // MARK: - Web Bluetooth bridge

    weak var webView: WKWebView?

    private var activeWebNotifications: Set<String> = []

    private var wbServices: [String: CBService] = [:]
    private var wbCharacteristics: [String: CBCharacteristic] = [:]

    private var pendingRequestDevice: Int?

    private var pendingServices: [
        String: (callId: Int, uuid: String)
    ] = [:]

    private var pendingChars: [
        String: (callId: Int, uuid: String)
    ] = [:]

    private var pendingReads: [String: Int] = [:]
    private var pendingNotify: [String: Int] = [:]

    private struct WriteJob {
        let callId: Int
        let data: Data
        let char: CBCharacteristic
    }

    private var writeQueue: [WriteJob] = []
    private var writeBusy = false

    // MARK: - Background setup task

    private var setupBackgroundTask: UIBackgroundTaskIdentifier = .invalid

    // MARK: - Other app integration

    var commandInterpreter = CommandInterpreter.shared

    // MARK: - Init

    override init() {
        super.init()

        central = CBCentralManager(
            delegate: self,
            queue: bleQueue,
            options: [
                CBCentralManagerOptionRestoreIdentifierKey:
                    "BlueWatchRestorationID",

                CBCentralManagerOptionShowPowerAlertKey:
                    true
            ]
        )

        commandInterpreter.ble = self

        /*
         If the user previously enabled Bluetooth management,
         automatically resume after application restoration.
         */
        if UserDefaults.standard.bool(forKey: autoStartKey) {
            bleQueue.async { [weak self] in
                self?.startOnBLEQueue()
            }
        }
    }

    // MARK: - UI publishing helpers

    private func publishStatus(_ value: String) {
        DispatchQueue.main.async { [weak self] in
            self?.status = value
        }
    }

    private func publishConnectionState(_ value: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = value
        }
    }

    private func publishHandshakeState(
        successful: Bool,
        handshaking: Bool
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.handshakeSuccessful = successful
            self.isHandshaking = handshaking
        }
    }

    private func publishLastMessage(_ value: String) {
        DispatchQueue.main.async { [weak self] in
            self?.lastMessage = value
        }
    }

    // MARK: - Lifecycle

    func start() {
        bleQueue.async { [weak self] in
            self?.startOnBLEQueue()
        }
    }

    private func startOnBLEQueue() {

        guard !started else {
            logger.log("[BLE] start() ignored — already started")
            return
        }

        started = true
        shouldAttemptConnect = true

        UserDefaults.standard.set(true, forKey: autoStartKey)

        logger.log("[BLE] Started")

        switch central.state {

        case .poweredOn:

            publishStatus("Ready")

            /*
             If restoration left a peripheral waiting for setup,
             let the restoration path handle it.
             */
            if restoredPeripheralPendingSetup != nil {
                handlePendingRestorationOnPoweredOn()
            } else {
                connectOnBLEQueue()
            }

        case .poweredOff:

            publishStatus("Bluetooth Off")

        case .resetting:

            publishStatus("Resetting...")

        case .unauthorized:

            publishStatus("Bluetooth Unauthorized")

        case .unsupported:

            publishStatus("Bluetooth Unsupported")

        case .unknown:

            publishStatus("Bluetooth Unknown")

        @unknown default:

            publishStatus("Bluetooth Unknown")
        }
    }

    /*
     Public stop.

     This completely invalidates the current connection generation,
     cancels every watchdog/retry, and prevents automatic reconnect.
     */
    func stop(destructive: Bool) {

        bleQueue.async { [weak self] in
            guard let self else { return }

            self.started = false
            self.shouldAttemptConnect = false

            self.restoredPeripheralPendingSetup = nil

            self.invalidateConnectionState(
                reason: destructive
                    ? "User disconnected"
                    : "BLE stopped"
            )

            if let p = self.peripheral {
                self.central.cancelPeripheralConnection(p)
            }

            self.central.stopScan()

            self.publishConnectionState(false)

            self.publishStatus(
                destructive
                    ? "Disconnected"
                    : "Inactive"
            )

            self.endSetupBackgroundTask()
        }
    }

    // MARK: - State invalidation

    /*
     This is the most important recovery function.

     It invalidates ALL work belonging to the current connection.

     The generation UUID changes, which means any previously scheduled
     handshake retry/watchdog automatically becomes stale.
     */
    private func invalidateConnectionState(reason: String) {

        connectionGeneration = UUID()

        cancelSetupWatchdog()
        cancelHandshakeTimers()

        bleConnected = false
        connectionInProgress = false
        setupComplete = false
        notificationsReady = false

        handshakeAttempts = 0
        handshakeState = false
        handshakingState = false

        incomingBuffer = ""

        writeCharacteristic = nil
        currentWriteCharacteristic = nil

        pendingChunks.removeAll()
        writeInProgress = false

        sendBusy = false
        pendingMessages.removeAll()

        activeWebNotifications.removeAll()

        wbServices.removeAll()
        wbCharacteristics.removeAll()

        pendingServices.removeAll()
        pendingChars.removeAll()
        pendingReads.removeAll()
        pendingNotify.removeAll()

        writeQueue.removeAll()
        writeBusy = false

        logger.log(
            "[BLE] Invalidated connection state: \(reason)"
        )
    }

    // MARK: - Connection

    func connect() {
        bleQueue.async { [weak self] in
            self?.connectOnBLEQueue()
        }
    }

    private func connectOnBLEQueue() {

        guard started,
              shouldAttemptConnect,
              central.state == .poweredOn else {

            logger.log(
                "[BLE] connect ignored — not ready"
            )

            return
        }

        /*
         If CoreBluetooth restoration is still pending,
         do not allow normal connection logic to race it.
         */
        if restoredPeripheralPendingSetup != nil {

            logger.log(
                "[BLE] connect ignored — restored peripheral is pending setup"
            )

            return
        }

        if bleConnected {

            logger.log(
                "[BLE] connect ignored — already connected"
            )

            return
        }

        if connectionInProgress {

            logger.log(
                "[BLE] connect ignored — connection already in progress"
            )

            return
        }

        connectionInProgress = true

        /*
         First try the saved peripheral.
         */
        if let idString = UserDefaults.standard.string(
            forKey: "banglePeripheralID"
        ),
           let uuid = UUID(uuidString: idString),
           let savedPeripheral =
                central.retrievePeripherals(
                    withIdentifiers: [uuid]
                ).first {

            setupAndConnect(savedPeripheral)
            return
        }

        /*
         Then see if CoreBluetooth already considers the device connected.
         */
        if let connectedPeripheral =
            central.retrieveConnectedPeripherals(
                withServices: [serviceUUID]
            ).first {

            setupAndConnect(connectedPeripheral)
            return
        }

        /*
         Finally scan.
         */
        connectionInProgress = false

        publishStatus("Scanning...")

        central.scanForPeripherals(
            withServices: [serviceUUID],
            options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: false
            ]
        )

        logger.log("[BLE] Scanning for Bangle")
    }

    private func setupAndConnect(_ p: CBPeripheral) {

        guard started,
              shouldAttemptConnect else {
            return
        }

        /*
         If this is already the active peripheral and already connected,
         don't start another connection attempt.
         */
        if peripheral === p,
           bleConnected {

            logger.log(
                "[BLE] setupAndConnect ignored — already connected"
            )

            connectionInProgress = false
            return
        }

        restoredPeripheralPendingSetup = nil

        peripheral = p
        p.delegate = self

        UserDefaults.standard.set(
            p.identifier.uuidString,
            forKey: "banglePeripheralID"
        )

        central.stopScan()

        publishStatus("Connecting...")

        logger.log(
            "[BLE] Connecting to \(p.name ?? "Bangle.js") \(p.identifier)"
        )

        central.connect(
            p,
            options: [
                // Ask CoreBluetooth to maintain this reconnect request across long background periods.
                CBConnectPeripheralOptionEnableAutoReconnect: true,
                CBConnectPeripheralOptionNotifyOnConnectionKey: true,
                CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
                CBConnectPeripheralOptionNotifyOnNotificationKey: true,
                CBConnectPeripheralOptionStartDelayKey: 0
            ]
        )
    }

    // MARK: - Restored connection handling

    /*
     Called only after CBCentralManager reaches .poweredOn.

     This is the critical restoration fix.

     willRestoreState() merely remembers the peripheral.
     This function performs the actual GATT work.
     */
    private func handlePendingRestorationOnPoweredOn() {

        guard started,
              shouldAttemptConnect,
              central.state == .poweredOn else {

            logger.log(
                "[BLE] Cannot continue restoration — BLE not ready"
            )

            return
        }

        guard let restored =
                restoredPeripheralPendingSetup else {

            return
        }

        restoredPeripheralPendingSetup = nil

        peripheral = restored
        restored.delegate = self

        logger.log(
            "[BLE] Continuing restored peripheral setup after Bluetooth became powered on"
        )

        /*
         * If iOS still considers the restored peripheral connected,
         * rebuild our GATT state without calling connect().
         */
        if restored.state == .connected {

            connectionGeneration = UUID()

            bleConnected = true
            connectionInProgress = false

            setupComplete = false
            notificationsReady = false

            handshakeState = false
            handshakingState = false
            handshakeAttempts = 0

            incomingBuffer = ""

            writeCharacteristic = nil
            currentWriteCharacteristic = nil

            pendingChunks.removeAll()
            writeInProgress = false

            sendBusy = false
            pendingMessages.removeAll()

            cancelHandshakeTimers()
            cancelSetupWatchdog()

            activeWebNotifications.removeAll()
            wbServices.removeAll()
            wbCharacteristics.removeAll()

            pendingServices.removeAll()
            pendingChars.removeAll()
            pendingReads.removeAll()
            pendingNotify.removeAll()

            writeQueue.removeAll()
            writeBusy = false

            publishConnectionState(true)

            publishHandshakeState(
                successful: false,
                handshaking: false
            )

            publishStatus("Setting up Bluetooth...")

            beginSetupBackgroundTask()

            startSetupWatchdog(
                generation: connectionGeneration,
                peripheral: restored
            )

            logger.log(
                "[BLE] Restored peripheral is connected — discovering BlueWatch service"
            )

            restored.discoverServices(
                [serviceUUID]
            )

        } else {

            /*
             * Restoration remembered the peripheral, but it isn't
             * currently connected.

             * Use the normal connection path.
             */
            connectionInProgress = false

            logger.log(
                "[BLE] Restored peripheral is no longer connected — reconnecting"
            )

            setupAndConnect(restored)
        }
    }

    // MARK: - Background task

    private func beginSetupBackgroundTask() {

        guard setupBackgroundTask == .invalid else {
            return
        }

        setupBackgroundTask =
            UIApplication.shared.beginBackgroundTask(
                withName: "BLESetup"
            ) { [weak self] in

                self?.bleQueue.async {
                    self?.endSetupBackgroundTask()
                }
            }

        logger.log(
            "[BLE] Setup background task started: \(self.setupBackgroundTask.rawValue)"
        )
    }

    private func endSetupBackgroundTask() {

        guard setupBackgroundTask != .invalid else {
            return
        }

        let task = setupBackgroundTask
        setupBackgroundTask = .invalid

        UIApplication.shared.endBackgroundTask(task)

        logger.log(
            "[BLE] Setup background task ended: \(task.rawValue)"
        )
    }

    // MARK: - Setup watchdog

    private func startSetupWatchdog(
        generation: UUID,
        peripheral: CBPeripheral
    ) {

        cancelSetupWatchdog()

        let work = DispatchWorkItem { [weak self] in

            guard let self else { return }

            guard self.started,
                  self.shouldAttemptConnect,
                  self.connectionGeneration == generation,
                  self.peripheral === peripheral,
                  !self.setupComplete else {
                return
            }

            logger.log(
                "[BLE] Setup watchdog expired — forcing reconnect"
            )

            self.forceReconnectOnBLEQueue(
                reason: "Setup timeout"
            )
        }

        setupWatchdogWorkItem = work

        bleQueue.asyncAfter(
            deadline: .now() + setupTimeout,
            execute: work
        )

        logger.log(
            "[BLE] Setup watchdog started (\(Int(self.setupTimeout))s)"
        )
    }

    private func cancelSetupWatchdog() {

        setupWatchdogWorkItem?.cancel()
        setupWatchdogWorkItem = nil
    }

    // MARK: - Handshake timers

    private func cancelHandshakeTimers() {

        handshakeRetryWorkItem?.cancel()
        handshakeRetryWorkItem = nil

        handshakeWatchdogWorkItem?.cancel()
        handshakeWatchdogWorkItem = nil
    }

    // MARK: - Handshake

    /*
     Kept public because MainScreen already calls this.

     `force: true` means:

       - cancel old retry chain
       - invalidate old handshake
       - start a fresh handshake

     It does NOT blindly create multiple simultaneous chains.
     */
    func startHandshake(force: Bool = false) {

        bleQueue.async { [weak self] in
            guard let self else { return }

            if self.handshakingState && !force {

                logger.log(
                    "[BLE] startHandshake ignored — already handshaking"
                )

                return
            }

            guard self.started,
                  self.bleConnected,
                  self.setupComplete,
                  self.notificationsReady else {

                logger.log(
                    "[BLE] Cannot start handshake — BLE/setup not ready"
                )

                if self.central.state != .poweredOn {

                    self.publishStatus(
                        "Waiting for Bluetooth..."
                    )

                } else if self.bleConnected {

                    self.publishStatus(
                        "Waiting for Bluetooth setup"
                    )

                } else {

                    self.publishStatus(
                        "Disconnected"
                    )
                }

                return
            }

            self.beginHandshakeOnBLEQueue()
        }
    }

    private func beginHandshakeOnBLEQueue() {

        cancelHandshakeTimers()

        handshakeAttempts = 0
        handshakeState = false
        handshakingState = true

        let generation = connectionGeneration

        publishHandshakeState(
            successful: false,
            handshaking: true
        )

        publishStatus("Waiting for watch...")

        logger.log(
            "[BLE] Starting handshake generation \(generation)"
        )

        /*
         Independent watchdog.

         This is NOT part of the retry chain.

         Even if every retry callback somehow disappears,
         this watchdog independently terminates the handshake.
         */
        let watchdog = DispatchWorkItem { [weak self] in

            guard let self else { return }

            guard self.started,
                  self.connectionGeneration == generation,
                  self.handshakingState,
                  !self.handshakeState else {
                return
            }

            logger.log(
                "[BLE] Handshake watchdog expired after \(Int(self.handshakeTimeout))s"
            )

            self.handshakingState = false
            self.handshakeState = false
            self.handshakeAttempts = 0

            self.publishHandshakeState(
                successful: false,
                handshaking: false
            )

            self.publishStatus("Handshake Failed")

            /*
             If the BLE layer claims to still be connected but the protocol
             never responded, assume the connection is stale and rebuild it.
             */
            self.forceReconnectOnBLEQueue(
                reason: "Handshake timeout"
            )
        }

        handshakeWatchdogWorkItem = watchdog

        bleQueue.asyncAfter(
            deadline: .now() + handshakeTimeout,
            execute: watchdog
        )

        attemptHandshakeOnBLEQueue(
            generation: generation
        )
    }

    private func attemptHandshakeOnBLEQueue(
        generation: UUID
    ) {

        guard started,
              shouldAttemptConnect,
              bleConnected,
              setupComplete,
              notificationsReady,
              handshakingState,
              connectionGeneration == generation else {

            logger.log(
                "[BLE] Handshake attempt discarded — stale state"
            )

            return
        }

        guard !handshakeState else {
            return
        }

        if handshakeAttempts >= maxHandshakeAttempts {

            logger.log(
                "[BLE] Maximum handshake attempts reached"
            )

            handshakingState = false

            publishHandshakeState(
                successful: false,
                handshaking: false
            )

            publishStatus("Handshake Failed")

            forceReconnectOnBLEQueue(
                reason: "Maximum handshake attempts"
            )

            return
        }

        handshakeAttempts += 1

        publishStatus("Waiting for watch...")

        logger.log(
            "[BLE] Handshake attempt \(self.handshakeAttempts)/\(self.maxHandshakeAttempts)"
        )

        sendOnBLEQueue(
            "BlueWatch Connected"
        )

        /*
         Schedule exactly ONE retry.

         It captures this connection's generation, so if the device
         disconnects/reconnects before this fires, the old callback becomes
         harmless.
         */
        let retry = DispatchWorkItem { [weak self] in

            guard let self else { return }

            guard self.started,
                  self.shouldAttemptConnect,
                  self.handshakingState,
                  !self.handshakeState,
                  self.connectionGeneration == generation,
                  self.bleConnected else {

                logger.log(
                    "[BLE] Old handshake retry discarded"
                )

                return
            }

            self.attemptHandshakeOnBLEQueue(
                generation: generation
            )
        }

        handshakeRetryWorkItem?.cancel()
        handshakeRetryWorkItem = retry

        bleQueue.asyncAfter(
            deadline: .now() + handshakeRetryInterval,
            execute: retry
        )
    }

    /*
     Called when the BlueWatch protocol actually responds.
     */
    private func didCompleteHandshakeOnBLEQueue() {

        guard started,
              bleConnected,
              handshakingState else {
            return
        }

        handshakeState = true
        handshakingState = false
        handshakeAttempts = 0

        cancelHandshakeTimers()

        logger.log("[BLE] Handshake Successful!")

        publishHandshakeState(
            successful: true,
            handshaking: false
        )

        publishStatus("Connected")

        /*
         These happen after the BLE protocol is confirmed.
         */
        DispatchQueue.main.async {

            Task {

                await LocationManager.shared.sendLocation()

                await WeatherManager.shared.updateWeatherAndSend()
            }
        }
    }

    // MARK: - Force reconnect

    /*
     This is deliberately stronger than startHandshake(force: true).

     If the BLE connection is stale, retrying the protocol alone is useless.
     We physically disconnect and rebuild the BLE connection.
     */
    private func forceReconnectOnBLEQueue(reason: String) {

        guard started,
              shouldAttemptConnect else {
            return
        }

        logger.log(
            "[BLE] FORCE RECONNECT: \(reason)"
        )

        let oldPeripheral = peripheral

        /*
         Invalidate EVERYTHING belonging to the old connection first.
         */
        invalidateConnectionState(
            reason: reason
        )

        publishConnectionState(false)

        publishHandshakeState(
            successful: false,
            handshaking: false
        )

        publishStatus("Reconnecting...")

        guard let p = oldPeripheral else {

            connectionInProgress = false

            if central.state == .poweredOn {
                connectOnBLEQueue()
            }

            return
        }

        /*
         Tell the web bridge immediately.
         */
        DispatchQueue.main.async { [weak self] in

            self?.webView?.evaluateJavaScript(
                "window.__bluetoothDisconnected && window.__bluetoothDisconnected()"
            )
        }

        /*
         cancelPeripheralConnection will normally result in
         didDisconnectPeripheral.

         To avoid waiting indefinitely if CoreBluetooth doesn't deliver
         the callback immediately, the callback itself is still the normal
         reconnection path.
         */
        central.cancelPeripheralConnection(p)

        /*
         If it is already disconnected, reconnect directly.
         */
        if p.state != .connected &&
            p.state != .connecting {

            connectionInProgress = false

            bleQueue.asyncAfter(
                deadline: .now() + 0.5
            ) { [weak self] in

                guard let self,
                      self.started,
                      self.shouldAttemptConnect else {
                    return
                }

                self.connectOnBLEQueue()
            }
        }
    }

    // MARK: - Native send

    func sendJSON(data: Codable) {

        let encoder = JSONEncoder()

        guard let jsonData = try? encoder.encode(data),
              let jsonString = String(
                data: jsonData,
                encoding: .utf8
              ) else {

            logger.log(
                "[BLE] Failed to encode JSON"
            )

            return
        }

        send(jsonString)
    }

    func send(
        _ text: String,
        sendRaw: Bool = false
    ) {

        bleQueue.async { [weak self] in
            guard let self else { return }

            self.pendingMessages.append(
                (text, sendRaw)
            )

            self.drainSendQueue()
        }
    }

    private func sendOnBLEQueue(
        _ text: String,
        sendRaw: Bool = false
    ) {

        pendingMessages.append(
            (text, sendRaw)
        )

        drainSendQueue()
    }

    private func sendNextChunk() {

        guard !writeInProgress,
              let p = peripheral,
              let c = currentWriteCharacteristic,
              !pendingChunks.isEmpty else {

            if pendingChunks.isEmpty {

                sendBusy = false

                drainSendQueue()
            }

            return
        }

        writeInProgress = true

        let chunk = pendingChunks.removeFirst()

        p.writeValue(
            chunk,
            for: c,
            type: .withResponse
        )
    }

    private func drainSendQueue() {

        guard !sendBusy,
              !pendingMessages.isEmpty else {
            return
        }

        guard started,
              bleConnected,
              let c = writeCharacteristic else {

            /*
             Don't silently retain messages from an old connection.
             */
            pendingMessages.removeAll()

            return
        }

        sendBusy = true

        let message = pendingMessages.removeFirst()

        let text = message.0
        let sendRaw = message.1

        let payload =
            (sendRaw ? "RAW: " : "") +
            text +
            "|"

        let base64Payload =
            payload
                .data(using: .utf8)?
                .base64EncodedString() ?? ""

        let jsCommand =
            "\u{10}require('bluewatch').receive(atob('\(base64Payload)'));\n"

        guard let fullData =
                jsCommand.data(using: .utf8) else {

            sendBusy = false

            drainSendQueue()

            return
        }

        let chunkSize =
            Settings.shared.optimizedBtChunks
            ? 15
            : 40

        logger.log(
            "ChunkSize \(chunkSize, privacy: .public)"
        )

        pendingChunks.removeAll()

        var offset = 0

        while offset < fullData.count {

            let length =
                min(
                    chunkSize,
                    fullData.count - offset
                )

            pendingChunks.append(
                fullData.subdata(
                    in: offset..<(offset + length)
                )
            )

            offset += length
        }

        currentWriteCharacteristic = c

        sendNextChunk()
    }

    // MARK: - Write queue for Web Bluetooth

    private func enqueueWrite(
        callId: Int,
        data: Data,
        char: CBCharacteristic
    ) {

        writeQueue.append(
            WriteJob(
                callId: callId,
                data: data,
                char: char
            )
        )

        drainWriteQueue()
    }

    private func drainWriteQueue() {

        guard started,
              bleConnected,
              !writeBusy,
              let p = peripheral else {
            return
        }

        while !writeQueue.isEmpty {

            guard p.canSendWriteWithoutResponse else {

                writeBusy = true

                return
            }

            let job = writeQueue.removeFirst()

            p.writeValue(
                job.data,
                for: job.char,
                type: .withoutResponse
            )

            wbResolve(
                id: job.callId,
                result: [:]
            )
        }

        writeBusy = false
    }

    // MARK: - Web Bluetooth bridge

    func handleWebBluetoothMessage(
        id: Int,
        method: String,
        args: [String: Any]
    ) {

        bleQueue.async { [weak self] in
            guard let self else { return }

            guard self.started else {

                self.wbReject(
                    id: id,
                    error: "Bluetooth is not started"
                )

                return
            }

            logger.log(
                "[WB] → \(method) id=\(id)"
            )

            switch method {

            case "requestDevice":

                self.wbRequestDevice(
                    id: id
                )

            case "gattConnect":

                self.wbGattConnect(
                    id: id,
                    args: args
                )

            case "gattDisconnect":

                self.wbGattDisconnect(
                    id: id
                )

            case "getPrimaryService":

                self.wbGetPrimaryService(
                    id: id,
                    args: args
                )

            case "getCharacteristic":

                self.wbGetCharacteristic(
                    id: id,
                    args: args
                )

            case "startNotifications":

                self.wbStartNotifications(
                    id: id,
                    args: args
                )

            case "stopNotifications":

                self.wbStopNotifications(
                    id: id,
                    args: args
                )

            case "readValue":

                self.wbReadValue(
                    id: id,
                    args: args
                )

            case "writeValue":

                self.wbWriteValue(
                    id: id,
                    args: args
                )

            default:

                self.wbReject(
                    id: id,
                    error: "Unknown method: \(method)"
                )
            }
        }
    }

    private func wbRequestDevice(id: Int) {

        guard started else {

            wbReject(
                id: id,
                error: "Bluetooth is not started"
            )

            return
        }

        activeWebNotifications.removeAll()
        wbCharacteristics.removeAll()
        wbServices.removeAll()

        writeQueue.removeAll()
        writeBusy = false

        incomingBuffer = ""

        if let p = peripheral,
           bleConnected,
           setupComplete,
           notificationsReady {

            let deviceId =
                p.identifier.uuidString

            let name =
                p.name ?? "Bangle.js"

            logger.log(
                "[WB] requestDevice → \(name)"
            )

            DispatchQueue.main.async { [weak self] in

                self?.webView?.evaluateJavaScript(
                    "window.__bluetoothResetSession && window.__bluetoothResetSession()"
                ) { [weak self] _, _ in

                    guard let self else { return }

                    self.bleQueue.async {

                        self.wbResolve(
                            id: id,
                            result: [
                                "deviceId": deviceId,
                                "name": name
                            ]
                        )
                    }
                }
            }

        } else {

            logger.log(
                "[WB] requestDevice parked — waiting for setup"
            )

            DispatchQueue.main.async { [weak self] in

                self?.webView?.evaluateJavaScript(
                    "window.__bluetoothResetSession && window.__bluetoothResetSession()"
                )
            }

            pendingRequestDevice = id

            if !bleConnected {

                connectOnBLEQueue()
            }
        }
    }

    private func wbGattConnect(
        id: Int,
        args: [String: Any]
    ) {

        guard let deviceId =
                args["deviceId"] as? String,
              let p = peripheral,
              p.identifier.uuidString == deviceId,
              bleConnected else {

            wbReject(
                id: id,
                error: "Bangle.js not connected"
            )

            return
        }

        wbResolve(
            id: id,
            result: [
                "deviceId": deviceId
            ]
        )
    }

    private func wbGattDisconnect(id: Int) {

        activeWebNotifications.removeAll()

        writeQueue.removeAll()
        writeBusy = false

        wbResolve(
            id: id,
            result: [:]
        )
    }

    private func wbGetPrimaryService(
        id: Int,
        args: [String: Any]
    ) {

        guard let deviceId =
                args["deviceId"] as? String,
              let requestedUUID =
                args["serviceUUID"] as? String,
              let p = peripheral,
              p.identifier.uuidString == deviceId,
              bleConnected else {

            wbReject(
                id: id,
                error: "Device not found"
            )

            return
        }

        if let service =
            p.services?.first(where: {

                $0.uuid.uuidString
                    .caseInsensitiveCompare(
                        requestedUUID
                    )
                    == .orderedSame
            }) {

            let serviceId =
                service.uuid.uuidString

            wbServices[serviceId] = service

            logger.log(
                "[WB] getPrimaryService: \(serviceId)"
            )

            wbResolve(
                id: id,
                result: [
                    "serviceId": serviceId
                ]
            )

            return
        }

        pendingServices[deviceId] = (
            id,
            requestedUUID
        )

        p.discoverServices([
            CBUUID(string: requestedUUID)
        ])
    }

    private func wbGetCharacteristic(
        id: Int,
        args: [String: Any]
    ) {

        guard let serviceId =
                args["serviceId"] as? String,
              let requestedUUID =
                args["charUUID"] as? String,
              let service =
                wbServices[serviceId] else {

            wbReject(
                id: id,
                error: "Service not found"
            )

            return
        }

        if let char =
            service.characteristics?.first(where: {

                $0.uuid.uuidString
                    .caseInsensitiveCompare(
                        requestedUUID
                    )
                    == .orderedSame
            }) {

            let charId =
                char.uuid.uuidString

            wbCharacteristics[charId] = char

            logger.log(
                "[WB] getCharacteristic: \(charId) isNotifying=\(char.isNotifying) props=\(char.properties.rawValue)"
            )

            wbResolve(
                id: id,
                result: [
                    "charId": charId,
                    "props": char.properties.rawValue
                ]
            )

            return
        }

        pendingChars[serviceId] = (
            id,
            requestedUUID
        )

        service.peripheral?.discoverCharacteristics(
            [CBUUID(string: requestedUUID)],
            for: service
        )
    }

    private func wbStartNotifications(
        id: Int,
        args: [String: Any]
    ) {

        guard let charId =
                args["charId"] as? String,
              let char =
                wbCharacteristics[charId] else {

            wbReject(
                id: id,
                error: "Characteristic not found"
            )

            return
        }

        activeWebNotifications.insert(charId)

        if char.isNotifying {

            wbResolve(
                id: id,
                result: [:]
            )

            return
        }

        pendingNotify[charId] = id

        char.service?.peripheral?.setNotifyValue(
            true,
            for: char
        )
    }

    private func wbStopNotifications(
        id: Int,
        args: [String: Any]
    ) {

        if let charId =
            args["charId"] as? String {

            activeWebNotifications.remove(
                charId
            )
        }

        wbResolve(
            id: id,
            result: [:]
        )
    }

    private func wbReadValue(
        id: Int,
        args: [String: Any]
    ) {

        guard let charId =
                args["charId"] as? String,
              let char =
                wbCharacteristics[charId] else {

            wbReject(
                id: id,
                error: "Characteristic not found"
            )

            return
        }

        pendingReads[charId] = id

        char.service?.peripheral?.readValue(
            for: char
        )
    }

    private func wbWriteValue(
        id: Int,
        args: [String: Any]
    ) {

        guard let charId =
                args["charId"] as? String,
              let char =
                wbCharacteristics[charId],
              let values =
                args["value"] as? [Int] else {

            wbReject(
                id: id,
                error: "Bad write args"
            )

            return
        }

        let data =
            Data(
                values.map {
                    UInt8(clamping: $0)
                }
            )

        if char.properties.contains(
            .writeWithoutResponse
        ) {

            enqueueWrite(
                callId: id,
                data: data,
                char: char
            )

        } else {

            char.service?.peripheral?.writeValue(
                data,
                for: char,
                type: .withResponse
            )

            wbResolve(
                id: id,
                result: [:]
            )
        }
    }

    // MARK: - Web Bluetooth JS helpers

    func wbResolve(
        id: Int,
        result: Any
    ) {

        guard let json =
                try? JSONSerialization.data(
                    withJSONObject: result
                ),
              let str =
                String(
                    data: json,
                    encoding: .utf8
                ) else {

            return
        }

        DispatchQueue.main.async { [weak self] in

            self?.webView?.evaluateJavaScript(
                "window.__bluetoothCallback(\(id), null, \(str))"
            )
        }
    }

    func wbReject(
        id: Int,
        error: String
    ) {

        let safe =
            error
                .replacingOccurrences(
                    of: "\\",
                    with: "\\\\"
                )
                .replacingOccurrences(
                    of: "\"",
                    with: "'"
                )

        DispatchQueue.main.async { [weak self] in

            self?.webView?.evaluateJavaScript(
                "window.__bluetoothCallback(\(id), \"\(safe)\", null)"
            )
        }
    }

    private func wbFireNotification(
        charId: String,
        bytes: [UInt8]
    ) {

        let arr =
            bytes.map {
                Int($0)
            }

        guard let json =
                try? JSONSerialization.data(
                    withJSONObject: arr
                ),
              let str =
                String(
                    data: json,
                    encoding: .utf8
                ) else {

            return
        }

        let preview =
            String(
                bytes.prefix(8).compactMap {

                    $0 >= 32 && $0 < 127
                    ? Character(
                        UnicodeScalar($0)
                    )
                    : nil
                }
            )

        logger.log(
            "[WB] notify \(bytes.count)B \"\(preview)\""
        )

        DispatchQueue.main.async { [weak self] in

            self?.webView?.evaluateJavaScript(
                "window.__bluetoothNotify('\(charId)', \(str))"
            )
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(
        _ central: CBCentralManager
    ) {

        switch central.state {

        case .poweredOn:

            logger.log(
                "[BLE] Bluetooth powered on"
            )

            guard started,
                  shouldAttemptConnect else {

                publishStatus("Ready")
                return
            }

            /*
             RESTORATION PATH

             If iOS restored a peripheral while the app was suspended,
             finish its GATT setup now that CoreBluetooth is actually
             powered on.
             */
            if restoredPeripheralPendingSetup != nil {

                handlePendingRestorationOnPoweredOn()

                return
            }

            /*
             NORMAL STARTUP / RECONNECT PATH
             */
            publishStatus("Ready")

            if !bleConnected,
               !connectionInProgress {

                connectOnBLEQueue()
            }

        case .poweredOff:

            logger.log(
                "[BLE] Bluetooth powered off"
            )

            invalidateConnectionState(
                reason: "Bluetooth powered off"
            )

            endSetupBackgroundTask()

            publishConnectionState(false)

            publishHandshakeState(
                successful: false,
                handshaking: false
            )

            publishStatus("Bluetooth Off")

        case .resetting:

            logger.log(
                "[BLE] Bluetooth resetting"
            )

            invalidateConnectionState(
                reason: "Bluetooth resetting"
            )

            publishConnectionState(false)

            publishStatus("Resetting...")

        case .unauthorized:

            publishStatus(
                "Bluetooth Unauthorized"
            )

        case .unsupported:

            publishStatus(
                "Bluetooth Unsupported"
            )

        case .unknown:

            publishStatus(
                "Waiting for Bluetooth..."
            )

        @unknown default:

            publishStatus(
                "Bluetooth Unknown"
            )
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        willRestoreState dict: [String: Any]
    ) {

        logger.log(
            "[BLE] willRestoreState — process restored"
        )

        /*
         Restore auto-start behavior.
         */
        if !started {

            guard UserDefaults.standard.bool(
                forKey: autoStartKey
            ) else {

                logger.log(
                    "[BLE] Restoration ignored — auto-start disabled"
                )

                return
            }

            started = true
            shouldAttemptConnect = true
        }

        guard
            let peripherals =
                dict[
                    CBCentralManagerRestoredStatePeripheralsKey
                ] as? [CBPeripheral],

            let restored =
                peripherals.first else {

            logger.log(
                "[BLE] No restored peripherals"
            )

            return
        }

        /*
         A restoration is a new logical connection generation.
         */
        connectionGeneration = UUID()

        peripheral = restored
        restored.delegate = self

        logger.log(
            "[BLE] Restored peripheral \(restored.identifier), state=\(restored.state.rawValue)"
        )

        publishStatus(
            "Restoring..."
        )

        /*
         IMPORTANT:

         Do NOT perform GATT operations here.

         CBCentralManager may still be initializing.

         We simply save the restored peripheral and allow
         centralManagerDidUpdateState(.poweredOn) to continue.
         */
        restoredPeripheralPendingSetup = restored

        bleConnected = false
        connectionInProgress = false

        setupComplete = false
        notificationsReady = false

        handshakeState = false
        handshakingState = false
        handshakeAttempts = 0

        logger.log(
            "[BLE] Restored peripheral saved — waiting for Bluetooth power"
        )
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {

        guard started,
              shouldAttemptConnect else {
            return
        }

        logger.log(
            "[BLE] Discovered \(peripheral.name ?? "Bangle.js")"
        )

        setupAndConnect(peripheral)
    }

    func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {

        guard started,
              shouldAttemptConnect else {

            central.cancelPeripheralConnection(
                peripheral
            )

            return
        }

        /*
         NEW PHYSICAL CONNECTION = NEW GENERATION.
         */
        connectionGeneration = UUID()

        let generation =
            connectionGeneration

        restoredPeripheralPendingSetup = nil

        self.peripheral = peripheral

        peripheral.delegate = self

        connectionInProgress = false
        bleConnected = true

        setupComplete = false
        notificationsReady = false

        handshakeState = false
        handshakingState = false
        handshakeAttempts = 0

        incomingBuffer = ""

        writeCharacteristic = nil
        currentWriteCharacteristic = nil

        pendingChunks.removeAll()
        writeInProgress = false

        sendBusy = false
        pendingMessages.removeAll()

        cancelHandshakeTimers()
        cancelSetupWatchdog()

        activeWebNotifications.removeAll()
        wbServices.removeAll()
        wbCharacteristics.removeAll()

        pendingServices.removeAll()
        pendingChars.removeAll()
        pendingReads.removeAll()
        pendingNotify.removeAll()

        writeQueue.removeAll()
        writeBusy = false

        logger.log(
            "[BLE] Connected — generation \(generation)"
        )

        publishConnectionState(true)

        publishHandshakeState(
            successful: false,
            handshaking: false
        )

        publishStatus(
            "Setting up Bluetooth..."
        )

        beginSetupBackgroundTask()

        startSetupWatchdog(
            generation: generation,
            peripheral: peripheral
        )

        peripheral.discoverServices(
            [serviceUUID]
        )
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {

        logger.log(
            "[BLE] Failed to connect: \(error?.localizedDescription ?? "unknown")"
        )

        guard started,
              shouldAttemptConnect else {
            return
        }

        connectionInProgress = false
        bleConnected = false
        setupComplete = false
        notificationsReady = false

        cancelSetupWatchdog()
        cancelHandshakeTimers()

        publishConnectionState(false)

        publishHandshakeState(
            successful: false,
            handshaking: false
        )

        publishStatus(
            "Connection Failed"
        )

        if let id = pendingRequestDevice {

            pendingRequestDevice = nil

            wbReject(
                id: id,
                error:
                    error?.localizedDescription
                    ?? "Failed to connect"
            )
        }

        /*
         Reconnect from the BLE queue.

         This is deliberately not a Timer.
         */
        bleQueue.asyncAfter(
            deadline: .now() + 5
        ) { [weak self] in

            guard let self,
                  self.started,
                  self.shouldAttemptConnect,
                  !self.bleConnected else {
                return
            }

            self.connectOnBLEQueue()
        }
    }

    private func handleDisconnect(
        peripheral: CBPeripheral,
        isReconnecting: Bool,
        error: Error?
    ) {

        /*
         IMPORTANT:

         Invalidate the generation FIRST.

         This kills every old handshake retry/watchdog before
         starting another connection.
         */
        logger.log(
            "[BLE] Disconnected: \(error?.localizedDescription ?? "normal") isReconnecting=\(isReconnecting)"
        )

        let shouldReconnect =
            started &&
            shouldAttemptConnect

        invalidateConnectionState(
            reason: "Peripheral disconnected"
        )

        publishConnectionState(false)

        publishHandshakeState(
            successful: false,
            handshaking: false
        )

        publishStatus(
            shouldReconnect
                ? "Reconnecting..."
                : "Disconnected"
        )

        DispatchQueue.main.async{
            LocalData.shared.battery = "--"
        }

        DispatchQueue.main.async {
            LocationManager.shared.stopGPSForwarding()
        }

        DispatchQueue.main.async { [weak self] in

            self?.webView?.evaluateJavaScript(
                "window.__bluetoothDisconnected && window.__bluetoothDisconnected()"
            )
        }

        guard shouldReconnect else {
            return
        }

        /*
         Keep the peripheral reference.

         CoreBluetooth can use it for a persistent reconnect request.
         */
        self.peripheral = peripheral

        guard !isReconnecting else {

            logger.log(
                "[BLE] System is already auto-reconnecting — skipping manual connect"
            )

            return
        }

        connectionInProgress = true

        logger.log(
            "[BLE] Re-issuing persistent connect request"
        )

        /*
         If Bluetooth is not currently powered on, don't issue
         the command yet.

         centralManagerDidUpdateState(.poweredOn) will handle it.
         */
        guard central.state == .poweredOn else {

            connectionInProgress = false

            logger.log(
                "[BLE] Bluetooth not powered on — waiting for poweredOn before reconnect"
            )

            publishStatus(
                "Waiting for Bluetooth..."
            )

            return
        }

        central.connect(
            peripheral,
            options: [
                // Ask CoreBluetooth to maintain the reconnect request across long background periods.
                CBConnectPeripheralOptionEnableAutoReconnect: true,
                CBConnectPeripheralOptionNotifyOnConnectionKey: true,
                CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
                CBConnectPeripheralOptionNotifyOnNotificationKey: true
            ]
        )
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        timestamp: CFAbsoluteTime,
        isReconnecting: Bool,
        error: Error?
    ) {
        handleDisconnect(
            peripheral: peripheral,
            isReconnecting: isReconnecting,
            error: error
        )
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        handleDisconnect(
            peripheral: peripheral,
            isReconnecting: false,
            error: error
        )
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {

        guard started,
              bleConnected,
              self.peripheral === peripheral else {
            return
        }

        if let error {

            logger.log(
                "[BLE] Service discovery error: \(error.localizedDescription)"
            )

            forceReconnectOnBLEQueue(
                reason: "Service discovery error"
            )

            return
        }

        let services =
            peripheral.services ?? []

        logger.log(
            "[BLE] Services discovered: \(services.map { $0.uuid.uuidString })"
        )

        let deviceId =
            peripheral.identifier.uuidString

        /*
         Web Bluetooth service discovery.
         */
        if let entry =
            pendingServices.removeValue(
                forKey: deviceId
            ) {

            if let service =
                services.first(where: {

                    $0.uuid.uuidString
                        .caseInsensitiveCompare(
                            entry.uuid
                        )
                        == .orderedSame
                }) {

                let serviceId =
                    service.uuid.uuidString

                wbServices[serviceId] =
                    service

                wbResolve(
                    id: entry.callId,
                    result: [
                        "serviceId": serviceId
                    ]
                )

            } else {

                wbReject(
                    id: entry.callId,
                    error: "Service not found"
                )
            }

            return
        }

        guard !services.isEmpty else {

            logger.log(
                "[BLE] No services found"
            )

            forceReconnectOnBLEQueue(
                reason: "No services found"
            )

            return
        }

        /*
         Only discover the UART characteristics on our target service.

         This avoids unnecessary discovery callbacks from unrelated services.
         */
        let targetServices =
            services.filter {
                $0.uuid == serviceUUID
            }

        guard !targetServices.isEmpty else {

            logger.log(
                "[BLE] Nordic UART service not found"
            )

            forceReconnectOnBLEQueue(
                reason: "UART service missing"
            )

            return
        }

        for service in targetServices {

            peripheral.discoverCharacteristics(
                [txUUID, rxUUID],
                for: service
            )
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {

        guard started,
              bleConnected,
              self.peripheral === peripheral else {
            return
        }

        if let error {

            logger.log(
                "[BLE] Characteristic discovery error: \(error.localizedDescription)"
            )

            forceReconnectOnBLEQueue(
                reason: "Characteristic discovery error"
            )

            return
        }

        let serviceId =
            service.uuid.uuidString

        logger.log(
            "[BLE] Characteristics for \(serviceId): \(service.characteristics?.map { $0.uuid.uuidString } ?? [])"
        )

        /*
         Web Bluetooth characteristic discovery.
         */
        if let entry =
            pendingChars.removeValue(
                forKey: serviceId
            ) {

            if let char =
                service.characteristics?.first(where: {

                    $0.uuid.uuidString
                        .caseInsensitiveCompare(
                            entry.uuid
                        )
                        == .orderedSame
                }) {

                let charId =
                    char.uuid.uuidString

                wbCharacteristics[charId] =
                    char

                wbResolve(
                    id: entry.callId,
                    result: [
                        "charId": charId,
                        "props": char.properties.rawValue
                    ]
                )

            } else {

                wbReject(
                    id: entry.callId,
                    error: "Characteristic not found"
                )
            }

            return
        }

        guard service.uuid == serviceUUID else {
            return
        }

        guard let characteristics =
                service.characteristics else {

            forceReconnectOnBLEQueue(
                reason: "UART characteristics missing"
            )

            return
        }

        var foundTX = false
        var foundRX = false

        for characteristic in characteristics {

            if characteristic.uuid == txUUID {

                writeCharacteristic =
                    characteristic

                foundTX = true

                logger.log(
                    "[BLE] TX ready props=\(characteristic.properties.rawValue)"
                )
            }

            if characteristic.uuid == rxUUID {

                foundRX = true

                logger.log(
                    "[BLE] RX characteristic found — enabling notifications"
                )

                /*
                 IMPORTANT:

                 Do NOT mark notificationsReady yet.

                 setNotifyValue(true) is asynchronous.
                 We wait for didUpdateNotificationStateFor.
                 */
                peripheral.setNotifyValue(
                    true,
                    for: characteristic
                )
            }
        }

        if !foundTX {

            logger.log(
                "[BLE] TX characteristic missing"
            )
        }

        if !foundRX {

            logger.log(
                "[BLE] RX characteristic missing"
            )
        }

        /*
         setupComplete is intentionally NOT set here.

         It is set only when:

             TX found
             +
             RX found
             +
             notifications actually enabled
         */
        if foundTX && foundRX {

            logger.log(
                "[BLE] TX/RX discovered — waiting for notification confirmation"
            )
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {

        guard started,
              bleConnected,
              self.peripheral === peripheral else {
            return
        }

        let charId =
            characteristic.uuid.uuidString

        logger.log(
            "[BLE] Notification state \(charId.prefix(8)) notifying=\(characteristic.isNotifying)"
        )

        /*
         Web Bluetooth notification request.
         */
        if let id =
            pendingNotify.removeValue(
                forKey: charId
            ) {

            if let error {

                wbReject(
                    id: id,
                    error: error.localizedDescription
                )

            } else {

                wbResolve(
                    id: id,
                    result: [:]
                )
            }
        }

        guard characteristic.uuid == rxUUID else {
            return
        }

        if let error {

            logger.log(
                "[BLE] RX notification enable failed: \(error.localizedDescription)"
            )

            forceReconnectOnBLEQueue(
                reason: "RX notification enable failed"
            )

            return
        }

        guard characteristic.isNotifying else {

            logger.log(
                "[BLE] RX notification state is false"
            )

            forceReconnectOnBLEQueue(
                reason: "RX notifications not enabled"
            )

            return
        }

        guard writeCharacteristic != nil else {

            logger.log(
                "[BLE] RX notifications ready but TX is missing"
            )

            return
        }

        /*
         NOW setup is actually complete.
         */
        notificationsReady = true
        setupComplete = true

        cancelSetupWatchdog()

        logger.log(
            "[BLE] Setup complete — RX notifications confirmed"
        )

        /*
         Resolve a parked Web Bluetooth request.
         */
        if let id = pendingRequestDevice {

            pendingRequestDevice = nil

            wbResolve(
                id: id,
                result: [
                    "deviceId":
                        peripheral.identifier.uuidString,

                    "name":
                        peripheral.name ?? "Bangle.js"
                ]
            )
        }

        /*
         Start handshake BEFORE ending the temporary background
         execution window.

         This gives the initial handshake its best opportunity to
         run when restoration happened in the background.
         */
        beginHandshakeOnBLEQueue()

        endSetupBackgroundTask()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {

        guard started,
              bleConnected,
              self.peripheral === peripheral else {
            return
        }

        if let error {

            logger.log(
                "[BLE] RX error: \(error.localizedDescription)"
            )

            return
        }

        guard let data =
                characteristic.value else {

            logger.log(
                "[BLE] RX empty data packet"
            )

            return
        }

        let charId =
            characteristic.uuid.uuidString

        let bytes =
            [UInt8](data)

        if let raw =
            String(
                data: data,
                encoding: .utf8
            ) {

            print(
                "RAW RX FROM WATCH: '\(raw)'"
            )

            logger.log(
                "[BLE RAW] charId=\(charId, privacy: .public) bytes=\(bytes.count, privacy: .public) text=\(raw.debugDescription, privacy: .public)"
            )

        } else {

            logger.log(
                "[BLE RAW] charId=\(charId, privacy: .public) bytes=\(bytes.count, privacy: .public) non-UTF8"
            )
        }

        /*
         Web Bluetooth notifications.
         */
        if activeWebNotifications.contains(charId) {

            if let id =
                pendingReads.removeValue(
                    forKey: charId
                ) {

                wbResolve(
                    id: id,
                    result: bytes
                )

            } else {

                wbFireNotification(
                    charId: charId,
                    bytes: bytes
                )
            }
        }

        guard characteristic.uuid == rxUUID else {
            return
        }

        guard let text =
                String(
                    data: data,
                    encoding: .utf8
                ) else {
            return
        }

        /*
         BLE packets can split lines arbitrarily, or contain several
         lines in one notification.

         Continue using the persistent buffer.
         */
        incomingBuffer += text

        logger.log(
            "[Receive] incoming buffer: \(self.incomingBuffer, privacy: .public)"
        )

        while let newlineRange =
                incomingBuffer.range(
                    of: "\n"
                ) {

            let line =
                String(
                    incomingBuffer[
                        ..<newlineRange.lowerBound
                    ]
                )
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

            incomingBuffer =
                String(
                    incomingBuffer[
                        newlineRange.upperBound...
                    ]
                )

            guard !line.isEmpty else {
                continue
            }

            logger.log(
                "[Receive] got command: \(line, privacy: .public)"
            )

            guard let prefixRange =
                    line.range(
                        of: "bwRX:"
                    ) else {

                logger.log(
                    "[Receive] Ignoring non-BlueWatch line"
                )

                continue
            }

            let payload =
                String(
                    line[
                        prefixRange.upperBound...
                    ]
                )

            logger.log(
                "[Receive] payload: \(payload, privacy: .public)"
            )

            /*
             Handshake completion is handled on the BLE queue,
             not the main queue.

             This is critical because the old code could have:

                 BLE callback
                    ↓
                 main queue
                    ↓
                 handshake state

             while a reconnect was already occurring on the BLE queue.
             */
            if !handshakeState &&
                handshakingState {

                didCompleteHandshakeOnBLEQueue()
            }

            publishLastMessage(
                payload
            )

            /*
             CommandInterpreter is existing application logic.
             It is kept on the BLE queue to preserve ordering with
             received data.
             */
            if let payloadData =
                payload.data(using: .utf8),
               let json =
                try? JSONSerialization.jsonObject(
                    with: payloadData
                ) as? [String: Any] {

                logger.log(
                    "[Receive] registered as JSON: \(payload, privacy: .public)"
                )

                DispatchQueue.main.async { [weak self] in

                    guard let self else {
                        return
                    }

                    self.commandInterpreter.handleJSON(
                        json
                    )
                }

            } else {

                logger.log(
                    "[Receive] registered as command: \(payload, privacy: .public)"
                )

                DispatchQueue.main.async { [weak self] in

                    guard let self else {
                        return
                    }

                    self.commandInterpreter.handleCommand(
                        command: payload
                    )
                }
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {

        guard self.peripheral === peripheral else {
            return
        }

        if let error {

            logger.log(
                "[BLE] Write error: \(error.localizedDescription)"
            )

            writeInProgress = false
            sendBusy = false

            pendingChunks.removeAll()

            /*
             If the connection is still supposedly alive,
             don't leave the send system permanently locked.
             */
            if bleConnected {

                drainSendQueue()
            }

            return
        }

        logger.log(
            "[BLE] Write success"
        )

        writeInProgress = false

        sendNextChunk()
    }

    func peripheralIsReady(
        toSendWriteWithoutResponse peripheral: CBPeripheral
    ) {

        guard started,
              bleConnected,
              self.peripheral === peripheral else {
            return
        }

        writeBusy = false

        drainWriteQueue()
    }
}
