//
//  WatchSettingsScreen.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 3/4/25.
//

import SwiftUI

struct ThumbSettingsScreen: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject var settings: Settings = Settings.shared
    var vm:ViewModel=ViewModel.shared
    @State private var showDeletePrompt = false
    
    var body: some View {
        Form{
            
            /*
             Section("Bluetooth"){
             VStack(spacing: 16) {
             Toggle(isOn:$settings.autoConnect) {
             Text("Automatically Connect")
             }
             }
             .padding()
             .liquidGlass(cornerRadius: 24)
             .frame(width:.infinity,height: .infinity)
             .ignoresSafeArea(.all)
             .listRowInsets(EdgeInsets())
             }
             .listRowBackground(Color.clear)
             */
            
            
            Section{
                VStack(spacing: 16) {
                    Toggle(isOn:$settings.showHrThumb ) {
                        Text("Show Heart Rate Metric")
                        
                    }
                    .tint(.accentColor)
                    Divider()
                    Toggle(isOn:$settings.showStepsThumb ) {
                        Text("Show Steps Metric")
                        
                    }
                    .tint(.accentColor)
                    Divider()

                    Toggle(isOn:$settings.showActiveCalThumb ) {
                        Text("Show Active Calories Metric")
                        
                    }
                    .tint(.accentColor)
                    Divider()

                    Toggle(isOn:$settings.showRestingCalThumb ) {
                        Text("Show Resting Calories Metric")
                        
                    }
                    .tint(.accentColor)
                    Divider()
                    Toggle(isOn:$settings.showBatteryThumb ) {
                        Text("Show Battery Metric")
                        
                    }
                    .tint(.accentColor)
                    
                }
                .padding()
                .liquidGlass(cornerRadius: 24)
                .ignoresSafeArea(.all)
                .listRowInsets(EdgeInsets())
            }
            .listRowBackground(Color.clear)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .appBackground()
    }
}

