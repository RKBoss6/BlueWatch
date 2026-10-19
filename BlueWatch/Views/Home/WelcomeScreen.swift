//
//  WelcomeScreen.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 3/3/25.
//

import SwiftUI

struct WelcomeScreen: View {
    @State private var titleText = ""
    @State private var textInputted = ""
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                Text("Welcome to BlueWatch")
                    .font(.title)
                    .fontWeight(.bold)
                    .padding()

                Spacer()
                FeatureCard(
                    icon: "gear",
                    description: "Customize your watch settings"
                )
                .padding(.leading, 15)
                .padding(.trailing, 15)

                FeatureCard(
                    icon: "appclip",
                    description: "Use Bluetooth and web app loaders"
                )
                .padding(.leading, 15)
                .padding(.trailing, 15)

                FeatureCard(
                    icon: "bell.badge",
                    description:
                        "See notifications, and push them to your watch"
                )
                .padding(.leading, 15)
                .padding(.trailing, 15)
                FeatureCard(
                    icon: "cloud.sun",
                    description: "Push weather, location and more"
                )
                .padding(.leading, 15)
                .padding(.trailing, 15)
                FeatureCard(
                    icon: "iphone.homebutton.radiowaves.left.and.right",
                    description: "Play alerts to find your phone and watch"
                )
                .padding(.leading, 15)
                .padding(.trailing, 15)
                Spacer()

                NavigationLink(
                    destination: WelcomeRequirementsView()
                ) {
                    Text("Get Started")
                        .frame(maxWidth: .infinity, maxHeight: 30)

                }

                .liquidGlassButton()

                .padding()

            }
            .appBackground()
        }

    }
}

struct ChooseDeviceScreen: View {

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Choose your device")
                .font(.title)
                .fontWeight(.bold)
                .padding()
            Spacer()
            let devices = [
                // DeviceData(img: "BangleJS1", name: "Bangle.js 1"),
                DeviceData(
                    img: "BangleJS2",
                    name: "Bangle.js 2",
                    manufacturer: "Espruino"
                )
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
struct WelcomeRequirementsView: View {
    @Environment(\.colorScheme) var colorScheme
    var body: some View {
        VStack{
            Text("Required")
                .font(.title)
                .bold()
                .padding(.bottom,40)
            Image(systemName: "macbook.and.applewatch")
                .font(.system(size: 120))
                .fontWeight(.light)
                .padding(.vertical,30)
            Text("In order for BlueWatch to communicate with your watch, the 'BlueWatch' app must be installed on your Bangle.js via the App Loader.")
                .padding(.bottom)
                .padding(.top,40)
                .padding(.horizontal)
                .fixedSize(horizontal: false, vertical: true)


            Text("The iOS integration app must also be installed in order for you to see iPhone notifications on your watch.")
                .padding(.horizontal,20)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
         

            NavigationLink(
                destination: SetupView(
                    type: .notifications,
                    icon: "bell.and.waves.left.and.right",
                    titleText: "Notifications",
                    body1Text:
                        "BlueWatch uses notifications to alert you during the find phone alarm when the setting is active.",
                    body2Text:
                        "You can always change this later in System Settings"
                )
            ) {
                Text("It's installed, continue")
                    .frame(maxWidth: .infinity, maxHeight: 30)

            }

            .liquidGlassButton()

            .padding()
        }
        .appBackground()
    }
}
#Preview {
    NavigationStack{
        WelcomeScreen()
            .environmentObject(BLEManager.shared)
    }
}

