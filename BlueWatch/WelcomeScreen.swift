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
                
                FeatureCard(icon: "appclip", description: "Use bluetooth and web app loaders")
                    .padding(.leading,15)
                    .padding(.trailing,15)
                
                FeatureCard(icon: "bell.badge", description: "Get notifications, and push them to your watch")
                    .padding(.leading,15)
                    .padding(.trailing,15)
                FeatureCard(icon: "cloud.sun", description: "Push weather, location and more")
                    .padding(.leading,15)
                    .padding(.trailing,15)
                Spacer()
                NavigationLink("Get started"){
                    WatchScreen()
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
            Text("Choose your device")
                .font(.title)
                .fontWeight(.bold)
                .padding()
            DeviceCard(img: "BangleJS2", description: "Bangle.js")
                .padding()
        }
        .appBackground()
        
    }
}


struct DeviceCard: View {
    let img:String
    let description:String
    var body: some View {
        HStack{
            Image(img)
                .resizable()
                .frame(width: 150,height: 150)
            Text(description)
                .font(.title2)
                .fontWeight(.semibold)
                
            Spacer()
            
        }
        .frame(width: 300,height:170)
        
        .padding()
        .foregroundStyle(.white)
        .background(.tint,in: RoundedRectangle(cornerRadius: 40))
    }
}


#Preview {
    WelcomeScreen()
}
