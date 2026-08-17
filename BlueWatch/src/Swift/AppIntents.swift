//
//  AppIntents.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 8/15/26.
//

import SwiftUI

import AppIntents

struct SendMessageIntent: AppIntent {
    static var title: LocalizedStringResource = "Send Message"
        
    static var description = IntentDescription("Sends a string to your connected watch")
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Message",
    )
    var message: String

    static var parameterSummary: some ParameterSummary {
        Summary("Send \(\.$message) to my watch")
    }

    init() {}
    init(message: String) {
        self.message = message
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        if(BLEManager.instance.isConnected){
            BLEManager.instance.send(message)
            return .result(dialog: "Successfully Sent")
        }
        return .result(dialog: "Watch Not Connected")
    }
}
struct IsConnectedIntent: AppIntent {
    // The name displayed in the Shortcuts app
    static var title: LocalizedStringResource = "Get Watch Connection"
    
    // Optional description for context
    static var description = IntentDescription("Checks if watch connected, and returns the value",resultValueName: "Watch Connected?")

    // Controls if the intent forces the main app to open in the foreground
    static var openAppWhenRun: Bool = false
    
    func perform() async throws -> some IntentResult & ReturnsValue<Bool>  {
        return .result(value:BLEManager.instance.isConnected)
        
    }
} 
struct SendWeatherIntent: AppIntent {
    // The name displayed in the Shortcuts app
    static var title: LocalizedStringResource = "Send Weather"
    
    // Optional description for context
    static var description = IntentDescription("Sends the latest weather to your watch if within rate-limits")

    // Controls if the intent forces the main app to open in the foreground
    static var openAppWhenRun: Bool = false
    
    func perform() async throws -> some IntentResult {
        if(BLEManager.instance.isConnected){
            await WeatherManager.shared.updateWeatherAndSend()
            return .result(dialog: "Successfully Sent")
        }
        return .result(dialog: "Watch Not Connected")
        // Execute background logic here (e.g., save to Database/CoreData)
        
    }
}
struct SendLocationIntent: AppIntent {
    // The name displayed in the Shortcuts app
    static var title: LocalizedStringResource = "Send Location"
    
    // Optional description for context
    static var description = IntentDescription("Sends your location to your watch's 'mylocation.json'")

    // Controls if the intent forces the main app to open in the foreground
    static var openAppWhenRun: Bool = false
    
    func perform() async throws -> some IntentResult {
        // Execute background logic here (e.g., save to Database/CoreData)
        if(BLEManager.instance.isConnected){
            await LocationManager.shared.sendLocation()
            return .result(dialog: "Successfully Sent")

            
        }
        return .result(dialog: "Watch Not Connected")
        
    }
}
/*
struct ShortcutsProvider: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .grayBlue
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SendMessageIntent(),
            phrases: [
                "send text to my watch through \(.applicationName)",
                "send text to my watch using \(.applicationName)",
                "use \(.applicationName) to send text to my watch",
            ],
            shortTitle: "Send Text",
            systemImageName: "applewatch.radiowaves.left.and.right"
        )
        AppShortcut(
            intent: SendWeatherIntent(),
            phrases: [
                "send latest weather to my watch using \(.applicationName)",
                "push latest weather to my watch using \(.applicationName)",
                "send the weather to my watch using \(.applicationName)",
                "update the weather on my watch using \(.applicationName)",

            ],
            shortTitle: "Push Weather",
            systemImageName: "cloud.sun.rain.fill"
        )
        AppShortcut(
            intent: SendLocationIntent(),
            phrases: [
                "send my location to my watch using \(.applicationName)",
                "push my location to my watch using \(.applicationName)",
                "update the location on my watch using \(.applicationName)",
            ],
            shortTitle: "Push Location",
            systemImageName: "location.fill"
        )
    }
}
*/
