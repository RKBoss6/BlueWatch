//
//  WatchScreen.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 3/4/25.
//

import SwiftUI


struct WatchScreen: View {
    @Environment(\.modelContext) private var modelContext
    
    @Environment(\.scenePhase) var scenePhase
    private var CI = CommandInterpreter()
    @EnvironmentObject var bleManager: BLEManager
    @ObservedObject private var ld:LocalData=LocalData.shared;
    @State private var findingWatch=false;
    func getBattImg(battStr:String) -> String{
        var img:String="battery.0percent"
        if let batt = Double(battStr){
            // has a percentage
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
                
                Image("BangleJS2")
                    .resizable()
                    .frame(width: 200,height: 200)
                    .padding(.top,50)
                HStack{
                    Text("Bangle.js")
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
                            //nothing
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
                        bleManager.send("Buzz")
                        
                    }label:{
                        Text("Buzz")
                            .frame(maxWidth: .infinity)
                            .padding(10)
                        
                    }
                    .disabled(!bleManager.isConnected)
                    
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
