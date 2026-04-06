import Foundation
import HealthKit

class CommandInterpreter {
    public static let shared = CommandInterpreter()

    weak var ble: BLEManager?

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
        
        switch (j["type"] as? String){
        case "health":
            handleHealthData(j)
        case "systemInfo":
            handleSystemInfo(j)
        default:
            break
        }
        
        
    }
    func handleSystemInfo(_ data: [String: Any]){
        if let batt = data["batt"] as? Double{
            LocalData.shared.battery=String(batt)+"%"
        }
    }
    func handleHealthData(_ data: [String: Any]) {
        if let hr = data["hr"] as? Double {
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
            syncSteps(watchTotal: total)
        }

    }

    private func syncSteps(watchTotal: Double) {
        let type       = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let startOfDay = Calendar.current.startOfDay(for: Date())

        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate),
            HKQuery.predicateForObjects(from: .default())
        ])

        let query = HKStatisticsQuery(
            quantityType:            type,
            quantitySamplePredicate: predicate,
            options:                 .cumulativeSum
        ) { [weak self] _, result, error in
            guard let self else { return }

            if let error {
                print("Step query failed: \(error)")
                return
            }

            let alreadySaved = result?.sumQuantity()?.doubleValue(for: .count()) ?? 0
            let delta        = watchTotal - alreadySaved

            guard delta > 0 else {
                print("Steps: no delta (watch=\(Int(watchTotal)) saved=\(Int(alreadySaved)))")
                return
            }

            let sample = HKCumulativeQuantitySample(
                type:     type,
                quantity: HKQuantity(unit: .count(), doubleValue: delta),
                start:    Date().addingTimeInterval(-60),
                end:      Date()
            )
            self.healthStore.save(sample) { ok, err in
                print(ok ? "Saved \(Int(delta)) steps" : "Step save failed: \(err!)")
            }
        }

        healthStore.execute(query)
    }
}
