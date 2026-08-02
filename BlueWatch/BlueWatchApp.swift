import SwiftUI
import HealthKit
import BackgroundTasks
import SwiftData

@main
struct BlueWatchApp: App {
    // Use the singleton we defined
    @StateObject private var bleManager = BLEManager.instance
    
    // ID must match Info.plist "Permitted background task scheduler identifiers"
    static let weatherTaskID = "com.rk.bluewatch.weatherRefresh"
    
    @Environment(\.scenePhase) var scenePhase
    
    init() {
        // Initialize BLE as early as possible for state restoration
        _ = BLEManager.instance
        
        // Register the background task immediately on launch
       // BGTaskScheduler.shared.register(forTaskWithIdentifier: BlueWatchApp.weatherTaskID, using: nil) { task in
       //     BlueWatchApp.handleWeatherTask(task: task as! BGAppRefreshTask)
       // }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bleManager)
        }
        .modelContainer(for: DataPoint.self)
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .background:
                
                logger.log("📱 App entering background")
                
                //BlueWatchApp.scheduleAppRefresh()
                
            case .active:
                logger.log("📱 App became active")
                // Reconnect if needed when app comes to foreground
                if !bleManager.isConnected {
                    bleManager.connect()
                }
                // fetch up to date system info
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
        
        let types: Set = [
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .stepCount)!
        ]
        
        healthStore.requestAuthorization(toShare: types, read: types) { success, error in
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
}
