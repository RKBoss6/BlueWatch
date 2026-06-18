//
//  WatchScreen.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 3/4/25.
//

import SwiftUI


struct WatchScreen: View {
    @Environment(\.modelContext) private var modelContext
    var vm:ViewModel=ViewModel.instance
    @ObservedObject var settings = Settings.instance
    @Environment(\.scenePhase) var scenePhase
    private var CI = CommandInterpreter()
    @State private var findingPhone=false;
    @EnvironmentObject var bleManager: BLEManager
    @ObservedObject private var ld:LocalData=LocalData.shared;
    @State private var findingWatch=false;
    private var findPhoneAlarm=FindPhoneAlarm()
    func getBattImg(battStr:String) -> String{
        var img:String="battery.0percent"
        if let batt = Double(battStr){
            // has a percentageb
            if(batt>5){
                img="battery.25percent"
            }
            if(batt>40){
                img="battery.50percent"
            }
            if(batt>70){
                img="battery.75percent"
            }
            if(batt>90){
                img="battery.100percent"
            }
            
        }
        return img;
    }
    
    var body: some View {
        ScrollView{
            VStack(spacing: 20) {
                
                Image(vm.savedDevice=="Bangle.js 2" ? "BangleJS2" : "BangleJS1" )
                    .resizable()
                    .frame(width: 200,height: 200)
                    .padding(.top,50)
                HStack{
                    Text(settings.deviceName.isEmpty==false ? settings.deviceName : vm.savedDevice)
                        .font(.title)
                        .fontWeight(.bold)
                    Spacer()
                    Image(systemName:getBattImg(battStr: ld.battery))
                    Text(ld.battery+"%")
                }
                .padding()
                
                /*
                 Text("Last message:")
                 .font(.caption)
                 
                 Text(bleManager.lastMessage)
                 .padding()
                 .frame(maxWidth: .infinity)
                 .background(Color.gray.opacity(0.1))
                 .cornerRadius(8)
                 */
                HStack {
                    Button(bleManager.isConnected ? "Paired" : "Connect") {
                        if(bleManager.isConnected){
                        }else{
                            bleManager.connect()
                        }
                        
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonStyle(.bordered)
                    Spacer()
                    Text(bleManager.status)
                        .foregroundColor(bleManager.isConnected ? .green : .orange)
                    
                }
                .padding(.leading)
                .padding(.trailing)
                Divider()
                Spacer()
                HStack{
                    
                    Button{
                        if(findingPhone){
                            findPhoneAlarm.stop()
                            
                        }else{
                            findPhoneAlarm.start()
                        }
                        findingPhone = !findingPhone

                        
                    }label:{
                        Text(findingPhone ? "Stop" : "Find Phone")
                            .frame(maxWidth: .infinity)
                            .padding(10)
                        
                        
                    }
                    .disabled(!bleManager.isConnected)
                    .tint(findingPhone ? .orange : .accent)
                    
                    .buttonStyle(.borderedProminent)
                    Button{
                        if(findingWatch){
                            bleManager.send("Stop Find Watch")
                            findingWatch=false
                        }else{
                            bleManager.send("Find Watch")
                            findingWatch=true
                        }
                        
                    }label:{
                        Text(findingWatch ? "Stop Finding" : "Find Watch")
                            .frame(maxWidth: .infinity)
                            .padding(10)
                        
                    }
                    .disabled(!bleManager.isConnected)
                    
                    .buttonStyle(.borderedProminent)
                    .tint(findingWatch ? .orange : .accent)
                }
                HStack{
                    
                    Button{
                        Task {
                            await WeatherManager.shared.updateWeatherAndSend()
                        }
                    }label:{
                        Text("Push Weather")
                            .frame(maxWidth: .infinity)
                            .padding(10)
                        
                    }
                    .disabled(!bleManager.isConnected)
                    .buttonStyle(.borderedProminent)
                    Button{
                        Task {
                            await LocationManager.shared.sendLocation()
                        }
                    }label:{
                        Text("Push Location")
                            .frame(maxWidth: .infinity)
                            .padding(10)
                        
                    }
                    .disabled(!bleManager.isConnected)
                    .buttonStyle(.borderedProminent)
                }
                Spacer()
                Divider()
                Text("Data from the last 24 hours")
                    .font(.headline)
                    .frame(maxWidth: .infinity,alignment: .leading)
                    .padding(.leading,10)
                Text("Heart Rate")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity,alignment: .leading)
                    .padding(.leading,10)
                DynamicDataChart(dataType: .heartRate, color: .red, suffix: " bpm")
                Text("Steps")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity,alignment: .leading)
                    .padding(.leading,10)
                DynamicDataChart(dataType: .steps, color: .purple, suffix: " steps")
                Text("Battery")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity,alignment: .leading)
                    .padding(.leading,10)
                DynamicDataChart(dataType: .battery, color: .green, suffix: "%")
                    .padding(.bottom,70)
                
                
                
            }
            Spacer()
            
        }
        .scrollIndicators(.hidden) // Hides indicators for this ScrollView

            
        .padding()
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                print("Active")
                bleManager.send("Request System Info")
                // Do something here
            
            }
        }
        .appBackground()
    }
}

#Preview{
    WatchScreen()
        .environmentObject(BLEManager.instance)
}
