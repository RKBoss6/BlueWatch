//
//  WatchSettingsScreen.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 3/4/25.
//

import SwiftUI



struct WatchSettingsScreen: View {
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var settings:Settings=Settings.instance
    @State var temp:Bool=false
    var vm:ViewModel=ViewModel.instance
    @State private var showDeletePrompt = false

    var body: some View {
        VStack {
            HStack {

                Text(settings.deviceName.isEmpty==false ? settings.deviceName : vm.savedDevice)
                    .font(.title)
                    .fontWeight(.bold)
                
               
            }.padding()
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
                        
                        Toggle(isOn:$settings.sendToHealthKit ) {
                            Text("Push health data to Apple Health")
                            
                        }
                        Divider()
                        Toggle(isOn:$settings.pushWeather ) {
                            Text("Push weather updates")
                            
                        }
                        Divider()
                        Toggle(isOn:$settings.pushLocation ) {
                            Text("Push location updates")
                            
                        }
                        
                        
                        
                    }
                    .padding()
                    .liquidGlass(cornerRadius: 24)
                    .ignoresSafeArea(.all)
                    .listRowInsets(EdgeInsets())
                    
                } header:{
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
                            Text("Delete saved data")
                        }
                        .alert("Are you sure?", isPresented: $showDeletePrompt) {
                                    Button("Delete", role: .destructive) {
                                        DataManager.clearAllData()
                                    }
                                    Button("Cancel", role: .cancel) { }
                                } message: {
                                    Text("This action removes all your watch's saved health and battery data from all time on your device. This action cannot be undone.")
                                }
                        .tint(.red)
                    }
                    .frame(maxWidth: .infinity) // Expands horizontally to screen edges
                    .padding(.vertical)
                    .listRowInsets(EdgeInsets())// Adds elegant padding inside the glass bubble
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
                
                Section("Other"){
                    VStack(spacing: 16) {
                        Toggle(isOn:$settings.lowBattNotify) {
                            Text("Notify when watch battery low")
                        }
                    }
                    .padding()
                    .liquidGlass(cornerRadius: 24)
                    .frame(width:.infinity,height: .infinity)
                    .listRowInsets(EdgeInsets())
                    
                }
                .listRowBackground(Color.clear)
                
                
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        
    }
}

#Preview {
    WatchSettingsScreen()
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
