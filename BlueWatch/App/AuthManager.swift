//
//  AuthManager.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 8/31/26.
//

import Foundation
import CoreLocation
import HealthKit
import UserNotifications

@MainActor
class AuthManager: NSObject, @MainActor CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var continuation: CheckedContinuation<Bool, Never>?
    let hkTypes: Set = [
        HKQuantityType.quantityType(forIdentifier: .heartRate)!,
        HKQuantityType.quantityType(forIdentifier: .stepCount)!,
        HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned)!
    ]
    static let shared = AuthManager()
    
    override init() {
        super.init()
        locationManager.delegate = self
    }
    
    /// Requests authorization and returns true if granted, false otherwise
    func requestLocationAuth() async -> Bool {
        let status = locationManager.authorizationStatus
        
        // 1. Return early if already decided
        if status == .authorizedWhenInUse || status == .authorizedAlways { return true }
        if status == .denied || status == .restricted { return false }
        
        // 2. Wrap the delegate response in a continuation
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            locationManager.requestWhenInUseAuthorization()
        }
    }
    
    // Delegate callback handles the user choice
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let continuation = continuation else { return }
        
        let status = manager.authorizationStatus
        // Skip the 'notDetermined' status which triggers on initial load
        if status != .notDetermined {
            let isAuthorized = (status == .authorizedWhenInUse || status == .authorizedAlways)
            continuation.resume(returning: isAuthorized)
            self.continuation = nil
        }
    }
    
    func requestHealthAuthorization() async -> Bool {
        let healthStore = HKHealthStore()
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        
        let types: Set = hkTypes
        
        do {
            try await healthStore.requestAuthorization(toShare: types, read: [])
            logger.log("HealthKit authorized")
            return true
        } catch {
            logger.log("HealthKit authorization error: \(error)")
            return false
        }
    }
    func requestNotificationAuthorization() async{
        let center = UNUserNotificationCenter.current()
        do{
            try await center.requestAuthorization(options: [.alert, .sound, .badge])

        }catch {
            logger.log("Error requesting notification")
        }
    }
}
