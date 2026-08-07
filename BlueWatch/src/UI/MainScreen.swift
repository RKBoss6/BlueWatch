//
//  WatchScreen.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 3/4/25.
//

import SwiftUI


struct WatchScreen: View {
    @Environment(\.isPreview) var isPreview
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
    func getConnectButtonText() -> String {
        var text = ""
        if(bleManager.isConnected){
            if(bleManager.handshakeSuccessful){
                text="Disconnect"
            }else{
                if(bleManager.isHandshaking){
                    text="In progress"
                }else{
                    text="Retry"
                }
            }
        }else{
            text="Connect"
        }
        return text
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
                    Text(bleManager.status)
                        .foregroundColor(bleManager.isConnected ? .green : .orange)
                    Spacer()
                    
                    Button(getConnectButtonText()) {
                        
                        if(bleManager.isConnected){
                            if(bleManager.handshakeSuccessful){
                                bleManager.stop(destructive: true)
                            }else{
                                if(bleManager.isHandshaking){
                                    // nothing to do while its handshaking
                                }else{
                                    // retry
                                    bleManager.startHandshake()
                                }
                            }
                        }else{
                            bleManager.start()
                            bleManager.connect()
                        }
                        
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonStyle(.bordered)
                    
                    
                }
                .padding(.leading)
                .padding(.trailing)
                .padding(.top,-10)
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
                   // .disabled(!bleManager.isConnected)
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
                    //.disabled(!bleManager.isConnected)
                    
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
                  //  .disabled(!bleManager.isConnected)
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
                   // .disabled(!bleManager.isConnected)
                    .buttonStyle(.borderedProminent)
                }
                Spacer()
                Divider()
                Text("Metrics")
                    .font(.title3)
                    .bold()
                    .frame(maxWidth: .infinity,alignment: .leading)
                    .padding(.leading,10)
                NavigationLink{
                    ExpandedMetricView(title: "Heart Rate", dataType: isPreview ? .test : .heartRate, color: .graphRed)
                }label:{
                    HStack{
                        Text("Heart Rate")
                            .font(.headline)
                            .frame(maxWidth: .infinity,alignment: .leading)
                            .padding(.leading,10)
                            .bold()
                            .tint(.primary)
                            .frame(maxWidth: .infinity)
                        Spacer()
                        Image(systemName: "arrowshape.right")
                            .bold()
                            .font(.title3)
                            .tint(.graphRed)
                    }
                }
                DataChart(dataType: isPreview ? .test : .heartRate, color: .graphRed)
                
                Divider()
                    .background(.primary)
                
                NavigationLink{
                    ExpandedMetricView(title: "Steps", dataType: isPreview ? .test : .steps, color: .graphPurple)
                }label:{
                    HStack{
                        Text("Steps")
                            .font(.headline)
                            .frame(maxWidth: .infinity,alignment: .leading)
                            .padding(.leading,10)
                            .bold()
                            .tint(.primary)
                            .frame(maxWidth: .infinity)
                        Spacer()
                        Image(systemName: "arrowshape.right")
                            .bold()
                            .font(.title3)
                            .tint(.graphPurple)
                    }
                }
                DataChart(dataType: isPreview ? .test : .steps, color: Color("GraphPurple"))
                Divider()
                    .background(.primary)
                NavigationLink{
                    ExpandedMetricView(title: "Battery", dataType: isPreview ? .test : .battery, color: .graphGreen)
                }label:{
                    HStack{
                        Text("Battery")
                            .font(.headline)
                            .frame(maxWidth: .infinity,alignment: .leading)
                            .padding(.leading,10)
                            .bold()
                            .tint(.primary)
                            .frame(maxWidth: .infinity)
                        Spacer()
                        Image(systemName: "arrowshape.right")
                            .bold()
                            .font(.title3)
                            .tint(.graphGreen)
                    }
                }
                DataChart(dataType: isPreview ? .test : .battery, color: .graphGreen)
                    .padding(.bottom,70)
                /*
                Divider()
                    .background(.primary)
                
                NavigationLink{
                    ExpandedMetricView(title: "Calories", dataType: isPreview ? .test : .calories, color: .graphOrange)
                }label:{
                    HStack{
                        Text("Calories")
                            .font(.headline)
                            .frame(maxWidth: .infinity,alignment: .leading)
                            .padding(.leading,10)
                            .bold()
                            .tint(.primary)
                            .frame(maxWidth: .infinity)
                        Spacer()
                        Image(systemName: "arrowshape.right")
                            .bold()
                            .font(.title3)
                            .tint(.graphOrange)
                    }
                }
                DataChart(dataType: isPreview ? .test : .calories, color: .graphOrange)
                    .padding(.bottom,70)
                
                */
                
                
                
            }
            Spacer()
            
        }
        .scrollIndicators(.hidden) // Hides indicators for this ScrollView

            
        .padding()
        .appBackground()
    }
}

#Preview{
    WatchScreen()
        .environmentObject(BLEManager.instance)
}
