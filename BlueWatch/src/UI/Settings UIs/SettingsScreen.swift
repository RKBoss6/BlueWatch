//
//  WatchSettingsScreen.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 3/4/25.
//

import SwiftUI


struct WatchSettingsScreen: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject var settings: Settings = Settings.instance
    var vm:ViewModel=ViewModel.instance
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
                            Text("Device name:")
                            TextField(ViewModel().savedDevice, text: $settings.deviceName)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                    }
                    .padding()
                    .liquidGlass(cornerRadius: 24)
                    .frame(width:.infinity,height: .infinity)
                    .ignoresSafeArea(.all)
                    .listRowInsets(EdgeInsets())
                }
                .listRowBackground(Color.clear)
                Section{
                    VStack(spacing: 16) {
                        
                        Toggle(isOn:$settings.optimizedBtChunks ) {
                            Text("Optimize chunks")
                            
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
                        
                        Toggle(isOn:$settings.sendToHealthKit ) {
                            Text("Push health data to Apple Health")
                            
                        }
                        .tint(.accentColor)
                        
                        
                    }
                    .padding()
                    .liquidGlass(cornerRadius: 24)
                    .ignoresSafeArea(.all)
                    .listRowInsets(EdgeInsets())
                    
                } header:{
                    Text("Data")
                }
               
                
                    .listRowBackground(Color.clear)
                Section{
                    VStack(spacing: 16) {
                        
    
                        Toggle(isOn:$settings.pushWeather ) {
                            Text("Push weather updates")
                            
                        }
                        .tint(.accentColor)
//                        if(settings.pushWeather){
//                            Divider()
//                            Stepper("Weather Rate Limit: \(settings.weatherRateLimit.formatted(.number.precision(.fractionLength(0)))) min", value: $settings.weatherRateLimit, in: 10...60, step:5)
//
//                        }
                        
                        
                        
                    }
                    .padding()
                    .liquidGlass(cornerRadius: 24)
                    .ignoresSafeArea(.all)
                    .listRowInsets(EdgeInsets())
                    
                }
                footer:{
                    Text("Weather data from [Weather](https://developer.apple.com/weatherkit/data-source-attribution/)")
                }
                
                    .listRowBackground(Color.clear)
                Section{
                    VStack(spacing: 16) {
                        

                        Toggle(isOn:$settings.pushLocation ) {
                            Text("Push location updates")
                            
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
                footer:{
                    Text("Periodically pushes location data to 'MyLocation.json'")
                }
                
                    .listRowBackground(Color.clear)
                
                Section {
                    VStack(spacing: 16) {
                        Button(role:.destructive) {
                            showDeletePrompt=true
                        } label: {
                            Text("Delete saved data")
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
                                .tint(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
                    .listRowInsets(EdgeInsets())
                    .liquidGlass()
                }
                .listRowBackground(Color.clear)
                Section(header: Text("Web View"),
                        footer: Text("Requires an app restart to display new URL in web view")
                        ){
                    VStack(spacing: 16) {
                        HStack {
                                Text("Web URL:")
                                TextField("banglejs.com/apps", text: $settings.webURL)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            }
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
        MoreScreen()
    }
}




// 2. Create the View Modifier for individual Form elements
struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    
    func body(content: Content) -> some View {
        if #available(iOS 26.0,*) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                
        } else {
            content
                .background(in: .rect(cornerRadius: cornerRadius))
        }
    }
}

// 3. Expose them cleanly via View extensions
extension View {
    // Safe modifier that applies Liquid Glass if supported by the OS, otherwise does nothing.
    func liquidGlass(cornerRadius: CGFloat = 24) -> some View {
        self.modifier(LiquidGlassModifier(cornerRadius: cornerRadius))
    }
    
    // Wraps a view hierarchy inside a Glass Effect Container if supported, otherwise passes it straight through.
  
}
