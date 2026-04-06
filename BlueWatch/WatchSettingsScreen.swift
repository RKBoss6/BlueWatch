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
    @State var autoConnect:Bool=LocalStorage.getBool(forKey: "autoConnect")
    @State var sendInfo:Bool=LocalStorage.getBool(forKey: "sendInfo")
    @State var webURL:String=LocalStorage.getString(forKey: "webURL")
    var body: some View {
        VStack {
            HStack {

                Text("Bangle.js 2")
                    .font(.title)
                    .fontWeight(.bold)
                
               
            }.padding()
            Form{
                Section("Web View"){
                    HStack {
                        Text("Web URL:")
                        TextField("placeholder.com", text: $webURL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onSubmit {
                                LocalStorage.set(webURL, forKey: "webURL")
                                
                            }
                    }
                    
                }
                Section("Bluetooth"){
                    Toggle(isOn:$autoConnect ) {
                        Text("Automatically Connect")
                    }
                    Toggle(isOn:$autoConnect ) {
                        Text("Notify when battery is low")
                    }
                }
                Section("Send and Recieve"){
                    Toggle(isOn:$sendInfo ) {
                        Text("Push weather updates")
                        
                    }
                    if(sendInfo){
                        withAnimation{
                            Picker(selection: /*@START_MENU_TOKEN@*/.constant(1)/*@END_MENU_TOKEN@*/, label: Text("Frequency")) {
                                Text("5 minutes").tag(1)
                                Text("10 minutes").tag(2)
                                Text("30 minutes").tag(1)
                                Text("1 hour").tag(2)
                            }
                        }
                        
                    }
                        
                    Toggle(isOn:$autoConnect ) {
                        Text("Notify when battery is low")
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
