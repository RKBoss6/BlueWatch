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
    var vm:ViewModel=ViewModel.instance
    var body: some View {
        VStack {
            HStack {

                Text(vm.savedDevice)
                    .font(.title)
                    .fontWeight(.bold)
                
               
            }.padding()
            Form{
                
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
                Section(
                    header: Text("Data"),
                    footer: Text("Periodically pushes location data for 'MyLocation.json'")){
                        VStack(spacing: 32) {
                            Toggle(isOn:$settings.sendToHealthKit ) {
                                Text("Push health data to Apple Health")
                                
                            }
                            Toggle(isOn:$settings.pushWeather ) {
                                Text("Push weather updates")
                                
                            }
                            Toggle(isOn:$settings.pushLocation ) {
                                Text("Push location updates")
                                
                            }
                        }
                        .padding()
                        .liquidGlass(cornerRadius: 24)
                        .ignoresSafeArea(.all)
                        .listRowInsets(EdgeInsets())
                    
                }
                    .listRowBackground(Color.clear)
                
                Section("Web View"){
                    VStack(spacing: 16) {
                        HStack {
                                Text("Web URL:")
                                TextField("placeholder.com", text: $settings.webURL)
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
                         */
                        Divider()
                        Button("Clear Cache") {
                            
                        }
                        .tint(.red)
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