struct WatchSettingsScreen: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject var settings: Settings = Settings.shared
    var vm:ViewModel=ViewModel.shared
    @State private var showDeletePrompt = false

    var body: some View {
        VStack {
            Form{
                
                /*
                Section("Bluetooth"){
                    VStack(spacing: 16) {
                        Toggle(isOn:$settings.autoConnect) {
                            Text("Automatically Connect")
                        }
                    }
                    .padding()
                    .liquidGlass(cornerRadius: 24)
                    .frame(width:.infinity,height: .infinity)
                    .ignoresSafeArea(.all)
                    .listRowInsets(EdgeInsets())
                }
                 .listRowBackground(Color.clear)
                 */
    
                    
                Section("Device"){
                    VStack(spacing: 16) {
                        HStack {
                            Text("Device Name:")
                            TextField(ViewModel().savedDevice, text: $settings.deviceName)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                    }
                    .padding()
                    .liquidGlass(cornerRadius: 24)
                    .ignoresSafeArea(.all)
                    .listRowInsets(EdgeInsets())
                }
                .listRowBackground(Color.clear)
                Section{
                    VStack(spacing: 16) {
                        
                        NavigationLink(destination: ThumbSettingsScreen() ){
                            Text("Show & Hide Metrics")
                        }
                        
                        
                    }
                    .padding()
                    .liquidGlass(cornerRadius: 24)
                    .ignoresSafeArea(.all)
                    .listRowInsets(EdgeInsets())
                    
                } header:{
                    Text("UI")
                }
                .listRowBackground(Color.clear)

                Section{
                    VStack(spacing: 16) {
                        
                        Toggle(isOn:$settings.optimizedBtChunks ) {
                            Text("Optimize Chunks")
                            
                        }
                        .tint(.accentColor)
                        
                        
                    }
                    .padding()
                    .liquidGlass(cornerRadius: 24)
                    .ignoresSafeArea(.all)
                    .listRowInsets(EdgeInsets())
                    
                } header:{
                    Text("Bluetooth")
                } footer:{
                    Text("Lowers chunk size from 40 to 15 bytes for more reliable Bluetooth transmissions. Highly recommended.")
                }
                .listRowBackground(Color.clear)
                Section{
                    VStack(spacing: 16) {
                        
                        Toggle(isOn:$settings.showFindPhoneNotification ) {
                            Text("Show Find Phone Notifications")
                            
                        }
                        .tint(.accentColor)
                        
                        
                    }
                    .padding()
                    .liquidGlass(cornerRadius: 24)
                    .ignoresSafeArea(.all)
                    .listRowInsets(EdgeInsets())
                }footer:{
                    Text("Shows a confirmation notification when the find phone alarm is triggered")
                }
                .listRowBackground(Color.clear)

                Section{
                    VStack(spacing: 16) {
                        
                        Toggle(isOn:$settings.sendToHealthKit ) {
                            Text("Push Health Data to Apple Health")
                            
                        }
                        .tint(.accentColor)
                        
                        
                    Divider()
                        
    
                        Toggle(isOn:$settings.pushWeather ) {
                            Text("Push Weather Updates")
                            
                        }
                        .tint(.accentColor)
//                        if(settings.pushWeather){
//                            Divider()
//                            Stepper("Weather Rate Limit: \(settings.weatherRateLimit.formatted(.number.precision(.fractionLength(0)))) min", value: $settings.weatherRateLimit, in: 10...60, step:5)
//
//
                        Divider()

                        Toggle(isOn:$settings.pushLocation ) {
                            Text("Push Location Updates")
                            
                        }
                        .tint(.accentColor)
                        
                        if(settings.pushLocation){
                            Divider()
                            Stepper("Location Rate Limit: \(settings.locationRateLimit) min", value: $settings.locationRateLimit, in: 0...60, step:5)

                        }
                        
                        
                        
                        
                    }
                    .padding()
                    .liquidGlass(cornerRadius: 24)
                    .ignoresSafeArea(.all)
                    .listRowInsets(EdgeInsets())
                    
                }
                header:{
                    Text("Data")
                }
                footer:{
                    Text("Periodically pushes location data to 'MyLocation.json'\nWeather data from [Weather](https://developer.apple.com/weatherkit/data-source-attribution/)")
                }
                
                    .listRowBackground(Color.clear)
                
                Section {
                    VStack(spacing: 16) {
                        Button(role:.destructive) {
                            showDeletePrompt=true
                        } label: {
                            Text("Delete Saved Data")
                        }
                        .alert("Are you sure?", isPresented: $showDeletePrompt) {
                                Button("Delete", role: .destructive) {
                                    DataManager.clearAllData()
                                }
                                Button("Cancel", role: .cancel) {
                                    // do nothing, just cancel
                                }
                                } message: {
                                    Text("This action permanently deletes the metrics shown in graphs from your device. Data saved to Health will not be deleted.")
                                }
                                .tint(.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
                    .listRowInsets(EdgeInsets())
                    .liquidGlass()
                }
                .listRowBackground(Color.clear)
                Section(header: Text("Web View")){
                    VStack(spacing: 16) {
                        HStack {
                                Text("Web URL:")
                                TextField("banglejs.com/apps", text: $settings.webURL)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                  
                            }
                        Divider()
                    
                            Toggle(isOn:$settings.pullToRefreshWebView) {
                                Text("Pull to Refresh")
                            }
                            .tint(.accentColor)
                        
                        /*
                            Divider()
                        
                        Toggle(isOn:$settings.enableHScroll) {
                            Text("Enable Horizontal Scrolling")
                        }

                            Divider()

                        Toggle(isOn:$settings.enableVScroll) {
                            Text("Enable Vertical Scrolling")v
                        }
                         
                        Divider()
                        
                        Button("Clear Cache") {
                            
                        }
                        .tint(.red)
                         */
                        }
                        .padding()
                        .liquidGlass(cornerRadius: 24)
                        .frame(width:.infinity,height: .infinity)
                        .ignoresSafeArea(.all)
                        .listRowInsets(EdgeInsets())
                    
                    
                }
                .listRowBackground(
                    Color.clear
                )
                .onChange(of: settings.webURL) { _, _ in
                    WebRefreshManager.shared.forceRefresh()
                }
                .onChange(of: settings.pullToRefreshWebView) { _, _ in
                    WebRefreshManager.shared.forceRefresh()
                }
                
                
                
                
//                Section("Other"){
//                    VStack(spacing: 16) {
//                        Toggle(isOn:$settings.lowBattNotify) {
//                            Text("Notify when watch battery low")
//                        }
//                        .tint(.accentColor)
//                    }
//                    .padding()
//                    .liquidGlass(cornerRadius: 24)
//                    .frame(width:.infinity,height: .infinity)
//                    .listRowInsets(EdgeInsets())
//                    
//                }
//                .listRowBackground(Color.clear)
                
                
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Settings")
        .appBackground()
        
    }
}

#Preview {
    NavigationStack{
        WatchSettingsScreen()
    }
}




