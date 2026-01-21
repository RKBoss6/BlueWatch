//
//  BlueWatchApp.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 2/28/25.
//

import SwiftUI
import HealthKit

@main
struct BlueWatchApp: App {
    init() {
        requestHealthAuthorization()
    }
    let healthStore=HKHealthStore()
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
    func requestHealthAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("HealthKit not available")
            return
        }

        // Define the types you want to read/write
        let typesToWrite: Set<HKSampleType> = [
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .stepCount)!,
            HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
        ]

        let typesToRead: Set<HKObjectType> = typesToWrite

        // Request authorization
        healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead) { success, error in
            if success {
                print("HealthKit authorization granted")
            } else {
                print("HealthKit authorization denied:", error?.localizedDescription ?? "")
            }
        }
    }
}

