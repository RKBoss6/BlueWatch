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
@Observable
class AuthManager: NSObject, @MainActor CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    var isLocationAuthorizedAlways: Bool = false
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
        isLocationAuthorizedAlways = (locationManager.authorizationStatus == .authorizedAlways)
        print("[LOCATIONAUTH] bool = \(self.isLocationAuthorizedAlways)")


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
            locationManager.requestAlwaysAuthorization()
        }
    }
    
    // Delegate callback handles the user choice
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus

        print("[LOCATIONAUTH] Status = \(status.rawValue)")

        // Always update the observable state.
        isLocationAuthorizedAlways = (status == .authorizedAlways)

        print("[LOCATIONAUTH] bool = \(self.isLocationAuthorizedAlways)")

        // Only resume the continuation if we're currently waiting for a request.
        if let continuation = continuation, status != .notDetermined {
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
