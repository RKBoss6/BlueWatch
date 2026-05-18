//
//  Utils.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 4/15/26.
//

import Foundation
import UserNotifications
import SwiftData
import _SwiftData_SwiftUI
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



enum DataType: String, Codable {
    case steps
    case heartRate
    case battery
}

@Model
final class DataPoint {
    var timestamp: Date
    var value: Double
    var rawType: String // Filter against this String

    init(timestamp: Date, value: Double, type: DataType) {
        self.timestamp = timestamp
        self.value = value
        self.rawType = type.rawValue
    }
}


@MainActor
class DataManager {
    static let shared = DataManager()
    
    // 1. Move the container to a static nonisolated property
    nonisolated static let sharedContainer: ModelContainer = {
        let schema = Schema([DataPoint.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [config])
    }()
    
    // Use the global container for the main context
    var mainContext: ModelContext {
        Self.sharedContainer.mainContext
    }
}

enum DataService {
    static func addDataPointInBackground(timestamp: Date, value: Double, type: DataType) {
        let container = DataManager.sharedContainer
        
        Task.detached(priority: .background) {
            let context = ModelContext(container)
            
            // 1. Setup a fetch to find the LATEST point of this type
            let typeRawValue = type.rawValue
            let descriptor = FetchDescriptor<DataPoint>(
                predicate: #Predicate<DataPoint> { $0.rawType == typeRawValue },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            
            // 2. Limit the fetch to 1 to save performance
            var limitedDescriptor = descriptor
            limitedDescriptor.fetchLimit = 1
            
            // 3. Compare values
            if let lastPoint = try? context.fetch(limitedDescriptor).first {
                if lastPoint.value == value {
                    print("Skipping save: Value for \(type.rawValue) hasn't changed (\(value))")
                    return // Stop here, don't insert
                }
            }
            
            // 4. If we get here, the value is different or it's the first entry
            let newPoint = DataPoint(timestamp: timestamp, value: value, type: type)
            context.insert(newPoint)
            
            try? context.save()
        }
    }
}






