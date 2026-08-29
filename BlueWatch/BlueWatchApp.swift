import SwiftUI
import HealthKit
import BackgroundTasks
import SwiftData
import CoreLocation
import HealthKit
import UserNotifications

@main
struct BlueWatchApp: App {
    static let hkTypes: Set = [
        HKQuantityType.quantityType(forIdentifier: .heartRate)!,
        HKQuantityType.quantityType(forIdentifier: .stepCount)!,
        HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned)!
    ]
    // Use the singleton we defined
    @StateObject private var bleManager = BLEManager.shared

    static func checkNotificationPermissions() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized ||
               settings.authorizationStatus == .provisional
    }
    
    static func hasHealthKitPermissions() -> Bool {
        if HKHealthStore.isHealthDataAvailable(),
           let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            let healthStatus = HKHealthStore().authorizationStatus(for: stepType)
            // .sharingAuthorized means you have permission to WRITE/SHARE data
           return (healthStatus == .sharingAuthorized)
        } else {
            return false
        }
    }

    static var hasLocationPermissions: Bool {
        let status = CLLocationManager().authorizationStatus
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }
    // ID must match Info.plist "Permitted background task scheduler identifiers"
    static let weatherTaskID = "com.rk.bluewatch.weatherRefresh"
    
    @Environment(\.scenePhase) var scenePhase
    
    init() {
        // Initialize BLE as early as possible for state restoration
        _ = BLEManager.shared
        
        // Register the background task immediately on launch
       // BGTaskScheduler.shared.register(forTaskWithIdentifier: BlueWatchApp.weatherTaskID, using: nil) { task in
       //     BlueWatchApp.handleWeatherTask(task: task as! BGAppRefreshTask)
       // }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bleManager)
                .tint(Color("AccentColor"))
        }
        .modelContainer(for: DataPoint.self)
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .background:
                
                logger.log("📱 App entering background")
                
                //BlueWatchApp.scheduleAppRefresh()
                
            case .active:
                logger.log("📱 App became active")
                if !bleManager.isConnected {
                    
                    bleManager.connect()
                    
                } else if !bleManager.handshakeSuccessful {
                    
                    // BLE link is already up but the handshake never finished.
                    // Note: no `&& !isHandshaking` check here — isHandshaking can be
                    // stranded `true` from a retry that got interrupted by the app
                    // being suspended overnight, and if we required it to be false
                    // first, this fallback could never fire in exactly the state it
                    // exists to recover from. force: true always restarts clean.
                    logger.log("📱 [Fallback] Connected but handshake not done — forcing retry")
                    bleManager.startHandshake(force: true)
                }
                if(bleManager.isConnected && bleManager.handshakeSuccessful){
                    bleManager.send("Request System Info")
                }
                
            case .inactive:
                logger.log("📱 App inactive")
                
            @unknown default:
                break
            }
        }
    }
    
    static func handleWeatherTask(task: BGAppRefreshTask) {
        logger.log("🌤️ Background weather task started")
        
        task.expirationHandler = {
            logger.log("⏰ Weather task expired")
            task.setTaskCompleted(success: false)
        }
        
        Task {
            // Background fetches have a strict time limit (approx 30s)
            await WeatherManager.shared.updateWeatherAndSend()
            BlueWatchApp.scheduleAppRefresh()
            task.setTaskCompleted(success: true)
            logger.log("✅ Weather task completed")
        }
    }

    static func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: BlueWatchApp.weatherTaskID)
        // Run every 15 minutes (iOS will batch this intelligently)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 7 * 60)
        
        
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.log("📅 Next weather refresh scheduled")
        } catch {
            logger.log("❌ Could not schedule weather refresh: \(error)")
        }
    }
    
    static func requestHealthAuthorization() {
        let healthStore = HKHealthStore()
        guard HKHealthStore.isHealthDataAvailable() else { return }
        
        let types: Set = hkTypes
        
        healthStore.requestAuthorization(toShare: types, read: []) { success, error in
            if let error = error {
                logger.log("❌ HealthKit authorization error: \(error)")
            } else {
                logger.log("✅ HealthKit authorized")
            }
        }
    }
    
    static func requestNotificationAuthorization() async{
        let center = UNUserNotificationCenter.current()
        do{
            try await center.requestAuthorization(options: [.alert, .sound, .badge])

        }catch {
            logger.log("Error requesting notification")
        }
    }

    static func hasHealthKitPromptBeenShown() async -> Bool {
        let healthStore = HKHealthStore()
        
        guard HKHealthStore.isHealthDataAvailable() else {
            return false
        }
        
        do {
            // FIX: Use the correct async API name here
            let status = try await healthStore.statusForAuthorizationRequest(toShare: hkTypes, read: [])
            
            switch status {
            case .unnecessary:
                return true
            case .shouldRequest:
                return false
            case .unknown:
                return false
            @unknown default:
                return false
            }
        } catch {
            return false
        }
    }


}
