//
//  SetupView.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 8/31/26.
//

import SwiftUI

// setup authorizations/permissions
enum SetupScreenType{
    case health
    case location
    case bluetooth
    case notifications
}


struct SetupView: View {
    let type:SetupScreenType
    @State private var navigateToNextScreen = false
    
    func getNextScreen() -> some View{
        // screen order is Notifications, Health, Location
        Group {
            switch type{
            case .bluetooth:
                // not in use right now
                return AnyView(SetupView(type:.bluetooth,icon:"Bluetooth",titleText: "Bluetooth", body1Text: "BlueWatch uses Bluetooth to pair and connect to your device, as well as receiving/sending data.", body2Text:"If Bluetooth permissions are not granted, BlueWatch cannot function properly."))
            case .notifications:
                return AnyView(SetupView(type:.health,icon:"heart.fill",titleText: "Health", body1Text: "BlueWatch can sync health data with Apple Health for a more comprehensive overview of your metrics.", body2Text:"You can always change this later in System Settings"))
                
            case .health:
                return AnyView(SetupView(type:.location,icon:"location.fill",titleText: "Location", body1Text: "BlueWatch uses location to send periodic location updates to your watch, act as a watch GPS, and update weather on your watch.", body2Text:"You can always change this later in System Settings"))
            case .location:
                return AnyView(ChooseDeviceScreen())
            }
            
        }
    }
   let icon:String
    let titleText:LocalizedStringKey
    let body1Text:LocalizedStringKey
    let body2Text:LocalizedStringKey
    var body: some View {
        VStack{
        
            HStack{
                Image(systemName:icon)
                    .font(.title)
                
                Text(titleText)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                /*
                Image(systemName:icon)
                        .font(.title)
                        .opacity(0)
                 */
            }
            Text(body1Text)
                .padding()
                .font(.title3)
                .fontWeight(.medium)
            Text(body2Text)
                .padding()
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Button{
                if(type == .location){
                    Task{
                        await AuthManager.shared.requestLocationAuth()
                        navigateToNextScreen=true
                    }
                }
                if(type == .health){
                    Task{
                        await AuthManager.shared.requestHealthAuthorization()
                        navigateToNextScreen=true
                    }
                }
                if(type == .notifications){
                    Task{
                        await AuthManager.shared.requestNotificationAuthorization()
                        navigateToNextScreen=true
                    }
                }
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity,maxHeight: 30)
                
            }
            
            .buttonStyle(.borderedProminent)
            .shadow(color:Color.black.opacity(0.1), radius: 16,x: 0,y: 5)
            
            
            .padding()
            
            Button{
                navigateToNextScreen=true
            }label:{
                Text("Skip")
                    .frame(maxWidth: .infinity,maxHeight: 30)
                
            }
        }.navigationTitle(String(""))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $navigateToNextScreen) {
                getNextScreen()
            }
            .appBackground()

    }
}

#Preview {
    NavigationStack{
        SetupView(type:.health,icon:"heart.fill",titleText: "Health", body1Text: "BlueWatch can sync health data with Apple Health for a more comprehensive overview of your metrics.", body2Text:"You can always change this later in System Settings")

    }
}
