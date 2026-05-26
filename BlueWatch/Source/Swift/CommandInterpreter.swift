import Foundation
import HealthKit

class CommandInterpreter {
    
    public static let shared = CommandInterpreter()

    var ble: BLEManager?

    private let healthStore    = HKHealthStore()
    private let findPhoneAlarm = FindPhoneAlarm()

    public func handleCommand(command: String) {
        switch command {
        case "FindPhone":
            findPhoneAlarm.start()
        case "StopFindPhone":
            findPhoneAlarm.stop()
        case "Pinging Connection...":
            ble?.send("iPhone Connected")
        case "Request Weather":
            Task{
                await WeatherManager.shared.updateWeatherAndSend()
            }
        case "Request Location":
            Task{
                await LocationManager.shared.sendLocation()
            }
        default:
            break
        }
    }
    func handleJSON(_ j: [String: Any]){
        print("Got json")
        switch (j["type"] as? String){
        case "health":
            handleHealthData(j)
        case "systemInfo":
            print("Got system json")
            handleSystemInfo(j)
        default:
            break
        }
        
        
    }
    func handleSystemInfo(_ data: [String: Any]){
        if let batt = data["batt"] as? Double{
            print("Got battery " + String(batt))
            DataService.addDataPointInBackground(timestamp: Date(), value: batt, type: .battery)
            DispatchQueue.main.async {
                LocalData.shared.battery = String(Int(batt))
                print("batt updated")
                
            }
            if(batt<80 && Settings.instance.lowBattNotify){
                Utils.pushNotification(title: "Bangle.js", subtitle: "Battery below 15%. Charge soon!", body: "", id: "LowBatt")
            }
        }
    }
    func handleHealthData(_ data: [String: Any]) {
        if let hr = data["hr"] as? Double {
            DataService.addDataPointInBackground(timestamp: Date(), value: hr, type: DataType.heartRate)
            let type = HKQuantityType.quantityType(forIdentifier: .heartRate)!
            var time: Date
            if let t = data["time"] as? Double {
                time=Date(timeIntervalSince1970: t / 1000)
            }else{
                time=Date()
            }
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
                print(ok ? "Saved HR" : " HR: \(err!)")
            }
        }

        if let total = data["steps"] as? Double {
            DataService.addDataPointInBackground(timestamp: Date(), value: total, type: DataType.steps)
            syncSteps(watchTotal: total)
        }

    }

    private func syncSteps(watchTotal: Double) {
        let type = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let startOfDay = Calendar.current.startOfDay(for: Date())

        // FIX 1: Use HKSource.default() to only count steps THIS APP saved.
        // This stops the iPhone pocket steps from interfering with your watch steps.
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate),
            HKQuery.predicateForObjects(from: HKSource.default())
        ])

        let query = HKStatisticsQuery(
            quantityType: type,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { [weak self] _, result, error in
            guard let self else { return }

            let alreadySaved = result?.sumQuantity()?.doubleValue(for: .count()) ?? 0
            
            // FIX 2: Handle midnight reset. If watch says 100 but Health says 12000,
            // it's a new day; the delta should just be the 100.
            var delta = watchTotal - alreadySaved
            if watchTotal < alreadySaved {
                delta = watchTotal
            }
            
            guard delta > 0 else {
                print("Steps: no delta (watch=\(Int(watchTotal)) saved=\(Int(alreadySaved)))")
                return
            }
            
            let sample = HKCumulativeQuantitySample(
                type: type,
                quantity: HKQuantity(unit: .count(), doubleValue: delta),
                start: Date().addingTimeInterval(-60),
                end: Date()
            )
            
            self.healthStore.save(sample) { ok, err in
                if ok { print("Saved \(Int(delta)) steps to HealthKit") }
            }
        }

        healthStore.execute(query)
    }

}
