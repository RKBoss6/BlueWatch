import Foundation
import HealthKit

class CommandInterpreter {
    
    public static let shared = CommandInterpreter()

    public var ble: BLEManager?

    private let healthStore    = HKHealthStore()
    private let findPhoneAlarm = FindPhoneAlarm()
    
    
    @MainActor
    public func handleCommand(command: String) {
        logger.log("[CommandInterpreter] received: '\(command, privacy: .public)' len=\(command.count, privacy: .public)")
        
        switch command {
        case "Start Polling GPS":
            LocationManager.shared.startGPSForwarding()
        case "Handshake Successful":
            ble?.didCompleteHandshake()
        case "Stop Polling GPS":
            LocationManager.shared.stopGPSForwarding()
        case "FindPhone":
            findPhoneAlarm.start()
        case "StopFindPhone":
            findPhoneAlarm.stop()
        case "Pinging Connection...":
            ble?.send("iPhone Connected")
        case "Request Weather":
            if(Settings.instance.pushWeather){
                Task{
                    await WeatherManager.shared.updateWeatherAndSend()
                }
            }
        case "Request Location":
            if(Settings.instance.pushLocation){
                Task {
                    await LocationManager.shared.sendLocation()
                }
            }
        default:
            break
        }
    }
    func handleJSON(_ j: [String: Any]){
        logger.log("Got json")
        
        switch (j["type"] as? String){
        case "health":
            handleHealthData(j)
        case "systemInfo":
            logger.log("Got system json")
            handleSystemInfo(j)
        default:
            break
        }
        
        
    }
    func handleSystemInfo(_ data: [String: Any]){
        if let batt = data["batt"] as? Double{
            logger.log("Got battery \(String(batt))"  )
            DataService.addDataPointInBackground(timestamp: Date(), value: batt, type: .battery)
            DispatchQueue.main.async {
                LocalData.shared.battery = String(Int(batt))
                logger.log("batt updated")
                
            }
            if(batt<80 && Settings.instance.lowBattNotify){
                Utils.pushNotification(title: "Bangle.js", body: "Battery below 15%. Charge soon!", id: "LowBatt")
            }
        }
    }
    func handleHealthData(_ data: [String: Any]) {
        var time: Date
        if let t = data["start"] as? Double {
            time=Date(timeIntervalSince1970: t / 1000)
        }else{
            time=Date()
        }
        if let hr = data["hr"] as? Double {
            
            DataService.addDataPointInBackground(timestamp: time, value: hr, type: DataType.heartRate)
            if(Settings.instance.sendToHealthKit==true){
                let type = HKQuantityType.quantityType(forIdentifier: .heartRate)!
                
                let quantity = HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: hr)
                let context: HKHeartRateMotionContext = (data["state"] as? String) == "sedentary"
                ? .sedentary : .notSet
                let sample = HKQuantitySample(
                    type:     type,
                    quantity: quantity,
                    start:    time.addingTimeInterval(-600),
                    end:      time,
                    metadata: [HKMetadataKeyHeartRateMotionContext: context.rawValue]
                )
                healthStore.save(sample) { ok, err in
                    //logger.log("HR: \(err!)")
                }
            }
        }

        if let total = data["steps"] as? Double {
            DataService.addDataPointInBackground(timestamp: time, value: total, type: DataType.steps)
            if(Settings.instance.sendToHealthKit==true){
                syncSteps(watchTotal: total)
            }
        }

    }
    
    private let lastWatchStepsKey = "LastWatchSteps"

    private func syncSteps(watchTotal: Double) {
        let type = HKQuantityType.quantityType(forIdentifier: .stepCount)!

        let defaults = UserDefaults.standard
        let today = Calendar.current.startOfDay(for: Date())

        // Reset every new day
        let savedDay = defaults.object(forKey: "LastStepSyncDay") as? Date ?? .distantPast
        if !Calendar.current.isDate(savedDay, inSameDayAs: today) {
            defaults.set(today, forKey: "LastStepSyncDay")
            defaults.removeObject(forKey: lastWatchStepsKey)
        }

        let lastWatchTotal = defaults.double(forKey: lastWatchStepsKey)

        // First reading of the day: establish the baseline, don't save anything.
        if defaults.object(forKey: lastWatchStepsKey) == nil {
            defaults.set(watchTotal, forKey: lastWatchStepsKey)
            logger.log("Initialized watch step baseline: \(Int(watchTotal))")
            return
        }

        var delta = watchTotal - lastWatchTotal
        
        // Watch rebooted or counter reset.
        if delta < 0 {
            logger.log("Watch step counter reset")
            delta = watchTotal
        }

        guard delta > 0 else {
            logger.log("No new steps")
            return
        }

        let sample = HKCumulativeQuantitySample(
            type: type,
            quantity: HKQuantity(unit: .count(), doubleValue: delta),
            start: Date().addingTimeInterval(-600), // last 10 minutes
            end: Date()
        )

        healthStore.save(sample) { ok, err in
            if ok {
                defaults.set(watchTotal, forKey: self.lastWatchStepsKey)
                logger.log("Saved \(Int(delta)) steps (watch total \(Int(watchTotal)))")
            } else {
                logger.log("Failed to save steps: \(err?.localizedDescription ?? "Unknown error")")
            }
        }
    }
}
