//
//  HealthManager.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 8/16/26.
//

import Foundation
import HealthKit
class HealthManager {
    public static let shared = HealthManager()
    
    private let healthStore  = HKHealthStore()
    private let lastWatchStepsKey = "LastWatchSteps"
    private let lastWatchActiveCaloriesKey = "LastActiveCalories"
    private let lastWatchRestingCaloriesKey = "LastRestingCalories"


    func handleHealthData(_ data: [String: Any]) {
        var time: Date
        if let t = data["start"] as? Double {
            time=Date(timeIntervalSince1970: t / 1000)
        }else{
            time=Date()
        }
        if let hr = data["hr"] as? Double {
            
            DataService.addDataPointInBackground(timestamp: time, value: hr, type: DataType.heartRate, alwaysSave: true)
            if(Settings.shared.sendToHealthKit==true){
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

        if let stepsTotal = data["steps"] as? Double {
            DataService.addDataPointInBackground(timestamp: time, value: stepsTotal, type: DataType.steps,alwaysSave: true)
            if(Settings.shared.sendToHealthKit==true){
                syncSteps(watchTotal: stepsTotal)
            }
        }
        
        if let activeCals = data["activeCalories"] as? Double {
            
            DataService.addDataPointInBackground(timestamp: time, value: activeCals, type: .activeCalories, alwaysSave: true)
            if(Settings.shared.sendToHealthKit==true){
                syncActiveCalories(watchTotal: activeCals)
            }
        }
        
        if let bmrCalories = data["bmrCalories"] as? Double {
            
            DataService.addDataPointInBackground(timestamp: time, value: bmrCalories, type: .restingCalories, alwaysSave: true)
            if(Settings.shared.sendToHealthKit==true){
                syncRestingCalories(watchTotal: bmrCalories)
            }
        }

    }
    

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
    
    
    private func syncActiveCalories(watchTotal: Double) {
        let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!

        let defaults = UserDefaults.standard
        let today = Calendar.current.startOfDay(for: Date())

        // Reset every new day
        let savedDay = defaults.object(forKey: "LastActiveCaloriesSyncDay") as? Date ?? .distantPast
        if !Calendar.current.isDate(savedDay, inSameDayAs: today) {
            defaults.set(today, forKey: "LastActiveCaloriesSyncDay")
            defaults.removeObject(forKey: lastWatchActiveCaloriesKey)
        }

        let lastWatchTotal = defaults.object(forKey: lastWatchActiveCaloriesKey) != nil
            ? defaults.double(forKey: lastWatchActiveCaloriesKey)
            : 0

        var delta = watchTotal - lastWatchTotal
        
        // Watch rebooted or counter reset.
        if delta < 0 {
            logger.log("Watch active calorie counter reset")
            delta = watchTotal
        }

        guard delta > 0 else {
            logger.log("No new active calories")
            return
        }

        let sample = HKCumulativeQuantitySample(
            type: type,
            quantity: HKQuantity(unit: .largeCalorie(), doubleValue: delta),
            start: Date().addingTimeInterval(-600), // last 10 minutes
            end: Date()
        )

        healthStore.save(sample) { ok, err in
            if ok {
                defaults.set(watchTotal, forKey: self.lastWatchActiveCaloriesKey)
                logger.log("Saved \(Int(delta)) active calories (watch total \(Int(watchTotal)))")
            } else {
                logger.log("Failed to save active calories: \(err?.localizedDescription ?? "Unknown error")")
            }
        }
    }
    
    private func syncRestingCalories(watchTotal: Double) {
        let type = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned)!

        let defaults = UserDefaults.standard
        let today = Calendar.current.startOfDay(for: Date())

        // Reset every new day
        let savedDay = defaults.object(forKey: "LastRestingCaloriesSyncDay") as? Date ?? .distantPast
        if !Calendar.current.isDate(savedDay, inSameDayAs: today) {
            defaults.set(today, forKey: "LastRestingCaloriesSyncDay")
            defaults.removeObject(forKey: lastWatchRestingCaloriesKey)
        }

        let lastWatchTotal = defaults.object(forKey: lastWatchRestingCaloriesKey) != nil
            ? defaults.double(forKey: lastWatchRestingCaloriesKey)
            : 0

        var delta = watchTotal - lastWatchTotal
        
        // Watch rebooted or counter reset.
        if delta < 0 {
            logger.log("Watch resting calorie counter reset")
            delta = watchTotal
        }

        guard delta > 0 else {
            logger.log("No new resting calories")
            return
        }

        let sample = HKCumulativeQuantitySample(
            type: type,
            quantity: HKQuantity(unit: .largeCalorie(), doubleValue: delta),
            start: Date().addingTimeInterval(-600), // last 10 minutes
            end: Date()
        )

        healthStore.save(sample) { ok, err in
            if ok {
                defaults.set(watchTotal, forKey: self.lastWatchRestingCaloriesKey)
                logger.log("Saved \(Int(delta)) resting calories (watch total \(Int(watchTotal)))")
            } else {
                logger.log("Failed to save resting calories: \(err?.localizedDescription ?? "Unknown error")")
            }
        }
    }
    
}
