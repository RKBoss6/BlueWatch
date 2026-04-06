import SwiftUI
import HealthKit
import BackgroundTasks

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
                .onAppear {
                    // Ask for Health/Location permissions when UI appears
                    requestHealthAuthorization()
                    
                    // Ensure BLE is connected
                    if !bleManager.isConnected {
                        bleManager.connect()
                    }
                }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .background:
                print("📱 App entering background")
                //BlueWatchApp.scheduleAppRefresh()
                
            case .active:
                print("📱 App became active")
                // Reconnect if needed when app comes to foreground
                if !bleManager.isConnected {
                    bleManager.connect()
                }
                
            case .inactive:
                print("📱 App inactive")
                
            @unknown default:
                break
            }
        }
    }
    
    static func handleWeatherTask(task: BGAppRefreshTask) {
        print("🌤️ Background weather task started")
        
        task.expirationHandler = {
            print("⏰ Weather task expired")
            task.setTaskCompleted(success: false)
        }
        
        Task {
            // Background fetches have a strict time limit (approx 30s)
            await WeatherManager.shared.updateWeatherAndSend()
            BlueWatchApp.scheduleAppRefresh()
            task.setTaskCompleted(success: true)
            print("✅ Weather task completed")
        }
    }

    static func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: BlueWatchApp.weatherTaskID)
        // Run every 15 minutes (iOS will batch this intelligently)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 7 * 60)
        
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("📅 Next weather refresh scheduled")
        } catch {
            print("❌ Could not schedule weather refresh: \(error)")
        }
    }
    
    func requestHealthAuthorization() {
        let healthStore = HKHealthStore()
        guard HKHealthStore.isHealthDataAvailable() else { return }
        
        let types: Set = [
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .stepCount)!
        ]
        
        healthStore.requestAuthorization(toShare: types, read: types) { success, error in
            if let error = error {
                print("❌ HealthKit authorization error: \(error)")
            } else {
                print("✅ HealthKit authorized")
            }
        }
    }
}
