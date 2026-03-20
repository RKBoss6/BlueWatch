//
//  WatchScreen.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 3/4/25.
//

import SwiftUI

struct WatchfScreen: View {
    
    var body: some View {
        VStack {
            
            Image("BangleJS2")
                .resizable()
                .frame(width: 250,height: 270)
           
            Text("Watch not connected")
                .font(.title2)
                .fontWeight(.bold)
                .padding()
            Button("Connect now"){
                DevicesAvailableView()
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
        
    }
}

#Preview {
    WatchScreen()
}


import SwiftUI

struct WatchScreen: View {
    
    private var CI = CommandInterpreter()
    @EnvironmentObject var bleManager: BLEManager


    var body: some View {
        VStack(spacing: 20) {
            Image("BangleJS2")
                .resizable()
                .frame(width: 200,height: 200)
                .padding(.top,50)
            HStack{
                Text("Bangle.js")
                    .font(.title)
                    .fontWeight(.bold)
                    .frame(width:.infinity,alignment: .leading)
                Spacer()
                Image(systemName: "battery.75percent")
                Text("69%")
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
            NavigationLink{
                WebView()
            }label:{
                    Text("Go to apps")
                        .frame(maxWidth: .infinity)
                        .padding(10)
                
            }
            .buttonStyle(.borderedProminent)
            HStack{
                Button{
                    bleManager.send("Buzz")
                }label:{
                    Text("Buzz")
                        .frame(maxWidth: .infinity)
                        .padding(10)
                }
                .buttonStyle(.borderedProminent)
                Button{
                    Task {
                        await WeatherManager.shared.updateWeatherAndSend()
                    }
                }label:{
                    Text("Push Weather")
                        .frame(maxWidth: .infinity)
                        .padding(10)
                    
                }

                .buttonStyle(.borderedProminent)
            }
            
            
            
            
            Spacer()
            
        }
        .padding()
        .appBackground()
    }
}

#Preview{
    WatchScreen()
        .environmentObject(BLEManager.shared)
}
