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
import OSLog
import SwiftUI
enum Utils{
    static func pushNotification(title:String,body:String,id:String){
        Task{
            await BlueWatchApp.requestNotificationAuthorization()
        }
        let center=UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default
        
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        
        center.add(request) { error in
            if let error = error {
                logger.log("Error adding notification: \(error)")
            }
        }
        logger.log("pushed")
    }
    static func unitSuffix(dataType: DataType) -> String {
        switch dataType {
        case .heartRate:
            return " bpm"
        case .steps:
            return " steps"
        case .activeCalories, .restingCalories:
            return " kcal"
        case .battery:
            return "%"
        case .test, .bluetoothBoundary:
            return " test units"
        }
    }
    static  func minutesBetweenDates(_ fromDate: Date, toDate: Date) -> Int? {
        // Use Calendar.current to access the user's current calendar and time zone settings.
        let calendar = Calendar.current
        
        // Request only the .minute component. The Calendar intelligently calculates
        // the total difference in minutes, considering any DST or time zone shifts.
        let components = calendar.dateComponents([.minute], from: fromDate, to: toDate)
        
        // The result is an optional Int
        return components.minute
    }

    
}

let logger = Logger(subsystem: "com.RK.BlueWatch", category: "Debugging")



enum DataType: String, Codable {
    case steps
    case heartRate
    case battery
    case test
    case activeCalories
    case restingCalories
    case bluetoothBoundary
}
private struct IsPreviewKey: EnvironmentKey {
    static let defaultValue: Bool = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
}

extension EnvironmentValues {
    var isPreview: Bool {
        get { self[IsPreviewKey.self] }
        set { self[IsPreviewKey.self] = newValue }
    }
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
    /// Wipes all DataPoint data from the database safely on a background thread
    static func clearAllData() {
        let container = DataManager.sharedContainer
        
        Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            
            do {
                // Batch deletes all instances of DataPoint matching the schema
                try context.delete(model: DataPoint.self)
                
                // Persist the changes instantly
                try context.save()
                logger.log("Successfully deleted all DataPoint data.")
            } catch {
                logger.log("Failed to delete SwiftData records: \(error.localizedDescription)")
            }
        }
    }
}

enum DataService {
    static func addDataPointInBackground(timestamp: Date, value: Double, type: DataType, alwaysSave:Bool) {
        let container = DataManager.sharedContainer
        
        Task.detached(priority: .background) {
            let context = ModelContext(container)
            
            // Setup a fetch to find the LATEST point of this type
            let typeRawValue = type.rawValue
            let descriptor = FetchDescriptor<DataPoint>(
                predicate: #Predicate<DataPoint> { $0.rawType == typeRawValue },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            
            // Limit the fetch to 1 to save performance
            var limitedDescriptor = descriptor
            limitedDescriptor.fetchLimit = 1
            // Check to make sure values arent the same only when alwaysSave is false
            if(!alwaysSave){
                // Compare values
                if let lastPoint = try? context.fetch(limitedDescriptor).first {
                    if lastPoint.value == value && Date().timeIntervalSince(lastPoint.timestamp) < 60*9 /*Only skip a save if its less than 9 minutes apart from the last one.*/  {
                        logger.log("Skipping save: Value for \(type.rawValue, privacy: .public) hasn't changed (\(value))")
                        return // Stop here, don't insert
                    }
                }
            }
            // If we get here, the value is different or it's the first entry
            let newPoint = DataPoint(timestamp: timestamp, value: value, type: type)
            context.insert(newPoint)
            
            try? context.save()
        }
    }
    static func dataPointExists(for type: DataType) -> Bool {
        let context = ModelContext(DataManager.sharedContainer)
        let typeRawValue = type.rawValue
        
        // Predicate to match the type
        let descriptor = FetchDescriptor<DataPoint>(
            predicate: #Predicate<DataPoint> { $0.rawType == typeRawValue }
        )
        
        // Optimize: limit to 1 and remove sorting for speed
        var limitedDescriptor = descriptor
        limitedDescriptor.fetchLimit = 1
        
        // Check if count is greater than 0
        if let count = try? context.fetchCount(limitedDescriptor) {
            return count > 0
        }
        
        return false
    }
}






