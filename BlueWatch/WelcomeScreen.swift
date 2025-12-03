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
                .foregroundStyle(.white)
            FeatureCard(icon: "gear", description: "Customize your watch settings.")
            FeatureCard(icon: "bell.badge", description: "Get notifications, and push them to your watch")
            
           
            
        }
            
        
    }
}

#Preview {
    WelcomeScreen()
}
