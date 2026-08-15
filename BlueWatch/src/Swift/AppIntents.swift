//
//  AppIntents.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 8/15/26.
//

import SwiftUI

import AppIntents

struct SendMessageIntent: AppIntent {
    // The name displayed in the Shortcuts app
    static var title: LocalizedStringResource = "Send Message"
    
    // Optional description for context
    static var description = IntentDescription("Sends a message to your connected watch")

    // Controls if the intent forces the main app to open in the foreground
    static var openAppWhenRun: Bool = false
    @Parameter(title: "Message", default: "")
    var message: String
    static var parameterSummary: some ParameterSummary {
        Summary("Send Message \(\.$message)")
    }
    // Required blank initializer
    init() {}

    init(message: String) {
        self.message = message
    }
    // The execution block
    func perform() async throws -> some IntentResult {
        // Execute background logic here (e.g., save to Database/CoreData)
        BLEManager.instance.send( message )
        
        // Return a successful result status
        return .result()
    }
}

struct SendWeatherIntent: AppIntent {
    // The name displayed in the Shortcuts app
    static var title: LocalizedStringResource = "Push Weather"
    
    // Optional description for context
    static var description = IntentDescription("Sends the latest weather to your watch if within rate-limits")

    // Controls if the intent forces the main app to open in the foreground
    static var openAppWhenRun: Bool = false
    
    func perform() async throws -> some IntentResult {
        // Execute background logic here (e.g., save to Database/CoreData)
        await WeatherManager.shared.updateWeatherAndSend()
        
        return .result()
    }
}
struct SendLocationIntent: AppIntent {
    // The name displayed in the Shortcuts app
    static var title: LocalizedStringResource = "Push Location"
    
    // Optional description for context
    static var description = IntentDescription("Sends your location to your watch's 'mylocation.json'")

    // Controls if the intent forces the main app to open in the foreground
    static var openAppWhenRun: Bool = false
    
    func perform() async throws -> some IntentResult {
        // Execute background logic here (e.g., save to Database/CoreData)
        await LocationManager.shared.sendLocation()
        return .result()
    }
}

struct ShortcutsProvider: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .grayBlue
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SendMessageIntent(),
            phrases: [
                "send message to my watch through \(.applicationName)",
            ],
            shortTitle: "Send Message",
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
            systemImageName: "cloud.sun.rain"
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
