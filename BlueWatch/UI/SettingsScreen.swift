//
//  WatchSettingsScreen.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 3/4/25.
//

import SwiftUI


enum sendFrequency: Int, CaseIterable, Identifiable {
    case nuts, cookies, blueberries
    var id: Self { self }
}
struct WatchSettingsScreen: View {
    @State var settings:Settings=Settings.instance
    @State var temp:Bool=false
    var body: some View {
        VStack {
            HStack {

                Text("Bangle.js 2")
                    .font(.title)
                    .fontWeight(.bold)
                
               
            }.padding()
            Form{
                
                Section("Bluetooth"){
                    Toggle(isOn:$settings.autoConnect) {
                        Text("Automatically Connect")
                    }
                }
                Section(
                    header: Text("Push Data"),
                    footer: Text("Periodically pushes location data for 'MyLocation.json'")){
                    Toggle(isOn:$settings.pushWeather ) {
                        Text("Push weather updates")
                        
                    }
                    Toggle(isOn:$settings.pushLocation ) {
                        Text("Push location updates")
                        
                    }
                    
                }
                
                Section("Web View"){
                    HStack {
                        Text("Web URL:")
                        TextField("placeholder.com", text: $settings.webURL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    Toggle(isOn:$settings.enableHScroll) {
                        Text("Enable Horizontal Scrolling")
                    }
                    Toggle(isOn:$settings.enableVScroll) {
                        Text("Enable Vertical Scrolling")
                    }
                }
                Section("Other"){
                    Toggle(isOn:$settings.lowBattNotify) {
                        Text("Notify when watch battery low")
                    }
                }
                
            }
        }
        .appBackground()
        
    }
}

#Preview {
    WatchSettingsScreen()
}
