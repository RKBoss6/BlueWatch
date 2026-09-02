//
//  AppMetricManager.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 8/31/26.
//

import Foundation
import SwiftUI
import StoreKit
class AppMetricManager: ObservableObject {
    @AppStorage("successfulSyncCount") private var successfulConnections = 0
    @AppStorage("expandedMetricViewOpens") private var expandedMetricViewOpens = 0
    @AppStorage("lastVersionPrompted") private var lastVersionPrompted = ""
    static var shared:AppMetricManager = AppMetricManager()
    func log(){
        logger.log("App Metrics: successfulConnections: \(self.successfulConnections, privacy: .public), expandedMetricViewOpens: \(self.expandedMetricViewOpens, privacy: .public), lastVersionPrompted: \(self.lastVersionPrompted, privacy: .public)")
    }
    func increaseConnectionCount() {
        successfulConnections += 1
        log()
    }
    func increaseExpandedMetricViewOpens() {
        expandedMetricViewOpens += 1
        log()
    }
    init(){
        log()
    }
    func tryTriggerReview(requestReviewAction: RequestReviewAction) {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        
        // should have at least 50 successful connections, should be different version than last request, and must have opened metrics at least 25 times
        if(successfulConnections >= 50 && lastVersionPrompted != currentVersion && expandedMetricViewOpens >= 25){
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                requestReviewAction()
                self.lastVersionPrompted = currentVersion
            }
        }else{
            logger.log("App Metrics: Review failed")
        }
        log()
        
       
    }
}
