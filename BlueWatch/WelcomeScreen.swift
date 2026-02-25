//
//  WelcomeScreen.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 3/3/25.
//

import SwiftUI

struct WelcomeScreen: View {
    
    @State private var titleText=""
    @State private var textInputted=""
    var body: some View {
        VStack{
            Text("Welcome to BlueWatch")
                .font(.title)
                .fontWeight(.bold)
                .padding()
            
             
            FeatureCard(icon: "gear", description: "Customize your watch settings.")
                .padding(.leading,15)
                .padding(.trailing,15)
            FeatureCard(icon: "bell.badge", description: "Get notifications, and push them to your watch")
                .padding(.leading,15)
                .padding(.trailing,15)
            FeatureCard(icon: "cloud.sun", description: "Push weather, location and more")
                .padding(.leading,15)
                .padding(.trailing,15)
            Button("Connect"){
                
            }
            .buttonStyle(.borderedProminent)
            .padding()
            
           
            
        }
            
        
    }
}

#Preview {
    WelcomeScreen()
}
