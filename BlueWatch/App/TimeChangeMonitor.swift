//
//  TimeChangeMonitor.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 11/3/26.
//

import Foundation
import UIKit
import Combine

class TimeChangeMonitor {
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        startMonitoring()
    }
    
    private func startMonitoring() {
        NotificationCenter.default
            .publisher(for: UIApplication.significantTimeChangeNotification)
            .sink { [weak self] _ in
                self?.handleSignificantTimeChange()
            }
            .store(in: &cancellables)
    }
    
    private func handleSignificantTimeChange() {
        if(BLEManager.shared.isConnected&&BLEManager.shared.handshakeSuccessful&&Settings.shared.updateTimeOnSignificantChange){
            DataSendManager.sendCurrentTime()
        }
    }
}
