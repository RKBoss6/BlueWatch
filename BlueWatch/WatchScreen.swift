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
            
            Text("Bangle.js Companion")
                .font(.title)
            
            Text(bleManager.status)
                .foregroundColor(bleManager.isConnected ? .green : .orange)
            
            Text("Last message:")
                .font(.caption)
            
            Text(bleManager.lastMessage)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            
            HStack {
                Button("Connect") {
                    bleManager.connect()
                }
                .buttonStyle(.borderedProminent)
                .buttonStyle(.bordered)
            }
            
            Divider()
            
            Button("Buzz Watch") {
                bleManager.send("Buzz")
            }
            Button("Send Weather") {
                Task {
                    await WeatherManager.shared.updateWeatherAndSend()
                }
            }
            
            Button("Find Watch") {
                bleManager.send("Find Watch")
            }
            Button("Stop Finding Watch") {
                bleManager.send("Stop Find Watch")
            }
            
        }
        .padding()
    }
}

#Preview{
    WatchScreen()
        .environmentObject(BLEManager.shared)
}
