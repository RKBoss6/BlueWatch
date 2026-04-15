//
//  Utils.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 4/15/26.
//

import Foundation
import UserNotifications

enum Utils{
    static func pushNotification(title:String,subtitle:String,body:String,id:String){
        let center=UNUserNotificationCenter.current();
        Task{
            try await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = subtitle
        content.sound = UNNotificationSound.default
        
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        
        center.add(request) { error in
            if let error = error {
                print("Error adding notification: \(error)")
            }
        }
        print("pushed")
    }
}
