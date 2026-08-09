//
//  DeviceCarousel.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 8/9/26.
//

import SwiftUI

struct DeviceCard: View {
    let img: String
    let name: String
    let manufacturer: String
    // 1. A simple boolean to control the screen shift
    @State private var isPresented = false
    
    var body: some View {
        Button(action: {
            
            ViewModel.instance.savedDevice=name
          
            isPresented = true
        }) {
            VStack {
                Image(img)
                    .resizable()
                    .frame(width: 180, height: 180)
                Text(name)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(manufacturer)
                    .font(.headline)
                    .fontWeight(.medium)
                    .opacity(0.7)
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
    let manufacturer: String
}

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
                            DeviceCard(img: device.img, name: device.name, manufacturer:device.manufacturer)
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

#Preview {
    DeviceCarouselView()
}
