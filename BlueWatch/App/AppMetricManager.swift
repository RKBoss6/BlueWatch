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
    var hasBeenInExpandedMetricView:Bool = false
    @AppStorage("dateLastRequested") private var dateLastRequested: Date = Date(timeIntervalSince1970: 0) // default to 1970 so its a long enough interval
    static var shared:AppMetricManager = AppMetricManager()
    #if DEBUG
    let isDebug = true
    #else
    let isDebug = false
    #endif
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
        let components = Calendar.current.dateComponents([.day], from: dateLastRequested, to: Date())
        
        
        // should have at least 60 successful connections, should be different version than last request, and must have opened metrics at least 35 times
        // shoudl be more than 30 days from last request
        if((successfulConnections >= 60 && lastVersionPrompted != currentVersion && expandedMetricViewOpens >= 35 && (components.day ?? 0) > 30 ) || isDebug){
            if(hasBeenInExpandedMetricView){
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    requestReviewAction()
                    self.dateLastRequested=Date()
                    self.lastVersionPrompted = currentVersion
                }
            }
                
        }else{
            logger.log("App Metrics: Review failed")
        }
        // reset
        hasBeenInExpandedMetricView=false
        
        log()
        
       
    }
}
