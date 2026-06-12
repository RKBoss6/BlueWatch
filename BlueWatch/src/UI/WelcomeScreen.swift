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
                
                FeatureCard(icon: "bell.badge", description: "Get notifications, and push them to your watch")
                    .padding(.leading,15)
                    .padding(.trailing,15)
                FeatureCard(icon: "cloud.sun", description: "Push weather, location and more")
                    .padding(.leading,15)
                    .padding(.trailing,15)
                Spacer()
                
                if #available(iOS 26.0, *) {
                    NavigationLink(destination: ChooseDeviceScreen()) {
                        Text("Get Started")
                            .frame(maxWidth: .infinity,maxHeight: 30)
                        
                    }
                    
                    .buttonStyle(.glassProminent)
                    
                    
                    .padding()
                } else {
                    NavigationLink(destination: ChooseDeviceScreen()) {
                        Text("Get Started")
                            .frame(maxWidth: .infinity,maxHeight: 30)
                        
                    }
                    
                    .buttonStyle(.borderedProminent)
                    .shadow(color:Color.black.opacity(0.1), radius: 16,x: 0,y: 5)
                    
                    
                    .padding()
                }
                
                
                
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
            let sampleDevices = [
               // DeviceData(img: "BangleJS1", name: "Bangle.js 1"),
                DeviceData(img: "BangleJS2", name: "Bangle.js 2")
            ]
            DeviceCarouselView(devices: sampleDevices)
            //DeviceCard(img: "BangleJS2", name: "Bangle.js 2")
             //   .padding()
            Spacer()
            Spacer()
        }
        .appBackground()
        
    }
}


struct DeviceCard: View {
    let img: String
    let name: String
    
    // 1. A simple boolean to control the screen shift
    @State private var isPresented = false
    
    var body: some View {
        Button(action: {
            
            ViewModel.instance.savedDevice=name
          
            isPresented = true
        }) {
            // Your exact visual card design
            VStack {
                Image(img)
                    .resizable()
                    .frame(width: 180, height: 180)
                Text(name)
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.top, 50)
            .padding(.bottom, 50)
            .padding(20)
            .frame(height: 270)
            .padding()
            .foregroundStyle(.white)
            .background(.tint, in: RoundedRectangle(cornerRadius: 40))
            .shadow(color: .black.opacity(0.2), radius: 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain) // Prevents the card from turning blue/fading
        
        // 3. This is the modern iOS 16+ way to trigger navigation via a boolean
        .navigationDestination(isPresented: $isPresented) {
            ContentView()//fe
        }
    }
}
struct DeviceData: Identifiable {
    let id = UUID()
    let img: String
    let name: String
}

import SwiftUI

struct DeviceCarouselView: View {
    let devices: [DeviceData]
    
    // Tracks the currently centered card ID for the dot indicators
    @State private var activeCardID: UUID?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) { // Keep zero spacing here; offset handle the gap
                        ForEach(devices) { device in
                            DeviceCard(img: device.img, name: device.name)
                                // count: 1, span: 1 stretches the item across container size
                                .containerRelativeFrame(.horizontal, count: 1, span: 1, spacing: 0)
                                .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                    content
                                        .scaleEffect(phase.isIdentity ? 1.0 : 0.8)
                                        // Pull side cards heavily inward to show past screen boundaries
                                        .offset(x: phase.value * -55)
                                        .rotation3DEffect(
                                            .degrees(phase.value * -15),
                                            axis: (x: 0, y: 1, z: 0)
                                        )
                                        .opacity(phase.isIdentity ? 1.0 : 0.6)
                                }
                        }
                    }
                    .scrollTargetLayout()
                }
                // Binds the active card ID automatically as you swipe
                .scrollPosition(id: $activeCardID)
                .scrollTargetBehavior(.viewAligned)
                // Adds extra breathing room inside the container so edges peek through safely
                .contentMargins(.horizontal, 60, for: .scrollContent)
                
                // Custom Tab Dot Indicators
                HStack(spacing: 8) {
                    ForEach(devices) { device in
                        Circle()
                            .fill(activeCardID == device.id ? Color.primary : Color.secondary.opacity(0.4))
                            .frame(width: 8, height: 8)
                            .animation(.spring(duration: 0.2), value: activeCardID)
                    }
                }
                .padding(.bottom, 20)
            }
            .onAppear {
                // Default to the first card on load
                if activeCardID == nil {
                    activeCardID = devices.first?.id
                }
            }
        }
    }
}


struct ScanForDevice: View {
    let img:String
    let description:String
    var body: some View {
        NavigationLink (destination: ContentView()){
            VStack{
                Image(img)
                    .resizable()
                    .frame(width: 180,height: 180)
                Text(description)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
            }
            .padding(.top,50)
            .padding(.bottom,50)
            .padding(20)
            .frame(height:270)
            .padding()
            .foregroundStyle(.white)
            .background(.tint,in: RoundedRectangle(cornerRadius: 40))
            .shadow(color: .black.opacity(0.2), radius: 15)
            .contentShape(Rectangle())
        }
        
    }
}


#Preview {
    WelcomeScreen()
        .environmentObject(BLEManager.instance)
}
