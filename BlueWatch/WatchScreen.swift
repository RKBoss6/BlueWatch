//
//  WatchScreen.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 3/4/25.
//

import SwiftUI

struct WatchScreen: View {
    
    var body: some View {
        VStack {
            
            Image("BangleJS2")
                .resizable()
                .frame(width: 250,height: 270)
            if(!watchConnected){
                
            }
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
