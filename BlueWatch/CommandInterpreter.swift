//
//  CommandCases.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 1/4/26.
//

import Foundation
import HealthKit
class CommandInterpreter {
    public static let shared=CommandInterpreter()
    weak var ble:BLEManager?
    private let healthStore = HKHealthStore()
    private let findPhoneAlarm = FindPhoneAlarm()
    // Request authorization to write heart rate and steps if needed
    
    public func handleCommand(command:String){
        // Handle commands
        switch command {
        case "FindPhone":
            findPhoneAlarm.start()
        case "StopFindPhone":
            findPhoneAlarm.stop()
        case "Pinging Connection...":
            print(ble!)
            ble?.send("iPhone Connected")
            print("sent")
        default:
            break
        }
    }
    
    func handleHealthData(_ data: [String: Any]) {

            if let hr = data["hr"] as? Double {
                let type = HKQuantityType.quantityType(forIdentifier: .heartRate)!
                let quantity = HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: hr)
                let sample = HKQuantitySample(type: type, quantity: quantity, start: Date().addingTimeInterval(-600), end: Date())
                self.healthStore.save(sample) { success, error in
                    if !success {
                        print("Failed to save HR:", error ?? "")
                    }else{
                        print("Sucessfully sent HR")
                    }
                }
            }

            if let steps = data["steps"] as? Double {
                let type = HKQuantityType.quantityType(forIdentifier: .stepCount)!
                let quantity = HKQuantity(unit: HKUnit.count(), doubleValue: steps)
                let sample = HKQuantitySample(type: type, quantity: quantity, start: Date().addingTimeInterval(-600), end: Date())
                self.healthStore.save(sample) { success, error in
                    if !success {
                        print("Failed to save steps:", error ?? "")
                    }else{
                        print("Sucessfully sent steps")
                    }
                }
            }
        
            if let temp = data["temp"] as? Double {
                let type = HKQuantityType.quantityType(forIdentifier: .appleSleepingWristTemperature)!
                let quantity = HKQuantity(unit: HKUnit.count(), doubleValue: temp)
                let sample = HKQuantitySample(type: type, quantity: quantity, start: Date().addingTimeInterval(-600), end: Date())
                self.healthStore.save(sample) { success, error in
                    if !success {
                        print("Failed to save temp:", error ?? "")
                    }else{
                        print("Sucessfully sent temp")
                    }
                }
            }
        
        }
    
}

    


