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
        NavigationStack{
            VStack(spacing:20){
                Spacer()
                Text("Welcome to BlueWatch")
                    .font(.title)
                    .fontWeight(.bold)
                    .padding()
                
                Spacer()
                FeatureCard(icon: "gear", description: "Customize your watch settings")
                    .padding(.leading,15)
                    .padding(.trailing,15)
                
                FeatureCard(icon: "appclip", description: "Use Bluetooth and web app loaders")
                    .padding(.leading,15)
                    .padding(.trailing,15)
                
                FeatureCard(icon: "bell.badge", description: "See notifications, and push them to your watch")
                    .padding(.leading,15)
                    .padding(.trailing,15)
                FeatureCard(icon: "cloud.sun", description: "Push weather, location and more")
                    .padding(.leading,15)
                    .padding(.trailing,15)
                FeatureCard(icon: "iphone.homebutton.radiowaves.left.and.right", description: "Play alerts to find your phone and watch")
                    .padding(.leading,15)
                    .padding(.trailing,15)
                Spacer()
                
                NavigationLink(destination: SetupView(type:.notifications,icon:"bell.fill",titleText: "Notifications", body1Text: "BlueWatch uses notifications to alert you during the find phone alarm when the setting is active.", body2Text:"You can always change this later in System Settings")) {
                    Text("Get Started")
                        .frame(maxWidth: .infinity,maxHeight: 30)
                    
                }
                
                .buttonStyle(.borderedProminent)
                
                
                .padding()
              
                
                
                
            }
            .appBackground()
        }
        
    }
}

struct ChooseDeviceScreen: View {

    var body: some View {
        VStack(spacing:20){
            Spacer()
            Text("Choose your device")
                .font(.title)
                .fontWeight(.bold)
                .padding()
            Spacer()
            let devices = [
               // DeviceData(img: "BangleJS1", name: "Bangle.js 1"),
                DeviceData(img: "BangleJS2", name: "Bangle.js 2", manufacturer: "Espruino")
            ]
            DeviceCarouselView(devices: devices)
            //DeviceCard(img: "BangleJS2", name: "Bangle.js 2")
             //   .padding()
            Spacer()
            Spacer()
        }
        .appBackground()
        
    }
}






#Preview {
    WelcomeScreen()
        .environmentObject(BLEManager.shared)
}
