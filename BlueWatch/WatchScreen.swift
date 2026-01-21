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
    @StateObject private var ble = BLEManager.shared

    var body: some View {
        VStack(spacing: 20) {
            
            Text("Bangle.js Companion")
                .font(.title)
            
            Text(ble.status)
                .foregroundColor(ble.isConnected ? .green : .orange)
            
            Text("Last message:")
                .font(.caption)
            
            Text(ble.lastMessage)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            
            HStack {
                Button("Connect") {
                    ble.connect()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Disconnect") {
                    ble.disconnect()
                }
                .buttonStyle(.bordered)
            }
            
            Divider()
            
            Button("Buzz Watch") {
                ble.send("Buzz")
            }
            
            Button("Find Watch") {
                ble.send("Find Watch")
            }
            Button("Stop Finding Watch") {
                ble.send("Stop Find Watch")
            }
            
        }
        .padding()
    }
}
